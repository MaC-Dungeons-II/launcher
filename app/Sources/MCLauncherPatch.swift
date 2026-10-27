// Optional: play Dungeons II from the Minecraft Launcher too. Turning it on
// patches the launcher's UI (ui.zip, Dungeons II only; edits in
// Resources/mclauncher/patch.json, injected code in mclauncher-link.js) and
// installs a per-user LaunchAgent: launchd listens on 127.0.0.1:47821 and runs
// Resources/mclauncher/agent-handler.sh per request, which opens this app on
// Play (only for the launcher page, Origin https://mojang). The launcher puts
// its own ui.zip back when it updates, so while the link is on the app
// re-applies the patch on every start. Writing into the launcher's bundle
// needs macOS App Management permission, which macOS asks for the first time.
import AppKit
import Foundation

@MainActor
final class MCLauncherPatch: ObservableObject {
    enum State: Equatable {
        case notInstalled          // no Minecraft Launcher on this Mac
        case off, on
        case failed(String)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var busy = false

    static let port = 47821
    private static let enabledKey = "mclauncher.link"
    private static let label = "io.github.mac-dungeons-ii.link"

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var mc: URL { home.appendingPathComponent("Library/Application Support/minecraft") }
    private var ui: URL { mc.appendingPathComponent("launcher/launcher.bundle/Contents/Resources/ui.zip") }
    /// The launcher's own ui.zip, kept to undo the patch.
    private var backup: URL { mc.appendingPathComponent("macd2-ui.zip.orig") }
    private var agent: URL { home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist") }
    private let handler: URL
    private var resources: URL { Bundle.main.resourceURL!.appendingPathComponent("mclauncher") }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    init() {
        // in the app's data folder (Launcher.data), which the handler reads to
        // tell whether the game is installed
        handler = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/M(a)C Dungeons II/mclauncher-link.sh")
        refresh()
    }

    func refresh() {
        guard fm.fileExists(atPath: ui.path) else { state = .notInstalled; return }
        if case .failed = state, enabled { return }
        state = enabled ? .on : .off
    }

    /// While the link is on: re-patch a launcher that updated, and keep the
    /// agent's handler current. Quiet; a failure shows in `state`.
    func keepApplied() async {
        guard enabled, fm.fileExists(atPath: ui.path) else { refresh(); return }
        await run { try await self.apply() }
    }

    func turnOn() async {
        await run {
            try await self.apply()
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
    }

    func turnOff() async {
        await run {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            await self.removeAgent()
            if self.fm.fileExists(atPath: self.ui.path), try await self.isPatched(),
               self.fm.fileExists(atPath: self.backup.path) {
                try self.writeIntoLauncher(try Data(contentsOf: self.backup))
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            state = enabled ? .on : .off
            if !fm.fileExists(atPath: ui.path) { state = .notInstalled }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Patch

    private struct Patch: Decodable {
        struct Edit: Decodable { let find: String; let replace: String; var regex: Bool? }
        struct Group: Decodable { let name: String; let requireAll: Bool; let edits: [Edit] }
        let marker: String
        let mainBundle: String
        let minFiles: Int
        let groups: [Group]
    }

    private func apply() async throws {
        guard fm.fileExists(atPath: ui.path) else { throw LinkError("Minecraft Launcher가 설치돼 있지 않아요.") }
        let patch = try JSONDecoder().decode(Patch.self, from: Data(contentsOf: resources.appendingPathComponent("patch.json")))
        if try await !isPatched(patch.marker) {
            // the launcher's own (new after each of its updates)
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: ui, to: backup)
        } else if !fm.fileExists(atPath: backup.path) {
            throw LinkError("Minecraft Launcher 화면 파일이 이미 바뀌어 있는데 원본 백업이 없어요.")
        }
        try installAgent()

        let work = fm.temporaryDirectory.appendingPathComponent("macd2-mclauncher-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try await tool("/usr/bin/unzip", ["-q", backup.path, "launcher/static/js/*.js", "-d", work.path])

        let script = try String(contentsOf: resources.appendingPathComponent("mclauncher-link.js"), encoding: .utf8)
            .replacingOccurrences(of: "__PORT__", with: String(Self.port))
        let jsDir = work.appendingPathComponent("launcher/static/js")
        var changed: [String] = []
        for name in try fm.contentsOfDirectory(atPath: jsDir.path).sorted()
        where name.hasSuffix(".js") && !name.contains("launcher-language") {
            let file = jsDir.appendingPathComponent(name)
            let text = try String(contentsOf: file, encoding: .utf8)
            var out = text
            for group in patch.groups { out = Self.apply(group, to: out) }
            guard out != text else { continue }
            let main = "/js/\(name)".contains(patch.mainBundle)
            out = (main ? patch.marker + script + "\n" : patch.marker) + out
            try out.write(to: file, atomically: true, encoding: .utf8)
            changed.append("launcher/static/js/\(name)")
        }
        guard changed.contains(where: { "/\($0)".contains(patch.mainBundle) }), changed.count >= patch.minFiles else {
            throw LinkError("이 버전의 Minecraft Launcher 화면에는 아직 맞지 않아요. 앱 업데이트를 기다려 주세요.")
        }
        let zip = work.appendingPathComponent("ui.zip")
        try fm.copyItem(at: backup, to: zip)
        try await tool("/usr/bin/zip", ["-q", zip.path] + changed, cwd: work)
        try writeIntoLauncher(try Data(contentsOf: zip))
    }

    private static func apply(_ group: Patch.Group, to text: String) -> String {
        func found(_ e: Patch.Edit) -> Bool {
            if e.regex == true {
                return (try? NSRegularExpression(pattern: e.find))?
                    .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
            return text.contains(e.find)
        }
        if group.requireAll && !group.edits.allSatisfy(found) { return text }
        var out = text
        for e in group.edits where found(e) {
            if e.regex == true, let re = try? NSRegularExpression(pattern: e.find) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: e.replace)
            } else if let r = out.range(of: e.find) {
                out.replaceSubrange(r, with: e.replace)
            }
        }
        return out
    }

    /// Whether the launcher's current ui.zip carries the patch (its main
    /// bundle starts with the marker).
    private func isPatched(_ marker: String? = nil) async throws -> Bool {
        let marker = try marker ?? JSONDecoder().decode(Patch.self, from: Data(contentsOf: resources.appendingPathComponent("patch.json"))).marker
        let names = String(decoding: try await tool("/usr/bin/unzip", ["-Z1", ui.path]), as: UTF8.self)
        guard let main = names.split(separator: "\n").first(where: { $0.range(of: #"/js/app\.[0-9a-f]+\.bundle\.js$"#, options: .regularExpression) != nil })
        else { return false }
        let head = try await tool("/usr/bin/unzip", ["-p", ui.path, String(main)]).prefix(marker.utf8.count)
        return String(decoding: head, as: UTF8.self) == marker
    }

    /// Writes ui.zip in place. macOS asks the user to allow this app to modify
    /// apps (App Management) the first time; refused, the write fails.
    private func writeIntoLauncher(_ data: Data) throws {
        do {
            let h = try FileHandle(forWritingTo: ui)
            defer { try? h.close() }
            try h.truncate(atOffset: 0)
            try h.write(contentsOf: data)
        } catch {
            throw LinkError("Minecraft Launcher를 바꿀 권한이 없어요. 시스템 설정 › 개인정보 보호 및 보안 › 앱 관리에서 M(a)C Dungeons II를 켜고 다시 시도해 주세요.")
        }
    }

    // MARK: - LaunchAgent

    private func installAgent() throws {
        try fm.createDirectory(at: handler.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: resources.appendingPathComponent("agent-handler.sh")).write(to: handler, options: .atomic)
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/bin/zsh", handler.path],
            "inetdCompatibility": ["Wait": false],
            "Sockets": ["Listener": ["SockNodeName": "127.0.0.1", "SockServiceName": String(Self.port), "SockType": "stream"]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let current = try? Data(contentsOf: agent)
        if current == data, launchctl(["print", "gui/\(getuid())/\(Self.label)"]) == 0 { return }
        try fm.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agent, options: .atomic)
        launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        guard launchctl(["bootstrap", "gui/\(getuid())", agent.path]) == 0 else {
            throw LinkError("Minecraft Launcher 연결용 백그라운드 항목을 등록하지 못했어요.")
        }
    }

    private func removeAgent() async {
        launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        try? fm.removeItem(at: agent)
        try? fm.removeItem(at: handler)
    }

    @discardableResult
    private func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Runs a system tool off the main thread; returns stdout, throws on failure.
    @discardableResult
    private func tool(_ path: String, _ args: [String], cwd: URL? = nil) async throws -> Data {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw LinkError("\(URL(fileURLWithPath: path).lastPathComponent) 실패 (\(p.terminationStatus))")
            }
            return data
        }.value
    }
}

struct LinkError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
