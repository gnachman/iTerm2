//
//  iTermExternalAttributeIndexPropertyListTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/15/26.
//

import XCTest
@testable import iTerm2SharedARC

// Saving a window arrangement to a file with contents serializes it as a
// binary property list, which only allows string dictionary keys. Hyperlinks,
// underline colors, and similar per-cell attributes are encoded by
// iTermExternalAttributeIndex, so its dictionaryValue must be plist-safe.
final class iTermExternalAttributeIndexPropertyListTests: XCTestCase {
    private func hyperlinkAttribute() -> iTermExternalAttribute {
        let url = iTermURL(url: URL(string: "https://example.com")!, identifier: nil, target: nil)
        return iTermExternalAttribute(underlineColor: VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: nil,
                                      controlCode: nil)
    }

    // An index where only columns 2 through 4 of a line are hyperlinked.
    private func partialHyperlinkIndex() -> iTermExternalAttributeIndex {
        let index = iTermExternalAttributeIndex()
        index.setAttributes(hyperlinkAttribute(), at: 2, count: 3)
        return index
    }

    private func binaryPropertyListRoundTrip(_ object: Any) throws -> Any {
        let data = try PropertyListSerialization.data(fromPropertyList: object,
                                                      format: .binary,
                                                      options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    func testDictionaryValueIsValidPropertyList() {
        let dict = partialHyperlinkIndex().dictionaryValue
        XCTAssertFalse(dict.isEmpty)
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: dict,
                                                            format: .binary,
                                                            options: 0))
    }

    func testRoundTripsThroughPropertyList() throws {
        let decoded = try binaryPropertyListRoundTrip(partialHyperlinkIndex().dictionaryValue)
        let restored = try XCTUnwrap(iTermExternalAttributeIndex(dictionary: try XCTUnwrap(decoded as? NSDictionary) as! [AnyHashable: Any]))
        XCTAssertNil(restored.attribute(at: 1))
        for i in Int32(2)...4 {
            XCTAssertEqual(restored.attribute(at: i)?.url?.url, URL(string: "https://example.com")!)
        }
        XCTAssertNil(restored.attribute(at: 5))
    }

    // Saves written before string keys were used have NSNumber keys. They
    // must still restore.
    func testDecodesLegacyNumberKeys() throws {
        let legacy: [NSNumber: Any] = [NSNumber(value: 7): hyperlinkAttribute().dictionaryValue]
        let restored = try XCTUnwrap(iTermExternalAttributeIndex(dictionary: legacy))
        XCTAssertEqual(restored.attribute(at: 7)?.url?.url, URL(string: "https://example.com")!)
        XCTAssertNil(restored.attribute(at: 6))
    }

    // The scrollback path that Save to File with Contents actually takes.
    func testLineBlockWithPartialHyperlinkIsValidPropertyList() throws {
        let text = "a link here"
        var buffer = Array<screen_char_t>(repeating: screen_char_t(), count: text.utf16.count * 3)
        let content = buffer.withUnsafeMutableBufferPointer { umbp -> iTermLegacyStyleString in
            var len = Int32(umbp.count)
            StringToScreenChars(text, umbp.baseAddress!, screen_char_t(), screen_char_t(), &len,
                                false, nil, nil, iTermUnicodeNormalization.none, 9, false, nil)
            return iTermLegacyStyleString(chars: umbp.baseAddress!,
                                          count: Int(len),
                                          eaIndex: partialHyperlinkIndex())
        }
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        let line = iTermLineString(content: content,
                                   eol: EOL_HARD,
                                   continuation: continuation,
                                   metadata: iTermLineStringMetadata(timestamp: 0, rtlFound: false),
                                   bidi: nil,
                                   dirty: false)
        let block = LineBlock(rawBufferSize: 100, absoluteBlockNumber: 1)
        XCTAssertTrue(block.appendLineString(line, width: 80))

        let decoded = try binaryPropertyListRoundTrip(block.dictionary())
        let restored = try XCTUnwrap(LineBlock(dictionary: try XCTUnwrap(decoded as? [AnyHashable: Any]),
                                               absoluteBlockNumber: 1))
        XCTAssertTrue(block.isEqual(restored))
    }
}
