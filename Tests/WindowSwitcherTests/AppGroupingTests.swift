import Testing
@testable import SwitcherCore

@Suite struct AppGroupingTests {
    /// (app, window) pairs in most-recently-used order.
    let recent = [("code", 1), ("chrome", 1), ("code", 2), ("slack", 1), ("chrome", 2), ("code", 3)]

    @Test func appsInOrderOfTheirMostRecentWindow() {
        let grouped = AppGrouping.grouped(recent) { $0.0 }
        #expect(grouped.map(\.0) == ["code", "code", "code", "chrome", "chrome", "slack"])
    }

    @Test func windowsKeepRecencyInsideEachApp() {
        let grouped = AppGrouping.grouped(recent) { $0.0 }
        #expect(grouped.filter { $0.0 == "code" }.map(\.1) == [1, 2, 3])
        #expect(grouped.filter { $0.0 == "chrome" }.map(\.1) == [1, 2])
    }

    @Test func emptyAndSingleApp() {
        #expect(AppGrouping.grouped([Int]()) { $0 }.isEmpty)
        #expect(AppGrouping.grouped([1, 1, 1]) { $0 } == [1, 1, 1])
    }
}

@Suite struct GroupedSessionTests {
    // Grouped list: code1 code2 code3 chrome1 chrome2 slack1, previous window (chrome1) at 3.

    @Test func quickTapGoesToPreviousWindow() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 6, previous: 3))
        #expect(state.handle(.released) == [.commit(index: 3)])
    }

    @Test func tabsBeforeLoadCountOnFromPrevious() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 6, previous: 3))
        #expect(state.handle(.released) == [.commit(index: 4)])
    }

    @Test func tabsAfterShowingMoveFromPreviousAndWrap() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 6, previous: 3))
        #expect(state.handle(.holdElapsed) == [.show, .updateSelection(3)])
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.trigger(reverse: false))
        #expect(state.handle(.trigger(reverse: false)) == [.updateSelection(0)])
    }

    @Test func reverseSessionStillStartsFromTheEnd() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: true))
        _ = state.handle(.loaded(count: 6, previous: 3))
        #expect(state.handle(.released) == [.commit(index: 5)])
    }

    @Test func reloadKeepsSlotInsteadOfJumping() {
        var state = SwitcherState()
        _ = state.handle(.trigger(reverse: false))
        _ = state.handle(.loaded(count: 6, previous: 3))
        _ = state.handle(.holdElapsed)
        #expect(state.handle(.loaded(count: 5, previous: 1)) == [.show, .updateSelection(3)])
    }
}
