//
//  KittyDnDChunkerTests.swift
//  iTerm2 ModernTests
//
//  Phase 0 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Outbound splitting of a binary payload (<=4096
//  base64 bytes per chunk, m=1/m=0 flags) and inbound reassembly.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDChunkerTests: XCTestCase {
    // MARK: - Outbound splitting

    func testSmallPayloadHasDataChunkThenEmptyTerminator() {
        let payload = Data("hello".utf8)
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            data: payload)
        // One data-bearing m=1 chunk, then the empty m=0 terminator.
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0].metadata["m"], "1")
        XCTAssertEqual(msgs[0].dataPayload, payload)
        XCTAssertEqual(msgs[1].metadata["m"], "0")
        XCTAssertEqual(msgs[1].rawPayload, "")
    }

    func testEmptyPayloadIsJustTerminator() {
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            data: Data())
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].metadata["m"], "0")
        XCTAssertEqual(msgs[0].rawPayload, "")
    }

    func testLargePayloadIsSplitWithMoreFlags() {
        // 10 KB forces several chunks.
        let payload = Data((0..<10_000).map { UInt8($0 & 0xff) })
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            data: payload)
        XCTAssertGreaterThan(msgs.count, 2)

        // Every data chunk carries m=1 and fits the 4096 limit; the terminator
        // is an empty m=0 message.
        let dataChunks = msgs.dropLast()
        for msg in dataChunks {
            XCTAssertEqual(msg.metadata["m"], "1")
            XCTAssertLessThanOrEqual(msg.rawPayload!.utf8.count, KittyDnDChunker.maxEncodedChunkSize)
        }
        XCTAssertEqual(msgs.last?.metadata["m"], "0")
        XCTAssertEqual(msgs.last?.rawPayload, "")

        // Base metadata is preserved on every message.
        for msg in msgs {
            XCTAssertEqual(msg.type, "r")
            XCTAssertEqual(msg.intValue("x"), 1)
        }

        // Concatenating the data-chunk payloads reconstructs the original.
        let joined = dataChunks.reduce(Data()) { $0 + ($1.dataPayload ?? Data()) }
        XCTAssertEqual(joined, payload)
    }

    // MARK: - Inbound reassembly

    func testReassemblesChunkedMessage() {
        let payload = Data((0..<10_000).map { UInt8(($0 * 7) & 0xff) })
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            data: payload)
        XCTAssertGreaterThan(msgs.count, 1)

        let reassembler = KittyDnDChunkReassembler()
        var completed: KittyDnDMessage?
        for (i, msg) in msgs.enumerated() {
            let result = reassembler.accept(msg.serializedContent())
            if i < msgs.count - 1 {
                XCTAssertNil(result, "chunk \(i) should not complete the message")
            } else {
                completed = result
            }
        }
        XCTAssertEqual(completed?.dataPayload, payload)
        XCTAssertEqual(completed?.type, "r")
        XCTAssertEqual(completed?.intValue("x"), 1)
        // The transient chunk flag must not survive into the reassembled message.
        XCTAssertNil(completed?.metadata["m"])
    }

    // A query (different t) interleaved into a chunked transfer is surfaced as
    // its own message, and the transfer still completes correctly afterward. The
    // spec permits t=q during a chunked transfer.
    func testInterleavedQueryDuringChunkedTransfer() {
        let payload = Data((0..<10_000).map { UInt8($0 & 0xff) })
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"], data: payload)
        XCTAssertGreaterThan(msgs.count, 2)

        let reassembler = KittyDnDChunkReassembler()
        // First chunk starts the sequence.
        XCTAssertNil(reassembler.accept(msgs[0].serializedContent()))
        // A query arrives mid-transfer: it must be returned, not merged.
        let query = reassembler.accept("t=q:i=5")
        XCTAssertEqual(query?.type, "q")
        XCTAssertEqual(query?.metadata["i"], "5")
        // The rest of the chunks complete the original transfer intact.
        var completed: KittyDnDMessage?
        for msg in msgs.dropFirst() {
            if let done = reassembler.accept(msg.serializedContent()) { completed = done }
        }
        XCTAssertEqual(completed?.type, "r")
        XCTAssertEqual(completed?.dataPayload, payload)
    }

    // An over-large sequence is abandoned at the cap, its remaining chunks are
    // drained (not misread as a new message), an interleaved query is still
    // surfaced during the drain, and the reassembler recovers for the next message.
    func testOverCapSequenceIsDrainedThenRecovers() {
        let reassembler = KittyDnDChunkReassembler(maxAccumulatedBytes: 100)
        let sixty = String(repeating: "A", count: 60)
        // First chunk (60 bytes) is under the cap.
        XCTAssertNil(reassembler.accept("t=r:x=1:m=1;\(sixty)"))
        // Second chunk pushes the total to 120 > 100: abandoned, now draining.
        XCTAssertNil(reassembler.accept("t=r:x=1:m=1;\(sixty)"))
        // A query mid-drain is still surfaced (different t), not swallowed.
        let query = reassembler.accept("t=q:i=5")
        XCTAssertEqual(query?.type, "q")
        // A further continuation chunk of the abandoned sequence is discarded.
        XCTAssertNil(reassembler.accept("t=r:x=1:m=1;\(sixty)"))
        // The terminator ends the drain (no message surfaces).
        XCTAssertNil(reassembler.accept("t=r:x=1;\(sixty)"))
        // The reassembler has recovered: the next message reassembles normally.
        let recovered = reassembler.accept("t=M:x=9;YWJj")
        XCTAssertEqual(recovered?.type, "M")
        XCTAssertEqual(recovered?.dataPayload, Data("abc".utf8))
    }

    func testReassemblerPassesThroughSingleMessage() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=M:x=1:y=2;YWJj")
        XCTAssertEqual(result?.type, "M")
        XCTAssertEqual(result?.dataPayload, Data("abc".utf8))
    }

    // Exact chunk-count boundaries: maxRawChunkSize bytes fit in one chunk;
    // one more byte forces a second.
    func testChunkCountBoundary() {
        // Counts include the trailing empty m=0 terminator.
        let boundary = KittyDnDChunker.maxRawChunkSize
        let atLimit = Data(repeating: 0xab, count: boundary)
        XCTAssertEqual(
            KittyDnDChunker.messages(baseMetadata: ["t": "r"], data: atLimit).count, 2)
        let overLimit = Data(repeating: 0xab, count: boundary + 1)
        XCTAssertEqual(
            KittyDnDChunker.messages(baseMetadata: ["t": "r"], data: overLimit).count, 3)
    }

    // The reassembler preserves the nil-vs-empty-payload distinction, matching
    // KittyDnDMessage's single-message parsing.
    func testReassemblerNoPayloadSection() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=a")
        XCTAssertEqual(result?.type, "a")
        XCTAssertNil(result?.rawPayload)
    }

    func testReassemblerEmptyPayloadSection() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=r:x=1;")
        XCTAssertEqual(result?.rawPayload, "")
        XCTAssertEqual(result?.dataPayload, Data())
    }

    // One reassembler must handle a second complete message after the first,
    // i.e. its internal state resets.
    func testReassemblerReusableAcrossMessages() {
        let reassembler = KittyDnDChunkReassembler()
        _ = reassembler.accept("t=r:x=1:m=1;YWJj")   // "abc", more coming
        let first = reassembler.accept("t=r:x=1:m=0;ZGVm")  // "def", final
        XCTAssertEqual(first?.dataPayload, Data("abcdef".utf8))

        // A fresh message reuses the same reassembler.
        let second = reassembler.accept("t=M:x=9;Z2hp")  // "ghi"
        XCTAssertEqual(second?.type, "M")
        XCTAssertEqual(second?.intValue("x"), 9)
        XCTAssertEqual(second?.dataPayload, Data("ghi".utf8))
    }

    // The meaningful robustness property: a peer that splits the base64 stream
    // at an arbitrary position (not a 4-char group boundary) still reassembles,
    // because we concatenate the raw payload and decode once at the point of use.
    func testReassemblesArbitraryBase64StreamSplit() {
        let payload = Data((0..<500).map { UInt8(($0 * 13) & 0xff) })
        let fullBase64 = payload.base64EncodedString()
        // Split at position 5, which leaves neither piece independently valid
        // base64.
        let splitIndex = fullBase64.index(fullBase64.startIndex, offsetBy: 5)
        let piece1 = String(fullBase64[..<splitIndex])
        let piece2 = String(fullBase64[splitIndex...])

        let reassembler = KittyDnDChunkReassembler()
        XCTAssertNil(reassembler.accept("t=r:x=1:m=1;\(piece1)"))
        let result = reassembler.accept("t=r:x=1:m=0;\(piece2)")
        XCTAssertEqual(result?.dataPayload, payload)
    }
}
