//
//  CompanionHEVCFramingTests.swift
//  iTerm2 ModernTests
//
//  The Mac encoder serializes HEVC parameter sets and access units; the iOS
//  decoder reconstructs them. These tests pin both byte formats and prove
//  round-trip fidelity and rejection of truncated buffers.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionHEVCFramingTests: XCTestCase {
    // MARK: Parameter sets

    func testParameterSetsRoundTrip() throws {
        let vps = Data([0x40, 0x01, 0x0C])
        let sps = Data([0x42, 0x01, 0x01, 0x02, 0x03])
        let pps = Data([0x44, 0x01])
        let blob = CompanionHEVCFraming.encodeParameterSets([vps, sps, pps])
        XCTAssertEqual(try CompanionHEVCFraming.decodeParameterSets(blob), [vps, sps, pps])
    }

    func testEmptyParameterSetsRoundTrip() throws {
        let blob = CompanionHEVCFraming.encodeParameterSets([])
        XCTAssertEqual(blob, Data([0x00, 0x00]))  // count = 0
        XCTAssertEqual(try CompanionHEVCFraming.decodeParameterSets(blob), [])
    }

    func testParameterSetsWireLayout() {
        let blob = CompanionHEVCFraming.encodeParameterSets([Data([0xAB, 0xCD])])
        // count(1) + len(2) + bytes
        XCTAssertEqual([UInt8](blob), [0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0xAB, 0xCD])
    }

    func testDecodeParameterSetsTruncatedLength() {
        // Declares one set of length 4 but only 1 payload byte follows.
        let blob = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x04, 0xAB])
        XCTAssertThrowsError(try CompanionHEVCFraming.decodeParameterSets(blob)) { error in
            XCTAssertEqual(error as? CompanionHEVCFraming.FramingError, .truncated)
        }
    }

    func testDecodeParameterSetsTruncatedCount() {
        XCTAssertThrowsError(try CompanionHEVCFraming.decodeParameterSets(Data([0x00]))) { error in
            XCTAssertEqual(error as? CompanionHEVCFraming.FramingError, .truncated)
        }
    }

    // MARK: Access units

    func testAccessUnitRoundTrip() throws {
        let nalu1 = Data([0x26, 0x01, 0xAF, 0x00])  // e.g. an IDR slice
        let nalu2 = Data([0x02, 0x01])
        let avcc = CompanionHEVCFraming.encodeAccessUnit(nalUnits: [nalu1, nalu2])
        XCTAssertEqual(try CompanionHEVCFraming.decodeAccessUnit(avcc), [nalu1, nalu2])
    }

    func testAccessUnitWireLayoutIsFourByteBigEndianLength() {
        let avcc = CompanionHEVCFraming.encodeAccessUnit(nalUnits: [Data([0xAA, 0xBB, 0xCC])])
        XCTAssertEqual([UInt8](avcc), [0x00, 0x00, 0x00, 0x03, 0xAA, 0xBB, 0xCC])
    }

    func testEmptyAccessUnitDecodesToNothing() throws {
        XCTAssertEqual(try CompanionHEVCFraming.decodeAccessUnit(Data()), [])
    }

    func testDecodeAccessUnitTruncatedLengthPrefix() {
        XCTAssertThrowsError(try CompanionHEVCFraming.decodeAccessUnit(Data([0x00, 0x00]))) { error in
            XCTAssertEqual(error as? CompanionHEVCFraming.FramingError, .truncated)
        }
    }

    func testDecodeAccessUnitOverrunningLengthThrows() {
        // Declares a 9-byte NAL unit but only 2 bytes follow.
        let bad = Data([0x00, 0x00, 0x00, 0x09, 0x01, 0x02])
        XCTAssertThrowsError(try CompanionHEVCFraming.decodeAccessUnit(bad)) { error in
            XCTAssertEqual(error as? CompanionHEVCFraming.FramingError, .truncated)
        }
    }

    func testDecodeAccessUnitFromNonZeroBasedSlice() throws {
        let nalu = Data([0x11, 0x22])
        var padded = Data([0xFF, 0xFF, 0xFF])
        padded.append(CompanionHEVCFraming.encodeAccessUnit(nalUnits: [nalu]))
        let slice = padded.suffix(from: padded.startIndex + 3)
        XCTAssertNotEqual(slice.startIndex, 0)
        XCTAssertEqual(try CompanionHEVCFraming.decodeAccessUnit(slice), [nalu])
    }
}
