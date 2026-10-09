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
                    launcher.start()
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var launcher: Launcher?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { launcher?.stopHelpers() }
    }
}

@MainActor
func NSApplicationTerminate() { NSApp.terminate(nil) }

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
        case .failed:
            Button("다시 시도") { launcher.start() }
                .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}
