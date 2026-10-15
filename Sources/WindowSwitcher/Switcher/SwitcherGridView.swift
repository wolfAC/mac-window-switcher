import AppKit
import SwitcherCore

/// Lays out one cell per window from a `GridLayout`, highlights the selection and
/// reports hover / click / per-window button presses.
@MainActor
final class SwitcherGridView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onCommand: ((Int, WindowCommand) -> Void)?

    private(set) var layout: GridLayout?
    private var cells: [WindowCellView] = []
    private var selected: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(windows: [WindowInfo], layout: GridLayout, metrics: GridMetrics, showTitles: Bool, showScreen: Bool, thumbnail: (WindowInfo) -> CGImage?) {
        self.layout = layout
        cells.forEach { $0.removeFromSuperview() }
        cells = zip(windows, layout.cellFrames).enumerated().map { index, pair in
            let (window, frame) = pair
            let cell = WindowCellView(frame: frame, metrics: metrics, showTitle: showTitles)
            cell.configure(window, screenNumber: showScreen ? window.screenIndex.map { $0 + 1 } : nil)
            cell.setThumbnail(thumbnail(window))
            cell.onCommand = { [weak self] command in self?.onCommand?(index, command) }
            addSubview(cell)
            return cell
        }
        setFrameSize(layout.contentSize)
        selected = nil
    }

    func select(_ index: Int) {
        if let selected, selected < cells.count { cells[selected].isSelected = false }
        guard index < cells.count else { return }
        selected = index
        cells[index].isSelected = true
        scrollToVisible(cells[index].frame.insetBy(dx: 0, dy: -8))
        NSAccessibility.post(element: cells[index], notification: .focusedUIElementChanged)
    }

    func setThumbnail(_ image: CGImage, forWindowAt indices: [Int]) {
        for index in indices where index < cells.count {
            cells[index].setThumbnail(image)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        if let index = index(for: event) { onHover?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        if let index = index(for: event) { onClick?(index) }
    }

    private func index(for event: NSEvent) -> Int? {
        layout?.index(at: convert(event.locationInWindow, from: nil))
    }
}

@MainActor
private final class WindowCellView: NSView {
    var onCommand: ((WindowCommand) -> Void)?

    private let thumbnailView = NSImageView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let screenLabel = NSTextField(labelWithString: "")
    private let trafficLights = TrafficLightGroup()
    private let quitButton = TrafficLightButton(kind: .quit, help: String(localized: "Quit app (Q)"))
    private let actions = NSStackView()
    private var appIcon: NSImage?
    private var label = ""

    var isSelected = false {
        didSet { updateSelection() }
    }

    init(frame: CGRect, metrics: GridMetrics, showTitle: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.clear.cgColor

        let pad = metrics.cellPadding
        let thumbFrame = CGRect(x: pad, y: pad, width: frame.width - 2 * pad, height: metrics.thumbnailHeight)
        thumbnailView.frame = thumbFrame
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        addSubview(thumbnailView)

        let iconSide = min(32, metrics.thumbnailHeight / 3)
        iconView.frame = CGRect(x: thumbFrame.minX + 4, y: thumbFrame.maxY - iconSide - 4, width: iconSide, height: iconSide)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        // Bottom-right: the top-left corner belongs to the traffic lights.
        screenLabel.frame = CGRect(x: thumbFrame.maxX - 32, y: thumbFrame.maxY - 20, width: 28, height: 16)
        screenLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        screenLabel.alignment = .center
        screenLabel.textColor = .white
        screenLabel.wantsLayer = true
        screenLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        screenLabel.layer?.cornerRadius = 4
        screenLabel.isHidden = true
        addSubview(screenLabel)

        if showTitle {
            titleLabel.frame = CGRect(x: pad, y: thumbFrame.maxY + 3, width: frame.width - 2 * pad, height: metrics.titleHeight - 3)
            titleLabel.font = .systemFont(ofSize: 12)
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.cell?.truncatesLastVisibleLine = true
            addSubview(titleLabel)
        }

        // macOS window buttons, top-left like on a real window.
        trafficLights.onCommand = { [weak self] command in self?.onCommand?(command) }
        trafficLights.frame.origin = CGPoint(x: thumbFrame.minX + 6, y: thumbFrame.minY + 6)
        trafficLights.isHidden = true
        addSubview(trafficLights)

        // Quit: a purple power button, top-right, centred on the traffic lights' row.
        let quitSide = TrafficLightButton.quitDiameter
        let rowMidY = thumbFrame.minY + 6 + TrafficLightGroup.diameter / 2
        quitButton.frame = CGRect(x: thumbFrame.maxX - quitSide - 6, y: rowMidY - quitSide / 2, width: quitSide, height: quitSide)
        quitButton.onPress = { [weak self] kind in self?.onCommand?(kind.command) }
        quitButton.isHidden = true
        addSubview(quitButton)

        // Hide has no macOS equivalent button, so it stays a small button left of Quit.
        actions.orientation = .horizontal
        let hide = ActionButton(symbol: "eye.slash", help: String(localized: "Hide app (H)")) { [weak self] in self?.onCommand?(.hide) }
        actions.addArrangedSubview(hide)
        let actionsSize = actions.fittingSize
        actions.frame = CGRect(x: quitButton.frame.minX - actionsSize.width - 4, y: rowMidY - actionsSize.height / 2, width: actionsSize.width, height: actionsSize.height)
        actions.isHidden = true
        addSubview(actions)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // Let the grid handle clicks and hover anywhere except the action buttons.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit.flatMap { $0 is ActionButton || $0.superview is ActionButton || $0 is TrafficLightButton ? $0 : nil }
    }

    func configure(_ window: WindowInfo, screenNumber: Int?) {
        appIcon = window.appIcon
        iconView.image = window.appIcon
        titleLabel.stringValue = window.displayTitle
        label = window.title.isEmpty ? window.appName : "\(window.appName): \(window.title)"
        var state: [String] = []
        if window.isMinimized { state.append(String(localized: "minimised")) }
        if window.isAppHidden { state.append(String(localized: "hidden")) }
        if let screenNumber {
            screenLabel.stringValue = "\(screenNumber)"
            screenLabel.isHidden = false
            state.append(String(localized: "display \(screenNumber)"))
        }
        setAccessibilityLabel(([label] + state).joined(separator: ", "))
        if window.isMinimized || window.isAppHidden {
            thumbnailView.alphaValue = 0.6
        }
    }

    func setThumbnail(_ image: CGImage?) {
        if let image {
            thumbnailView.image = NSImage(cgImage: image, size: .zero)
            iconView.isHidden = false
        } else {
            // Placeholder: a big app icon in the thumbnail area, no badge.
            thumbnailView.image = appIcon
            iconView.isHidden = true
        }
    }

    private func updateSelection() {
        layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : nil
        layer?.borderColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        actions.isHidden = !isSelected
        trafficLights.isHidden = !isSelected
        quitButton.isHidden = !isSelected
        setAccessibilitySelected(isSelected)
    }
}

@MainActor
private final class ActionButton: NSButton {
    private let handler: () -> Void

    init(symbol: String, help: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        bezelStyle = .circular
        isBordered = true
        toolTip = help
        target = self
        action = #selector(fire)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func fire() { handler() }
}

/// Red / yellow / green buttons drawn like macOS's window controls. Real
/// `standardWindowButton`s render grey here because the panel is never the key window.
@MainActor
private final class TrafficLightGroup: NSView {
    var onCommand: ((WindowCommand) -> Void)?
    private let buttons: [TrafficLightButton]

    static let diameter: CGFloat = 12
    static let spacing: CGFloat = 8

    init() {
        buttons = [
            TrafficLightButton(kind: .close, help: String(localized: "Close window (W)")),
            TrafficLightButton(kind: .minimize, help: String(localized: "Minimise window (M)")),
            TrafficLightButton(kind: .fullScreen, help: String(localized: "Switch to this window in full screen")),
        ]
        let width = Self.diameter * 3 + Self.spacing * 2
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: Self.diameter))
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * (Self.diameter + Self.spacing), y: 0, width: Self.diameter, height: Self.diameter)
            button.onPress = { [weak self] kind in self?.onCommand?(kind.command) }
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // Like macOS, all three glyphs appear when the pointer is over any of the buttons.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setGlyphs(true) }
    override func mouseExited(with event: NSEvent) { setGlyphs(false) }

    override var isHidden: Bool {
        didSet { if isHidden { setGlyphs(false) } }
    }

    private func setGlyphs(_ visible: Bool) {
        buttons.forEach { $0.showsGlyph = visible }
    }
}

