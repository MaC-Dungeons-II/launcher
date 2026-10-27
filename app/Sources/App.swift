import AppKit
import SwiftUI

@main
struct MaCDungeonsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launcher = Launcher()

    var body: some Scene {
        Window("M(a)C Dungeons II", id: "launcher") {
            LauncherView()
                .environmentObject(launcher)
                .frame(width: 520, height: 380)
                .onAppear {
                    delegate.launcher = launcher
                    launcher.refreshWasdLayouts()
                    launcher.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    launcher.refreshWasdLayouts()   // layouts dropped into the folder show up
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("조작") {
                Toggle("WASD 조작 (wasdmod)", isOn: $launcher.wasdEnabled)
                Picker("키 배치", selection: $launcher.wasdLayout) {
                    ForEach(launcher.wasdLayouts, id: \.self) { Text(Launcher.wasdLayoutTitle($0)).tag($0) }
                }
                .disabled(!launcher.wasdEnabled)
                Divider()
                Button("키 배치 편집기 열기…") { launcher.openWasdEditor() }
                Button("키 배치 폴더 열기") { launcher.openWasdFolder() }
                Divider()
                Text("바꾼 설정은 다음 게임 실행부터 적용돼요")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var launcher: Launcher? {
        didSet {
            MainActor.assumeIsolated {
                guard let launcher, link == nil else { return }
                link = MCLauncherLink(launcher: launcher)
                link?.start()
                if openedByLink { link?.openedFromMinecraftLauncher() }
            }
        }
    }
    private var link: MCLauncherLink?
    private var openedByLink = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// macd2://play: Minecraft Launcher's Play button (see mac/mclauncher-link.py
    /// and MCLauncherLink). Opening the app already starts the game.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard urls.contains(where: { $0.scheme == "macd2" }) else { return }
            guard let launcher, let link else { openedByLink = true; return }   // still launching
            if launcher.stage == .failed { launcher.start() }
            launcher.resumeDownload()   // Play on a paused download
            link.openedFromMinecraftLauncher()
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

struct LauncherView: View {
    @EnvironmentObject var launcher: Launcher

    private static let green = Color(red: 0.37, green: 0.75, blue: 0.23)
    private static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backdrop
            VStack(spacing: 0) {
                Spacer(minLength: 34)
                logo
                Spacer(minLength: 22)
                stagePanel
                    .padding(.horizontal, 40)
                Spacer(minLength: 16)
                Text("Mojang·Microsoft와 관계없는 비공식 프로젝트예요")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("종료")
            .padding(12)
        }
        .background(WindowChrome())
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    private var backdrop: some View {
        ZStack {
            Self.ink
            RadialGradient(colors: [Self.green.opacity(0.28), .clear],
                           center: .init(x: 0.5, y: 0.0), startRadius: 10, endRadius: 360)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
        }
    }

    private var logo: some View {
        VStack(spacing: 6) {
            Text("M(a)C")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundStyle(Self.green)
            Text("DUNGEONS II")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.72)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 3)
            Text("비공식 Mac 포팅 런처")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().stroke(.white.opacity(0.25)))
                .padding(.top, 6)
        }
    }

    @ViewBuilder private var stagePanel: some View {
        if launcher.stage == .needsLogin {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("이 앱에도 Microsoft 계정 로그인이 한 번 필요해요")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Minecraft Launcher와 별개로 로그인해요. 게임을 구매한 계정으로 로그인해 주세요. 로그인 정보는 이 Mac의 키체인에만 저장돼요.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { launcher.login() } label: {
                    Text("Microsoft 계정으로 로그인")
                        .font(.system(size: 13.5, weight: .bold))
                        .frame(width: 240, height: 36)
                }
                .buttonStyle(PrimaryButton(color: Self.green))
                .keyboardShortcut(.defaultAction)
            }
        } else {
            VStack(spacing: 10) {
                Text(launcher.status)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if launcher.progress != nil || launcher.stage == .working {
                    ProgressBar(value: launcher.progress, color: Self.green)
                }
                if !launcher.detail.isEmpty {
                    Text(launcher.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions.padding(.top, 2)
            }
        }
    }

    @ViewBuilder var actions: some View {
        switch launcher.stage {
        case .needsConsent:
            HStack(spacing: 14) {
                Link("라이선스 보기",
                     destination: URL(string: "https://www.nuget.org/packages/Microsoft.GDK.Windows/2604.4.7897/License")!)
                    .font(.system(size: 12))
                Button("동의하고 계속") { launcher.acceptLicense() }
                    .buttonStyle(PrimaryButton(color: Self.green))
                    .keyboardShortcut(.defaultAction)
            }
        case .paused:
            Button("이어 받기") { launcher.resumeDownload() }
                .buttonStyle(PrimaryButton(color: Self.green))
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("다시 시도") { launcher.start() }
                .buttonStyle(PrimaryButton(color: Self.green))
                .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}

/// A flat bar; nil is indeterminate (a sliding segment).
struct ProgressBar: View {
    let value: Double?
    let color: Color
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                if let value {
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
                        .animation(.easeOut(duration: 0.4), value: value)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: (geo.size.width * 1.3) * phase - geo.size.width * 0.3)
                        .onAppear {
                            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 8)
    }
}

/// A solid, slightly blocky button with a darker bottom edge.
struct PrimaryButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(configuration.isPressed ? 0.75 : 1))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.black.opacity(0.3)).frame(height: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
            )
            .offset(y: configuration.isPressed ? 1 : 0)
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
            window.backgroundColor = .black
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
