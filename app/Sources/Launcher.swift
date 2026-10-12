// M(a)C Dungeons II launcher: sign-in, runtime dependencies, game download and
// updates, prefix setup, then the game. Everything the user owns (game files,
// prefix, saves, session) lives in ~/Library/Application Support/M(a)C Dungeons II.
import Foundation
import AppKit
import CryptoKit

@MainActor
final class Launcher: ObservableObject {
    enum Stage: Equatable {
        case idle, working, needsConsent, needsLogin, playing, failed
    }

    @Published var stage: Stage = .idle
    @Published var status = "준비 중…"
    @Published var detail = ""
    @Published var progress: Double? = nil

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

    private var helpers: [Process] = []
    private var lastSample: (Date, Double)? = nil
    private var speed: Double = 0

    // MARK: - Flow

    func start() {
        Task { await run() }
    }

    func acceptLicense() {
        try? Data("accepted \(Date())\n".utf8).write(to: licenseMarker)
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

            set("Microsoft 계정 확인 중…")
            let sessionCode = await runProcess(cli, ["mac-session", session.path], log: "session.log")
            if sessionCode != 0 {
                stage = .needsLogin
                set("Microsoft 계정으로 로그인해 주세요",
                    "게임을 구매한 계정으로 로그인하면, 게임을 내려받고 실행할 수 있어요.")
                return
            }

            if !fm.fileExists(atPath: licenseMarker.path) {
                stage = .needsConsent
                set("Microsoft GDK 라이선스 동의가 필요해요",
                    "게임이 쓰는 Xbox 런타임(Microsoft GDK)을 Microsoft에서 직접 내려받아요.")
                return
            }
            try await ensureDependencies()
            try await ensureGame()
            try overlayLayer()
            try await ensurePrefix()
            try await launch()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func set(_ s: String, _ d: String = "", _ p: Double? = nil) {
        status = s; detail = d; progress = p
    }

    private func fail(_ message: String) {
        stage = .failed
        set("문제가 생겼어요", message + "\n로그: \(logs.path)")
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
                ("native/260404/windows/bin/x64/xgameruntime.thunks.dll", "xgameruntime-adapter-thunks.dll",
                 "862236063d4872f43435384eb4030dfa4b1fb6fbe91fe93969557de18c5f9601"),
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

    private func ensureDependencies() async throws {
        for dep in dependencies {
            let pinned = dep.members.filter { !$0.sha256.isEmpty }
            if pinned.allSatisfy({ (try? sha256(deps.appendingPathComponent($0.name))) == $0.sha256 }) { continue }
            let source = URL(string: dep.url)!
            let name = source.lastPathComponent
            set("런타임 내려받는 중… (\(name))", "출처: \(source.host ?? "")", 0)
            let archive = deps.appendingPathComponent(name)
            try await download(source, to: archive)
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
            try? fm.removeItem(at: archive)
        }
    }

    private func download(_ url: URL, to target: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: nil)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LauncherError("내려받기 실패: \(url.absoluteString)") }
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
        let info = try await capture(cli.path, ["package-info", Self.productId])
        guard let line = info.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let latest = json["version"] as? String else {
            if installed != nil && fm.fileExists(atPath: gameBinaries.path) { return } // offline: play installed copy
            throw LauncherError("게임 버전 정보를 받지 못했어요. 인터넷 연결을 확인해 주세요.")
        }
        if installed == latest && fm.fileExists(atPath: gameBinaries.appendingPathComponent(Self.gameExe).path) {
            return
        }
        let staging = data.appendingPathComponent("game.new")
        try? fm.removeItem(at: staging)
        set(installed == nil ? "게임 내려받는 중…" : "업데이트 내려받는 중… (\(latest))", "Microsoft에서 \(latest) 버전을 받고 있어요", 0)
        var fetchEnv = ProcessInfo.processInfo.environment
        fetchEnv["MACD2_PROGRESS_JSON"] = "1"
        let code = await runProcess(cli, ["mac-fetch", Self.productId, data.appendingPathComponent("downloads").path, staging.path],
                                    env: fetchEnv, log: "fetch.log", onLine: { [weak self] line in self?.fetchProgress(line) })
        guard code == 0 else { throw LauncherError("게임을 내려받지 못했어요 (코드 \(code)). 다시 실행하면 이어서 받아요.") }
        if fm.fileExists(atPath: game.path) {
            let old = data.appendingPathComponent("game.old")
            try? fm.removeItem(at: old)
            try fm.moveItem(at: game, to: old)
            try fm.moveItem(at: staging, to: game)
            try? fm.removeItem(at: old)
        } else {
            try fm.moveItem(at: staging, to: game)
        }
        try JSONSerialization.data(withJSONObject: ["version": latest]).write(to: stateFile)
    }

