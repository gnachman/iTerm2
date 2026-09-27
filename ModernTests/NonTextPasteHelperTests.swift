//
//  NonTextPasteHelperTests.swift
//  iTerm2 ModernTests
//
//  Covers the two parts of the non-text paste helper that issue 13024 got wrong:
//  deciding whether a file is text (which used to read the whole file on the main
//  thread) and escaping a path for the shell (which used to ignore the user's
//  quoting preference).
//

import XCTest
@testable import iTerm2SharedARC

final class NonTextPasteHelperTests: XCTestCase {

    // MARK: - trimmingPartialTrailingSequence

    func test_trimming_emptyData_unchanged() {
        let data = Data()
        XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data), data)
    }

    func test_trimming_ascii_unchanged() {
        let data = Data("hello".utf8)
        XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data), data)
    }

    func test_trimming_completeSequences_unchanged() {
        // Two-, three- and four-byte scalars, each ending the buffer.
        for scalar in ["é", "€", "😀"] {
            let data = Data("abc\(scalar)".utf8)
            XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data),
                           data,
                           "complete sequence for \(scalar) should not be trimmed")
        }
    }

    func test_trimming_cutSequence_dropsThePartialTail() {
        // For each multi-byte scalar, cut it after 1..n-1 bytes and check that exactly
        // the partial tail comes off, leaving the ASCII prefix.
        let prefix = Data("abc".utf8)
        for scalar in ["é", "€", "😀"] {
            let encoded = Array(scalar.utf8)
            for kept in 1..<encoded.count {
                let data = prefix + Data(encoded.prefix(kept))
                XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data),
                               prefix,
                               "\(scalar) cut after \(kept) of \(encoded.count) bytes")
            }
        }
    }

    func test_trimming_orphanedContinuationBytes_unchanged() {
        // More continuation bytes than any sequence can have: not valid UTF-8 whatever
        // follows, so leave it for the validator to reject rather than trimming forever.
        let data = Data("abc".utf8) + Data([0x80, 0x80, 0x80, 0x80])
        XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data), data)
    }

    func test_trimming_onlyAPartialSequence_becomesEmpty() {
        let data = Data(Array("😀".utf8).prefix(2))
        XCTAssertEqual(iTermNonTextPasteHelper.trimmingPartialTrailingSequence(data), Data())
    }

    // MARK: - prefixIsValidUTF8

    private func writeTempFile(_ data: Data, line: UInt = #line) throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "NonTextPasteHelperTests-\(UUID().uuidString)")
        try data.write(to: URL(fileURLWithPath: path))
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return path
    }

    func test_prefixIsValidUTF8_textFile() throws {
        let path = try writeTempFile(Data("hello, wörld".utf8))
        XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_emptyFile() throws {
        let path = try writeTempFile(Data())
        XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_binaryFile() throws {
        let path = try writeTempFile(Data([0x41, 0xC3, 0x28, 0xFF]))
        XCTAssertFalse(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_missingFile() {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertFalse(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_truncatedSequenceInACompleteFile_isInvalid() throws {
        // The file really does end mid-sequence, so it is not valid UTF-8. Only a cut we
        // made ourselves may be forgiven.
        let path = try writeTempFile(Data("abc".utf8) + Data(Array("😀".utf8).prefix(2)))
        XCTAssertFalse(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_multibyteScalarStraddlingTheSampleBoundary() throws {
        // The regression this whole change is about: a scalar that starts inside the
        // sampled megabyte and ends outside it must not make the file look like binary.
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let emoji = Array("😀".utf8)
        for bytesInsideSample in 1..<emoji.count {
            let leading = Data(repeating: UInt8(ascii: "a"), count: sample - bytesInsideSample)
            let data = leading + Data(emoji) + Data(repeating: UInt8(ascii: "b"), count: 1024)
            let path = try writeTempFile(data)
            XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path),
                          "scalar with \(bytesInsideSample) of \(emoji.count) bytes inside the sample")
        }
    }

    func test_prefixIsValidUTF8_readsOnlyThePrefix() throws {
        // Deliberate: we assume the rest of the file matches the sample rather than pay
        // to read it. A file whose first megabyte is text reports text.
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let data = Data(repeating: UInt8(ascii: "a"), count: sample) + Data([0xFF, 0xFE, 0xFF])
        let path = try writeTempFile(data)
        XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_binaryAtTheStartOfALargeFile() throws {
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let data = Data([0xFF, 0xFE]) + Data(repeating: UInt8(ascii: "a"), count: sample)
        let path = try writeTempFile(data)
        XCTAssertFalse(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_fileExactlyTheSampleSize_truncatedSequenceIsInvalid() throws {
        // A file whose size is exactly the sample size fills the buffer without our having
        // cut anything off, so a sequence it really ends mid-way through must still be
        // rejected. Reading only utf8SampleByteCount bytes could not tell the two apart.
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let partial = Array("😀".utf8).prefix(2)
        let data = Data(repeating: UInt8(ascii: "a"), count: sample - partial.count) + Data(partial)
        XCTAssertEqual(data.count, sample)
        let path = try writeTempFile(data)
        XCTAssertFalse(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_fileExactlyTheSampleSize_validTextIsValid() throws {
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let path = try writeTempFile(Data(repeating: UInt8(ascii: "a"), count: sample))
        XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    func test_prefixIsValidUTF8_oneByteBeyondTheSample_cutSequenceIsForgiven() throws {
        // The smallest file for which we really do truncate: the byte past the sample is
        // the second half of a scalar whose lead byte is the sample's last byte.
        let sample = iTermNonTextPasteHelper.utf8SampleByteCount
        let scalar = Array("é".utf8)
        XCTAssertEqual(scalar.count, 2)
        let data = Data(repeating: UInt8(ascii: "a"), count: sample - 1) + Data(scalar)
        XCTAssertEqual(data.count, sample + 1)
        let path = try writeTempFile(data)
        XCTAssertTrue(iTermNonTextPasteHelper.prefixIsValidUTF8(ofFileAt: path))
    }

    // MARK: - escapedPathForPaste

    func test_escapedPathForPaste_backslashStyle() {
        XCTAssertEqual(iTermNonTextPasteHelper.escapedPathForPaste("/path/to/a file", wrapInQuotes: false),
                       "/path/to/a\\ file")
    }

    func test_escapedPathForPaste_quotedStyle() {
        XCTAssertEqual(iTermNonTextPasteHelper.escapedPathForPaste("/path/to/a file", wrapInQuotes: true),
                       "\"/path/to/a file\"")
    }

    func test_escapedPathForPaste_plainPathIsUnchangedByBackslashStyle() {
        XCTAssertEqual(iTermNonTextPasteHelper.escapedPathForPaste("/tmp/plain.txt", wrapInQuotes: false),
                       "/tmp/plain.txt")
    }
}
