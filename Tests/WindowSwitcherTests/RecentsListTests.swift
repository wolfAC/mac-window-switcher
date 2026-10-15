import Testing
@testable import SwitcherCore

@Suite struct RecentsListTests {
    @Test func touchMovesToFront() {
        var list = RecentsList<Int>()
        list.touch(1)
        list.touch(2)
        list.touch(3)
        list.touch(1)
        #expect(list.keys == [1, 3, 2])
    }

    @Test func capacityDropsOldest() {
        var list = RecentsList<Int>(capacity: 2)
        list.touch(1)
        list.touch(2)
        list.touch(3)
        #expect(list.keys == [3, 2])
    }

    @Test func orderPutsKnownFirstAndKeepsTheRestStable() {
        var list = RecentsList<String>()
        list.touch("b")
        list.touch("d")
        // "a", "c", "e" are unknown and keep their input (z-order) positions after the known ones.
        let ordered = list.ordered(["a", "b", "c", "d", "e"]) { $0 }
        #expect(ordered == ["d", "b", "a", "c", "e"])
    }

    @Test func retainDropsClosedWindows() {
        var list = RecentsList<Int>()
        [1, 2, 3].forEach { list.touch($0) }
        list.retain([1, 3])
        #expect(list.keys == [3, 1])
    }

    @Test func removeWhere() {
        var list = RecentsList<Int>()
        [1, 2, 3, 4].forEach { list.touch($0) }
        list.removeAll { $0 % 2 == 0 }
        #expect(list.keys == [3, 1])
    }
}
