import AppKit
import CoreGraphics

/// Watches for Secure Event Input. While any app has it on (usually a password field,
/// sometimes left stuck on by a browser), macOS stops delivering key events to event taps,
/// so the trigger never reaches `HotkeyTap` and the native Cmd+Tab switcher runs instead.
/// Nothing can override it; the best we can do is say so and name the app holding it.
@MainActor
final class SecureInputMonitor {
    /// The app holding Secure Input, or nil when it's off.
    private(set) var holder: NSRunningApplication?
    private(set) var isActive = false
    var onChange: (() -> Void)?

    private var timer: Timer?

    func start(interval: TimeInterval) {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let pid = Self.secureInputPID()
        let active = pid != nil
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        guard active != isActive || app?.processIdentifier != holder?.processIdentifier else { return }
        isActive = active
        holder = app
        if active {
            Log.input.notice("Secure Input on (held by \(app?.localizedName ?? "pid \(pid ?? 0)", privacy: .public)); the trigger falls through to macOS")
        } else {
            Log.input.notice("Secure Input off")
        }
        onChange?()
    }

    /// The display name for menus, e.g. "Google Chrome".
    var holderName: String {
        holder?.localizedName ?? String(localized: "another app")
    }

    private static func secureInputPID() -> pid_t? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
              pid > 0 else { return nil }
        return pid
    }
}
