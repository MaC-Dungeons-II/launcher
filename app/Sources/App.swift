import AppKit
import SwiftUI

@main
struct MaCDungeonsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launcher = Launcher()
    @StateObject private var mcLauncher = MCLauncherPatch()

    var body: some Scene {
        Window("M(a)C Dungeons II", id: "launcher") {
            LauncherView()
                .environmentObject(launcher)
                .environmentObject(mcLauncher)
                .frame(width: 560, height: 340)
                .onAppear {
                    delegate.launcher = launcher
                    launcher.start()
                    Task { await mcLauncher.keepApplied() }   // after a Minecraft Launcher update
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    mcLauncher.refresh()   // installed or opened in the meantime
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var launcher: Launcher? {
        didSet {
            MainActor.assumeIsolated {
                guard let launcher, link == nil else { return }
                link = MCLauncherLink(launcher: launcher)
                link?.start()
                if openedByLink {
                    link?.openedFromMinecraftLauncher()
                    launcher.play()
                }
            }
        }
    }
    private var link: MCLauncherLink?
    private var openedByLink = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// Opening the app again (Finder, Dock, Spotlight) while it runs out of
    /// sight for the Minecraft Launcher shows its window and keeps it shown.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { link?.userReopened() }
        return true
    }
    /// macd2://play: Minecraft Launcher's Play button (MCLauncherLink): go
    /// straight on to the game.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard urls.contains(where: { $0.scheme == "macd2" }) else { return }
            guard let launcher, let link else { openedByLink = true; return }   // still launching
            link.openedFromMinecraftLauncher()
            launcher.play()
        }
    }
    /// While playing, the game is asked to close first; the launcher replies
    /// once it has (Wine is stopped after 20 s if it hasn't).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let launcher, launcher.gameRunning else { return .terminateNow }
            launcher.quitAfterGame()
            return .terminateLater
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        // stops Wine first if the game is still running, then helpers and other children
        MainActor.assumeIsolated { launcher?.shutdown() }
    }
}

/// Minecraft Launcher's palette (its UI's colour tokens), so the window looks
/// like part of it.
enum MCL {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let grey1 = hex(0x6B6562), grey2 = hex(0x514D4C), grey3 = hex(0x3D3938)
    static let grey4 = hex(0x312D2C), grey5 = hex(0x262423), grey6 = hex(0x171615)
    static let light1 = hex(0xFCF5F1), light3 = hex(0xD0C5C0), light5 = hex(0xABA09C)
    static let green3 = hex(0x52A535), green5 = hex(0x3C8527), green6 = hex(0x2A641C)
    static let red = hex(0xFF605E)
    // the Dungeons II play button
    static let orangeTop = hex(0xFDDF93), orangeHi = hex(0xF6C25A), orangeLo = hex(0xF1AD42)
    static let orangeBottom = hex(0xE89133), orangeText = hex(0x7A3306)
}

