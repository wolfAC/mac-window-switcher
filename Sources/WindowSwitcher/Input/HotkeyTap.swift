import CoreGraphics
import Foundation

@MainActor
protocol HotkeyTapDelegate: AnyObject {
    var switcherIsActive: Bool { get }
    var switcherIsVisible: Bool { get }
    func hotkeyTriggered(reverse: Bool)
    func hotkeyModifierReleased()
    func hotkeyEscape()
    func hotkeyArrow(_ keyCode: CGKeyCode)
    func hotkeyCommand(_ command: WindowCommand)
}

/// A session event tap that catches the trigger (e.g. Cmd+Tab) before macOS's own switcher.
///
/// Only events the switcher handles are swallowed. While the switcher is open every key
/// event is swallowed, so e.g. Cmd+Q aimed at the overlay can't quit the frontmost app.
/// If the tap isn't running, nothing is intercepted and the native switcher works.
@MainActor
final class HotkeyTap {
    weak var delegate: HotkeyTapDelegate?
    private let bindings: () -> [KeyBinding]
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The modifier that opened the current session; releasing it commits.
    private var heldModifier: CGEventFlags?

    var isRunning: Bool { tap != nil }

    init(bindings: @escaping () -> [KeyBinding]) {
        self.bindings = bindings
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.input.error("Could not create event tap (Accessibility permission missing?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Log.input.info("Event tap started")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
        heldModifier = nil
        Log.input.info("Event tap stopped")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns slow taps off; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.input.notice("Event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            return pass

        case .flagsChanged:
            if let held = heldModifier, !event.flags.contains(held) {
                heldModifier = nil
                delegate?.hotkeyModifierReleased()
            }
            return pass

        case .keyDown, .keyUp:
            return handleKey(event, isDown: type == .keyDown) ? nil : pass

        default:
            return pass
        }
    }

    /// Returns true to swallow the event.
    private func handleKey(_ event: CGEvent, isDown: Bool) -> Bool {
        guard let delegate else { return false }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // A missed flagsChanged would leave the session stuck open; the key event's own flags tell the truth.
        if let held = heldModifier, !flags.contains(held) {
            heldModifier = nil
            delegate.hotkeyModifierReleased()
        }

        if let binding = bindings().first(where: { $0.matches(keyCode: keyCode, flags: flags) }) {
            if isDown {
                heldModifier = binding.modifier.flag
                delegate.hotkeyTriggered(reverse: flags.contains(.maskShift))
            }
            return true
        }

        guard delegate.switcherIsActive else { return false }
        guard isDown else { return true }

        switch keyCode {
        case KeyCode.escape:
            heldModifier = nil
            delegate.hotkeyEscape()
        case KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow:
            delegate.hotkeyArrow(keyCode)
        case KeyCode.w where delegate.switcherIsVisible:
            delegate.hotkeyCommand(.close)
        case KeyCode.m where delegate.switcherIsVisible:
            delegate.hotkeyCommand(.minimize)
        case KeyCode.q where delegate.switcherIsVisible:
            delegate.hotkeyCommand(.quit)
        case KeyCode.h where delegate.switcherIsVisible:
            delegate.hotkeyCommand(.hide)
        default:
            break
        }
        return true
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    return MainActor.assumeIsolated {
        tap.handle(type: type, event: event)
    }
}
