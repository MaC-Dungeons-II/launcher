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
                .frame(width: 440, height: 150)
                .onAppear {
                    delegate.launcher = launcher
                    launcher.refreshWasdLayouts()
                    launcher.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    launcher.refreshWasdLayouts()   // layouts dropped into the folder show up
                }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(launcher.status)
                .font(.system(size: 14, weight: .semibold))
            if let p = launcher.progress {
                ProgressView(value: p)
            } else if launcher.stage == .working {
                ProgressView().progressViewStyle(.linear)
            }
            if !launcher.detail.isEmpty {
                Text(launcher.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                actions
            }
        }
        .padding(20)
    }

    @ViewBuilder var actions: some View {
        switch launcher.stage {
        case .needsLogin:
            Button("로그인") { launcher.login() }
                .keyboardShortcut(.defaultAction)
        case .needsConsent:
            Link("라이선스 보기",
                 destination: URL(string: "https://www.nuget.org/packages/Microsoft.GDK.Windows/2604.4.7897/License")!)
                .font(.system(size: 12))
            Button("동의하고 계속") { launcher.acceptLicense() }
                .keyboardShortcut(.defaultAction)
        case .paused:
            Button("이어 받기") { launcher.resumeDownload() }
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("다시 시도") { launcher.start() }
                .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}
