//
//  UILanguageCaseTests.swift
//  ModernTests
//
//  Changing the case of translated text has to follow the UI language. In Turkish, “i” uppercases
//  to “İ”, not “I”, so a header like “işlem” must become “İŞLEM”.
//

import XCTest
@testable import iTerm2SharedARC

final class UILanguageCaseTests: XCTestCase {
    private let turkish = Locale(identifier: "tr")

    func testUppercaseFollowsTheLocale() {
        XCTAssertEqual(UILanguageCase.uppercase("işlem kimliği", locale: turkish), "İŞLEM KİMLİĞİ")
        XCTAssertEqual(UILanguageCase.uppercase("process id", locale: Locale(identifier: "en")), "PROCESS ID")
    }

    func testCapitalizingFirstLetterFollowsTheLocale() {
        XCTAssertEqual(UILanguageCase.capitalizingFirstLetter("ikili dosya", locale: turkish), "İkili dosya")
        XCTAssertEqual(UILanguageCase.capitalizingFirstLetter("ıhlamur", locale: turkish), "Ihlamur")
        XCTAssertEqual(UILanguageCase.capitalizingFirstLetter("plain text", locale: Locale(identifier: "en")), "Plain text")
        XCTAssertEqual(UILanguageCase.capitalizingFirstLetter("", locale: turkish), "")
    }

    func testLocaleIsTheUILocalization() {
        XCTAssertEqual(UILanguageCase.locale(forLocalization: "tr").identifier, "tr")
        XCTAssertEqual(UILanguageCase.locale(forLocalization: nil).identifier, "en")
    }
}
