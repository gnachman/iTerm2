//
//  LocalizedUnitFormatterTests.swift
//  iTerm2
//
//  QA finding F-405: Advanced Paste’s chunk size and delay labels and the
//  byte counts in Paste History used hard-coded English units in every UI
//  language.
//

import XCTest
@testable import iTerm2SharedARC

final class LocalizedUnitFormatterTests: XCTestCase {
    func testEnglishUILanguageIsNil() {
        XCTAssertNil(LocalizedUnitFormatter.nonEnglishLanguage(nil))
        XCTAssertNil(LocalizedUnitFormatter.nonEnglishLanguage("en"))
        XCTAssertNil(LocalizedUnitFormatter.nonEnglishLanguage("en-GB"))
        XCTAssertNil(LocalizedUnitFormatter.nonEnglishLanguage("Base"))
        XCTAssertEqual(LocalizedUnitFormatter.nonEnglishLanguage("ru"), "ru")
        XCTAssertEqual(LocalizedUnitFormatter.nonEnglishLanguage("pt-BR"), "pt-BR")
    }

    // MARK: - Advanced Paste chunk size

    func testChunkSizeEnglishIsUnchanged() {
        XCTAssertEqual(LocalizedUnitFormatter.chunkSizeDescription(1, language: nil), "1 B")
        XCTAssertEqual(LocalizedUnitFormatter.chunkSizeDescription(1024, language: nil), "1 kB")
        XCTAssertEqual(LocalizedUnitFormatter.chunkSizeDescription(1024 * 1024, language: nil), "1 MB")
    }

    func testChunkSizeRussianUsesRussianUnits() {
        let description = LocalizedUnitFormatter.chunkSizeDescription(1024, language: "ru")
        XCTAssertTrue(description.contains("кБ"), description)
        XCTAssertTrue(description.hasPrefix("1"), description)
        XCTAssertFalse(description.contains("kB"), description)
    }

    func testChunkSizeLocalizesDecimalSeparator() {
        let description = LocalizedUnitFormatter.chunkSizeDescription(1536, language: "de")
        XCTAssertTrue(description.hasPrefix("1,5"), description)
    }

    // MARK: - Advanced Paste delay

    func testDurationEnglishIsUnchanged() {
        XCTAssertEqual(LocalizedUnitFormatter.durationDescription(0.01, language: nil), "10 ms")
        XCTAssertEqual(LocalizedUnitFormatter.durationDescription(2, language: nil), "2 sec")
        XCTAssertEqual(LocalizedUnitFormatter.durationDescription(120, language: nil), "2 min")
    }

    func testDurationRussianUsesRussianUnits() {
        XCTAssertNotNil(LocalizedUnitFormatter.localizationBundle(language: "ru"))
        let ms = LocalizedUnitFormatter.durationDescription(0.01, language: "ru")
        XCTAssertTrue(ms.contains("мс"), ms)
        XCTAssertTrue(ms.hasPrefix("10"), ms)
        let sec = LocalizedUnitFormatter.durationDescription(2, language: "ru")
        XCTAssertFalse(sec.contains("sec"), sec)
        XCTAssertTrue(sec.contains("с"), sec)
    }

    func testDurationGermanUsesGermanUnits() {
        let sec = LocalizedUnitFormatter.durationDescription(2, language: "de")
        XCTAssertEqual(sec, "2 s")
    }

    // MARK: - Paste History byte counts (NSString it_formatBytes)

    func testFormatBytesEnglishIsUnchanged() {
        XCTAssertEqual(NSString.it_formatBytes(7, nonEnglishLanguage: nil), "7 bytes")
        XCTAssertEqual(NSString.it_formatBytes(1500, nonEnglishLanguage: nil), "1.5 kB")
        XCTAssertEqual(NSString.it_formatBytes(123_456, nonEnglishLanguage: nil), "123 kB")
    }

    func testFormatBytesGermanUsesGermanUnits() {
        let bytes = NSString.it_formatBytes(7, nonEnglishLanguage: "de")
        XCTAssertTrue(bytes.hasPrefix("7"), bytes)
        XCTAssertTrue(bytes.contains("Byte"), bytes)
        XCTAssertFalse(bytes.contains("bytes"), bytes)
        let kb = NSString.it_formatBytes(1500, nonEnglishLanguage: "de")
        XCTAssertTrue(kb.hasPrefix("1,5"), kb)
    }

    func testFormatBytesRussianUsesRussianUnits() {
        let kb = NSString.it_formatBytes(123_456, nonEnglishLanguage: "ru")
        XCTAssertTrue(kb.hasPrefix("123"), kb)
        XCTAssertTrue(kb.contains("кБ"), kb)
        // Matches the English rounding: no fraction above 10 kB.
        XCTAssertFalse(kb.contains(","), kb)
    }
}
