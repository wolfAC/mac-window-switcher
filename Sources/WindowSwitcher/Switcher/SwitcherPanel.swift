import AppKit
import SwitcherCore

/// A non-activating floating panel: it never takes focus from the app you're in,
/// and it follows you onto every Space and over full-screen apps.
@MainActor
final class SwitcherPanel: NSPanel {
    let grid = SwitcherGridView()
    private let scrollView = NSScrollView()
    private let background = NSVisualEffectView()
    private let searchBar = SearchBarView()
    private let emptyLabel = NSTextField(labelWithString: "")

    /// Space above the grid for the search bar (the grid adds its own inset below it).
    private static let headerHeight: CGFloat = 14 + SearchBarView.height
    private static let minWidth: CGFloat = 480
    private static let maxSearchWidth: CGFloat = 440
    /// Room for the "no matches" message when the grid is empty.
    private static let emptyHeight: CGFloat = 120

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "Window Switcher"))

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = grid
        scrollView.autoresizingMask = [.width, .height]
        background.addSubview(scrollView)
        background.addSubview(searchBar)

        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        background.addSubview(emptyLabel)
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Reduce Transparency swaps the frosted glass for a solid background.
    private func applyAccessibilitySettings() {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        background.state = reduceTransparency ? .inactive : .active
        background.material = reduceTransparency ? .windowBackground : .hudWindow
    }

    /// `query` is the type-to-filter text ("" shows the placeholder); `total` is the
    /// unfiltered window count, for the "2 of 9" in the search bar.
    func present(windows: [WindowInfo], query: String, total: Int, metrics: GridMetrics, showTitles: Bool, on screen: NSScreen, appearance: NSAppearance?, thumbnail: (WindowInfo) -> CGImage?) {
        self.appearance = appearance
        applyAccessibilitySettings()

        let visible = screen.visibleFrame
        let header = Self.headerHeight
        let maxSize = CGSize(width: visible.width * 0.9, height: visible.height * 0.85 - header)
        let layout = GridLayout.compute(aspectRatios: windows.map(\.aspectRatio), maxSize: maxSize, metrics: metrics)
        grid.configure(
            windows: windows, layout: layout, metrics: metrics, showTitles: showTitles,
            showScreen: NSScreen.screens.count > 1, thumbnail: thumbnail
        )

        let gridHeight = windows.isEmpty ? Self.emptyHeight : layout.viewportSize.height
        let size = CGSize(
            width: max(layout.viewportSize.width, min(Self.minWidth, visible.width * 0.9)),
            height: gridHeight + header
        )
        // Centred on the screen, so it stays put as matches change.
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setFrame(CGRect(origin: origin, size: size).integral, display: false)

        let bounds = background.bounds
        // The grid is narrower than the panel when there are few windows: centre it.
        let gridWidth = min(layout.viewportSize.width, bounds.width)
        scrollView.frame = CGRect(x: ((bounds.width - gridWidth) / 2).rounded(), y: 0, width: gridWidth, height: bounds.height - header)

        let barWidth = min(Self.maxSearchWidth, bounds.width - 40)
        // NSVisualEffectView isn't flipped: y counts up from the bottom, so the bar's top sits 14 pt below the panel's top.
        searchBar.frame = CGRect(
            x: ((bounds.width - barWidth) / 2).rounded(), y: bounds.height - 14 - SearchBarView.height,
            width: barWidth, height: SearchBarView.height
        )
        searchBar.update(query: query, matches: windows.count, total: total)

        emptyLabel.isHidden = !windows.isEmpty
        if windows.isEmpty {
            emptyLabel.stringValue = String(localized: "No windows match “\(query)”")
            emptyLabel.sizeToFit()
            emptyLabel.frame = CGRect(x: 20, y: ((gridHeight - emptyLabel.frame.height) / 2).rounded(), width: bounds.width - 40, height: emptyLabel.frame.height)
        }
        grid.scroll(.zero)
        // No fade: the overlay should feel instant, and this also respects Reduce Motion.
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
