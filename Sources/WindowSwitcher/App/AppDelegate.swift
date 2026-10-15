import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusMenuDelegate {
    private let preferences = Preferences.shared
    private let permissions = PermissionsService()
    private let catalog = WindowCatalog()
    private let recents = RecentsTracker()
    private let thumbnails = ThumbnailService()
    private lazy var controller = SwitcherController(catalog: catalog, recents: recents, thumbnails: thumbnails, preferences: preferences)
    private lazy var tap = HotkeyTap { [preferences] in preferences.bindings }
    private lazy var onboarding = OnboardingWindow(permissions: permissions, preferences: preferences)
    private lazy var settings = SettingsWindow(preferences: preferences)
    private var statusMenu: StatusMenu?

    private(set) var isPaused = false

    var permissionsMissing: Bool { !permissions.allGranted }

    func applicationDidFinishLaunching(_ notification: Notification) {
        tap.delegate = controller
        statusMenu = StatusMenu(delegate: self)

        permissions.observe { [weak self] in self?.syncWithPermissions() }
        permissions.startPolling(interval: 2)
        syncWithPermissions()

        let relaunchedFromOnboarding = PermissionsService.consumeRelaunchFlag()
        if relaunchedFromOnboarding || (!permissions.allGranted && !preferences.hasCompletedOnboarding) || !permissions.accessibilityGranted {
            onboarding.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
        recents.stop()
    }

    /// The tap runs only while Accessibility is granted and not paused. If permission is
    /// revoked the tap stops, and the native Cmd+Tab takes over again.
    private func syncWithPermissions() {
        if permissions.accessibilityGranted {
            recents.stop()
            recents.start()
            catalog.startWatchingSpaces()
        }
        updateTap()
        statusMenu?.refreshIcon()
    }

    private func updateTap() {
        if permissions.accessibilityGranted && !isPaused {
            tap.start()
        } else {
            controller.reset()
            tap.stop()
        }
    }

    // MARK: StatusMenuDelegate

    func showPermissions() { onboarding.show() }
    func showSettings() { settings.show() }
    func dumpWindows() { controller.dumpWindows() }

    func togglePause() {
        isPaused.toggle()
        updateTap()
        statusMenu?.refreshIcon()
    }
}
