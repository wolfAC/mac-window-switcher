import AppKit
import SwitcherCore

/// A non-activating floating panel: it never takes focus from the app you're in,
/// and it follows you onto every Space and over full-screen apps.
@MainActor
final class SwitcherPanel: NSPanel {
    let grid = SwitcherGridView()
    private let scrollView = NSScrollView()
    private let background = NSVisualEffectView()

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

    func present(windows: [WindowInfo], metrics: GridMetrics, showTitles: Bool, on screen: NSScreen, appearance: NSAppearance?, thumbnail: (WindowInfo) -> CGImage?) {
        self.appearance = appearance
        applyAccessibilitySettings()

        let visible = screen.visibleFrame
        let maxSize = CGSize(width: visible.width * 0.9, height: visible.height * 0.85)
        let layout = GridLayout.compute(aspectRatios: windows.map(\.aspectRatio), maxSize: maxSize, metrics: metrics)
        grid.configure(
            windows: windows, layout: layout, metrics: metrics, showTitles: showTitles,
            showScreen: NSScreen.screens.count > 1, thumbnail: thumbnail
        )

        let size = layout.viewportSize
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setFrame(CGRect(origin: origin, size: size).integral, display: false)
        scrollView.frame = background.bounds
        grid.scroll(.zero)
        // No fade: the overlay should feel instant, and this also respects Reduce Motion.
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
