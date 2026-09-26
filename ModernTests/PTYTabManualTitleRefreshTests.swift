//
//  PTYTabManualTitleRefreshTests.swift
//  ModernTests
//
//  A tab title the user set by hand (Edit Tab Title, ⌘I) lives in the tab's
//  titleOverride and must outrank the session name, the way an OSC 2 title
//  already does. Two code paths set the tab bar's label and they disagreed:
//  -updateTabTitleForCurrentSessionName: reads the override, while
//  -tabBarLabel (at the time named -labelForActiveSession) read
//  activeSession.name. Every caller of the latter
//  (-_refreshLabels:, reached from -updateAggregatedTabStatus,
//  -sessionSubtitleDidChange: and kUpdateLabelsNotification) therefore replaced
//  the user's title with the session name -- which for a hand-named tab is the
//  profile-name fallback in -[PTYSession name].
//
//  The Claude Code integration made this constant: its cc-status hook fires on
//  ten events, each one a tab-status change, so a tab named "swift" flipped to
//  the profile name the moment Claude started working. Issue 13072.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabManualTitleRefreshTests: XCTestCase {
    private let sessionName = "Mac OS"     // the profile-name fallback
    private let manualTitle = "swift"      // what the user typed into Edit Tab Title

    // Free text rather than a canonical "work"/"wait"/"idle" wire value:
    // -localizedStatusForDisplay: passes free text through unchanged, so the
    // expected subtitle doesn't depend on the test runner's language.
    private let statusText = "Crunching"

    private var savedShowStatusInSubtitle = true

    /// PTYTab.tabViewItem is weak -- the tab view normally owns the item. Nothing
    /// here plays that part, so the test has to keep them alive itself.
    private var tabViewItems = [NSTabViewItem]()

    override func setUp() {
        super.setUp()
        savedShowStatusInSubtitle = iTermUserDefaults.showSessionStatusInTabSubtitle
        iTermUserDefaults.showSessionStatusInTabSubtitle = true
    }

    override func tearDown() {
        iTermUserDefaults.showSessionStatusInTabSubtitle = savedShowStatusInSubtitle
        tabViewItems.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeSession() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        session.genericScope.setValue(sessionName, forVariableNamed: iTermVariableKeySessionName)
        return session
    }

    private func attachTabViewItem(to tab: PTYTab) {
        let item = NSTabViewItem(identifier: tab)
        tabViewItems.append(item)
        tab.tabViewItem = item
    }

    /// A tab holding one session named `sessionName`, with a tab view item so the
    /// label the tab bar would draw is readable.
    private func makeTab() -> (PTYTab, PTYSession) {
        let session = makeSession()
        let tab = PTYTab(session: session, parentWindow: nil)!
        attachTabViewItem(to: tab)
        tab.name(of: session, didChangeTo: sessionName)
        return (tab, session)
    }

    /// Puts the tab in the state ⌘I leaves behind. -setTitleOverride: stores an
    /// interpolated-string format that an iTermSwiftyString evaluates onto the
    /// tab's title through a main-queue hop, so wait for the label to catch up
    /// rather than assuming the assignment was synchronous.
    private func applyManualTitle(to tab: PTYTab,
                                  session: PTYSession,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        tab.titleOverride = manualTitle
        let resolved = expectation(description: "title override evaluated onto the label")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak tab] timer in
            guard let tab, tab.tabViewItem?.label.hasPrefix(self.manualTitle) == true else {
                return
            }
            timer.invalidate()
            resolved.fulfill()
        }
        defer { poll.invalidate() }
        wait(for: [resolved], timeout: 30.0)
        XCTAssertEqual(titleLine(of: tab), manualTitle, file: file, line: line)

        // Spinning the runloop above also let iTermSessionNameController compute a
        // title for this profile-less session, which lands on the session's name
        // variable as " " (its empty-result placeholder). Put the name back so a
        // failure below reads as the bug the user reported -- the tab reverting to
        // the profile name -- rather than as a blank. Nothing spins the runloop
        // after this point, so the name controller cannot clobber it again.
        session.genericScope.setValue(sessionName, forVariableNamed: iTermVariableKeySessionName)
        XCTAssertEqual(session.name, sessionName, file: file, line: line)
    }

    /// The tab bar's label is "<title>\n<subtitle>"; the first line is the title.
    private func titleLine(of tab: PTYTab,
                           file: StaticString = #filePath,
                           line: UInt = #line) -> String {
        guard let label = tab.tabViewItem?.label else {
            XCTFail("tab has no tab view item label", file: file, line: line)
            return ""
        }
        return label.components(separatedBy: "\n").first ?? ""
    }

    /// PTYTab.variablesScope is typed `iTermVariableScope<iTermTabScope> *`, which
    /// Swift cannot import, and PTYTab has no genericScope the way PTYSession does.
    /// Its backing iTermVariables is reachable though, and a scope built over that
    /// writes where the tab's own scope reads.
    private func scope(of tab: PTYTab) -> iTermVariableScope {
        let scope = iTermVariableScope()
        scope.add(tab.variables, toScopeNamed: nil)
        return scope
    }

    private func subtitleLine(of tab: PTYTab) -> String {
        let parts = tab.tabViewItem?.label.components(separatedBy: "\n") ?? []
        return parts.count > 1 ? parts[1] : ""
    }

    // MARK: - Tests

    /// Baseline: the override-aware path gets this right, and has all along.
    func testManualTitleWinsOverSessionName() {
        let (tab, session) = makeTab()
        XCTAssertEqual(titleLine(of: tab), sessionName)

        applyManualTitle(to: tab, session: session)
        XCTAssertEqual(tab.title, manualTitle)
    }

    /// The regression. A tab-status change refreshes the label, and must not
    /// launder the user's title into the session name on the way through.
    func testTabStatusChangeKeepsManualTitle() {
        let (tab, session) = makeTab()
        applyManualTitle(to: tab, session: session)

        session.tabStatus?.statusText = statusText
        tab.sessionTabStatusDidChange(session)

        XCTAssertEqual(titleLine(of: tab), manualTitle,
                       "a status change must not replace the hand-set tab title with the session name")
        XCTAssertEqual(subtitleLine(of: tab), statusText,
                       "the status still belongs in the subtitle")
    }

    /// Clearing the status refreshes the label again, by the same route.
    func testClearingTabStatusKeepsManualTitle() {
        let (tab, session) = makeTab()
        applyManualTitle(to: tab, session: session)

        session.tabStatus?.statusText = statusText
        tab.sessionTabStatusDidChange(session)
        session.tabStatus?.statusText = nil
        tab.sessionTabStatusDidChange(session)

        XCTAssertEqual(titleLine(of: tab), manualTitle)
        XCTAssertFalse(subtitleLine(of: tab).contains(statusText),
                       "the cleared status must be gone from the subtitle")
    }

    /// The other, older caller of the shared label builder: a subtitle change.
    func testSubtitleChangeKeepsManualTitle() {
        let (tab, session) = makeTab()
        applyManualTitle(to: tab, session: session)

        tab.sessionSubtitleDidChange(session)

        XCTAssertEqual(titleLine(of: tab), manualTitle)
    }

    /// The whole label, not just its title line, must come out the same whichever
    /// path assembled it. -updateTabTitleForCurrentSessionName: draws one and
    /// -tabBarLabel draws the other, and the two drifting apart is what issue
    /// 13072 was. Exercised with a status present, since that is the part of the
    /// label the two paths could most plausibly disagree about.
    func testNameChangeAndRefreshProduceTheSameLabel() {
        let (tab, session) = makeTab()
        session.tabStatus?.statusText = statusText
        tab.sessionTabStatusDidChange(session)

        // What -updateTabTitleForCurrentSessionName: draws.
        tab.name(of: session, didChangeTo: "zsh")
        let afterNameChange = tab.tabViewItem?.label

        // What -tabBarLabel draws, with no other input changed.
        tab.sessionSubtitleDidChange(session)
        let afterRefresh = tab.tabViewItem?.label

        XCTAssertEqual(afterNameChange, "zsh\n\(statusText)",
                       "test setup: title line plus the status as subtitle")
        XCTAssertEqual(afterRefresh, afterNameChange,
                       "both paths must assemble the identical label, not merely the same title")
    }

    /// With no override set, the label still follows the session name. The fix
    /// must not strand tabs on a stale title.
    func testWithoutOverrideLabelFollowsSessionName() {
        let (tab, session) = makeTab()
        XCTAssertEqual(titleLine(of: tab), sessionName)

        session.genericScope.setValue("vim", forVariableNamed: iTermVariableKeySessionName)
        tab.name(of: session, didChangeTo: "vim")
        tab.sessionTabStatusDidChange(session)

        XCTAssertEqual(titleLine(of: tab), "vim")
    }

    /// A terminal session may legitimately clear its name (browsers suppress a
    /// blank title, terminals honor it). Whatever that draws, the two label
    /// paths have to draw the same thing -- otherwise which one ran last decides
    /// what the user sees, which is the whole bug. The chosen behavior is the one
    /// the tmux branch of -updateTabTitleForCurrentSessionName: already
    /// implements: fall back to the session's name.
    func testClearedTitleDrawsTheSameByBothPaths() {
        let (tab, session) = makeTab()

        // What -updateTabTitleForCurrentSessionName: draws.
        tab.name(of: session, didChangeTo: nil)
        let afterNameChange = titleLine(of: tab)

        // What -tabBarLabel draws on the next refresh.
        tab.sessionTabStatusDidChange(session)
        let afterRefresh = titleLine(of: tab)

        XCTAssertEqual(afterRefresh, afterNameChange,
                       "both label paths must agree on what a cleared title draws")
        XCTAssertEqual(afterNameChange, sessionName,
                       "a cleared title falls back to the session name, as the tmux branch does")
    }

    /// The in-the-wild shape: the name controller clears the session's name and
    /// its presentation name together, so the fallback has nothing but the
    /// profile name left. Both paths must still agree.
    func testClearedSessionNameDrawsTheSameByBothPaths() {
        let (tab, session) = makeTab()
        session.genericScope.setValue(nil, forVariableNamed: iTermVariableKeySessionName)
        XCTAssertEqual(session.name, "Untitled",
                       "test setup: with no name and no profile, PTYSession.name bottoms out here")

        tab.name(of: session, didChangeTo: nil)
        let afterNameChange = titleLine(of: tab)

        tab.sessionTabStatusDidChange(session)
        let afterRefresh = titleLine(of: tab)

        XCTAssertEqual(afterRefresh, afterNameChange,
                       "both label paths must agree when the session name is cleared too")
        XCTAssertEqual(afterNameChange, "Untitled")
    }

    /// The empty-string flavor of the same thing: a script title provider may
    /// return @"" deliberately, and that is honored rather than suppressed.
    func testEmptySessionNameDrawsTheSameByBothPaths() {
        let (tab, session) = makeTab()
        session.genericScope.setValue("", forVariableNamed: iTermVariableKeySessionName)

        tab.name(of: session, didChangeTo: "")
        let afterNameChange = titleLine(of: tab)

        tab.sessionTabStatusDidChange(session)

        XCTAssertEqual(titleLine(of: tab), afterNameChange,
                       "both label paths must agree on an empty session name")
    }

    /// The name controller's empty-result placeholder is a single space, which
    /// -updateTabTitleForCurrentSessionName: draws as-is. A refresh must draw the
    /// same thing: falling back here would put the two paths back into the
    /// disagreement this whole fix is about.
    func testWhitespaceTabTitleIsDrawnTheSameByBothPaths() {
        let (tab, session) = makeTab()
        tab.name(of: session, didChangeTo: " ")
        XCTAssertEqual(titleLine(of: tab), " ", "test setup: the name-change path draws the placeholder")

        tab.sessionTabStatusDidChange(session)

        XCTAssertEqual(titleLine(of: tab), " ",
                       "a refresh must agree with the name-change path")
    }

    /// -setActiveSession:nil leaves the tab view item alive and returns early, so
    /// a title recomputation can land while there is no active session. The tab
    /// title must not become nil: that both removes tab.title from the scope and
    /// draws the literal text “(null)” in the tab bar.
    func testTabTitleWithNoActiveSessionIsNotNull() {
        let (tab, _) = makeTab()
        tab.activeSession = nil

        // A public path that funnels into -updateTabTitle. The tab is not a tmux
        // tab, so this takes the same non-tmux branch every other caller does.
        tab.tmuxWindowName = "ignored"

        XCTAssertEqual(tab.title, "", "a nil title would be removed from the scope entirely")
        XCTAssertEqual(titleLine(of: tab), "")
        // Both halves of the label, not just the title: -[PTYSession subtitle] is
        // also nil here, and %@ would render it as “(null)”.
        XCTAssertFalse(tab.tabViewItem?.label.contains("(null)") ?? true,
                       "neither a nil title nor a nil subtitle may reach the tab bar as text")
        XCTAssertEqual(subtitleLine(of: tab), "")
    }

    /// The other way to reach a nil subtitle: a live session that has not had a
    /// profile applied yet, so its subtitle swifty string does not exist. The
    /// newline separating title from subtitle is deliberate and must stay (it is
    /// how a stale subtitle gets erased, issue 10143), so the nil has to be
    /// coalesced rather than the separator made conditional.
    func testNilSubtitleIsNotDrawnAsNull() {
        let (tab, session) = makeTab()
        XCTAssertNil(session.subtitle,
                     "test setup: no profile applied, so there is no subtitle swifty string")

        tab.sessionSubtitleDidChange(session)

        XCTAssertEqual(titleLine(of: tab), sessionName)
        XCTAssertEqual(subtitleLine(of: tab), "")
        XCTAssertFalse(tab.tabViewItem?.label.contains("(null)") ?? true)
        XCTAssertTrue(tab.tabViewItem?.label.hasSuffix("\n") ?? false,
                      "the title/subtitle separator must survive an empty subtitle")
    }

    // MARK: - New tabs

    /// The sequence every ordinary new tab goes through:
    /// -[PseudoTerminal insertSession:atIndex:] runs -initWithSession:parentWindow:
    /// (which never computes a title) and then -insertTab:atIndex:, whose
    /// -setTabViewItem: asks for the label. So the tab has no resolved title yet
    /// and -tabBarLabel's fallback supplies what the tab is first drawn with.
    /// Nothing else seeds an initial label, so this must not come out empty.
    func testLabelBeforeFirstTitleComputationUsesSessionName() {
        let tab = PTYTab(session: makeSession(), parentWindow: nil)!
        XCTAssertNil(tab.title, "test setup: no title computed yet")

        attachTabViewItem(to: tab)
        XCTAssertEqual(titleLine(of: tab), sessionName)
    }
}
