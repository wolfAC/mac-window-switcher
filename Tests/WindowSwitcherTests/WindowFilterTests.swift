import CoreGraphics
import Testing
@testable import SwitcherCore

@Suite struct WindowFilterTests {
    func window(
        subrole: String? = WindowFilter.standardSubrole, size: CGSize = CGSize(width: 800, height: 600), layer: Int? = 0,
        minimized: Bool = false, hidden: Bool = false, own: Bool = false, onSpace: Bool = true, screen: Int? = 0
    ) -> WindowCandidate {
        WindowCandidate(
            subrole: subrole, size: size, layer: layer, isMinimized: minimized, isAppHidden: hidden,
            isOwnProcess: own, isOnCurrentSpace: onSpace, screenIndex: screen
        )
    }

    @Test func showsANormalWindow() {
        #expect(WindowFilter.shouldShow(window(), options: .init()))
    }

    @Test func dropsJunk() {
        let options = WindowFilterOptions()
        #expect(!WindowFilter.shouldShow(window(own: true), options: options))
        #expect(!WindowFilter.shouldShow(window(subrole: "AXFloatingWindow"), options: options))
        #expect(!WindowFilter.shouldShow(window(subrole: nil), options: options))
        #expect(!WindowFilter.shouldShow(window(size: .zero), options: options))
        #expect(!WindowFilter.shouldShow(window(size: CGSize(width: 800, height: 10)), options: options))
        #expect(!WindowFilter.shouldShow(window(layer: 3), options: options))
    }

    @Test func unmatchedLayerIsAllowed() {
        #expect(WindowFilter.shouldShow(window(layer: nil), options: .init()))
    }

    @Test func minimisedAndHiddenFollowSettings() {
        let off = WindowFilterOptions(includeMinimized: false, includeHidden: false)
        #expect(!WindowFilter.shouldShow(window(minimized: true), options: off))
        #expect(!WindowFilter.shouldShow(window(hidden: true), options: off))
        #expect(WindowFilter.shouldShow(window(minimized: true), options: .init()))
        #expect(WindowFilter.shouldShow(window(hidden: true), options: .init()))
    }

    @Test func currentSpaceScope() {
        let options = WindowFilterOptions(scope: .currentSpace)
        #expect(WindowFilter.shouldShow(window(onSpace: true), options: options))
        #expect(!WindowFilter.shouldShow(window(onSpace: false), options: options))
        // Minimised windows aren't on any Space but still count as "here".
        #expect(WindowFilter.shouldShow(window(minimized: true, onSpace: false), options: options))
    }

    @Test func currentScreenScope() {
        let options = WindowFilterOptions(scope: .currentScreen, activeScreenIndex: 1)
        #expect(WindowFilter.shouldShow(window(screen: 1), options: options))
        #expect(!WindowFilter.shouldShow(window(screen: 0), options: options))
        #expect(!WindowFilter.shouldShow(window(screen: nil), options: options))
    }
}
