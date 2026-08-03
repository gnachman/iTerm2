//
//  StreamingReplyAccumulatorTests.swift
//  CompanionCore
//

import XCTest
@testable import CompanionProtocol

final class StreamingReplyAccumulatorTests: XCTestCase {
    func test_beginSeedsSoFirstChunkIsNotDropped() {
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I", isLabel: false)), "I")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: " don't have")), "I don't have")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: " a reliable way")),
                       "I don't have a reliable way")
    }

    func test_appendWithoutBegin_startsFromEmpty() {
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "hi")), "hi")
    }

    func test_emptyBeginSeed_concatenatesCleanly() {
        // A substance-free .begin snapshot (e.g. a reasoning-only multipart, once
        // stripped) is seeded as "" so the real streamed answer doesn't get a
        // placeholder ("Empty message") prefix.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "", isLabel: false)), "")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "I don't have")), "I don't have")
    }

    func test_attachmentReusesBeginPreview_notADebugString() {
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 report.pdf", isLabel: true)), "📄 report.pdf")
        // The following attachment delta must keep the seeded preview, not fall
        // back to its own (raw) description.
        XCTAssertEqual(acc.accumulate(.appendAttachment(id: "U", previewIfEmpty: "raw debug", isLabel: true)),
                       "📄 report.pdf")
    }

    func test_attachmentWithoutBegin_usesFallback() {
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.appendAttachment(id: "U", previewIfEmpty: "📄 report.pdf", isLabel: true)),
                       "📄 report.pdf")
    }

    func test_codeAttachmentThenText_concatenates_notReplaced() {
        // A .code attachment previews as real TEXT (isLabel: false), so a following
        // text delta must EXTEND it (matching the whole-message multipart path),
        // not replace it as it would for a "📄 name" label.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.appendAttachment(id: "U", previewIfEmpty: "let x = 1", isLabel: false)),
                       "let x = 1")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "\nlet y = 2")),
                       "let x = 1\nlet y = 2")
    }

    func test_textAfterLabelBegin_replacesLabel_notConcatenated() {
        // Attachment-first reply that then streams text: the raw text must NOT be
        // glued onto the rendered "📄 name" label.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 report.pdf", isLabel: true)), "📄 report.pdf")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "Here is the summary")),
                       "Here is the summary")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: " of the report")),
                       "Here is the summary of the report")
    }

    func test_growingWholeMessageSnapshots_replaceNotGarble() {
        // The Mac's common mode: repeated full-text .begin under one id, each a
        // superset of the last. Must REPLACE, not prepend ("I don't knowI don'tI").
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I", isLabel: false)), "I")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I don't", isLabel: false)), "I don't")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I don't know", isLabel: false)), "I don't know")
    }

    func test_attachmentThenTextSnapshots_replaceLabel_notGarble() {
        // Attachment-first reply delivered as GROWING .begin snapshots under one
        // id: snapshot 1 is the rendered label, snapshot 2 adds text. Neither is
        // a prefix of the other, but the text must REPLACE the label - not
        // prepend into "Here is the summary📄 report.pdf".
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 report.pdf", isLabel: true)), "📄 report.pdf")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "Here is the summary", isLabel: false)),
                       "Here is the summary")
    }

    func test_twoAttachmentLabels_newestWins_notReversedConcat() {
        // A label assembled from an appendAttachment delta (seededByBegin == false),
        // then a DIFFERING label begin. Neither is a prefix of the other and both are
        // labels, so this must NOT hit the reordered-leading-chunk prepend branch
        // (that is for non-label text); newest wins, not "📄 b.pdf📄 a.pdf".
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.appendAttachment(id: "U", previewIfEmpty: "📄 a.pdf", isLabel: true)),
                       "📄 a.pdf")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 b.pdf", isLabel: true)),
                       "📄 b.pdf")
    }

    func test_textThenLabelSnapshots_keepText_notGarble() {
        // Reverse of test_attachmentThenTextSnapshots: real text arrives first,
        // then a growing .begin snapshot that is only an attachment LABEL. The
        // label must not glue onto or replace the text ("📄 report.pdfHere is the
        // summary"); the text is the substance.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "Here is the summary", isLabel: false)),
                       "Here is the summary")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 report.pdf", isLabel: true)),
                       "Here is the summary")
    }

    func test_emptyBeginThenAttachmentThenRevisedBegin_replaces_notPrepend() {
        // Empty (reasoning-only) begin SEEDS the id, then an attachment delta, then
        // a revised non-prefix begin. The revised begin must REPLACE (a begin seeded
        // this id) - the attachment branch must not reset seededByBegin, or it
        // prepends into "Revised textcode body".
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "", isLabel: false)), "")
        XCTAssertEqual(acc.accumulate(.appendAttachment(id: "U", previewIfEmpty: "code body", isLabel: false)),
                       "code body")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "Revised text", isLabel: false)),
                       "Revised text")
    }

    func test_labelSeedThenTextThenRevisedBegin_replaces_notGarble() {
        // Attachment-first reply: a LABEL begin, then streamed text replaces the
        // label, then a revised non-prefix begin. The revised begin must REPLACE
        // (a begin seeded this id), not prepend "Here is the revised summaryHere
        // is the summary" - the label-branch append must keep seededByBegin.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "📄 report.pdf", isLabel: true)),
                       "📄 report.pdf")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "Here is the summary")),
                       "Here is the summary")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "Here is the revised summary", isLabel: false)),
                       "Here is the revised summary")
    }

    func test_manyAppendDeltas_accumulateCorrectly() {
        // Guards the in-place append optimization: many deltas must still produce
        // the full concatenation, and a later revised begin must still REPLACE
        // (seededByBegin preserved across the in-place appends).
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "a", isLabel: false)), "a")
        var expected = "a"
        for i in 0..<50 {
            let delta = "-\(i)"
            expected += delta
            XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: delta)), expected)
        }
        // A non-prefix revised snapshot replaces (not prepends) despite the appends.
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "REVISED", isLabel: false)),
                       "REVISED")
    }

    func test_revisedNonPrefixSnapshots_replaceNewestWins_notGarble() {
        // Two whole-message .begin snapshots under one id where neither is a prefix
        // of the other (a revised token / re-normalized punctuation between markdown
        // renders). Newest must WIN, not prepend into "The answer is 6The answer is 5".
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "The answer is 5", isLabel: false)),
                       "The answer is 5")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "The answer is 6", isLabel: false)),
                       "The answer is 6")
    }

    func test_revisedSnapshotAfterAppendDeltas_replaces_notGarble() {
        // A begin seeds, append deltas grow it, THEN a non-prefix begin arrives (a
        // re-rendered/revised snapshot). Because a begin already seeded this id, it
        // must REPLACE, not prepend into "The answer is 6The answer is 5 maybe" -
        // the append must not have made it look like a reordered leading chunk.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "The answer is 5", isLabel: false)),
                       "The answer is 5")
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: " maybe")),
                       "The answer is 5 maybe")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "The answer is 6", isLabel: false)),
                       "The answer is 6")
    }

    func test_shorterSnapshot_keepsLongerAccumulation() {
        // A shorter/equal replay snapshot must not truncate the accumulation.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I don't know", isLabel: false)), "I don't know")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I don't", isLabel: false)), "I don't know")
    }

    func test_emptySnapshot_doesNotWipeAccumulation() {
        // A snapshot that strips to substance-free reasoning ("") must not erase
        // the real answer already accumulated.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "The answer is 42", isLabel: false)),
                       "The answer is 42")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "", isLabel: false)), "The answer is 42")
    }

    func test_beginAfterAppend_prependsInsteadOfDropping() {
        // Reorder/replay: a delta arrived before its .begin; the begin must not
        // overwrite (dropping the delta) - it prepends.
        var acc = StreamingReplyAccumulator()
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: " don't have")), " don't have")
        XCTAssertEqual(acc.accumulate(.begin(id: "U", preview: "I", isLabel: false)), "I don't have")
    }

    func test_reset_forgetsAccumulation() {
        var acc = StreamingReplyAccumulator()
        _ = acc.accumulate(.begin(id: "U", preview: "first", isLabel: false))
        acc.reset()
        XCTAssertEqual(acc.accumulate(.appendText(id: "U", delta: "second")), "second")
    }

    func test_separateMessageIDsAccumulateIndependently() {
        var acc = StreamingReplyAccumulator()
        _ = acc.accumulate(.begin(id: "A", preview: "alpha", isLabel: false))
        _ = acc.accumulate(.begin(id: "B", preview: "beta", isLabel: false))
        XCTAssertEqual(acc.accumulate(.appendText(id: "A", delta: "!")), "alpha!")
        XCTAssertEqual(acc.accumulate(.appendText(id: "B", delta: "?")), "beta?")
    }
}
