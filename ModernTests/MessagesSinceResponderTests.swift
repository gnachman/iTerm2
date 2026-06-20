//
//  MessagesSinceResponderTests.swift
//  iTerm2 ModernTests
//
//  The Mac-side core of the relay-push messagesSince reply: drop hidden
//  messages, take the newest `limit`, and produce short, attachment-free
//  previews so a 100 KB turn or a multi-MB attachment never reaches the phone's
//  Notification Service Extension.
//

import XCTest
@testable import iTerm2SharedARC

final class MessagesSinceResponderTests: XCTestCase {

    private func msg(_ content: Message.Content,
                     author: Participant = .agent,
                     id: UUID = UUID()) -> Message {
        Message(chatID: "c", author: author, content: content, sentDate: Date(), uniqueID: id)
    }

    func testSummarize_dropsHiddenMessages() {
        let visible = msg(.markdown("hello"))
        let hidden = msg(.commit(UUID()))   // hiddenFromClient == true
        let r = MessagesSinceResponder.summarize(fetched: [hidden, visible],
                                                 limit: 10, bodyMaxLength: 100)
        XCTAssertEqual(r.previews.map { $0.uniqueID }, [visible.uniqueID])
        XCTAssertFalse(r.truncated)
    }

    func testSummarize_truncatesLongBody() {
        let long = String(repeating: "x", count: 500)
        let r = MessagesSinceResponder.summarize(fetched: [msg(.markdown(long))],
                                                 limit: 10, bodyMaxLength: 20)
        let body = r.previews.first?.body ?? ""
        XCTAssertLessThanOrEqual(body.count, 20, "body must be capped at bodyMaxLength; got \(body.count)")
        XCTAssertNotEqual(body, long)
    }

    /// The memory-critical guarantee: a multi-MB attachment must NOT cross into
    /// the preview. snippetText renders a file as "📄 name", carrying no bytes.
    func testSummarize_stripsAttachmentBytes() {
        let bigData = Data(count: 5 * 1024 * 1024)   // 5 MB of zeros
        let file = LLM.Message.Attachment.AttachmentType.File(
            name: "huge.bin", content: bigData,
            mimeType: "application/octet-stream", localPath: nil)
        let attachment = LLM.Message.Attachment(inline: true, id: "a1", type: .file(file))
        let content = Message.Content.multipart([.attachment(attachment)], vectorStoreID: nil)

        let r = MessagesSinceResponder.summarize(fetched: [msg(content)],
                                                 limit: 10, bodyMaxLength: 100)
        let body = r.previews.first?.body ?? ""
        XCTAssertTrue(body.contains("huge.bin"), "expected the file name in the preview; got \(body)")
        XCTAssertLessThan(body.utf8.count, 1_000, "preview must be tiny, not the 5 MB payload")
        XCTAssertFalse(body.unicodeScalars.contains("\u{0}"), "raw attachment bytes must not leak into the preview")
    }

    func testSummarize_takesNewestLimitAndFlagsTruncated() {
        // fetched is newest-first; m0 is newest.
        let msgs = (0..<5).map { msg(.markdown("m\($0)")) }
        let r = MessagesSinceResponder.summarize(fetched: msgs, limit: 3, bodyMaxLength: 100)
        XCTAssertEqual(r.previews.map { $0.uniqueID },
                       Array(msgs.prefix(3)).map { $0.uniqueID },
                       "must keep the newest 3 in input order")
        XCTAssertTrue(r.truncated, "more visible than limit -> truncated")
    }

    func testSummarize_notTruncatedAtOrUnderLimit() {
        let msgs = (0..<3).map { msg(.markdown("m\($0)")) }
        let r = MessagesSinceResponder.summarize(fetched: msgs, limit: 3, bodyMaxLength: 100)
        XCTAssertEqual(r.previews.count, 3)
        XCTAssertFalse(r.truncated)
    }