struct LauncherView: View {
    @EnvironmentObject var launcher: Launcher
    @EnvironmentObject var mcLauncher: MCLauncherPatch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            message
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            playSection
        }
        .background(MCL.grey5)
        .background(WindowChrome())
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    // MARK: - Header (like a product page's title row)

    private var header: some View {
        HStack(spacing: 10) {
            Text("M(a)C DUNGEONS II")
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(MCL.light1)
            Text("비공식")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(MCL.light3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(MCL.grey1, lineWidth: 1))
            Spacer(minLength: 8)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MCL.light1)
                    .frame(width: 26, height: 26)
                    .background(MCL.grey3)
                    .overlay(alignment: .bottom) { Rectangle().fill(MCL.grey6).frame(height: 2) }
            }
            .buttonStyle(.plain)
            .help("종료")
            .accessibilityLabel("M(a)C Dungeons II 종료")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(MCL.grey6)
    }

    // MARK: - Message

    @ViewBuilder private var message: some View {
        VStack(spacing: 10) {
            switch launcher.stage {
            case .needsLogin:
                title("이 앱에도 Microsoft 로그인이 필요해요")
                body("M(a)C Dungeons II는 Minecraft Launcher와 별도로 로그인하는 비공식 Mac 포팅 런처예요. 게임을 구매한 Microsoft 계정으로 한 번만 로그인하면 돼요.")
                note("로그인 정보는 이 Mac의 키체인에만 저장돼요.")
            case .needsConsent:
                title("Microsoft GDK 라이선스 동의가 필요해요")
                body(launcher.detail.isEmpty ? "게임이 쓰는 Xbox 런타임을 Microsoft에서 직접 내려받아요." : launcher.detail)
                Link("라이선스 보기",
                     destination: URL(string: "https://www.nuget.org/packages/Microsoft.GDK.Windows/2604.4.7897/License")!)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MCL.green3)
            case .failed:
                title(launcher.status, color: MCL.red)
                body(launcher.detail)
            case .ready:
                title(launcher.status)
                body(launcher.detail)
                MinecraftLauncherLinkRow()
                    .padding(.top, 10)
            default:
                title(launcher.status)
                // while downloading the bar below carries the same line
                if launcher.transfer?.phase != "download" { body(launcher.detail) }
            }
        }
        .frame(maxWidth: 460)
    }

    private func title(_ text: String, color: Color = MCL.light1) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func body(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(MCL.light3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(6)              // long errors end in "…"; the full text is in the tooltip
                .help(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(MCL.light5)
            .multilineTextAlignment(.center)
    }

    // MARK: - Play section (the launcher's button row and download bar)

    private var playSection: some View {
        VStack(spacing: 10) {
            switch launcher.stage {
            case .needsLogin:
                Button("Microsoft 계정으로 로그인") { launcher.login() }
                    .buttonStyle(PlayButton())
                    .keyboardShortcut(.defaultAction)
            case .needsConsent:
                Button("동의하고 계속") { launcher.acceptLicense() }
                    .buttonStyle(PlayButton())
                    .keyboardShortcut(.defaultAction)
            case .paused:
                DownloadBar(value: launcher.progress, label: "일시 정지됨", paused: true, animate: false)
                Button("이어 받기") { launcher.resumeDownload() }
                    .buttonStyle(PlayButton())
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("다시 시도") { launcher.play() }
                    .buttonStyle(PlayButton())
                    .keyboardShortcut(.defaultAction)
            case .ready:
                Button(launcher.gameInstalled ? "플레이" : "설치") { launcher.play() }
                    .buttonStyle(PlayButton())
                    .keyboardShortcut(.defaultAction)
            case .playing:
                Button("게임 실행 중") {}
                    .buttonStyle(PlayButton())
                    .disabled(true)
            default:
                DownloadBar(value: launcher.progress, label: barLabel, paused: false, animate: !reduceMotion)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(MCL.grey4)
        .overlay(alignment: .top) { Rectangle().fill(MCL.grey3).frame(height: 2) }
    }

    /// Bytes, speed and time left while downloading (the detail line), else
    /// the percentage.
    private var barLabel: String {
        if launcher.transfer?.phase == "download", !launcher.detail.isEmpty { return launcher.detail }
        guard let p = launcher.progress else { return "준비 중" }
        return "\(Int((p * 100).rounded()))%"
    }
}

/// The optional link to the Minecraft Launcher (MCLauncherPatch): a switch
/// with what it does, asked once before turning it on.
struct MinecraftLauncherLinkRow: View {
    @EnvironmentObject var link: MCLauncherPatch

    var body: some View {
        if link.state != .notInstalled {
            VStack(spacing: 5) {
                Toggle(isOn: Binding(get: { link.state == .on }, set: { on in on ? confirmOn() : turnOff() })) {
                    Text("Minecraft Launcher에서도 플레이")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MCL.light1)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(MCL.green5)
                .disabled(link.busy || link.state == .notReady)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(isFailed ? MCL.red : MCL.light5)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(MCL.grey4)
            .overlay(Rectangle().stroke(MCL.grey3, lineWidth: 1))
        }
    }

    private var isFailed: Bool { if case .failed = link.state { return true } else { return false } }

    private var caption: String {
        if link.busy { return "Minecraft Launcher에 연결하는 중…" }
        switch link.state {
        case .on: return "Minecraft Launcher의 Dungeons II 플레이 버튼으로도 이 앱이 게임을 실행해요."
        case .notReady: return "Minecraft Launcher를 한 번 실행한 뒤에 켤 수 있어요."
        case .failed(let message): return message
        default: return "선택 기능이에요. 켜면 Minecraft Launcher의 Dungeons II 화면에서도 플레이할 수 있어요."
        }
    }

    private func confirmOn() {
        let alert = NSAlert()
        alert.messageText = "Minecraft Launcher에 연결할까요?"
        alert.informativeText = """
        Minecraft Launcher의 Dungeons II 화면에 플레이 버튼이 생기고, 누르면 이 앱이 뒤에서 게임을 내려받고 실행해요.

        • Minecraft Launcher의 화면 파일을 Dungeons II 부분만 고쳐요. 원본은 따로 보관하고, 끄면 되돌려요.
        • 이 Mac 사용자 계정에 작은 백그라운드 항목(LaunchAgent)을 설치해요.
        • macOS가 이 앱이 다른 앱을 수정하도록 허용할지 물을 수 있어요.

        Mojang·Microsoft와 관계없는 비공식 기능이에요.
        """
        alert.addButton(withTitle: "연결")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await link.turnOn() }
    }

    private func turnOff() { Task { await link.turnOff() } }
}

/// Minecraft Launcher's download bar: dark track, green fill, text inside.
/// nil progress shows an empty bar with a moving sheen (unless reduced motion).
struct DownloadBar: View {
    let value: Double?
    let label: String
    let paused: Bool
    let animate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(MCL.grey6)
                if let value {
                    Rectangle()
                        .fill(paused ? MCL.grey3 : MCL.green5)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                        .animation(.linear(duration: 0.5), value: value)
                } else if animate {
                    // driven by the clock, so it keeps moving whenever the bar
                    // turns indeterminate again (an onAppear animation ran once)
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        LinearGradient(colors: [.clear, MCL.green5.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: geo.size.width * (CGFloat(phase) * 1.3 - 0.3))
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCL.light1)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
            }
            .clipped()
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
    }
}

/// The Dungeons II play button: black outline, light top edge, darker bottom
/// edge, two-tone fill.
struct PlayButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? MCL.orangeText : MCL.light5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 28)
            .frame(minWidth: 280, minHeight: 46)
            .background(
                LinearGradient(colors: isEnabled ? [MCL.orangeHi, MCL.orangeLo] : [MCL.grey2, MCL.grey3],
                               startPoint: .top, endPoint: .bottom)
                    .brightness(pressed ? -0.06 : 0)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(isEnabled ? MCL.orangeTop : MCL.grey1).frame(height: pressed ? 2 : 4)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(isEnabled ? MCL.orangeBottom : MCL.grey4).frame(height: pressed ? 2 : 4)
            }
            .overlay(Rectangle().stroke(.black, lineWidth: 2))
            .contentShape(Rectangle())
    }
}

/// No title bar: hides the traffic lights and lets the window be dragged by
/// its background.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0x26 / 255, green: 0x24 / 255, blue: 0x23 / 255, alpha: 1)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
