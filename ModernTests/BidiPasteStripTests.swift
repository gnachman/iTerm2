//
//  BidiPasteStripTests.swift
//  ModernTests
//
//  The "strip zero-width bidi/format characters on paste" option is titled for
//  bidi/format characters, so its set must include the actual bidi reordering
//  controls (the Trojan-Source set: directional embeddings/overrides, isolates,
//  and the Arabic Letter Mark), not just the cosmetic <200c> subset.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiPasteStripTests: XCTestCase {
    func testZeroWidthFormatSetIncludesBidiReorderingControls() {
        let set = iTermPasteHelper.zeroWidthFormatCharacterSet() as CharacterSet

        // The reordering controls a "bidi/format" stripper is most expected to remove.
        let required: [UInt32] = [0x202A, 0x202B, 0x202C, 0x202D, 0x202E,  // LRE RLE PDF LRO RLO
                                  0x2066, 0x2067, 0x2068, 0x2069,          // LRI RLI FSI PDI
                                  0x061C]                                   // ALM
        for cp in required {
            XCTAssertTrue(set.contains(UnicodeScalar(cp)!),
                          "strip set must include U+\(String(cp, radix: 16, uppercase: true))")
        }

        // The original cosmetic subset must still be present.
        let original: [UInt32] = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x00AD, 0x2060, 0xFEFF]
        for cp in original {
            XCTAssertTrue(set.contains(UnicodeScalar(cp)!),
                          "strip set must still include U+\(String(cp, radix: 16, uppercase: true))")
        }
    }

    // MARK: - Sanitizing with the option on (QA findings F-075 and F-207)

    private let strip = "StripZeroWidthFormatCharactersOnPaste"

    private func setBidi(_ on: Bool) {
        iTermPreferences.setBool(on, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(5)
        while iTermPreferences.bidiEnabled() != on && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func withStripping(_ block: () -> Void) {
        let defaults = iTermUserDefaults.userDefaults()
        let saved = defaults.object(forKey: strip)
        defaults.set(true, forKey: strip)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidi(true)
        defer {
            setBidi(false)
            if let saved { defaults.set(saved, forKey: strip) } else { defaults.removeObject(forKey: strip) }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        XCTAssertTrue(iTermAdvancedSettingsModel.stripZeroWidthFormatCharactersOnPaste())
        block()
    }

    private func sanitized(_ string: String, flags: iTermPasteFlags) -> String? {
        guard let event = PasteEvent(string: string,
                                     flags: flags,
                                     defaultChunkSize: 1,
                                     chunkKey: nil,
                                     defaultDelay: 1,
                                     delayKey: nil,
                                     tabTransform: .tabTransformNone,
                                     spacesPerTab: 0,
                                     regex: nil,
                                     substitution: nil,
                                     shouldPasteNewlinesOutsideBrackets: false) else {
            XCTFail("Could not create paste event")
            return nil
        }
        iTermPasteHelper.sanitizePasteEvent(event, encoding: String.Encoding.utf8.rawValue)
        return event.string
    }

    private let family = "X\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}Y"

    func testZWJInsideEmojiSequenceIsKept() {
        withStripping {
            XCTAssertEqual(sanitized(family, flags: []), family)
            let rainbow = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"
            XCTAssertEqual(sanitized(rainbow, flags: []), rainbow)
        }
    }

    func testFormatCharactersOutsideEmojiAreStillStripped() {
        withStripping {
            XCTAssertEqual(sanitized("می\u{200C}خواهم", flags: []), "میخواهم")
            XCTAssertEqual(sanitized("a\u{202E}b\u{200F}c", flags: []), "abc")
            // A ZWJ between letters does not join them into one character, so
            // it is still removed.
            XCTAssertEqual(sanitized("ب\u{200D}ب", flags: []), "بب")
            // A ZWJ in an emoji sequence is kept while other format characters
            // in the same paste are removed.
            XCTAssertEqual(sanitized("\u{200E}" + family, flags: []), family)
        }
    }

    func testBase64PasteIsByteExact() {
        withStripping {
            let text = family + " می\u{200C}خواهم \u{202E}"
            guard let encoded = sanitized(text, flags: .pasteFlagsBase64Encode) else { return }
            let joined = encoded.replacingOccurrences(of: "\r", with: "")
            guard let data = Data(base64Encoded: joined) else { return XCTFail("not base64: \(encoded)") }
            XCTAssertEqual(data, text.data(using: .utf8))
        }
    }
}
