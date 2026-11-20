import Foundation
import Testing
@testable import SwitcherCore

@Suite struct WindowNamingTests {
    @Test func vsCodeShowsWorktreeFolder() {
        let name = { WindowNaming.name(title: $0, appName: "Code", style: .projectFolder) }
        #expect(name("functions.env — NINTO-832") == "NINTO-832")
        #expect(name("consentFormat.js (Working Tree) (consentFormat.js) — ninto-NINTO-1056") == "ninto-NINTO-1056")
        #expect(name("● users.js — NINTO-870 — Visual Studio Code") == "NINTO-870")
        // Nothing open but the folder: the title is the folder.
        #expect(name("NINTO-832") == "NINTO-832")
    }

    @Test func chromeShowsProfile() {
        let name = { WindowNaming.name(title: $0, appName: "Google Chrome", style: .browserProfile) }
        #expect(name("GitHub - wolf/repo · GitHub - Google Chrome - Anbu (Your Chrome)") == "Anbu (Your Chrome)")
        // A page title that itself mentions the browser still takes the last suffix.
        #expect(name("Google Chrome - Google Chrome - Work - Google Chrome - Wolf") == "Wolf")
        // Single profile: no suffix, so the app name.
        #expect(name("GitHub") == "Google Chrome")
    }

    @Test func terminalShowsTabTitleOnly() {
        let name = { WindowNaming.name(title: $0, appName: "Terminal", style: .terminal, userName: "wolf") }
        #expect(name("wolf — ◑ Mac alt-tab window switching — caffeinate ◂ claude — 80×24") == "Mac alt-tab window switching")
        #expect(name("wolf — ✳ RemoveMacAI.zip — caffeinate ◂ claude — 80×24") == "RemoveMacAI.zip")
        #expect(name("wolf — -zsh — 80×24") == "-zsh")
        #expect(name("wolf — ~/Workspace — vim notes.md — 120×40") == "~/Workspace")
        // Only the size left: fall back to the full title rather than blank.
        #expect(name("wolf — 80×24") == "wolf — 80×24")
    }

    @Test func appNameAndTitle() {
        #expect(WindowNaming.name(title: "@someone - Discord", appName: "Discord", style: .appName) == "Discord")
        #expect(WindowNaming.name(title: "Inbox", appName: "Mail", style: .title) == "Inbox")
        #expect(WindowNaming.name(title: "", appName: "Mail", style: .title) == "Mail")
    }

    @Test func customPatternUsesFirstGroup() {
        #expect(WindowNaming.name(title: "file.kt – [backend] – IntelliJ", appName: "IntelliJ", style: .custom, pattern: #"\[(.+?)\]"#) == "backend")
        #expect(WindowNaming.name(title: "abc 123", appName: "X", style: .custom, pattern: #"\d+"#) == "123")
    }

    @Test func badOrMissingMatchFallsBackToTitle() {
        #expect(WindowNaming.name(title: "Some title", appName: "X", style: .custom, pattern: "(") == "Some title")
        #expect(WindowNaming.name(title: "Some title", appName: "X", style: .custom, pattern: "zzz") == "Some title")
        #expect(WindowNaming.name(title: "Some title", appName: "X", style: .custom, pattern: "") == "Some title")
    }

    @Test func rulesRoundTrip() throws {
        let data = try JSONEncoder().encode(NamingRule.defaults)
        #expect(try JSONDecoder().decode([NamingRule].self, from: data) == NamingRule.defaults)
    }
}
