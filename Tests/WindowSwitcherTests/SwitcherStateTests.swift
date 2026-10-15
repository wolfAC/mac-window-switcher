import Testing
@testable import SwitcherCore

@Suite struct SwitcherStateTests {
    @Test func quickTapSwitchesToPreviousWithoutShowing() {
        var state = SwitcherState()
        #expect(state.handle(.trigger(reverse: false)) == [.loadWindows, .startHoldTimer])
        #expect(state.handle(.loaded(count: 5)) == [])
        #expect(state.handle(.released) == [.commit(index: 1)])
        #expect(!state.isActive)
        // A late hold timer does nothing.
        #expect(state.handle(.holdElapsed) == [])
    }

    @Test func releaseBeforeLoadCommitsOnceLoaded() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        #expect(state.handle(.released) == [])
        #expect(state.handle(.loaded(count: 3)) == [.commit(index: 1)])
        #expect(!state.isActive)
    }

    @Test func holdShowsOverlay() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 4))
        #expect(state.handle(.holdElapsed) == [.show, .updateSelection(1)])
        #expect(state.isVisible)
        #expect(state.handle(.released) == [.hide, .commit(index: 1)])
    }

    @Test func holdBeforeLoadShowsWhenLoaded() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        #expect(state.handle(.holdElapsed) == [])
        #expect(state.handle(.loaded(count: 4)) == [.show, .updateSelection(1)])
    }

    @Test func tabsCountedBeforeLoadAndWrap() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 3))
        // 3 forward steps over 3 windows wraps back to the current window.
        #expect(state.selection == 0)
    }

    @Test func shiftTabGoesBackwardsWithWrap() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: true))
        _ = state.handle(.loaded(count: 4))
        #expect(state.selection == 3)
        _ = state.handle(.holdElapsed)
        #expect(state.handle(.trigger(reverse: true)) == [.updateSelection(2)])
        #expect(state.handle(.trigger(reverse: false)) == [.updateSelection(3)])
        #expect(state.handle(.trigger(reverse: false)) == [.updateSelection(0)])
    }

    @Test func escapeCancels() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 4))
        _ = state.handle(.holdElapsed)
        #expect(state.handle(.escape) == [.hide, .cancel])
        #expect(!state.isActive)
        #expect(state.handle(.released) == [])
    }

    @Test func escapeBeforeShowingCancelsQuietly() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        #expect(state.handle(.escape) == [.cancel])
    }

    @Test func singleWindowSelectsIt() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 1))
        #expect(state.handle(.released) == [.commit(index: 0)])
    }

    @Test func noWindowsCancels() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.holdElapsed)
        #expect(state.handle(.loaded(count: 0)) == [])
        #expect(!state.isVisible)
        #expect(state.handle(.released) == [.cancel])
    }

    @Test func mouseAndArrows() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 5))
        // Ignored until visible.
        #expect(state.handle(.select(index: 3)) == [])
        _ = state.handle(.holdElapsed)
        #expect(state.handle(.select(index: 3)) == [.updateSelection(3)])
        #expect(state.handle(.select(index: 3)) == [])
        #expect(state.handle(.select(index: 9)) == [])
        #expect(state.handle(.move(by: 2)) == [.updateSelection(0)])
        #expect(state.handle(.move(by: -1)) == [.updateSelection(4)])
        #expect(state.handle(.click(index: 2)) == [.hide, .commit(index: 2)])
    }

    @Test func reloadAfterClosingClampsSelection() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: true))
        _ = state.handle(.loaded(count: 3))
        _ = state.handle(.holdElapsed)
        #expect(state.selection == 2)
        // The last window was closed.
        #expect(state.handle(.loaded(count: 2)) == [.show, .updateSelection(1)])
        // Everything closed.
        #expect(state.handle(.loaded(count: 0)) == [.hide, .cancel])
        #expect(!state.isActive)
    }

    @Test func retriggerAfterFinishStartsFresh() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 3))
        _ = state.handle(.released)
        #expect(state.handle(.trigger(reverse: false)) == [.loadWindows, .startHoldTimer])
        #expect(state.count == nil)
    }
}