    private func fetchProgress(_ line: String) {
        guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        switch j["phase"] as? String {
        case "download":
            if let done = j["done"] as? Double, let total = j["total"] as? Double, total > 0 {
                progress = done / total
                let now = Date()
                if let (t0, d0) = lastSample, now.timeIntervalSince(t0) >= 1 {
                    let rate = (done - d0) / now.timeIntervalSince(t0)
                    speed = speed == 0 ? rate : speed * 0.8 + rate * 0.2   // smoothed bytes/s
                    lastSample = (now, done)
                } else if lastSample == nil {
                    lastSample = (now, done)
                }
                var text = String(format: "%.1f / %.1f GB", done / 1e9, total / 1e9)
                if speed > 0 {
                    text += String(format: " · %.1f MB/s", speed / 1e6)
                    let left = Int((total - done) / speed)
                    text += left >= 60 ? " · 약 \(left / 60)분 남음" : " · 1분 이내"
                }
                detail = text
            }
        case "extract":
            status = "게임 설치 중…"
            if let done = j["done"] as? Double, let total = j["total"] as? Double, total > 0 {
                progress = min(done / total, 1)
                detail = String(format: "%.1f / %.1f GB · 계정 라이선스로 패키지를 풀고 있어요", done / 1e9, total / 1e9)
            } else {
                detail = "계정 라이선스로 패키지를 풀고 있어요"; progress = nil
            }
        default: break
        }
    }

    // MARK: - Compatibility layer in the game folder

    private func overlayLayer() throws {
        let sources =
            ["xgameruntime.dll", "xgameruntime-native.dll", "XCurl.dll"].map { layer.appendingPathComponent($0) } +
            ["xgameruntime_original.dll", "xgameruntime-adapter-thunks.dll", "curl-compat.dll", "curl-ca-bundle.crt"]
                .map { deps.appendingPathComponent($0) }
        for src in sources { try replace(gameBinaries.appendingPathComponent(src.lastPathComponent), with: src) }
        for base in [gameBinaries, gameBinaries.deletingLastPathComponent()] {
            let certs = base.appendingPathComponent("etc/ssl/certs")
            try fm.createDirectory(at: certs, withIntermediateDirectories: true)
            try replace(certs.appendingPathComponent("ca-bundle.crt"), with: caBundle)
        }
        // The adapter finds its data folder (session.bin, logs) through this sidecar.
        try Data(windowsPath(session).utf8).write(to: gameBinaries.appendingPathComponent("dungeons-crossover.ini"))
    }

    private func replace(_ target: URL, with source: URL) throws {
        try? fm.removeItem(at: target)
        try fm.copyItem(at: source, to: target)
    }

    private func windowsPath(_ url: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }

    // MARK: - Wine prefix

    private var wineEnv: [String: String] {
        var env = ProcessInfo.processInfo.environment
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
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml=;msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1=n,b;xgameruntime,xcurl=n"
        return env
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
        if isNew { try await createPrefix() }
        syncBuiltins()
        await configureControllers()
        await configureMedia()
        if isNew { try Data().write(to: marker) }
    }

