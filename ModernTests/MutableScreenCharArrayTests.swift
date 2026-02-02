//
//  MutableScreenCharArrayTests.swift
//  iTerm2
//
//  Created by George Nachman on 2/2/26.
//

import XCTest
@testable import iTerm2SharedARC

final class MutableScreenCharArrayTests: XCTestCase {

    private func makeStyle() -> screen_char_t {
        var style = screen_char_t()
        style.foregroundColor = 1
        style.fgGreen = 2
        style.fgBlue = 3
        style.backgroundColor = 4
        style.bgGreen = 5
        style.bgBlue = 6
        style.foregroundColorMode = 1
        style.backgroundColorMode = 2
        style.complexChar = 0
        style.bold = 1
        style.faint = 0
        style.italic = 1
        style.blink = 0
        style.underline = 1
        style.image = 0
        style.strikethrough = 1
        style.underlineStyle = .single
        style.invisible = 0
        style.inverse = 1
        style.guarded = 0
        style.virtualPlaceholder = 0
        style.rtlStatus = .unknown
        return style
    }

    /// Test that setMetadata: does not leak the external attributes index.
    /// This test creates metadata with an external attributes index, sets it on a
    /// MutableScreenCharArray, then replaces it with new metadata and verifies the
    /// old external attributes index is deallocated.
    func testSetMetadataDoesNotLeak() {
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 2)
        msca.append("AB", fg: style, bg: style)

        // Create the first external attributes index and keep a weak reference
        weak var weakEaIndex1: iTermExternalAttributeIndex?
        autoreleasepool {
            let eaIndex1 = iTermExternalAttributeIndex()
            weakEaIndex1 = eaIndex1
            let ea1 = iTermExternalAttribute(
                havingUnderlineColor: true,
                underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
                url: nil,
                blockIDList: nil,
                controlCode: nil
            )
            eaIndex1.setAttributes(ea1, at: 0, count: 1)

            var metadata1 = iTermMetadataDefault()
            metadata1.timestamp = 1000.0
            iTermMetadataSetExternalAttributes(&metadata1, eaIndex1)
            msca.setMetadata(metadata1)
            iTermMetadataRelease(metadata1)

            // Verify it was set
            XCTAssertNotNil(msca.eaIndex)
        }

        // The eaIndex1 should still be alive because msca holds it
        XCTAssertNotNil(weakEaIndex1, "eaIndex1 should still be retained by msca")

        // Now replace the metadata with new metadata containing a different external attributes index
        weak var weakEaIndex2: iTermExternalAttributeIndex?
        autoreleasepool {
            let eaIndex2 = iTermExternalAttributeIndex()
            weakEaIndex2 = eaIndex2
            let ea2 = iTermExternalAttribute(
                havingUnderlineColor: true,
                underlineColor: VT100TerminalColorValue(red: 0, green: 1, blue: 0, mode: ColorModeNormal),
                url: nil,
                blockIDList: nil,
                controlCode: nil
            )
            eaIndex2.setAttributes(ea2, at: 1, count: 1)

            var metadata2 = iTermMetadataDefault()
            metadata2.timestamp = 2000.0
            iTermMetadataSetExternalAttributes(&metadata2, eaIndex2)
            msca.setMetadata(metadata2)
            iTermMetadataRelease(metadata2)
        }

        // After replacing, the old eaIndex1 should be deallocated (no longer retained)
        XCTAssertNil(weakEaIndex1, "eaIndex1 should have been released when metadata was replaced - LEAK DETECTED")

        // The new eaIndex2 should still be alive
        XCTAssertNotNil(weakEaIndex2, "eaIndex2 should still be retained by msca")

        // Clean up: release msca's hold on eaIndex2 by setting metadata without external attributes
        autoreleasepool {
            var emptyMetadata = iTermMetadataDefault()
            msca.setMetadata(emptyMetadata)
            iTermMetadataRelease(emptyMetadata)
        }

        // Now eaIndex2 should also be deallocated
        XCTAssertNil(weakEaIndex2, "eaIndex2 should have been released when metadata was cleared - LEAK DETECTED")
    }

    /// Test that setMetadata: works correctly when replacing metadata that has no external attributes
    func testSetMetadataFromEmptyToNonEmpty() {
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 2)
        msca.append("AB", fg: style, bg: style)

        // Start with empty metadata
        var emptyMetadata = iTermMetadataDefault()
        msca.setMetadata(emptyMetadata)
        iTermMetadataRelease(emptyMetadata)

        XCTAssertNil(msca.eaIndex)

        // Now set metadata with external attributes
        weak var weakEaIndex: iTermExternalAttributeIndex?
        autoreleasepool {
            let eaIndex = iTermExternalAttributeIndex()
            weakEaIndex = eaIndex
            let ea = iTermExternalAttribute(
                havingUnderlineColor: true,
                underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
                url: nil,
                blockIDList: nil,
                controlCode: nil
            )
            eaIndex.setAttributes(ea, at: 0, count: 1)

            var metadata = iTermMetadataDefault()
            iTermMetadataSetExternalAttributes(&metadata, eaIndex)
            msca.setMetadata(metadata)
            iTermMetadataRelease(metadata)
        }

        XCTAssertNotNil(msca.eaIndex)
        XCTAssertNotNil(weakEaIndex, "eaIndex should still be retained by msca")
    }

    /// Test multiple consecutive setMetadata calls
    func testSetMetadataMultipleTimes() {
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 2)
        msca.append("AB", fg: style, bg: style)

        var weakRefs: [() -> iTermExternalAttributeIndex?] = []

        // Create and set multiple metadata objects in sequence
        for i in 0..<5 {
            autoreleasepool {
                let eaIndex = iTermExternalAttributeIndex()
                weak var weakEa = eaIndex
                weakRefs.append({ weakEa })

                let ea = iTermExternalAttribute(
                    havingUnderlineColor: true,
                    underlineColor: VT100TerminalColorValue(red: Int32(i), green: 0, blue: 0, mode: ColorModeNormal),
                    url: nil,
                    blockIDList: nil,
                    controlCode: nil
                )
                eaIndex.setAttributes(ea, at: 0, count: 1)

                var metadata = iTermMetadataDefault()
                metadata.timestamp = Double(i * 1000)
                iTermMetadataSetExternalAttributes(&metadata, eaIndex)
                msca.setMetadata(metadata)
                iTermMetadataRelease(metadata)
            }
        }

        // All but the last should be deallocated
        for i in 0..<4 {
            XCTAssertNil(weakRefs[i](), "eaIndex[\(i)] should have been released - LEAK DETECTED")
        }

        // The last one should still be alive
        XCTAssertNotNil(weakRefs[4](), "eaIndex[4] should still be retained by msca")
    }
}
