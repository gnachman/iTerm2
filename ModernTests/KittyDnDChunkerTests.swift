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
