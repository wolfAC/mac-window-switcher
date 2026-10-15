import CoreGraphics

enum KeyCode {
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let downArrow: CGKeyCode = 125
    static let upArrow: CGKeyCode = 126
    static let w: CGKeyCode = 13
    static let m: CGKeyCode = 46
    static let q: CGKeyCode = 12
    static let h: CGKeyCode = 4
}

enum TriggerModifier: String, CaseIterable, Identifiable {
    case command, option, control

    var id: String { rawValue }

    var flag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        }
    }

    var title: String {
        switch self {
        case .command: String(localized: "⌘ Command")
        case .option: String(localized: "⌥ Option")
        case .control: String(localized: "⌃ Control")
        }
    }

    static let all: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
}

/// A modifier + key that opens the switcher. Shift reverses direction.
struct KeyBinding: Equatable {
    var modifier: TriggerModifier
    var keyCode: CGKeyCode = KeyCode.tab

    /// Exactly this modifier among Cmd/Option/Control (Shift is allowed), plus the key.
    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(TriggerModifier.all) == modifier.flag
    }
}
