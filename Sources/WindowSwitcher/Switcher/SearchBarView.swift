import AppKit

/// The pill-shaped search field at the top of the overlay. It isn't a real text field:
/// the panel never takes keyboard focus (it must not steal it from the app you're in),
/// so the event tap feeds it text and this view only draws it.
@MainActor
final class SearchBarView: NSView {
    static let height: CGFloat = 34

    private let icon = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let caret = NSView()

    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.borderWidth = 1

        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        icon.imageScaling = .scaleNone
        addSubview(icon)

        textLabel.font = .systemFont(ofSize: 15, weight: .medium)
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.maximumNumberOfLines = 1
        addSubview(textLabel)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countLabel.alignment = .right
        countLabel.textColor = .tertiaryLabelColor
        addSubview(countLabel)

        caret.wantsLayer = true
        caret.layer?.cornerRadius = 1
        addSubview(caret)

        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilitySubrole(.searchField)
        setAccessibilityLabel(String(localized: "Search windows"))
        startCaretBlink()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            caret.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        icon.contentTintColor = .secondaryLabelColor
    }

    /// Empty `query` shows the placeholder.
    func update(query: String, matches: Int, total: Int) {
        applyColors()
        let empty = query.isEmpty
        textLabel.stringValue = empty ? String(localized: "Type to search") : query
        textLabel.textColor = empty ? .tertiaryLabelColor : .labelColor
        countLabel.stringValue = empty ? "" : String(localized: "\(matches) of \(total)")
        caret.isHidden = empty
        setAccessibilityValue(query)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let inset: CGFloat = 14
        icon.frame = CGRect(x: inset - 2, y: (h - 18) / 2, width: 18, height: 18)

        countLabel.sizeToFit()
        let countWidth = countLabel.stringValue.isEmpty ? 0 : countLabel.frame.width
        countLabel.frame = CGRect(x: bounds.width - inset - countWidth, y: (h - countLabel.frame.height) / 2, width: countWidth, height: countLabel.frame.height)

        let textX = icon.frame.maxX + 8
        let maxText = max(0, countLabel.frame.minX - 10 - textX - 4)
        let natural = textLabel.attributedStringValue.size().width + 4
        let textHeight = textLabel.intrinsicContentSize.height
        textLabel.frame = CGRect(x: textX, y: (h - textHeight) / 2, width: min(natural, maxText), height: textHeight)
        caret.frame = CGRect(x: textLabel.frame.maxX - 1, y: (h - 18) / 2, width: 2, height: 18)
    }

    private func startCaretBlink() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0
        blink.duration = 0.53
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        caret.layer?.add(blink, forKey: "blink")
    }
}
