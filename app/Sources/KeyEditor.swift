import AppKit
import WebKit

/// wasdmod's key layout editor (Keybinder.html) in a window of its own, with
/// the host functions the page uses when an app serves it (window.wasdmodHost,
/// described at the top of the page): the editor's saved state, saving a
/// layout into the launcher's layout folder, exporting a file, and reading and
/// changing the game's own keyboard settings (EnhancedInputUserSettings.sav in
/// the prefix), which is what its "change the in-game controls" button needs.
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
            guard let path = controlsFile(), let data = fm.contents(atPath: path.path) else { return (nil, nil) }
            return (data.base64EncodedString(), nil)
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

    /// Written by the game the first time a key is changed in its settings.
    private func controlsFile() -> URL? {
        let users = launcher.prefix.appendingPathComponent("drive_c/users")
        for user in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] {
            let file = users.appendingPathComponent(user)
                .appendingPathComponent("AppData/Local/Dungeons2/Saved/SaveGames/EnhancedInputUserSettings.sav")
            if fm.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    /// The file's size and time, "" when there is none.
    private func controlsStamp() -> String {
        guard let path = controlsFile()?.path else { return "" }
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

    /// Changed only while the game isn't running (it has its settings loaded
    /// and may save them again). The first write keeps the original beside it.
    private func writeControls(_ base64: String?) -> (Any?, String?) {
        guard let base64, let data = Data(base64Encoded: base64), data.starts(with: Array("GVAS".utf8)) else { return (nil, "Unknown request.") }
        if launcher.gameRunning { return (nil, "게임이 실행 중이에요. 게임을 끈 뒤 다시 눌러 주세요.") }
        guard let file = controlsFile() else { return (nil, "게임 설정 파일이 아직 없어요. 게임의 설정 › 조작 › 키보드에서 아무 키나 한 번 바꾼 뒤 다시 눌러 주세요.") }
        let backup = file.appendingPathExtension("wasdmod-backup")
        do {
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
            try data.write(to: file, options: .atomic)
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
