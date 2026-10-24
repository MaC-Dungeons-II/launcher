import AppKit
import CryptoKit
import WebKit

/// wasdmod's key layout editor (Keybinder.html) in a window of its own, with
/// the host functions the page uses when an app serves it (window.wasdmodHost,
/// described at the top of the page): the editor's saved state, saving a
/// layout into the launcher's layout folder, exporting a file, and reading and
/// changing the game's own keyboard settings (see controlsStore), which is
/// what its "change the in-game controls" button needs.
@MainActor
final class KeyEditor: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, NSWindowDelegate {
    private unowned let launcher: Launcher
    private var window: NSWindow?
    private var web: WKWebView?
    private let fm = FileManager.default

    init(launcher: Launcher) {
        self.launcher = launcher
    }

    private var storeFile: URL { launcher.wasdData.appendingPathComponent("editor.json") }
    private var page: URL { launcher.wasdBundle.appendingPathComponent("Keybinder.html") }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        launcher.refreshWasdLayouts()
        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "wasdmod")
        config.userContentController.addUserScript(WKUserScript(source: hostScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "키 배치 편집기 (wasdmod)"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.web = web
        self.window = window
        web.loadFileURL(page, allowingReadAccessTo: launcher.wasdBundle)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        // the content controller holds this object: let both go
        web?.configuration.userContentController.removeAllScriptMessageHandlers()
        web = nil
        window = nil
    }

    // MARK: - window.wasdmodHost

    private func hostScript() -> String {
        let store = (try? Data(contentsOf: storeFile)) ?? Data("{}".utf8)
        let layout = launcher.wasdLayout
        var game = Data("null".utf8)
        if let text = try? String(contentsOf: launcher.wasdData.appendingPathComponent(layout), encoding: .utf8),
           let json = try? JSONSerialization.data(withJSONObject: ["file": layout, "text": text]) { game = json }
        let lang = UserDefaults.standard.string(forKey: "wasdmod.lang") ?? Locale.preferredLanguages.first ?? "en"
        let langJSON = (try? JSONSerialization.data(withJSONObject: [lang])).map { String(decoding: $0, as: UTF8.self) } ?? "[\"en\"]"
        return """
        window.wasdmodHost = (() => {
          const fromB64 = b => JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))));
          let store = {};
          try { store = fromB64("\(store.base64EncodedString())") || {}; } catch (e) {}
          const post = m => window.webkit.messageHandlers.wasdmod.postMessage(m);
          return {
            store,
            lang: \(langJSON)[0],
            app: "mac",
            game: fromB64("\(game.base64EncodedString())"),
            set(k, v) { store[k] = v; post({ cmd: "store", value: JSON.stringify(store) }); },
            setLang(code) { post({ cmd: "lang", value: code }); },
            gameControls() { return post({ cmd: "controls" }); },
            waitGameControls(stamp) { return post({ cmd: "controls-wait", stamp }); },
            writeGameControls(data) { return post({ cmd: "controls-write", data }); },
            save(name, text) { return post({ cmd: "save", name, text }); },
            exportFile(name, text) { return post({ cmd: "export", name, text }); }
          };
        })();
        """
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return (nil, "Unknown request.") }
        switch cmd {
        case "store":
            guard let value = body["value"] as? String, value.utf8.count < 2 << 20 else { return (nil, nil) }
            try? fm.createDirectory(at: launcher.wasdData, withIntermediateDirectories: true)
            try? Data(value.utf8).write(to: storeFile, options: .atomic)
            return (nil, nil)
        case "lang":
            if let value = body["value"] as? String, value.count < 20 { UserDefaults.standard.set(value, forKey: "wasdmod.lang") }
            return (nil, nil)
        case "controls":
            return (readControls()?.base64EncodedString(), nil)
        case "controls-wait":
            return (await waitForControls(have: body["stamp"] as? String), nil)
        case "controls-write":
            return writeControls(body["data"] as? String)
        case "save":
            guard let name = body["name"] as? String, let text = body["text"] as? String else { return (nil, "Unknown request.") }
            return saveLayout(name, text)
        case "export":
            guard let name = body["name"] as? String, let text = body["text"] as? String else { return (nil, "Unknown request.") }
            return await export(name, text)
        default:
            return (nil, "Unknown request.")
        }
    }

    // MARK: - The game's own keyboard settings

    private static let controlsContainer = "EnhancedInputUserSettings"

    /// The Launcher edition keeps them as a GameSave container (a UE GVAS file
    /// in blob "Data") in the local save store the Flightdeck proxy writes,
    /// drive_c/gamesave/<account>/state.bin, which the game creates the first
    /// time it saves its settings. With several accounts, the newest store.
    private func controlsStore() -> URL? {
        let root = launcher.prefix.appendingPathComponent("drive_c/gamesave")
        let stores = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .map { root.appendingPathComponent($0).appendingPathComponent("state.bin") }
            .filter { fm.fileExists(atPath: $0.path) }
            .sorted { modified($0) > modified($1) }
        return stores.first { url in
            guard let data = try? Data(contentsOf: url), let state = LocalSaveStore.decode(data) else { return false }
            return state.controls(Self.controlsContainer) != nil
        }
    }

    private func modified(_ url: URL) -> Date {
        ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
    }

    private func readControls() -> Data? {
        guard let url = controlsStore(), let data = try? Data(contentsOf: url) else { return nil }
        return LocalSaveStore.decode(data)?.controls(Self.controlsContainer)
    }

    /// The store's size and time, "" when there is none.
    private func controlsStamp() -> String {
        guard let path = controlsStore()?.path else { return "" }
        var st = stat()
        guard stat(path, &st) == 0 else { return "" }
        return "\(st.st_size):\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)"
    }

    /// Answers the stamp once it isn't `have`, or after 25 seconds.
    private func waitForControls(have: String?) async -> String {
        let deadline = Date().addingTimeInterval(25)
        var now = controlsStamp()
        while now == have && Date() < deadline && window != nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
            now = controlsStamp()
        }
        return now
    }

    /// Replaces only the settings container, as the proxy commits a save
    /// (next generation, the container's time, checksum, atomic rename), and
    /// only while the game isn't running: it holds the store open and writes
    /// it from memory. The store also has the game's other saves, so every
    /// write first keeps a copy in <data>/wasdmod/backups (the last ten), and
    /// the result must decode with every other container unchanged.
    private func writeControls(_ base64: String?) -> (Any?, String?) {
        guard let base64, let gvas = Data(base64Encoded: base64), gvas.starts(with: Array("GVAS".utf8)),
              gvas.count < 1 << 20 else { return (nil, "Unknown request.") }
        if launcher.gameRunning { return (nil, "게임이 실행 중이에요. 게임을 끈 뒤 다시 눌러 주세요.") }
        guard let url = controlsStore(), let original = try? Data(contentsOf: url),
              var state = LocalSaveStore.decode(original) else {
            return (nil, "게임 설정이 아직 저장되지 않았어요. 게임의 설정 › 조작 › 키보드에서 아무 키나 한 번 바꾼 뒤 게임을 끄고 다시 눌러 주세요.")
        }
        let before = state
        state.setControls(Self.controlsContainer, gvas, now: UInt64(Date().timeIntervalSince1970))
        let encoded = LocalSaveStore.encode(state)
        guard let check = LocalSaveStore.decode(encoded), check.controls(Self.controlsContainer) == gvas,
              check.containers.filter({ $0.key != Self.controlsContainer }) == before.containers.filter({ $0.key != Self.controlsContainer })
        else { return (nil, "게임 설정 파일을 안전하게 고치지 못했어요. 아무것도 바꾸지 않았어요.") }
        do {
            let backups = launcher.wasdData.appendingPathComponent("backups")
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try original.write(to: backups.appendingPathComponent("state-\(stamp).bin"))
            let old = ((try? fm.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasPrefix("state-") }.sorted().dropLast(10)
            for name in old { try? fm.removeItem(at: backups.appendingPathComponent(name)) }
            try encoded.write(to: url, options: .atomic)
        } catch {
            return (nil, error.localizedDescription)
        }
        return ("ok", nil)
    }

    // MARK: - Layouts

    /// Saves into the launcher's layout folder and makes it the layout in use.
    /// The bundled presets are refreshed on every app launch, so an edited
    /// preset is kept under its own name.
    private func saveLayout(_ name: String, _ text: String) -> (Any?, String?) {
        var file = (name as NSString).lastPathComponent
        guard text.utf8.count < 1 << 20, !file.isEmpty, !file.hasPrefix(".") else { return (nil, "Unknown request.") }
        if !file.lowercased().hasSuffix(".txt") { file += ".txt" }
        if ["default.txt", "author.txt"].contains(file.lowercased()) { file = "wasdmod-" + file.lowercased() }
        do {
            try fm.createDirectory(at: launcher.wasdData, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: launcher.wasdData.appendingPathComponent(file), options: .atomic)
        } catch {
            return (nil, error.localizedDescription)
        }
        launcher.refreshWasdLayouts()
        launcher.wasdLayout = file
        if !launcher.wasdEnabled { return (nil, "saved:저장했어요. 메뉴의 조작 › WASD 조작을 켜면 이 배치를 써요.") }
        return (file, nil)
    }

    private func export(_ name: String, _ text: String) async -> (Any?, String?) {
        guard let window else { return ("cancelled", nil) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (name as NSString).lastPathComponent
        panel.allowedContentTypes = [.plainText]
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return ("cancelled", nil) }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return ("saved", nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Links

    /// The page itself stays in the window; its links open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if (url.isFileURL && url.path == page.path) || url.scheme == "about" { return .allow }
        if action.navigationType == .linkActivated, ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return .cancel
    }
}

/// The local GameSave store the Flightdeck proxy keeps (GameSaveLocalCore.cpp):
/// "XDLOCAL1", u32 version 1, u64 generation, u32 container count, then per
/// container its name, display name, u64 modified (Unix seconds) and blobs
/// (name, u32 size, bytes); strings are u32 length + UTF-8; little-endian;
/// a SHA-256 of everything before it at the end. Containers stay in order.
enum LocalSaveStore {
    struct Container: Equatable {
        var key: String
        var display: String
        var modified: UInt64
        var blobs: [Blob]
    }
    struct Blob: Equatable {
        var key: String
        var bytes: Data
    }
    struct State {
        var generation: UInt64
        var containers: [Container]

        func controls(_ name: String) -> Data? {
            containers.first { $0.key == name }?.blobs.first { $0.key == "Data" }?.bytes
        }

        mutating func setControls(_ name: String, _ bytes: Data, now: UInt64) {
            guard let i = containers.firstIndex(where: { $0.key == name }),
                  let j = containers[i].blobs.firstIndex(where: { $0.key == "Data" }) else { return }
            containers[i].blobs[j].bytes = bytes
            containers[i].modified = now
            generation += 1
        }
    }

    private static let magic = Array("XDLOCAL1".utf8)

    static func decode(_ data: Data) -> State? {
        let all = [UInt8](data)
        guard all.count >= 56, Array(all.prefix(8)) == magic else { return nil }
        let body = Array(all.dropLast(32))
        guard Array(SHA256.hash(data: body)) == Array(all.suffix(32)) else { return nil }
        var at = 8
        func take(_ n: Int) -> [UInt8]? {
            guard n >= 0, at + n <= body.count else { return nil }
            defer { at += n }
            return Array(body[at..<at + n])
        }
        func u32() -> UInt32? { take(4).map { $0.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } } }
        func u64() -> UInt64? { take(8).map { $0.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) } } }
        func text() -> String? { u32().flatMap { take(Int($0)) }.flatMap { String(bytes: $0, encoding: .utf8) } }
        guard u32() == 1, let generation = u64(), let count = u32(), count <= 4096 else { return nil }
        var containers: [Container] = []
        for _ in 0..<count {
            guard let key = text(), let display = text(), let modified = u64(), let n = u32(), n <= 65536 else { return nil }
            var blobs: [Blob] = []
            for _ in 0..<n {
                guard let name = text(), let size = u32(), let bytes = take(Int(size)) else { return nil }
                blobs.append(Blob(key: name, bytes: Data(bytes)))
            }
            containers.append(Container(key: key, display: display, modified: modified, blobs: blobs))
        }
        return at == body.count ? State(generation: generation, containers: containers) : nil
    }

    static func encode(_ state: State) -> Data {
        var out = magic
        func u32(_ v: UInt32) { out += (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        func u64(_ v: UInt64) { out += (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        func text(_ s: String) { let b = Array(s.utf8); u32(UInt32(b.count)); out += b }
        u32(1)
        u64(state.generation)
        u32(UInt32(state.containers.count))
        for c in state.containers {
            text(c.key)
            text(c.display)
            u64(c.modified)
            u32(UInt32(c.blobs.count))
            for b in c.blobs {
                text(b.key)
                u32(UInt32(b.bytes.count))
                out += [UInt8](b.bytes)
            }
        }
        out += Array(SHA256.hash(data: out))
        return Data(out)
    }
}
