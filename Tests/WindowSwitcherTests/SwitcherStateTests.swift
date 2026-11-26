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

@Suite struct TypeToFilterTests {
    private func visibleState(count: Int = 5) -> SwitcherState {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: count))
        _ = state.handle(.holdElapsed)
        return state
    }

    @Test func filteringSelectsFirstMatchAndPins() {
        var state = visibleState()
        #expect(state.handle(.filtered(count: 2)) == [.show, .updateSelection(0)])
        #expect(state.isPinned)
    }

    @Test func releasingModifierWhileSearchingKeepsItOpen() {
        var state = visibleState()
        _ = state.handle(.filtered(count: 2))
        #expect(state.handle(.released) == [])
        #expect(state.isActive && state.isVisible)
        #expect(state.handle(.confirm) == [.hide, .commit(index: 0)])
        #expect(!state.isActive)
    }

    @Test func noMatchesStaysOpenAndReturnCancels() {
        var state = visibleState()
        #expect(state.handle(.filtered(count: 0)) == [.show])
        #expect(state.isVisible)
        // A reload that still finds nothing doesn't close it either.
        #expect(state.handle(.loaded(count: 0)) == [.show])
        #expect(state.handle(.confirm) == [.hide, .cancel])
    }

    @Test func escapeCancelsSearch() {
        var state = visibleState()
        _ = state.handle(.filtered(count: 3))
        #expect(state.handle(.escape) == [.hide, .cancel])
        #expect(!state.isPinned)
    }

    @Test func filterIgnoredBeforeOverlayShows() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        #expect(state.handle(.filtered(count: 1)) == [])
        #expect(!state.isPinned)
    }

    @Test func returnWithoutSearchingCommitsSelection() {
        var state = visibleState()
        #expect(state.handle(.confirm) == [.hide, .commit(index: 1)])
    }

    @Test func tabMovesThroughMatches() {
        var state = visibleState()
        _ = state.handle(.filtered(count: 3))
        #expect(state.handle(.move(by: 1)) == [.updateSelection(1)])
        #expect(state.handle(.move(by: -2)) == [.updateSelection(2)])
    }
}

@Suite struct WindowSearchTests {
    @Test func matchesAnyFieldIgnoringCaseAndAccents() {
        #expect(WindowSearch.matches("1056", fields: ["NINTO-1056", "Code", "x.js — NINTO-1056"]))
        #expect(WindowSearch.matches("WOLF", fields: ["Wolf", "Google Chrome", ""]))
        #expect(WindowSearch.matches("cafe", fields: ["Café menu"]))
        #expect(!WindowSearch.matches("1057", fields: ["NINTO-1056", "Code"]))
    }

    @Test func everyTermMustMatchSomewhere() {
        let fields = ["NINTO-870", "Code", "posts.js — NINTO-870"]
        #expect(WindowSearch.matches("code 870", fields: fields))
        #expect(WindowSearch.matches("posts 870", fields: fields))
        #expect(!WindowSearch.matches("code 1056", fields: fields))
    }

    @Test func emptyQueryMatchesAll() {
        #expect(WindowSearch.matches("", fields: ["anything"]))
        #expect(WindowSearch.matches("   ", fields: ["anything"]))
    }
}
