import XCTest
@testable import iTerm2SharedARC

final class iTermPromptOnCloseReasonTests: XCTestCase {
    private func compound() -> iTermPromptOnCloseReason {
        return iTermPromptOnCloseReason.no()!
    }

    private func pinned(_ tabNumber: Int32) -> iTermPromptOnCloseReason {
        return iTermPromptOnCloseReason.tabIsPinned(withNumber: tabNumber)!
    }

    func testNoReasonHasNoReason() {
        XCTAssertFalse(compound().hasReason)
    }

    func testTabIsPinnedHasReasonAndIncludesTabNumber() {
        let reason = pinned(3)
        XCTAssertTrue(reason.hasReason)
        XCTAssertEqual(reason.message, "Tab #3 is pinned.")
    }

    func testCompoundContainsAddedReasonMessage() {
        let c = compound()
        c.add(pinned(7))
        XCTAssertTrue(c.hasReason)
        XCTAssertTrue(c.message.contains("Tab #7 is pinned."))
    }

    func testCompoundListsEveryPinnedTabSeparately() {
        let c = compound()
        c.add(pinned(1))
        c.add(pinned(2))
        c.add(pinned(3))
        XCTAssertTrue(c.message.contains("Tab #1 is pinned."))
        XCTAssertTrue(c.message.contains("Tab #2 is pinned."))
        XCTAssertTrue(c.message.contains("Tab #3 is pinned."))
    }

    func testCompoundDeduplicatesIdenticalMessages() {
        let c = compound()
        c.add(iTermPromptOnCloseReason.sessionIsLocked()!)
        c.add(iTermPromptOnCloseReason.sessionIsLocked()!)
        let occurrences = c.message.components(separatedBy: "This pane is locked.").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testTabIsPinnedAndSessionIsLockedBothAppear() {
        let c = compound()
        c.add(iTermPromptOnCloseReason.sessionIsLocked()!)
        c.add(pinned(5))
        XCTAssertTrue(c.message.contains("This pane is locked."))
        XCTAssertTrue(c.message.contains("Tab #5 is pinned."))
    }
}
