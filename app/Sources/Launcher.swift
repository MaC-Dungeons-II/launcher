// M(a)C Dungeons II launcher: sign-in, runtime dependencies, game download and
// updates, prefix setup, then the game. Everything the user owns (game files,
// prefix, saves, session) lives in ~/Library/Application Support/M(a)C Dungeons II.
import Foundation
import AppKit
import CoreGraphics
import CryptoKit

@MainActor
final class Launcher: ObservableObject {
    enum Stage: Equatable {
        case idle, working, needsConsent, needsLogin, ready, playing, failed, paused
    }

    @Published var stage: Stage = .idle {
        didSet { holdActivity(stage == .working || stage == .playing) }
    }
    /// Started from Minecraft Launcher the app has no window, and macOS would
    /// throttle it and its children (App Nap): the download crawled and the
    /// game would stutter. Held while working or playing.
    private var activity: NSObjectProtocol? = nil
    @Published var status = "준비 중…"
    @Published var detail = ""
    @Published var progress: Double? = nil
    /// The game's window is on screen (after .playing starts, it takes a while).
    @Published private(set) var gameWindowShown = false
    /// The game download or install under way, for Minecraft Launcher's
    /// progress bar (MCLauncherLink); nil otherwise.
    struct Transfer { var phase: String; var update: Bool; var done: Double; var total: Double; var speed: Double = 0 }
    private(set) var transfer: Transfer? = nil
    private var transferIsUpdate = false
    /// The running game download (`macd2 mac-fetch`), to pause or cancel it
    /// from Minecraft Launcher's download bar. Interrupting it is safe: the
    /// download keeps finished chunks and resumes on the next run.
    private var fetchProcess: Process? = nil
    private enum DownloadStop { case pause, cancel }
    private var downloadStop: DownloadStop? = nil
    static let productId = "9P5786PJB9RP"
    static let gameExe = "Dungeons-WinGDK-Shipping.exe"
    let fm = FileManager.default
    let resources = Bundle.main.resourceURL!
    let data: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/M(a)C Dungeons II", isDirectory: true)

    var wine: URL { resources.appendingPathComponent("wine") }
    var wineBin: URL { wine.appendingPathComponent("bin/wine") }
    var wineServer: URL { wine.appendingPathComponent("bin/wineserver") }
    var layer: URL { resources.appendingPathComponent("layer") }
    var cli: URL { resources.appendingPathComponent("bin/macd2") }
    var broker: URL { resources.appendingPathComponent("bin/macd2-broker") }
    var game: URL { data.appendingPathComponent("game") }
    var prefix: URL { data.appendingPathComponent("prefix") }
    var system32: URL { prefix.appendingPathComponent("drive_c/windows/system32") }
    var deps: URL { data.appendingPathComponent("deps") }
    var caBundle: URL { deps.appendingPathComponent("curl-ca-bundle.crt") }
    var session: URL { data.appendingPathComponent("session") }
    var logs: URL { data.appendingPathComponent("logs") }
    var stateFile: URL { data.appendingPathComponent("state.json") }
    var licenseMarker: URL { data.appendingPathComponent("gdk-license-accepted") }
    var gameBinaries: URL { game.appendingPathComponent("Dungeons/Binaries/WinGDK") }
    var gameOld: URL { data.appendingPathComponent("game.old") }
    var lockFile: URL { data.appendingPathComponent(".lock") }
    var brokerPidFile: URL { data.appendingPathComponent("broker.pid") }
    /// `mac-session --serve`, which keeps the session file fresh while playing.
    var sessionPidFile: URL { data.appendingPathComponent("session-serve.pid") }
    static let brokerSocket = "/tmp/macd2.sock"
    static let rotatedLogs = ["game.log", "fetch.log", "broker.log", "session.log", "prefix.log"]

    private var helpers: [Process] = []
    private var lastSample: (Date, Double)? = nil
    private var speed: Double = 0
    private var fetchErrorStage: String? = nil
    private var lockFD: Int32 = -1
    private var prepared = false
    /// Wine may be running (prefix setup or the game); quitting must stop it.
    private var usedWine = false
    /// The game process (`macd2 run`) is running, with this environment.
    private(set) var gameRunning = false
    private var gameEnv: [String: String]? = nil
    private var stoppingGame = false
    private var quitPending = false

    // MARK: - Flow

    /// Checks the account and the license, then waits at .ready for Install /
    /// Play (or goes straight on when Play was asked for).
    func start() {
        guard !running else { return }
        running = true
        Task { await run(); running = false }
    }

    /// Install or Play: from the window, or Minecraft Launcher's Play button.
    func play() {
        autoLaunch = true
        switch stage {
        case .paused: resumeDownload()
        case .working, .playing: break   // the run under way goes on to the game
        default: start()
        }
    }

    /// Set by MCLauncherLink when Minecraft Launcher drives the app: it quits
    /// when the game ends or the download is cancelled, instead of going back
    /// to its window.
    var drivenByMinecraftLauncher = false
    private var running = false
    private var autoLaunch = false

    /// Back to the Install / Play state (the window), or quit when the
    /// Minecraft Launcher drives the app.
    private func finishRun() {
        autoLaunch = false
        if drivenByMinecraftLauncher { NSApp.terminate(nil); return }
        stage = .ready
        setReady()
    }

    private func setReady() {
        if gameInstalled {
            set("플레이할 준비가 됐어요", "업데이트가 있으면 플레이할 때 먼저 받아요.")
        } else {
            set("게임이 아직 설치되지 않았어요", "설치를 누르면 Microsoft에서 게임(약 9.6 GB)을 내려받아요.")
        }
    }

    func acceptLicense() {
        do {
            try Data("accepted \(Date())\n".utf8).write(to: licenseMarker, options: .atomic)
        } catch {
            fail("라이선스 동의를 저장하지 못했어요. \(error.localizedDescription)")
            return
        }
        start()
    }

    func login() {
        Task {
            stage = .working
            set("Microsoft 계정 로그인 창을 열었어요", "로그인 창에서 로그인을 마치면 자동으로 계속돼요.")
            let code = await runProcess(cli, ["login"], log: "login.log")
            if code != 0 {
                fail("로그인을 마치지 못했어요 (코드 \(code)). 다시 시도해 주세요.")
                stage = .needsLogin
                return
            }
            await run()
        }
    }

