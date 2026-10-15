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

        screenLabel.frame = CGRect(x: thumbFrame.minX + 4, y: thumbFrame.minY + 4, width: 28, height: 16)
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

        actions.orientation = .horizontal
        actions.spacing = 2
        for (symbol, command, help) in [
            ("xmark", WindowCommand.close, String(localized: "Close window (W)")),
            ("minus", .minimize, String(localized: "Minimise window (M)")),
            ("eye.slash", .hide, String(localized: "Hide app (H)")),
            ("power", .quit, String(localized: "Quit app (Q)")),
        ] {
            let button = ActionButton(symbol: symbol, help: help) { [weak self] in self?.onCommand?(command) }
            actions.addArrangedSubview(button)
        }
        let actionsSize = actions.fittingSize
        actions.frame = CGRect(x: thumbFrame.maxX - actionsSize.width - 4, y: thumbFrame.minY + 4, width: actionsSize.width, height: actionsSize.height)
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
        return hit.flatMap { $0 is ActionButton || $0.superview is ActionButton ? $0 : nil }
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
