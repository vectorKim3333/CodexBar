import AppKit
import SwiftUI

struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .codexbarOpenSettings)) { _ in
                Task { @MainActor in
                    self.openSettings()
                    // The SwiftUI `Settings` scene opens asynchronously; poll briefly and
                    // then surface it (front + on-screen) so it can't hide behind another
                    // app or land off-screen on a disconnected-monitor restore.
                    for _ in 0 ..< 20 {
                        if PreferencesView.presentSettingsWindowToFront() { break }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
            .task {
                // Migrate keychain items to reduce permission prompts during development (runs off main thread)
                await Task.detached(priority: .userInitiated) {
                    KeychainMigration.migrateIfNeeded()
                }.value
            }
            .onAppear {
                if let window = NSApp.windows.first(where: { $0.title == "CodexBarLifecycleKeepalive" }) {
                    // Make the keepalive window truly invisible and non-interactive.
                    window.styleMask = [.borderless]
                    window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                    window.isExcludedFromWindowsMenu = true
                    window.level = .floating
                    window.isOpaque = false
                    window.alphaValue = 0
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.canHide = false
                    window.setContentSize(NSSize(width: 1, height: 1))
                    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                }
            }
    }
}