    private func run() async {
        stage = .working
        do {
            try fm.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for dir in [deps, session, logs] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            guard try acquireLock() else {
                stage = .failed
                set("이미 실행 중이에요.", "다른 M(a)C Dungeons II 창을 닫고 다시 시도해 주세요.")
                return
            }
            if !prepared {
                // once per app launch, before anything touches the game or helpers
                try restoreGameFolder()
                rotateLogs()
                await stopStaleHelpers()
                prepared = true
            }

            set("Microsoft 계정 확인 중…")
            // signs in to the title's Xbox services and writes the session file
            // the runtime's XUser reads (private, in the data folder)
            let check = await execute(cli, ["mac-session", session.path], log: "session.log", timeout: 60)
            if check.timedOut || check.code == 69 {
                failOffline()
                return
            }
            if check.code == 77 {
                stage = .needsLogin
                set("Microsoft 계정으로 로그인해 주세요",
                    "게임을 구매한 계정으로 로그인하면, 게임을 내려받고 실행할 수 있어요.")
                return
            }
            if check.code != 0 {
                fail("Microsoft 계정을 확인하지 못했어요 (코드 \(check.code)).")
                return
            }

            if !fm.fileExists(atPath: licenseMarker.path) {
                stage = .needsConsent
                set("Microsoft GDK 라이선스 동의가 필요해요",
                    "게임이 쓰는 Xbox 런타임(Microsoft GDK)을 Microsoft에서 직접 내려받아요.")
                return
            }
            guard autoLaunch else {
                stage = .ready
                setReady()
                return
            }
            autoLaunch = false
            try await ensureRosetta()
            try await ensureDependencies()
            try await ensureGame()
            try overlayLayer()
            removeLegacyWasdmod()
            try await ensurePrefix()
            try await launch()
        } catch is OfflineError {
            failOffline()
        } catch let stopped as DownloadStopped {
            if stopped.cancelled {
                finishRun()   // as if Install was never pressed
            } else {
                let last = transfer
                stage = .paused
                set("내려받기 일시 정지됨", "이어 받으면 멈춘 곳부터 계속 받아요")
                transfer = last
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func set(_ s: String, _ d: String = "", _ p: Double? = nil) {
        status = s; detail = d; progress = p; transfer = nil
    }

    private func fail(_ message: String) {
        stage = .failed
        set("문제가 생겼어요", message + "\n로그: \(logs.path)")
    }

    private func failOffline() {
        stage = .failed
        set("인터넷 연결을 확인해 주세요.", "연결된 뒤 다시 시도해 주세요.")
    }

    // MARK: - Single instance and leftovers from a previous run

    /// Exclusive lock on <data>/.lock for the app's lifetime (released by the
    /// kernel when the process exits, also on a crash).
    private func acquireLock() throws -> Bool {
        if lockFD >= 0 { return true }
        let fd = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw LauncherError("잠금 파일을 만들지 못했어요: \(String(cString: strerror(errno)))")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    /// A game-folder swap that was interrupted leaves only game.old; put it back.
    /// With both present, the swap finished and game.old is a leftover.
    private func restoreGameFolder() throws {
        guard fm.fileExists(atPath: gameOld.path) else { return }
        if fm.fileExists(atPath: game.path) {
            try? fm.removeItem(at: gameOld)
        } else {
            try fm.moveItem(at: gameOld, to: game)
        }
    }

    /// Keeps one previous copy of each log (<name>.1).
    private func rotateLogs() {
        for name in Self.rotatedLogs {
            let log = logs.appendingPathComponent(name)
            guard fm.fileExists(atPath: log.path) else { continue }
            let previous = logs.appendingPathComponent(name + ".1")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: log, to: previous)
        }
    }

    /// Stops helpers recorded by an earlier run (quit or crash) whose PID still
    /// belongs to the expected executable.
    private func stopStaleHelpers() async {
        for (file, exe) in [(brokerPidFile, broker), (sessionPidFile, cli)] {
            defer { try? fm.removeItem(at: file) }
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
                  isHelper(pid, exe) else { continue }
            kill(pid, SIGTERM)
            for _ in 0..<30 where isHelper(pid, exe) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if isHelper(pid, exe) { kill(pid, SIGKILL) }
        }
    }

    /// The running process `pid` is this app's `exe` (same file, or the same
    /// helper in another copy of the app, e.g. a translocated one).
    private func isHelper(_ pid: Int32, _ exe: URL) -> Bool {
        let path = Self.realPath(executablePath(pid))
        if path.isEmpty { return false }
        if path == Self.realPath(exe.path) { return true }
        return (path as NSString).lastPathComponent == exe.lastPathComponent
            && path.contains(".app/Contents/Resources/bin/")
    }

    private func writePid(_ p: Process, to file: URL) {
        try? Data("\(p.processIdentifier)\n".utf8).write(to: file, options: .atomic)
    }

    // MARK: - Microsoft GDK runtime and curl (fetched, never bundled)

    /// An archive and the members taken from it. An empty sha256 marks an
    /// optional, unpinned member (license texts).
    struct Dependency {
        let url: String
        let members: [(suffix: String, name: String, sha256: String)]
    }

    let dependencies = [
        Dependency(
            url: "https://api.nuget.org/v3-flatcontainer/microsoft.gdk.windows/2604.4.7897/microsoft.gdk.windows.2604.4.7897.nupkg",
            members: [
                ("native/260404/windows/bin/x64/xgameruntime.dll", "xgameruntime_original.dll",
                 "815d0c5b0aa5c84eb6104168da551a4922f49f8dd02dbdf3bbc5119beec11b59"),
                ("LICENSE.md", "Microsoft-GDK-LICENSE.md", ""),
            ]),
        Dependency(
            url: "https://curl.se/windows/dl-8.22.0_2/curl-8.22.0_2-win64-mingw.zip",
            members: [
                ("/bin/libcurl-x64.dll", "curl-compat.dll",
                 "f31fa58061e162ff4702b37224404df210346df6dff4a49e92d07b8dd5217334"),
                ("/bin/curl-ca-bundle.crt", "curl-ca-bundle.crt",
                 "1fdcf2a55c9806c4c1e8391cb283871ee3b209d68a2879ce4c0898d949de2545"),
                ("/COPYING.txt", "curl-LICENSE.txt", ""),
            ]),
    ]

    /// Architecture folders of the bundled Wine runtime, read from the bundle
    /// itself: the current runtime is x86_64 (runs under Rosetta); an arm64
    /// runtime (ARM64 Wine with an x86_64 emulator, see docs/arm64-migration.md)
    /// would ship aarch64-unix/aarch64-windows instead.
    private var wineUnixDir: String {
        fm.fileExists(atPath: wine.appendingPathComponent("lib/wine/aarch64-unix").path) ? "aarch64-unix" : "x86_64-unix"
    }
    private var winePEDir: String {
        fm.fileExists(atPath: wine.appendingPathComponent("lib/wine/aarch64-windows").path) ? "aarch64-windows" : "x86_64-windows"
    }

    /// An x86_64 Wine runtime needs Rosetta 2. Without it every Wine process
    /// fails with an unclear error, so check first and say what to do.
    /// macOS 27 is the last release with full Rosetta (see docs/arm64-migration.md).
    private func ensureRosetta() async throws {
        guard wineUnixDir == "x86_64-unix" else { return }
        let probe = await execute(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"],
                                  log: "tools.log", timeout: 20)
        guard probe.code != 0 else { return }
        throw LauncherError("Rosetta가 필요해요. 터미널에서 softwareupdate --install-rosetta 를 실행한 뒤 다시 시도해 주세요.")
    }

    private func ensureDependencies() async throws {
        for dep in dependencies {
            let pinned = dep.members.filter { !$0.sha256.isEmpty }
            if pinned.allSatisfy({ (try? sha256(deps.appendingPathComponent($0.name))) == $0.sha256 }) { continue }
            let source = URL(string: dep.url)!
            let name = source.lastPathComponent
            set("런타임 내려받는 중… (\(name))", "출처: \(source.host ?? "")", 0)
            let archive = deps.appendingPathComponent(name)
            try await download(source, to: archive)
            defer { try? fm.removeItem(at: archive) }   // also when a hash did not match
            let entries = try await capture("/usr/bin/zipinfo", ["-1", archive.path])
                .split(separator: "\n").map(String.init)
            for member in dep.members {
                guard let entry = entries.first(where: { $0.hasSuffix(member.suffix) }) else {
                    if member.sha256.isEmpty { continue }
                    throw LauncherError("\(name)에서 \(member.suffix)를 찾지 못했어요")
                }
                let out = deps.appendingPathComponent(member.name)
                let bytes = try await captureData("/usr/bin/unzip", ["-p", archive.path, entry])
                try bytes.write(to: out)
                if !member.sha256.isEmpty, try sha256(out) != member.sha256 {
                    try? fm.removeItem(at: out)
                    throw LauncherError("\(member.name) 해시가 맞지 않아요. 내려받은 파일을 사용하지 않았어요.")
                }
            }
        }
    }

    private func download(_ url: URL, to target: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: nil)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? fm.removeItem(at: temp)
            throw LauncherError("내려받기 실패: \(url.absoluteString)")
        }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: temp, to: target)
    }

