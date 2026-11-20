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
    private lazy var updater = Updater(preferences: preferences)
    private let secureInput = SecureInputMonitor()
    private var tapWatchdog: Timer?
    private var wakeToken: NSObjectProtocol?
    private var statusMenu: StatusMenu?

    private(set) var isPaused = false

    var permissionsMissing: Bool { !permissions.allGranted }
    var isUpdating: Bool { updater.isBusy }
    /// The app blocking the trigger with Secure Input, if any.
    var secureInputHolder: String? { secureInput.isActive ? secureInput.holderName : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXTimeout.applyGlobally()
        tap.delegate = controller
        statusMenu = StatusMenu(delegate: self)

        permissions.observe { [weak self] in self?.syncWithPermissions() }
        permissions.startPolling(interval: 2)
        syncWithPermissions()
        updater.start()
        secureInput.onChange = { [weak self] in self?.statusMenu?.refreshIcon() }
        secureInput.start(interval: 2)
        startTapWatchdog()

        let relaunchedFromOnboarding = PermissionsService.consumeRelaunchFlag()
        Log.app.notice("Launched (after onboarding relaunch: \(relaunchedFromOnboarding)), accessibility=\(self.permissions.accessibilityGranted) screenRecording=\(self.permissions.screenRecordingGranted) previews=\(self.permissions.previewsAllowed)")
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

    /// The tap otherwise only starts when permissions change, so a failed start at launch or
    /// a tap lost across sleep would leave the native Cmd+Tab in charge until a relaunch.
    private func startTapWatchdog() {
        tapWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureTapHealthy(reason: "watchdog") }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureTapHealthy(reason: "wake") }
        }
    }

    private func ensureTapHealthy(reason: String) {
        guard permissions.accessibilityGranted, !isPaused, !tap.isHealthy else { return }
        let restarted = tap.restart()
        Log.input.notice("Event tap was down (\(reason, privacy: .public)); restart \(restarted ? "succeeded" : "failed")")
    }

    // MARK: StatusMenuDelegate

    func showPermissions() { onboarding.show() }
    func showSettings() { settings.show() }
    func dumpWindows() { controller.dumpWindows() }
    func checkForUpdates() { updater.check(userInitiated: true) }
    func showSecureInputHolder() { secureInput.holder?.activate() }

    func togglePause() {
        isPaused.toggle()
        updateTap()
        statusMenu?.refreshIcon()
    }
}
