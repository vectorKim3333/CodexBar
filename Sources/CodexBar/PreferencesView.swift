import AppKit
import CodexBarCore
import SwiftUI

enum PreferencesTab: String, CaseIterable, Hashable {
    case general
    case providers
    case display
    case advanced
    case about

    static let defaultWidth: CGFloat = 546
    static let providersWidth: CGFloat = 792
    static let windowHeight: CGFloat = 638

    var title: String {
        switch self {
        case .general: L("tab_general")
        case .providers: L("tab_providers")
        case .display: L("tab_display")
        case .advanced: L("tab_advanced")
        case .about: L("tab_about")
        }
    }

    var preferredWidth: CGFloat {
        self == .providers ? PreferencesTab.providersWidth : PreferencesTab.defaultWidth
    }

    var preferredHeight: CGFloat {
        PreferencesTab.windowHeight
    }
}

@MainActor
struct PreferencesView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var selection: PreferencesSelection
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
    @State private var contentWidth: CGFloat = PreferencesTab.general.preferredWidth
    @State private var contentHeight: CGFloat = PreferencesTab.general.preferredHeight

    init(
        settings: SettingsStore,
        store: UsageStore,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator(),
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator? = nil,
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void = { _ in })
    {
        self.settings = settings
        self.store = store
        self.selection = selection
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
            ?? CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: managedCodexAccountCoordinator)
        self.runProviderLoginFlow = runProviderLoginFlow
    }

    var body: some View {
        TabView(selection: self.$selection.tab) {
            GeneralPane(settings: self.settings, store: self.store)
                .tabItem { Label(L("tab_general"), systemImage: "gearshape") }
                .tag(PreferencesTab.general)

            ProvidersPane(
                settings: self.settings,
                store: self.store,
                managedCodexAccountCoordinator: self.managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: self.codexAccountPromotionCoordinator,
                runProviderLoginFlow: self.runProviderLoginFlow)
                .tabItem { Label(L("tab_providers"), systemImage: "square.grid.2x2") }
                .tag(PreferencesTab.providers)

            DisplayPane(settings: self.settings, store: self.store)
                .tabItem { Label(L("tab_display"), systemImage: "eye") }
                .tag(PreferencesTab.display)

            AdvancedPane(settings: self.settings)
                .tabItem { Label(L("tab_advanced"), systemImage: "slider.horizontal.3") }
                .tag(PreferencesTab.advanced)

            AboutPane()
                .tabItem { Label(L("tab_about"), systemImage: "info.circle") }
                .tag(PreferencesTab.about)

        }
        // Korean-only fork; no language reactive id needed.
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: self.contentWidth, height: self.contentHeight)
        .onAppear {
            self.updateLayout(for: self.selection.tab, animate: false)
        }
        .onChange(of: self.selection.tab) { _, newValue in
            self.updateLayout(for: newValue, animate: true)
        }
    }

    private func updateLayout(for tab: PreferencesTab, animate: Bool) {
        let change = {
            self.contentWidth = tab.preferredWidth
            self.contentHeight = tab.preferredHeight
        }
        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { change() }
        } else {
            change()
        }
        Self.resizeSettingsWindow(width: tab.preferredWidth, height: tab.preferredHeight, animate: animate)
    }

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
    private static let knownTabTitles = Set(PreferencesTab.allCases.map(\.title))

    static func settingsWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue == settingsWindowIdentifier
                || knownTabTitles.contains($0.title)
        }
    }

    /// Brings the Settings window to the front and pulls it onto a visible screen.
    /// Returns `false` when the window doesn't exist yet (the SwiftUI `Settings`
    /// scene opens asynchronously, so callers poll until this succeeds).
    ///
    /// Robustness this buys, beyond just opening the scene:
    /// - Multi-monitor / disconnected-display restore: SwiftUI restores the window
    ///   to its last saved frame, which can land on a monitor that is no longer
    ///   attached — the window "opens" but is entirely off every current screen and
    ///   the user sees nothing. We recenter it onto the main screen in that case.
    /// - Opening behind the frontmost app: `orderFrontRegardless()` guarantees it
    ///   surfaces even when another app is active.
    @discardableResult
    static func presentSettingsWindowToFront() -> Bool {
        guard let window = settingsWindow() else { return false }
        constrainOnScreen(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return true
    }

    private static func constrainOnScreen(_ window: NSWindow) {
        let frame = window.frame
        // Reachable if the title-bar strip overlaps some visible screen area.
        let titleStrip = NSRect(
            x: frame.minX, y: frame.maxY - 24, width: frame.width, height: 24)
        let reachable = NSScreen.screens.contains { $0.visibleFrame.intersects(titleStrip) }
        if reachable { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: vf.midX - frame.width / 2,
            y: vf.midY - frame.height / 2))
    }

    private static func resizeSettingsWindow(width: CGFloat, height: CGFloat, animate: Bool) {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == settingsWindowIdentifier
                || knownTabTitles.contains($0.title)
        }) else { return }
        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        guard toolbarHeight > 0 else { return }
        let newSize = NSSize(width: width, height: height + toolbarHeight)
        var frame = window.frame
        frame.origin.y += frame.size.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: animate)
    }

}