    // MARK: - Game download and updates (xodus, the account's own license)

    private func installedVersion() -> String? {
        guard let d = try? Data(contentsOf: stateFile),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return j["version"] as? String
    }

    private func ensureGame() async throws {
        set("업데이트 확인 중…")
        let installed = installedVersion()
        let info = await execute(cli, ["package-info", Self.productId], log: "tools.log", captureOutput: true, timeout: 120)
        let text = String(decoding: info.output, as: UTF8.self)
        guard info.code == 0, !info.timedOut,
              let line = text.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let latest = json["version"] as? String else {
            // offline or service trouble: play the installed copy
            if fm.fileExists(atPath: gameBinaries.appendingPathComponent(Self.gameExe).path) { return }
            throw LauncherError("게임 버전 정보를 받지 못했어요. 인터넷 연결을 확인해 주세요.")
        }
        if installed == latest && fm.fileExists(atPath: gameBinaries.appendingPathComponent(Self.gameExe).path) {
            return
        }
        let staging = data.appendingPathComponent("game.new")
        try? fm.removeItem(at: staging)
        set(installed == nil ? "게임 내려받는 중…" : "업데이트 내려받는 중… (\(latest))", "Microsoft에서 \(latest) 버전을 받고 있어요", 0)
        transferIsUpdate = installed != nil
        var fetchEnv = ProcessInfo.processInfo.environment
        fetchEnv["MACD2_PROGRESS_JSON"] = "1"
        speed = 0
        lastSample = nil
        fetchErrorStage = nil
        downloadStop = nil
        let code = await execute(cli, ["mac-fetch", Self.productId, downloads.path, staging.path],
                                 env: fetchEnv, log: "fetch.log", onLine: { [weak self] line in self?.fetchProgress(line) },
                                 onStart: { [weak self] p in self?.fetchProcess = p }).code
        fetchProcess = nil
        if let stop = downloadStop {
            downloadStop = nil
            if stop == .cancel { discardPartialDownload() }
            throw DownloadStopped(cancelled: stop == .cancel)
        }
        guard code == 0 else {
            switch fetchErrorStage {
            case "disk-full": throw LauncherError("저장 공간이 부족해요. 약 20GB가 필요해요.")
            case "network": throw OfflineError()
            case "busy": throw LauncherError("다른 내려받기가 진행 중이에요. 잠시 후 다시 시도해 주세요.")
            default: throw LauncherError("게임을 내려받지 못했어요 (코드 \(code)). 다시 실행하면 이어서 받아요.")
            }
        }
        if fm.fileExists(atPath: game.path) {
            // If the app dies between the two moves, startup restores game.old.
            try? fm.removeItem(at: gameOld)
            try fm.moveItem(at: game, to: gameOld)
            do {
                try fm.moveItem(at: staging, to: game)
            } catch {
                try? fm.moveItem(at: gameOld, to: game)
                throw error
            }
            try? fm.removeItem(at: gameOld)
        } else {
            try fm.moveItem(at: staging, to: game)
        }
        try JSONSerialization.data(withJSONObject: ["version": latest]).write(to: stateFile, options: .atomic)
    }

    var downloads: URL { data.appendingPathComponent("downloads") }
    var gameInstalled: Bool { fm.fileExists(atPath: gameBinaries.appendingPathComponent(Self.gameExe).path) }

