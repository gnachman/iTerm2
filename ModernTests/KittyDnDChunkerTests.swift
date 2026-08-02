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
}
