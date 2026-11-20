import ApplicationServices

/// AX calls block until the target app answers, so every element gets a short timeout.
/// A frozen app then costs at most this long instead of hanging the switcher.
let axMessagingTimeout: Float = 0.25

enum AXTimeout {
    /// Sets the process-wide default, which also covers elements AX hands back to us (a
    /// focused window, an observer's element). Without it those wait up to 6 s.
    static func applyGlobally() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeout)
    }
}

/// Runs AX queries off the main thread. The event tap's callback runs on the main thread,
/// so any AX wait there delays every keystroke system-wide and can get the tap disabled.
enum AXQueue {
    private static let queue = DispatchQueue(label: "AXQueries", qos: .userInteractive)

    /// Serial, so results arrive in the order they were asked for.
    static func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    static func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}

extension AXUIElement {
    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        return element
    }

    func rawValue(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? {
        rawValue(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        (rawValue(attribute) as? NSNumber)?.boolValue
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = rawValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        guard let value = rawValue(attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    var position: CGPoint? {
        guard let value = axValue(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value = axValue(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Global frame, top-left origin (same space as CGWindow bounds).
    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// False once the element is destroyed (e.g. its window closed). A busy app that times out still counts as alive.
    var isAlive: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value) != .invalidUIElement
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    private func axValue(_ attribute: String) -> AXValue? {
        guard let value = rawValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
