import AppKit
import ApplicationServices

/// Accessibility (event tap + AX window control) and Screen Recording (previews).
@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false

    var allGranted: Bool { accessibilityGranted && screenRecordingGranted }

    private var timer: Timer?
    private var onChange: [() -> Void] = []

    init() {
        refresh()
    }

    func observe(_ handler: @escaping () -> Void) {
        onChange.append(handler)
    }

    /// Polls so the UI and the event tap react when the user flips a switch in System Settings.
    func startPolling(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        guard ax != accessibilityGranted || screen != screenRecordingGranted else { return }
        accessibilityGranted = ax
        screenRecordingGranted = screen
        Log.app.info("Permissions: accessibility=\(ax) screenRecording=\(screen)")
        onChange.forEach { $0() }
    }

    /// Shows the system prompt (once per app) and adds the app to the Accessibility list.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    /// Adds the app to the Screen Recording list. macOS usually needs a relaunch before it takes effect.
    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            openScreenRecordingSettings()
        }
        refresh()
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    /// Screen Recording access is only re-read at launch, so offer a relaunch after granting it.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
