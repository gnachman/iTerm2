//
//  TransferrableFileStatusRowLayoutTests.swift
//  iTerm2
//
//  F-723: in the Downloads menu the status and the size were each drawn across the whole
//  bottom row, so a long status such as “Finished, with some items left out” ran into the
//  size, and German “Abgeschlossen, einige Objekte ausgelassen” was drawn over
//  “223 Byte von 223 Byte”.
//

import XCTest
@testable import iTerm2SharedARC

final class TransferrableFileStatusRowLayoutTests: XCTestCase {
    // The menu item is 300 points wide with 14 point margins.
    private let row = NSRect(x: 14, y: 3, width: 272, height: 13)
    private let font = NSFont.systemFont(ofSize: 10)

    private func width(_ string: String) -> CGFloat {
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func assertSeparate(_ layout: TransferrableFileStatusRowLayout,
                                sizeWidth: CGFloat,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        XCTAssertLessThanOrEqual(layout.statusRect.maxX + TransferrableFileStatusRowLayout.gap,
                                 layout.sizeRect.minX + 0.001,
                                 "The status must end before the size begins",
                                 file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.sizeRect.width, ceil(sizeWidth),
                                    "The size must have room to be drawn in full",
                                    file: file, line: line)
        XCTAssertEqual(layout.sizeRect.maxX, row.maxX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(layout.statusRect.minX, row.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertGreaterThan(layout.statusRect.width, 0, file: file, line: line)
    }

    func testLongTranslationsDoNotOverlapTheSize() {
        let cases = [
            ("Finished, with some items left out", "223 bytes of 223 bytes"),
            ("Abgeschlossen, einige Objekte ausgelassen", "223 Byte von 223 Byte"),
            ("Завершено, некоторые элементы пропущены", "223 Б из 223 Б"),
            ("完了（一部の項目を除外）", "223 バイト / 223 バイト"),
            ("Abgeschlossen, einige Objekte ausgelassen", "1023,9 MB von 1023,9 MB"),
        ]
        for (status, size) in cases {
            let sizeWidth = width(size)
            let layout = TransferrableFileStatusRowLayout(rowRect: row,
                                                          statusWidth: width(status),
                                                          sizeWidth: sizeWidth)
            assertSeparate(layout, sizeWidth: sizeWidth)
        }
    }

    func testShortStatusAndSizeEachGetTheirNaturalWidth() {
        let layout = TransferrableFileStatusRowLayout(rowRect: row, statusWidth: 40, sizeWidth: 90)
        XCTAssertEqual(layout.sizeRect.width, 90)
        XCTAssertEqual(layout.statusRect.width, row.width - 90 - TransferrableFileStatusRowLayout.gap)
        assertSeparate(layout, sizeWidth: 90)
    }

    func testStatusTooLongForTheRowIsGivenTheRest() {
        let layout = TransferrableFileStatusRowLayout(rowRect: row, statusWidth: 1000, sizeWidth: 100)
        XCTAssertEqual(layout.sizeRect.width, 100)
        XCTAssertEqual(layout.statusRect.width, row.width - 100 - TransferrableFileStatusRowLayout.gap)
        assertSeparate(layout, sizeWidth: 100)
    }

    func testHugeSizeLeavesTheStatusAThirdOfTheRow() {
        let layout = TransferrableFileStatusRowLayout(rowRect: row, statusWidth: 200, sizeWidth: 1000)
        XCTAssertEqual(layout.statusRect.width, row.width / 3, accuracy: 0.001)
        XCTAssertEqual(layout.statusRect.maxX + TransferrableFileStatusRowLayout.gap,
                       layout.sizeRect.minX,
                       accuracy: 0.001)
        XCTAssertEqual(layout.sizeRect.maxX, row.maxX, accuracy: 0.001)
    }

    func testNoSizeGivesTheStatusTheWholeRow() {
        let layout = TransferrableFileStatusRowLayout(rowRect: row, statusWidth: 1000, sizeWidth: 0)
        XCTAssertEqual(layout.statusRect, row)
        XCTAssertEqual(layout.sizeRect.width, 0)
    }

    func testNoStatusGivesTheSizeTheWholeRow() {
        let layout = TransferrableFileStatusRowLayout(rowRect: row, statusWidth: 0, sizeWidth: 90)
        XCTAssertEqual(layout.sizeRect, row)
        XCTAssertEqual(layout.statusRect.width, 0)
    }
}
