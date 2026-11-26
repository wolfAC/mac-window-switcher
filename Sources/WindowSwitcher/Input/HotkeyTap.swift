import AppKit
import CoreGraphics

@MainActor
protocol HotkeyTapDelegate: AnyObject {
    var switcherIsActive: Bool { get }
    var switcherIsVisible: Bool { get }
    func hotkeyTriggered(reverse: Bool)
    func hotkeyModifierReleased()
    func hotkeyEscape()
    func hotkeyArrow(_ keyCode: CGKeyCode)
    func hotkeyCommand(_ command: WindowCommand)
    /// Text typed while the overlay is open, for type-to-filter.
    func hotkeyType(_ text: String)
    func hotkeyBackspace()
    func hotkeyConfirm()
    /// Tab without the modifier (after it was released while searching).
    func hotkeyMove(by delta: Int)
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

    /// False when the tap should be catching keys but isn't: never created, invalidated
    /// (e.g. across sleep or a WindowServer restart), or left disabled by macOS.
    var isHealthy: Bool {
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    /// Recreates the tap from scratch.
    @discardableResult
    func restart() -> Bool {
        stop()
        return start()
    }

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

        let visible = delegate.switcherIsVisible
        // Window commands need Shift, so plain letters are free for type-to-filter.
        let shift = flags.contains(.maskShift)
        switch keyCode {
        case KeyCode.escape:
            heldModifier = nil
            delegate.hotkeyEscape()
        case KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow:
            delegate.hotkeyArrow(keyCode)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            heldModifier = nil
            delegate.hotkeyConfirm()
        case KeyCode.tab:
            delegate.hotkeyMove(by: shift ? -1 : 1)
        case KeyCode.delete where visible:
            delegate.hotkeyBackspace()
        case KeyCode.w where visible && shift:
            delegate.hotkeyCommand(.close)
        case KeyCode.m where visible && shift:
            delegate.hotkeyCommand(.minimize)
        case KeyCode.q where visible && shift:
            delegate.hotkeyCommand(.quit)
        case KeyCode.h where visible && shift:
            delegate.hotkeyCommand(.hide)
        default:
            if visible, let text = Self.typedText(event) {
                delegate.hotkeyType(text)
            }
        }
        return true
    }
}

extension HotkeyTap {
    /// The printable characters a key event types, ignoring the held modifier (so Cmd+N
    /// types "n"). Nil for keys that type nothing printable.
    static func typedText(_ event: CGEvent) -> String? {
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
        else { return nil }
        return characters
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    return MainActor.assumeIsolated {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = tap.handle(type: type, event: event)
        // Every keystroke on the Mac waits for this callback; anything slow here is a bug.
        let ms = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        if ms >= 50 { Log.perf.notice("Event tap callback took \(ms) ms (type \(type.rawValue))") }
        return result
    }
}