    private func holdActivity(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled, .latencyCritical],
                reason: "game download or play")
        } else if !on, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    /// Minecraft Launcher's pause and cancel buttons (MCLauncherLink).
    func pauseDownload() { stopDownload(.pause) }
    func cancelDownload() {
        if stage == .paused {
            discardPartialDownload()
            finishRun()
        } else {
            stopDownload(.cancel)
        }
    }
    func resumeDownload() {
        guard stage == .paused else { return }
        autoLaunch = true
        start()
    }

    /// Only while downloading: stopping the extraction would discard the package.
    private func stopDownload(_ stop: DownloadStop) {
        guard transfer?.phase == "download", let p = fetchProcess, p.isRunning else { return }
        downloadStop = stop
        p.terminate()
    }

    /// A fresh start next time: the partial package and the staging folder go.
    private func discardPartialDownload() {
        for f in (try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.contains(".msixvc") { try? fm.removeItem(at: f) }
        try? fm.removeItem(at: data.appendingPathComponent("game.new"))
    }

    private func fetchProgress(_ line: String) {
        guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        switch j["phase"] as? String {
        case "download":
            if let done = j["done"] as? Double, let total = j["total"] as? Double, total > 0 {
                progress = min(max(done / total, 0), 1)
                let now = Date()
                if let (t0, d0) = lastSample {
                    let dt = now.timeIntervalSince(t0)
                    if dt >= 1 {
                        let rate = (done - d0) / dt
                        // a negative rate means bytes were rolled back: not a speed sample
                        if rate >= 0 { speed = speed == 0 ? rate : speed * 0.8 + rate * 0.2 }   // smoothed bytes/s
                        lastSample = (now, done)
                    }
                } else {
                    lastSample = (now, done)
                }
                transfer = Transfer(phase: "download", update: transferIsUpdate, done: done, total: total,
                                    speed: speed > 10_000 ? speed : 0)
                var text = String(format: "%.1f / %.1f GB", done / 1e9, total / 1e9)
                if speed > 10_000 {
                    text += speed >= 1e6 ? String(format: " · %.1f MB/s", speed / 1e6)
                                         : String(format: " · %.0f KB/s", speed / 1e3)
                }
                if speed > 100_000 {   // below ~100 KB/s a time estimate is meaningless
                    let seconds = max(total - done, 0) / speed
                    let left = seconds.isFinite ? Int(min(seconds, 99 * 3600)) : 99 * 3600
                    text += left >= 60 ? " · 약 \(left / 60)분 남음" : " · 1분 이내"
                }
                detail = text
            }
        case "extract":
            status = "게임 설치 중…"
            if let done = j["done"] as? Double, let total = j["total"] as? Double, total > 0 {
                progress = min(done / total, 1)
                transfer = Transfer(phase: "install", update: transferIsUpdate, done: done, total: total)
                detail = String(format: "%.1f / %.1f GB · 게임 파일을 풀고 있어요", done / 1e9, total / 1e9)
            } else {
                detail = "게임 파일을 풀고 있어요"; progress = nil
                transfer = Transfer(phase: "install", update: transferIsUpdate, done: 0, total: 0)
            }
        case "error":
            fetchErrorStage = j["stage"] as? String
        default: break
        }
    }

    // MARK: - Compatibility layer in the game folder

    private func overlayLayer() throws {
        // the runtime (Flightdeck-based, over the genuine GDK runtime) and the
        // XCurl wrapper over curl.se's libcurl
        let sources =
            ["xgameruntime.dll", "XCurl.dll"].map { layer.appendingPathComponent($0) } +
            ["xgameruntime_original.dll", "curl-compat.dll", "curl-ca-bundle.crt"].map { deps.appendingPathComponent($0) }
        for src in sources { try replace(gameBinaries.appendingPathComponent(src.lastPathComponent), with: src) }
        // left by versions that shipped the mcd2-crossover adapter
        for name in ["xgameruntime-native.dll", "xgameruntime-adapter-thunks.dll", "dungeons-crossover.ini"] {
            try? fm.removeItem(at: gameBinaries.appendingPathComponent(name))
        }
        // Diagnostics: MACD2_LAYER_DIR=<folder> in debug.env copies every file
        // in that folder next to the game afterwards (e.g. another runtime build).
        if let dir = debugOverrides()["MACD2_LAYER_DIR"], !dir.isEmpty {
            let extra = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            for name in (try? fm.contentsOfDirectory(atPath: extra.path)) ?? [] where !name.hasPrefix(".") {
                try replace(gameBinaries.appendingPathComponent(name), with: extra.appendingPathComponent(name))
            }
            appendLog("game.log", "launcher: layer files from \(extra.path) (MACD2_LAYER_DIR)")
        }
        for base in [gameBinaries, gameBinaries.deletingLastPathComponent()] {
            let certs = base.appendingPathComponent("etc/ssl/certs")
            try fm.createDirectory(at: certs, withIntermediateDirectories: true)
            try replace(certs.appendingPathComponent("ca-bundle.crt"), with: caBundle)
        }
    }

    private func windowsPath(_ url: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }

    private func replace(_ target: URL, with source: URL) throws {
        try? fm.removeItem(at: target)
        try fm.copyItem(at: source, to: target)
    }

    // MARK: - Leftovers of the removed wasdmod support

    /// Earlier versions could put wasdmod (keyboard and mouse as a controller)
    /// next to the game and keep its layouts in <data>/wasdmod; take them out.
    private func removeLegacyWasdmod() {
        for name in (try? fm.contentsOfDirectory(atPath: gameBinaries.path)) ?? [] {
            let n = name.lowercased()
            guard ["xinput1_4.dll", "default.txt", "author.txt", "wasdmod.log"].contains(n)
                || (n.hasPrefix("wasd") && (n.hasSuffix(".txt") || n.hasSuffix(".ini") || n.hasSuffix(".flag")))
            else { continue }   // the game ships none of these names
            try? fm.removeItem(at: gameBinaries.appendingPathComponent(name))
        }
        try? fm.removeItem(at: data.appendingPathComponent("wasdmod"))
        try? fm.removeItem(at: logs.appendingPathComponent("wasdmod.log"))
        for key in ["wasdmod.enabled", "wasdmod.layout", "wasdmod.names"] { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// ...and the game's Option-as-Alt and cursor-clipping keys it set in the prefix.
    private func removeLegacyWasdKeys() async {
        let state = prefix.appendingPathComponent(".macd2-wasd-keys")
        guard let applied = try? String(contentsOf: state, encoding: .utf8) else { return }
        if applied == "on" {
            await prefixWine(["reg", "delete", "HKCU\\Software\\Wine\\AppDefaults\\\(Self.gameExe)\\Mac Driver", "/f"])
            await killWineServer(env: wineEnv, log: "prefix.log")
        }
        try? fm.removeItem(at: state)
    }

    // MARK: - Wine prefix

    private var wineEnv: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.merge(debugOverrides()) { _, file in file }
        env["WINEPREFIX"] = prefix.path
        env["PATH"] = wine.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["DYLD_FALLBACK_LIBRARY_PATH"] = wine.appendingPathComponent("lib").path + ":/usr/lib"
        env["WINEDEBUG"] = env["MACD2_WINEDEBUG"] ?? "err+all,fixme-all"
        // Mach-semaphore sync (CrossOver's msync): thread waits stay in the
        // process instead of round-tripping to wineserver. wineserver and every
        // Wine process must agree, so it is set for all of them here.
        env["WINEMSYNC"] = env["MACD2_MSYNC"] ?? "1"
        // Bundled GStreamer only (winegstreamer decodes the game's videos)
        env["GST_PLUGIN_SYSTEM_PATH_1_0"] = wine.appendingPathComponent("lib/gstreamer-1.0").path
        env["GST_PLUGIN_SCANNER_1_0"] = wine.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path
        env["GST_REGISTRY_1_0"] = data.appendingPathComponent("gstreamer-registry.bin").path
        env.removeValue(forKey: "GST_PLUGIN_PATH_1_0")
        env.removeValue(forKey: "GST_PLUGIN_PATH")
        // DXMT (D3D11 on Metal): Metal paces frames at a rate that divides the
        // display's refresh rate (60 on a 120 Hz ProMotion panel) instead of
        // the game rendering as fast as the GPU allows; MetalFX spatial
        // upscaling sharpens the swapchain output to the Retina resolution.
        // Compiled shaders persist across launches.
        env["DXMT_CONFIG"] = env["MACD2_DXMT_CONFIG"] ?? "d3d11.preferredMaxFrameRate=\(Self.pacedFrameRate());"
        env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = env["MACD2_METALFX"] ?? "1"
        env["DXMT_SHADER_CACHE_PATH"] = data.appendingPathComponent("shader-cache").path
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml=;msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1=n,b;xgameruntime,xcurl=n"
        return env
    }

    /// Largest frame rate up to 60 that divides the main display's refresh
    /// rate (DXMT requires a divisor): 120 Hz -> 60, 60 Hz -> 60, 144 Hz -> 48.
    private static func pacedFrameRate() -> Int {
        let hz = NSScreen.main?.maximumFramesPerSecond ?? 60
        guard hz > 0 else { return 60 }
        return (1...min(60, hz)).reversed().first { hz % $0 == 0 } ?? 60
    }

    /// Optional KEY=VALUE lines in <data>/debug.env (blank lines and # comments
    /// ignored) applied to every Wine process, for diagnostics without a
    /// rebuild, e.g. MACD2_WINEDEBUG=err+all,+seh or MACD2_METALFX=0.
    private func debugOverrides() -> [String: String] {
        guard let text = try? String(contentsOf: data.appendingPathComponent("debug.env"), encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            out[String(line[..<eq]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Runs a Wine command against the prefix, logging to prefix.log.
    @discardableResult
    private func prefixWine(_ args: [String]) async -> Int32 {
        await runProcess(wineBin, args, env: wineEnv, log: "prefix.log")
    }

    private func killWineServer(env: [String: String], log: String) async {
        await runProcess(wineServer, ["-k"], env: env, log: log)
    }

    private func ensurePrefix() async throws {
        let marker = prefix.appendingPathComponent(".macd2-ready")
        let isNew = !fm.fileExists(atPath: marker.path)
        usedWine = true
        if isNew { try await createPrefix() }
        syncBuiltins()
        await configureControllers()
        await configureMedia()
        await removeLegacyWasdKeys()
        if isNew { try Data().write(to: marker) }
    }

    private func createPrefix() async throws {
        set("처음 실행 준비 중… (Windows 환경 만들기)", "1~2분 걸려요")
        let boot = await prefixWine(["wineboot", "-i"])
        await runProcess(wineServer, ["-w"], env: wineEnv, log: "prefix.log")
        guard boot == 0 else { throw LauncherError("Windows 환경을 만들지 못했어요 (wineboot 코드 \(boot)).") }
        let cfg = await prefixWine(["winecfg", "/v", "win11"])
        await runProcess(wineServer, ["-w"], env: wineEnv, log: "prefix.log")
        guard cfg == 0 else { throw LauncherError("Windows 환경을 만들지 못했어요 (winecfg 코드 \(cfg)).") }
        try replace(system32.appendingPathComponent("curl-ca-bundle.crt"), with: caBundle)
        try fm.createDirectory(at: prefix.appendingPathComponent("drive_c/gamesave"), withIntermediateDirectories: true)
    }

    /// Gamepads go through SDL (bundled libSDL2), which knows the Xbox
    /// Bluetooth layout on macOS; raw IOHID reports map buttons wrongly.
    /// Undo the v1 setup that disabled SDL.
    private func configureControllers() async {
        let marker = prefix.appendingPathComponent(".macd2-controllers-v2")
        if fm.fileExists(atPath: marker.path) { return }
        let key = "HKLM\\System\\CurrentControlSet\\Services\\winebus"
        let code = await prefixWine(["reg", "add", key, "/v", "Enable SDL", "/t", "REG_DWORD", "/d", "1", "/f"])
        await prefixWine(["reg", "delete", key, "/v", "DisableInput", "/f"])
        await killWineServer(env: wineEnv, log: "prefix.log")
        if code == 0 { fm.createFile(atPath: marker.path, contents: nil) }
    }

    /// In-game videos are H.264/AAC mp4 played through Media Foundation,
    /// decoded by winegstreamer with the bundled GStreamer (libav). Register
    /// its COM classes in prefixes created before it was bundled, and make
    /// the MF DLLs KnownDLLs: the game restricts its DLL search path
    /// (SetDefaultDllDirectories without System32), so their imports are not
    /// found otherwise.
    private func configureMedia() async {
        let marker = prefix.appendingPathComponent(".macd2-media-v3")
        if fm.fileExists(atPath: marker.path) { return }
        let knownDlls = "HKLM\\System\\CurrentControlSet\\Control\\Session Manager\\KnownDLLs"
        await prefixWine(["reg", "delete", "HKCU\\Software\\Wine\\MediaFoundation", "/v", "DisableGstByteStreamHandler", "/f"])
        var code = await prefixWine(["regsvr32", "/s", "winegstreamer.dll"])
        for name in ["winegstreamer", "winedmo", "mfplat"] where code == 0 {
            code = await prefixWine(["reg", "add", knownDlls, "/v", name, "/t", "REG_SZ", "/d", "\(name).dll", "/f"])
        }
        await killWineServer(env: wineEnv, log: "prefix.log")
        if code == 0 { fm.createFile(atPath: marker.path, contents: nil) }
    }

    /// The prefix keeps copies of builtin DLLs from the Wine that created it.
    /// Refresh the ones this launcher replaces: GameInput (controllers), the
    /// media decoders, and DXMT (d3d11/dxgi on Metal) so runtime updates apply.
    private func syncBuiltins() {
        // the prefix keeps its own copies of these; refresh them from the runtime
        for name in ["gameinput.dll", "winedmo.dll", "winegstreamer.dll",
                     "d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll", "xodus_store_test.dll"] {
            let src = wine.appendingPathComponent("lib/wine/\(winePEDir)/\(name)")
            if fm.fileExists(atPath: src.path) { try? replace(system32.appendingPathComponent(name), with: src) }
        }
    }

    // MARK: - Launch

    private func launch() async throws {
        set("게임 시작 중…")
        let prefixCaBundle = "C:\\windows\\system32\\curl-ca-bundle.crt"
        var env = wineEnv
        env["SSL_CERT_FILE"] = prefixCaBundle
        env["CURL_CA_BUNDLE"] = prefixCaBundle
        env["XODUS_USER_RUNTIME"] = "1"   // Store queries go through the Xodus user runtime
        env["XODUS_MAC_SESSION"] = windowsPath(session)   // XUser from the session file (runtime MacUser.cpp)
        env["XODUS_LOCAL_GAMESAVE"] = "1"
        env["XODUS_LOCAL_GAMESAVE_ROOT"] = "C:\\gamesave"
        env["XODUS_USER_SOCKET_SUFFIX"] = "macd2.sock"
        env["MACD2_VIEW"] = "1"   // decrypted executables live only in a RAM-disk view of the game
        env["MACD2_ICON_MASK"] = resources.appendingPathComponent("dock-mask.png").path  // rounded Dock icon
        if let display = launcherDisplayID() {
            env["MACD2_PRIMARY_DISPLAY"] = String(display)
            appendLog("game.log", "launcher: using display \(display) (the launcher's) as the primary monitor")
        }

        await stopStaleHelpers()
        do {
            try fm.removeItem(atPath: Self.brokerSocket)
        } catch let e as CocoaError where e.code == .fileNoSuchFile {
        } catch {
            throw LauncherError("\(Self.brokerSocket)을 지우지 못했어요. \(error.localizedDescription)")
        }
        var brokerEnv = ProcessInfo.processInfo.environment
        brokerEnv["MACD2_SOCKET"] = "macd2.sock"
        guard let brokerProcess = spawn(broker, [], env: brokerEnv, log: "broker.log") else {
            throw LauncherError("라이선스 도우미(macd2-broker)를 시작하지 못했어요.")
        }
        helpers.append(brokerProcess)
        writePid(brokerProcess, to: brokerPidFile)
        // keeps the session file current and answers the runtime's refresh requests
        if let serve = spawn(cli, ["mac-session", session.path, "--serve"], env: nil, log: "session.log") {
            helpers.append(serve)
            writePid(serve, to: sessionPidFile)
        }
        // wait until the broker accepts connections (up to ~10 s)
        let deadline = Date().addingTimeInterval(10)
        while !Self.socketAccepts(Self.brokerSocket) {
            if !brokerProcess.isRunning || Date() > deadline {
                stopHelpers()
                throw LauncherError("라이선스 도우미(macd2-broker)가 응답하지 않아요.")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        stage = .playing
        gameWindowShown = false
        set("게임을 여는 중…", "게임 창이 뜨기까지 1분쯤 걸릴 수 있어요")
        usedWine = true
        let watchdog = Task { await self.watchGameExit(env: env) }
        let opening = Task { await self.waitForGameWindow() }
        // xodus decrypts the encrypted executable into memory with the
        // account's license on every launch; nothing is written decrypted.
        gameRunning = true
        gameEnv = env
        let code = await runProcess(cli,
                                    ["run", game.path, wineBin.path,
                                     "--exe", "\\Dungeons\\Binaries\\WinGDK\\\(Self.gameExe)",
                                     "--", "-dx11"],
                                    env: env, cwd: gameBinaries, log: "game.log")
        gameRunning = false
        gameEnv = nil
        let stoppedByLauncher = stoppingGame
        stoppingGame = false
        watchdog.cancel()
        opening.cancel()
        let stoppedByWatchdog = await watchdog.value
        appendLog("game.log", "launcher: game process ended with code \(code)\(stoppedByWatchdog ? " after the exit watchdog stopped Wine" : "")")
        await killWineServer(env: env, log: "game.log")
        usedWine = false
        stopHelpers()
        if quitPending {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        // After the watchdog's or the launcher's stop the exit status is not an error.
        if code != 0 && code != 1 && !stoppedByWatchdog && !stoppedByLauncher {
            fail("게임이 비정상 종료됐어요 (코드 \(code)).")
        } else {
            finishRun()
        }
    }

    /// Asks the game to close the way Windows does (taskkill without /f posts
    /// WM_CLOSE to its windows), and stops Wine only if the game is still
    /// running after 20 s. launch() continues when the game process ends.
    func stopGame() {
        guard gameRunning, !stoppingGame, let env = gameEnv else { return }
        stoppingGame = true
        set("게임 종료 중…", "게임에 종료 신호를 보냈어요")
        Task {
            appendLog("game.log", "launcher: asking the game to close (WM_CLOSE)")
            await runProcess(wineBin, ["taskkill", "/im", Self.gameExe], env: env, log: "game.log")
            let deadline = Date().addingTimeInterval(20)
            while gameRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 250_000_000) }
            if gameRunning {
                appendLog("game.log", "launcher: the game did not close within 20 s; stopping Wine")
                await killWineServer(env: env, log: "game.log")
            }
        }
    }

    /// Quitting the app while playing: close the game first, then let AppKit
    /// finish quitting (applicationShouldTerminate returned .terminateLater).
    func quitAfterGame() {
        quitPending = true
        stopGame()
    }

    /// The game opens, and goes fullscreen, on Windows' primary monitor, which
    /// Wine maps to the macOS menu-bar display. To use the display the launcher
    /// window (or Minecraft Launcher's) is on instead, hand its CGDirectDisplayID to winemac
    /// (MACD2_PRIMARY_DISPLAY, mac/patches/winemac-primary-display.patch),
    /// which then reports that display as primary. nil when it already is.
    private func launcherDisplayID() -> CGDirectDisplayID? {
        guard let primary = NSScreen.screens.first,
              // started from Minecraft Launcher (no window): the display it is on
              let screen = NSApp.windows.first(where: { $0.isVisible })?.screen ?? MCLauncherLink.minecraftLauncherScreen(),
              screen != primary,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// The game hangs after quitting from its menu: its window stays (hidden)
    /// and one game thread keeps the process alive. Measured: ~100-130 Wine
    /// threads while playing, 8 after the game shut down, with its windows
    /// still listed but none on screen. Stop the Wine session only when, after
    /// the game has run, the thread count stays low for 3 s AND none of its
    /// windows is on screen. A sample that can't be read counts as "unknown",
    /// never as low. Every decision that stops Wine is written to game.log.
    /// Returns true when it stopped the Wine session itself.
    private func watchGameExit(env: [String: String]) async -> Bool {
        let runningThreads: Int32 = 60, exitedThreads: Int32 = 12, holdSeconds = 3.0
        // only Wine's own processes; `macd2 run` matches the pattern too.
        // Both sides resolved: app translocation, /var -> /private/var.
        let wineDir = Self.realPath(wine.path) + "/"
        var started = false
        var lowSince: Date? = nil
        var lowSamples = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { break }
            let found = await execute(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-f", Self.gameExe],
                                      log: "tools.log", captureOutput: true)
            let pids = String(decoding: found.output, as: UTF8.self)
                .split(separator: "\n").compactMap { Int32($0) }
                .filter { Self.realPath(executablePath($0)).hasPrefix(wineDir) }
            if found.code == 1 && pids.isEmpty { return false }   // pgrep: no game process left
            let counts = pids.compactMap(threadCount)
            guard let threads = counts.max() else { lowSince = nil; lowSamples = 0; continue }  // unknown
            if threads >= runningThreads { started = true; lowSince = nil; lowSamples = 0; continue }
            guard started, threads <= exitedThreads else { lowSince = nil; lowSamples = 0; continue }
            let onScreen = onScreenWindows(of: Set(pids))
            guard onScreen == 0 else { lowSince = nil; lowSamples = 0; continue }
            lowSamples += 1
            guard let since = lowSince else { lowSince = Date(); continue }
            let held = Date().timeIntervalSince(since)
            if held >= holdSeconds && lowSamples >= 6 {
                appendLog("game.log", "launcher: game exit detected (threads=\(threads), low for \(String(format: "%.1f", held))s, \(lowSamples) samples, on-screen windows=0); stopping Wine")
                await killWineServer(env: env, log: "game.log")
                return true
            }
        }
        return false
    }

    /// Game windows currently on screen (not just listed: a hung, finished
    /// game keeps hidden windows around).
    /// Until the game's window is on screen the launch looks stalled: the
    /// window says the game is opening, then that it is running.
    private func waitForGameWindow() async {
        let wineDir = Self.realPath(wine.path) + "/"
        while !Task.isCancelled, !gameWindowShown {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let found = await execute(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-f", Self.gameExe],
                                      log: "tools.log", captureOutput: true)
            let pids = String(decoding: found.output, as: UTF8.self)
                .split(separator: "\n").compactMap { Int32($0) }
                .filter { Self.realPath(executablePath($0)).hasPrefix(wineDir) }
            if !Task.isCancelled, stage == .playing, onScreenWindows(of: Set(pids)) > 0 {
                gameWindowShown = true
                set("게임 실행 중", "게임을 끄면 런처도 함께 정리돼요")
            }
        }
    }

    private func onScreenWindows(of pids: Set<Int32>) -> Int {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        return windows.filter { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid) else { return false }
            return ((w[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > 200
        }.count
    }


    private func appendLog(_ name: String, _ line: String) {
        guard let h = logHandle(name) else { return }
        h.write(Data((line + "\n").utf8))
        try? h.close()
    }

    private func executablePath(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    /// nil when the process can't be read (exiting, transient failure).
    private func threadCount(_ pid: Int32) -> Int32? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info.pti_threadnum : nil
    }

    func stopHelpers() {
        for p in helpers where p.isRunning { p.terminate() }
        helpers.removeAll()
        try? fm.removeItem(at: brokerPidFile)
        try? fm.removeItem(at: sessionPidFile)
    }

    /// App is quitting: stop Wine (if it may be running) before its helpers,
    /// then every remaining child process.
    func shutdown() {
        if usedWine {
            let p = makeProcess(wineServer, ["-k"], env: wineEnv)
            let h = logHandle("game.log") ?? FileHandle.nullDevice
            p.standardOutput = h
            p.standardError = h
            if (try? p.run()) != nil {
                let deadline = Date().addingTimeInterval(5)
                while p.isRunning && Date() < deadline { usleep(50_000) }
                if p.isRunning { p.terminate() }
            }
            usedWine = false
        }
        stopHelpers()
        ChildProcesses.shared.terminateAll()
    }

    nonisolated static func realPath(_ path: String) -> String {
        guard !path.isEmpty, let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when a Unix socket at `path` accepts a connection.
    nonisolated static func socketAccepts(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        addr.sun_len = UInt8(len)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        } == 0
    }

    // MARK: - Process helpers

    private func logHandle(_ name: String) -> FileHandle? {
        let url = logs.appendingPathComponent(name)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }

    private func makeProcess(_ exe: URL, _ args: [String], env: [String: String]? = nil, cwd: URL? = nil) -> Process {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        if let env { p.environment = env }
        if let cwd { p.currentDirectoryURL = cwd }
        p.qualityOfService = .userInitiated
        return p
    }

    private func spawn(_ exe: URL, _ args: [String], env: [String: String]?, log: String) -> Process? {
        let p = makeProcess(exe, args, env: env)
        let h = logHandle(log) ?? FileHandle.nullDevice
        p.standardOutput = h
        p.standardError = h
        p.terminationHandler = { ChildProcesses.shared.remove($0) }
        ChildProcesses.shared.add(p)
        do { try p.run(); return p } catch { ChildProcesses.shared.remove(p); return nil }
    }

    /// Runs a process to completion, appending stderr (and stdout) to the
    /// named log. With `onLine`, stdout is also delivered line by line.
    @discardableResult
    private func runProcess(_ exe: URL, _ args: [String], env: [String: String]? = nil, cwd: URL? = nil,
                            log: String, onLine: (@MainActor @Sendable (String) -> Void)? = nil) async -> Int32 {
        await execute(exe, args, env: env, cwd: cwd, log: log, onLine: onLine).code
    }

    /// Runs a process without blocking the main actor. stderr goes to the log;
    /// stdout goes to the log, or through a pipe that is read off the main
    /// thread (`captureOutput` keeps it, `onLine` gets each line on the main
    /// actor). Returns after both the exit and the end of stdout, so no line
    /// arrives after the caller moved on. `timeout` terminates the process.
    private func execute(_ exe: URL, _ args: [String], env: [String: String]? = nil, cwd: URL? = nil,
                         log: String, captureOutput: Bool = false, timeout: TimeInterval? = nil,
                         onLine: (@MainActor @Sendable (String) -> Void)? = nil,
                         onStart: ((Process) -> Void)? = nil) async -> ProcessResult {
        let p = makeProcess(exe, args, env: env, cwd: cwd)
        onStart?(p)
        let h = logHandle(log)
        p.standardError = h ?? FileHandle.nullDevice
        let pipe: Pipe? = (captureOutput || onLine != nil) ? Pipe() : nil
        p.standardOutput = pipe ?? h ?? FileHandle.nullDevice
        let run = ChildRun(process: p, pipe: pipe, copyTo: onLine != nil ? h : nil,
                           keepOutput: captureOutput, onLine: onLine)
        return await withCheckedContinuation { cont in run.start(timeout: timeout, cont) }
    }

    private func captureData(_ exe: String, _ args: [String]) async throws -> Data {
        let tool = URL(fileURLWithPath: exe)
        let result = await execute(tool, args, log: "tools.log", captureOutput: true)
        guard result.code == 0 else { throw LauncherError("\(tool.lastPathComponent) 실패") }
        return result.output
    }

    private func capture(_ exe: String, _ args: [String]) async throws -> String {
        String(decoding: try await captureData(exe, args), as: UTF8.self)
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Network or service unavailable: shown as "check your connection" with retry.
struct OfflineError: Error {}
/// The game download was paused or cancelled by the user.
struct DownloadStopped: Error { let cancelled: Bool }

struct LauncherError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Splits a byte stream into lines; used only from one readability handler.
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            lines.append(String(decoding: data[data.startIndex..<nl], as: UTF8.self))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }
    /// The unterminated rest of the stream, if any.
    func flush() -> String? {
        defer { data.removeAll() }
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}

struct ProcessResult: Sendable {
    var code: Int32
    var output: Data
    var timedOut: Bool
}

/// Every child process the launcher starts, so quitting can stop them all.
final class ChildProcesses: @unchecked Sendable {
    static let shared = ChildProcesses()
    private let lock = NSLock()
    private var running: [ObjectIdentifier: Process] = [:]

    func add(_ p: Process) { lock.withLock { running[ObjectIdentifier(p)] = p } }
    func remove(_ p: Process) { lock.withLock { running[ObjectIdentifier(p)] = nil } }
    func terminateAll() {
        let all = lock.withLock { Array(running.values) }
        for p in all where p.isRunning { p.terminate() }
    }
}

/// One child run: waits for both the exit and EOF on stdout, then resumes the
/// caller on the main queue, after every line it already delivered there.
final class ChildRun: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let pipe: Pipe?
    private let copyTo: FileHandle?
    private let keepOutput: Bool
    private let onLine: (@MainActor @Sendable (String) -> Void)?
    private let lines = LineBuffer()
    private var cont: CheckedContinuation<ProcessResult, Never>?
    private var output = Data()
    private var exited = false, eof = false, timedOut = false
    private var status: Int32 = -1

    init(process: Process, pipe: Pipe?, copyTo: FileHandle?, keepOutput: Bool,
         onLine: (@MainActor @Sendable (String) -> Void)?) {
        self.process = process
        self.pipe = pipe
        self.copyTo = copyTo
        self.keepOutput = keepOutput
        self.onLine = onLine
    }

    func start(timeout: TimeInterval?, _ cont: CheckedContinuation<ProcessResult, Never>) {
        self.cont = cont
        if let pipe {
            pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty { endOfOutput() } else { consume(chunk) }
            }
        } else {
            eof = true
        }
        process.terminationHandler = { [self] p in processExited(p.terminationStatus) }
        ChildProcesses.shared.add(process)
        do {
            try process.run()
        } catch {
            ChildProcesses.shared.remove(process)
            process.terminationHandler = nil
            lock.withLock { status = -1; exited = true }
            endOfOutput()
            return
        }
        if let timeout {
            let p = process
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                guard p.isRunning else { return }
                lock.withLock { timedOut = true }
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                }
            }
        }
    }

    private func consume(_ chunk: Data) {
        lock.withLock {
            guard !eof else { return }
            copyTo?.write(chunk)
            if keepOutput { output.append(chunk) }
            if let onLine {
                for line in lines.append(chunk) {
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                }
            }
        }
    }

    private func processExited(_ code: Int32) {
        ChildProcesses.shared.remove(process)
        lock.withLock { status = code; exited = true }
        // A grandchild that inherited stdout can keep the pipe open; don't wait for it forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in endOfOutput() }
        finishIfDone()
    }

    private func endOfOutput() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        lock.withLock {
            guard !eof else { return }
            eof = true
            if let onLine, let rest = lines.flush() {
                DispatchQueue.main.async { MainActor.assumeIsolated { onLine(rest) } }
            }
        }
        finishIfDone()
    }

    private func finishIfDone() {
        lock.withLock {
            guard exited, eof, let c = cont else { return }
            cont = nil
            process.terminationHandler = nil
            let result = ProcessResult(code: status, output: output, timedOut: timedOut)
            DispatchQueue.main.async { c.resume(returning: result) }
        }
    }
}
