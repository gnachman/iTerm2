//
//  KittyDnDChunkerTests.swift
//  iTerm2 ModernTests
//
//  Phase 0 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Outbound splitting (<=4096 base64 bytes per chunk,
//  m=1/m=0 flags) and inbound reassembly.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDChunkerTests: XCTestCase {
    // MARK: - Outbound splitting

    func testSmallPayloadIsSingleFinalChunk() {
        let payload = Data("hello".utf8)
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            payload: payload)
        XCTAssertEqual(msgs.count, 1)
        // A single chunk is final.
        XCTAssertNotEqual(msgs[0].metadata["m"], "1")
        XCTAssertEqual(msgs[0].payload, payload)
    }

    func testLargePayloadIsSplitWithMoreFlags() {
        // 10 KB forces several chunks.
        let payload = Data((0..<10_000).map { UInt8($0 & 0xff) })
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            payload: payload)
        XCTAssertGreaterThan(msgs.count, 1)

        // Every chunk's base64 payload must fit the 4096 limit.
        for msg in msgs {
            let b64 = msg.payload!.base64EncodedString()
            XCTAssertLessThanOrEqual(b64.utf8.count, KittyDnDChunker.maxEncodedChunkSize)
        }

        // All but the last are m=1; the last is not.
        for msg in msgs.dropLast() {
            XCTAssertEqual(msg.metadata["m"], "1")
        }
        XCTAssertNotEqual(msgs.last?.metadata["m"], "1")

        // Base metadata is preserved on every chunk.
        for msg in msgs {
            XCTAssertEqual(msg.type, "r")
            XCTAssertEqual(msg.intValue("x"), 1)
        }

        // Concatenating the chunk payloads reconstructs the original.
        let joined = msgs.reduce(Data()) { $0 + $1.payload! }
        XCTAssertEqual(joined, payload)
    }

    // MARK: - Inbound reassembly

    func testReassemblesChunkedMessage() {
        let payload = Data((0..<10_000).map { UInt8(($0 * 7) & 0xff) })
        let msgs = KittyDnDChunker.messages(baseMetadata: ["t": "r", "x": "1"],
                                            payload: payload)
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
        XCTAssertEqual(completed?.payload, payload)
        XCTAssertEqual(completed?.type, "r")
        XCTAssertEqual(completed?.intValue("x"), 1)
        // The transient chunk flag must not survive into the reassembled message.
        XCTAssertNil(completed?.metadata["m"])
    }

    func testReassemblerPassesThroughSingleMessage() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=M:x=1:y=2;YWJj")
        XCTAssertEqual(result?.type, "M")
        XCTAssertEqual(result?.payload, Data("abc".utf8))
    }

    // Exact chunk-count boundaries: maxRawChunkSize bytes fit in one chunk;
    // one more byte forces a second.
    func testChunkCountBoundary() {
        let boundary = KittyDnDChunker.maxRawChunkSize
        let atLimit = Data(repeating: 0xab, count: boundary)
        XCTAssertEqual(
            KittyDnDChunker.messages(baseMetadata: ["t": "r"], payload: atLimit).count, 1)
        let overLimit = Data(repeating: 0xab, count: boundary + 1)
        XCTAssertEqual(
            KittyDnDChunker.messages(baseMetadata: ["t": "r"], payload: overLimit).count, 2)
    }

    // The reassembler preserves the nil-vs-empty-payload distinction, matching
    // KittyDnDMessage's single-message parsing.
    func testReassemblerNoPayloadSection() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=a")
        XCTAssertEqual(result?.type, "a")
        XCTAssertNil(result?.payload)
    }

    func testReassemblerEmptyPayloadSection() {
        let reassembler = KittyDnDChunkReassembler()
        let result = reassembler.accept("t=r:x=1;")
        XCTAssertEqual(result?.payload, Data())
    }

    // One reassembler must handle a second complete message after the first,
    // i.e. its internal state resets.
    func testReassemblerReusableAcrossMessages() {
        let reassembler = KittyDnDChunkReassembler()
        _ = reassembler.accept("t=r:x=1:m=1;YWJj")   // "abc", more coming
        let first = reassembler.accept("t=r:x=1:m=0;ZGVm")  // "def", final
        XCTAssertEqual(first?.payload, Data("abcdef".utf8))

        // A fresh message reuses the same reassembler.
        let second = reassembler.accept("t=M:x=9;Z2hp")  // "ghi"
        XCTAssertEqual(second?.type, "M")
        XCTAssertEqual(second?.intValue("x"), 9)
        XCTAssertEqual(second?.payload, Data("ghi".utf8))
    }

    // The meaningful robustness property: a peer that splits the base64 *stream*
    // at an arbitrary position (not a 4-char group boundary) still reassembles,
    // because we concatenate raw base64 and decode once.
    func testReassemblesArbitraryBase64StreamSplit() {
        let payload = Data((0..<500).map { UInt8(($0 * 13) & 0xff) })
        let fullBase64 = payload.base64EncodedString()
        // Split at position 5, which is inside the first 4-char group boundary
        // region and leaves neither piece independently valid base64.
        let splitIndex = fullBase64.index(fullBase64.startIndex, offsetBy: 5)
        let piece1 = String(fullBase64[..<splitIndex])
        let piece2 = String(fullBase64[splitIndex...])

        let reassembler = KittyDnDChunkReassembler()
        XCTAssertNil(reassembler.accept("t=r:x=1:m=1;\(piece1)"))
        let result = reassembler.accept("t=r:x=1:m=0;\(piece2)")
        XCTAssertEqual(result?.payload, payload)
    }
}
