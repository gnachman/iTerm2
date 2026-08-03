//
//  ChatAgentGuidStabilizationTests.swift
//  iTerm2 ModernTests
//
//  When a chat that predates stableIDs is continued, ChatAgent rewrites the
//  session guids the model wrote in prose (@-mentions) into the reload-durable
//  stableID before sending the history to the provider, so the model sees
//  references consistent with the stableIDs the <workgroups> snapshot now emits.
//  Only resolvable guids are rewritten; workgroup ids, dead sessions, and bare
//  uuids in output are left untouched.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatAgentGuidStabilizationTests: XCTestCase {
    private let liveGuid = "01234567-89ab-cdef-0123-456789abcdef"
    private let stableID = "ptys_9QK3ZM7WX4VBT"

    private func resolve(_ guid: String) -> String? {
        return guid == liveGuid ? stableID : nil
    }

    func testRewritesResolvableGuidInMention() {
        let out = ChatAgent.stabilizeSessionGuids(in: "done @\(liveGuid) now", resolve: resolve)
        XCTAssertEqual(out, "done @\(stableID) now")
    }

    func testRewritesSessionScopedAndAllOccurrences() {
        let out = ChatAgent.stabilizeSessionGuids(
            in: "@session:\(liveGuid) and again @\(liveGuid)", resolve: resolve)
        XCTAssertEqual(out, "@session:\(stableID) and again @\(stableID)")
    }

    func testLeavesUnresolvableGuidUntouched() {
        // A workgroup id (or a dead session's guid) does not resolve as a
        // session, so the resolution gate keeps it verbatim.
        let other = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        let out = ChatAgent.stabilizeSessionGuids(in: "@wg-\(other) here", resolve: resolve)
        XCTAssertEqual(out, "@wg-\(other) here")
    }

    func testNoGuidsIsNoOp() {
        let s = "no ids here, just prose"
        XCTAssertEqual(ChatAgent.stabilizeSessionGuids(in: s, resolve: resolve), s)
    }

    func testAddsAtSignToBareResolvableGuid() {
        // The model wrote a bare session id without the @ sigil; rewriting it
        // both stabilizes it and turns it into a clickable mention.
        let out = ChatAgent.stabilizeSessionGuids(in: "restart session \(liveGuid) please",
                                                  resolve: resolve)
        XCTAssertEqual(out, "restart session @\(stableID) please")
    }

    func testDoesNotDoubleAtExistingMentionForms() {
        for form in ["@\(liveGuid)", "@session:\(liveGuid)", "@wg-\(liveGuid)"] {
            let expected = form.replacingOccurrences(of: liveGuid, with: stableID)
            XCTAssertEqual(ChatAgent.stabilizeSessionGuids(in: form, resolve: resolve), expected)
        }
    }

    func testBareUnresolvableGuidStaysBareWithoutAtSign() {
        let other = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        let s = "unknown \(other) here"
        XCTAssertEqual(ChatAgent.stabilizeSessionGuids(in: s, resolve: resolve), s)
    }
}
