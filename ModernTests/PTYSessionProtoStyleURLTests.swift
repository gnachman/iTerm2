//
//  PTYSessionProtoStyleURLTests.swift
//  iTerm2 ModernTests
//
//  Regression test for GitLab #13003: OSC 8 hyperlinks were invisible to the
//  Python API. protoStyleForCharacter:externalAttributes: built an ITMURL from
//  the cell's external attribute but never assigned it to the ITMCellStyle, so
//  CellStyle.url was always None even for hyperlinked cells. These tests pin the
//  assignment.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionProtoStyleURLTests: XCTestCase {
    private func makeExternalAttribute(url: iTermURL?) -> iTermExternalAttribute? {
        return iTermExternalAttribute(havingUnderlineColor: false,
                                      underlineColor: VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())
    }

    func testProtoStyleCarriesOSC8URL() {
        let url = iTermURL(url: URL(string: "https://example.com/osc8-test")!,
                           identifier: "42",
                           target: nil)
        guard let ea = makeExternalAttribute(url: url) else {
            XCTFail("expected non-nil external attribute"); return
        }
        let c = screen_char_t()
        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)
        XCTAssertTrue(style.hasURL, "hyperlinked cell must expose a URL")
        XCTAssertEqual(style.url.url, "https://example.com/osc8-test")
        XCTAssertEqual(style.url.identifier, "42")
    }

    func testProtoStyleHasNoURLWhenAbsent() {
        // An external attribute carrying something other than a URL (here an
        // underline color) must not spuriously report a URL.
        let uc = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                         hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        guard let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                              underlineColor: uc,
                                              url: nil,
                                              blockIDList: nil,
                                              controlCode: nil,
                                              dualModeForeground: iTermDualModeColor(),
                                              dualModeBackground: iTermDualModeColor()) else {
            XCTFail("expected non-nil external attribute"); return
        }
        let c = screen_char_t()
        let style = PTYSession.protoStyle(forCharacter: c, externalAttributes: ea)
        XCTAssertFalse(style.hasURL)
    }
}