@MainActor
private final class TrafficLightButton: NSView {
    enum Kind {
        case close, minimize, fullScreen, quit

        var command: WindowCommand {
            switch self {
            case .close: .close
            case .minimize: .minimize
            case .fullScreen: .fullScreen
            case .quit: .quit
            }
        }

        // macOS Sonoma/Sequoia window control colours.
        var fill: NSColor {
            switch self {
            case .close: NSColor(srgbRed: 1.0, green: 0.373, blue: 0.341, alpha: 1)
            case .minimize: NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1)
            case .fullScreen: NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)
            case .quit: NSColor(srgbRed: 0.686, green: 0.322, blue: 0.871, alpha: 1) // systemPurple
            }
        }

        var border: NSColor {
            switch self {
            case .close: NSColor(srgbRed: 0.878, green: 0.267, blue: 0.243, alpha: 1)
            case .minimize: NSColor(srgbRed: 0.871, green: 0.631, blue: 0.137, alpha: 1)
            case .fullScreen: NSColor(srgbRed: 0.102, green: 0.671, blue: 0.161, alpha: 1)
            case .quit: NSColor(srgbRed: 0.553, green: 0.231, blue: 0.722, alpha: 1)
            }
        }
    }

    /// The quit button carries its power glyph all the time, so it's a little bigger.
    static let quitDiameter: CGFloat = 16

    let kind: Kind
    var onPress: ((Kind) -> Void)?
    var showsGlyph = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(kind: Kind, help: String) {
        self.kind = kind
        super.init(frame: .zero)
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?(kind) }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?(kind)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (isPressed ? kind.fill.blended(withFraction: 0.25, of: .black) ?? kind.fill : kind.fill).setFill()
        circle.fill()
        kind.border.setStroke()
        circle.lineWidth = 0.5
        circle.stroke()

        if kind == .quit {
            drawPowerSymbol()
            return
        }
        guard showsGlyph else { return }
        NSColor.black.withAlphaComponent(0.55).set()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.1
        glyph.lineCapStyle = .round
        switch kind {
        case .close:
            let r: CGFloat = 2.6
            glyph.move(to: CGPoint(x: c.x - r, y: c.y - r)); glyph.line(to: CGPoint(x: c.x + r, y: c.y + r))
            glyph.move(to: CGPoint(x: c.x - r, y: c.y + r)); glyph.line(to: CGPoint(x: c.x + r, y: c.y - r))
            glyph.stroke()
        case .minimize:
            glyph.move(to: CGPoint(x: c.x - 3.2, y: c.y)); glyph.line(to: CGPoint(x: c.x + 3.2, y: c.y))
            glyph.stroke()
        case .fullScreen:
            // Two triangles pointing to opposite corners (flipped coordinates: y grows down).
            let a = NSBezierPath()
            let r: CGFloat = 2.7, leg: CGFloat = 0.4
            a.move(to: CGPoint(x: c.x - r, y: c.y - r)); a.line(to: CGPoint(x: c.x + leg, y: c.y - r)); a.line(to: CGPoint(x: c.x - r, y: c.y + leg)); a.close()
            a.move(to: CGPoint(x: c.x + r, y: c.y + r)); a.line(to: CGPoint(x: c.x - leg, y: c.y + r)); a.line(to: CGPoint(x: c.x + r, y: c.y - leg)); a.close()
            a.fill()
        case .quit:
            break // drawn by drawPowerSymbol()
        }
    }

    private func drawPowerSymbol() {
        let config = NSImage.SymbolConfiguration(pointSize: bounds.height * 0.42, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let size = symbol.size
        symbol.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }
}