    /// A non-positive limit must not trap prefix(_:) (the wire limit is
    /// untrusted); it yields no previews and reports truncated when any visible
    /// message existed.
    func testSummarize_nonPositiveLimitDoesNotTrap() {
        let msgs = (0..<3).map { msg(.markdown("m\($0)")) }
        for badLimit in [0, -5, Int.min] {
            let r = MessagesSinceResponder.summarize(fetched: msgs, limit: badLimit, bodyMaxLength: 100)
            XCTAssertTrue(r.previews.isEmpty, "limit \(badLimit) should yield no previews")
            XCTAssertTrue(r.truncated, "limit \(badLimit): 3 visible > 0 shown -> truncated")
        }
    }

    func testSummarize_dropsUserAuthoredMessages() {
        // A push fires for an agent turn, but messagesSince sweeps up the user's
        // own preceding message too. The user must not be notified about it.
        let userMsg = msg(.markdown("my question"), author: .user)
        let agentMsg = msg(.markdown("the answer"), author: .agent)
        let r = MessagesSinceResponder.summarize(fetched: [agentMsg, userMsg],
                                                 limit: 10, bodyMaxLength: 100)
        XCTAssertEqual(r.previews.map { $0.uniqueID }, [agentMsg.uniqueID])
        XCTAssertFalse(r.truncated)
    }

    func testSummarize_allUserAuthoredYieldsNoPreviews() {
        let msgs = (0..<3).map { msg(.markdown("m\($0)"), author: .user) }
        let r = MessagesSinceResponder.summarize(fetched: msgs, limit: 10, bodyMaxLength: 100)
        XCTAssertTrue(r.previews.isEmpty)
        XCTAssertFalse(r.truncated, "user messages are not 'visible' surplus")
    }

    private let guid = "550E8400-E29B-41D4-A716-446655440000"

    func testSummarize_rendersResolvedMentionAsSessionName() {
        let m = msg(.markdown("see @\(guid) for details"))
        let r = MessagesSinceResponder.summarize(fetched: [m], limit: 10, bodyMaxLength: 200,
                                                 resolveMention: { _ in "Build Server" })
        let body = r.previews.first?.body ?? ""
        XCTAssertFalse(body.contains(guid), "raw guid must not appear: \(body)")
        XCTAssertTrue(body.contains("Build Server"), body)
        XCTAssertTrue(body.contains(MentionPlainTextRenderer.sessionPrefix), body)
    }

    func testSummarize_rendersUnresolvedMentionAsDefunct() {
        let m = msg(.markdown("see @\(guid) please"))
        let r = MessagesSinceResponder.summarize(fetched: [m], limit: 10, bodyMaxLength: 200)
        let body = r.previews.first?.body ?? ""
        XCTAssertFalse(body.contains(guid), body)
        XCTAssertTrue(body.contains("[defunct session]"), body)
    }

    func testSummarize_rendersMentionStraddlingTheBodyCap() {
        // A mention starting just before the cap must still be rendered (not cut
        // mid-uuid), thanks to the snippet headroom.
        let prefix = String(repeating: "x", count: 195)
        let m = msg(.markdown(prefix + " @\(guid) tail"))
        let r = MessagesSinceResponder.summarize(fetched: [m], limit: 10, bodyMaxLength: 200,
                                                 resolveMention: { _ in "S1" })
        let body = r.previews.first?.body ?? ""
        XCTAssertFalse(body.contains("@550E8400"), "mention must not be left half-rendered: \(body)")
    }
}

final class MentionPlainTextRendererTests: XCTestCase {
    private let guid = "550E8400-E29B-41D4-A716-446655440000"

    func testNoMentionsReturnsInputUnchanged() {
        let s = "plain text, no mentions"
        XCTAssertEqual(MentionPlainTextRenderer.render(s, resolve: { _ in "x" }), s)
    }

    func testReplacesMultipleMentionsPreservingSurroundingText() {
        let other = "660E8400-E29B-41D4-A716-446655440001"
        let input = "a @\(guid) b @\(other) c"
        let out = MentionPlainTextRenderer.render(input) { id in
            id == self.guid ? "One" : "Two"
        }
        XCTAssertEqual(out, "a \(MentionPlainTextRenderer.sessionPrefix)One b \(MentionPlainTextRenderer.sessionPrefix)Two c")
    }

    func testUnresolvedBecomesDefunct() {
        XCTAssertEqual(MentionPlainTextRenderer.render("x @\(guid)", resolve: { _ in nil }),
                       "x [defunct session]")
    }
}
