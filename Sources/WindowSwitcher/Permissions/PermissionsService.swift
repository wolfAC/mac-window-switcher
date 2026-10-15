import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Accessibility (event tap + AX window control) and Screen Recording (previews).
@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    /// macOS 15+ separately asks to let the app "bypass the system private window picker"
    /// the first time it captures windows directly. There's no way to check this without
    /// triggering the prompt, so a successful capture is remembered here.
    @Published private(set) var previewsAllowed: Bool
    @Published private(set) var previewsDeclined = false

    var needsPreviewApproval: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    var allGranted: Bool {
        accessibilityGranted && screenRecordingGranted && (previewsAllowed || !needsPreviewApproval)
    }

    private static let previewsAllowedKey = "previewsAllowed"
    private var timer: Timer?
    private var onChange: [() -> Void] = []

    init() {
        previewsAllowed = UserDefaults.standard.bool(forKey: Self.previewsAllowedKey)
        refresh()
    }

    /// Asks ScreenCaptureKit for the window list, which shows the macOS 15 "bypass the
    /// private window picker" prompt if the user hasn't allowed it yet.
    func requestPreviewAccess() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                setPreviewsAllowed(true)
                previewsDeclined = false
            } catch {
                Log.app.error("Preview access not allowed: \(error.localizedDescription, privacy: .public)")
                setPreviewsAllowed(false)
                previewsDeclined = true
            }
        }
    }

    private func setPreviewsAllowed(_ allowed: Bool) {
        guard allowed != previewsAllowed else { return }
        previewsAllowed = allowed
        Log.app.notice("Previews allowed: \(allowed)")
        UserDefaults.standard.set(allowed, forKey: Self.previewsAllowedKey)
        onChange.forEach { $0() }
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
        Log.app.notice("Permissions: accessibility=\(ax) screenRecording=\(screen)")
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

    private static let reopenOnboardingKey = "reopenOnboardingAfterRelaunch"

    /// True once, on the launch that follows `relaunch()`, so onboarding picks up where it left off.
    static func consumeRelaunchFlag() -> Bool {
        let flag = UserDefaults.standard.bool(forKey: reopenOnboardingKey)
        if flag { UserDefaults.standard.removeObject(forKey: reopenOnboardingKey) }
        return flag
    }

    /// Screen Recording access is only re-read at launch, so offer a relaunch after granting it.
    func relaunch() {
        UserDefaults.standard.set(true, forKey: Self.reopenOnboardingKey)
        Log.app.notice("Relaunching")
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit first; otherwise `open` just re-activates the dying instance.
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path, String(pid)]
        do {
            try task.run()
        } catch {
            Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