    private func createPrefix() async throws {
        set("처음 실행 준비 중… (Windows 환경 만들기)", "1~2분 걸려요")
        await prefixWine(["wineboot", "-i"])
        await runProcess(wineServer, ["-w"], env: wineEnv, log: "prefix.log")
        await prefixWine(["winecfg", "/v", "win11"])
        await runProcess(wineServer, ["-w"], env: wineEnv, log: "prefix.log")
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
    /// Refresh the ones this launcher replaces (full GameInput for controllers).
    private func syncBuiltins() {
        for name in ["gameinput.dll", "winedmo.dll", "winegstreamer.dll"] {
            let src = wine.appendingPathComponent("lib/wine/x86_64-windows/\(name)")
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
        env["XODUS_USER_RUNTIME"] = "1"
        env["XODUS_LOCAL_GAMESAVE"] = "1"
        env["XODUS_LOCAL_GAMESAVE_ROOT"] = "C:\\gamesave"
        env["XODUS_USER_SOCKET_SUFFIX"] = "macd2.sock"
        env["MACD2_VIEW"] = "1"   // decrypted executables live only in a RAM-disk view of the game
        env["MACD2_ICON_MASK"] = resources.appendingPathComponent("dock-mask.png").path  // rounded Dock icon

        await runProcess(URL(fileURLWithPath: "/usr/bin/pkill"), ["-f", broker.path], log: "broker.log")
        try? fm.removeItem(atPath: "/tmp/macd2.sock")
        var brokerEnv = ProcessInfo.processInfo.environment
        brokerEnv["MACD2_SOCKET"] = "macd2.sock"
        helpers = [
            spawn(broker, [], env: brokerEnv, log: "broker.log"),
            spawn(cli, ["mac-session", session.path, "--serve"], env: nil, log: "session.log"),
        ].compactMap { $0 }
        try await Task.sleep(nanoseconds: 1_500_000_000)

        stage = .playing
        set("게임 실행 중", "게임을 끄면 런처도 함께 정리돼요")
        let watchdog = Task { await self.watchGameExit(env: env) }
        defer { watchdog.cancel() }
        // xodus decrypts the encrypted executable into memory with the
        // account's license on every launch; nothing is written decrypted.
        let code = await runProcess(cli,
                                    ["run", game.path, wineBin.path,
                                     "--exe", "\\Dungeons\\Binaries\\WinGDK\\\(Self.gameExe)",
                                     "--", "-dx11"],
                                    env: env, cwd: gameBinaries, log: "game.log")
        await killWineServer(env: env, log: "game.log")
        stopHelpers()
        if code != 0 && code != 1 {
            fail("게임이 비정상 종료됐어요 (코드 \(code)).")
        } else {
            NSApp.terminate(nil)
        }
    }

    /// The game hangs after quitting from its menu: its window stays (hidden)
    /// and one game thread keeps the process alive. Window state is not a
    /// reliable signal (windows stay listed after exit, and leave the screen
    /// during fullscreen/resize), so watch the Wine process's thread count:
    /// ~100+ while running, under 10 once the game has shut down. Once it has
    /// run and then stays low for a second, stop the Wine session.
    private func watchGameExit(env: [String: String]) async {
        let runningThreads: Int32 = 60, exitedThreads: Int32 = 12
        // only Wine's own processes; `macd2 run` matches the pattern too
        let wineDir = wine.path + "/"
        var started = false
        var lowSince: Date? = nil
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let pids = (try? await capture("/usr/bin/pgrep", ["-f", Self.gameExe]))?
                .split(separator: "\n").compactMap { Int32($0) } ?? []
            if pids.isEmpty { return }
            let threads = pids.filter { executablePath($0).hasPrefix(wineDir) }.map(threadCount).max() ?? 0
            if threads >= runningThreads { started = true; lowSince = nil; continue }
            guard started, threads <= exitedThreads else { lowSince = nil; continue }
            guard let since = lowSince else { lowSince = Date(); continue }
            if Date().timeIntervalSince(since) >= 1 {
                await killWineServer(env: env, log: "game.log")
                return
            }
        }
    }

    private func executablePath(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    private func threadCount(_ pid: Int32) -> Int32 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info.pti_threadnum : 0
    }

    func stopHelpers() {
        for p in helpers where p.isRunning { p.terminate() }
        helpers.removeAll()
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
        return p
    }

    private func spawn(_ exe: URL, _ args: [String], env: [String: String]?, log: String) -> Process? {
        let p = makeProcess(exe, args, env: env)
        let h = logHandle(log)
        p.standardOutput = h
        p.standardError = h
        do { try p.run(); return p } catch { return nil }
    }

    /// Runs a process to completion, appending stderr (and stdout) to the
    /// named log. With `onLine`, stdout is also delivered line by line.
    @discardableResult
    private func runProcess(_ exe: URL, _ args: [String], env: [String: String]? = nil, cwd: URL? = nil,
                            log: String, onLine: (@MainActor (String) -> Void)? = nil) async -> Int32 {
        let p = makeProcess(exe, args, env: env, cwd: cwd)
        let h = logHandle(log)
        p.standardError = h
        if let onLine {
            let pipe = Pipe()
            p.standardOutput = pipe
            let buffer = LineBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                h?.write(chunk)
                for line in buffer.append(chunk) {
                    Task { @MainActor in onLine(line) }
                }
            }
        } else {
            p.standardOutput = h
        }
        return await withCheckedContinuation { cont in
            p.terminationHandler = { proc in cont.resume(returning: proc.terminationStatus) }
            do { try p.run() } catch { cont.resume(returning: -1) }
        }
    }

    private func captureData(_ exe: String, _ args: [String]) async throws -> Data {
        let tool = URL(fileURLWithPath: exe)
        let p = makeProcess(tool, args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = logHandle("tools.log")
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw LauncherError("\(tool.lastPathComponent) 실패") }
        return data
    }

    private func capture(_ exe: String, _ args: [String]) async throws -> String {
        String(decoding: try await captureData(exe, args), as: UTF8.self)
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}

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
}
