// Minecraft Launcher's Dungeons II page, patched by mac/mclauncher-link.py,
// starts this app with Play (`open -g -j macd2://play`, hidden) and then shows
// its state in place of the Play button: it polls http://127.0.0.1:47822/status
// and posts /pause, /resume and /cancel (its download bar) and /show,
// /stop and /retry. Only that page (Origin https://mojang) is
// answered. Started this way the app keeps no window or Dock icon except
// while the user has to act (sign-in, the GDK license, a pause, an error),
// and goes back out of sight once the work resumes.
import AppKit
import Combine
import Network

@MainActor
final class MCLauncherLink {
    static let port: UInt16 = 47822
    static let origin = "https://mojang"
    private static let mcLauncherBundleID = "com.mojang.mclauncher"

    private weak var launcher: Launcher?
    private var listener: NWListener?
    private var stageWatch: AnyCancellable?
    /// Started from Minecraft Launcher's Play button: the launcher shows the
    /// progress, this app's window only what needs the user.
    private(set) var driven = false

    init(launcher: Launcher) {
        self.launcher = launcher
        stageWatch = launcher.$stage.sink { [weak self] stage in
            guard let self, self.driven else { return }
            switch stage {
            case .needsLogin, .needsConsent, .failed: self.reveal()
            case .working, .playing: self.conceal()
            default: break
            }
        }
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let listener = try? NWListener(using: params) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    /// The app was opened by macd2://play. Launched hidden (open -j) means the
    /// Minecraft Launcher drives it: drop the Dock icon and stay out of sight.
    func openedFromMinecraftLauncher() {
        guard NSApp.isHidden || driven else { reveal(); return }   // opened by the user: stays theirs
        driven = true
        switch launcher?.stage {
        case .needsLogin, .needsConsent, .failed: reveal()
        default: conceal()
        }
    }

    private var launcherWindow: NSWindow? {
        let windows = NSApp.windows.filter { $0.canBecomeMain }
        return windows.first { $0.identifier?.rawValue.hasPrefix("launcher") == true } ?? windows.first
    }

    /// Back out of sight: the app hides (as with ⌘H) and drops its Dock icon.
    /// Not orderOut: SwiftUI counts the only window going away as the last
    /// window closing, and the app would quit.
    private func conceal() {
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    /// The user opened the app themselves: the window is theirs from now on.
    func userReopened() {
        driven = false
        reveal()
    }

    func reveal() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        launcherWindow?.makeKeyAndOrderFront(nil)
    }

    /// The display Minecraft Launcher's window is on, for the game to open there.
    static func minecraftLauncherScreen() -> NSScreen? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: mcLauncherBundleID).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let bounds = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                      && (($0[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > 200
              })?[kCGWindowBounds as String] as? [String: Double],
              let primary = NSScreen.screens.first
        else { return nil }
        // CG window bounds are top-left based on the primary display
        let center = NSPoint(x: (bounds["X"] ?? 0) + (bounds["Width"] ?? 0) / 2,
                             y: primary.frame.maxY - ((bounds["Y"] ?? 0) + (bounds["Height"] ?? 0) / 2))
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    // MARK: - HTTP

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                let reply = self?.respond(to: data ?? Data()) ?? Self.reply(500)
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func respond(to request: Data) -> Data {
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return Self.reply(400) }
        let method = String(parts[0]), path = String(parts[1])
        let origin = lines.dropFirst().first { $0.lowercased().hasPrefix("origin:") }
            .map { $0.dropFirst("origin:".count).trimmingCharacters(in: .whitespaces) }
        guard origin == Self.origin else { return Self.reply(403) }
        guard let launcher else { return Self.reply(503) }

        switch (method, path) {
        case ("OPTIONS", _):
            return Self.reply(204)
        case ("GET", "/status"):
            return Self.reply(200, json: status(of: launcher))
        case ("POST", "/show"):
            reveal()
        case ("POST", "/stop"):
            launcher.stopGame()
        case ("POST", "/pause"):
            launcher.pauseDownload()
        case ("POST", "/resume"):
            launcher.resumeDownload()
        case ("POST", "/cancel"):
            launcher.cancelDownload()
        case ("POST", "/retry"):
            if launcher.stage == .failed { launcher.start() } else { reveal() }
        default:
            return Self.reply(404)
        }
        return Self.reply(204)
    }

    private func status(of launcher: Launcher) -> Data {
        let stage: String = switch launcher.stage {
        case .idle: "idle"
        case .working: "working"
        case .needsConsent: "needsConsent"
        case .needsLogin: "needsLogin"
        case .playing: "playing"
        case .failed: "failed"
        case .paused: "paused"
        }
        var body: [String: Any] = ["stage": stage, "status": launcher.status, "detail": launcher.detail,
                                   "installed": launcher.gameInstalled]
        if let p = launcher.progress { body["progress"] = p }
        if let t = launcher.transfer {
            body["transfer"] = ["phase": t.phase, "update": t.update, "done": t.done, "total": t.total, "speed": t.speed]
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
    }

    private static func reply(_ code: Int, json: Data? = nil) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                      404: "Not Found", 500: "Internal Server Error", 503: "Service Unavailable"][code] ?? ""
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Access-Control-Allow-Origin: \(origin)\r\n"
        head += "Access-Control-Allow-Private-Network: true\r\n"
        head += "Access-Control-Allow-Methods: GET, POST\r\n"
        head += "Cache-Control: no-store\r\n"
        if json != nil { head += "Content-Type: application/json; charset=utf-8\r\n" }
        head += "Content-Length: \(json?.count ?? 0)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + (json ?? Data())
    }
}
