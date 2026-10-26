import Testing
@testable import SwitcherCore

@Suite struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() {
        #expect(AppVersion("v0.2.0")?.parts == [0, 2, 0])
        #expect(AppVersion("1.10")?.parts == [1, 10])
        #expect(AppVersion("1.3.0-beta")?.parts == [1, 3, 0])
    }

    @Test func rejectsJunk() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumerically() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("1.2") == v("1.2.0"))
        #expect(try v("0.2.0") < v("v0.2.1"))
        #expect(try !(v("0.3.0") < v("0.3.0")))
    }
}
