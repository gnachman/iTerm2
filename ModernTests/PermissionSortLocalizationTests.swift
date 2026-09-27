//
//  PermissionSortLocalizationTests.swift
//  iTerm2
//
//  VALIDATION test for FINDING 1: the site-permission reset menu is sorted with
//  Swift's `<` operator over localized display names, not a locale-aware
//  collation.
//
//  Production site (inline, no injectable seam):
//    sources/Browser/UI/iTermBrowserToolbar.swift ~384
//      let sortedPermissionTypes =
//          permissions.keys.sorted { $0.displayName < $1.displayName }
//
//  `displayName` (BrowserPermissions.swift) returns LOCALIZED nouns
//  (pt-BR: "Câmera", "Localização", "Notificações"; and CJK, etc.). Swift's
//  `<` on String compares by Unicode scalar value, which is neither a locale
//  collation nor case-insensitive:
//    - Accented letters (U+00C0 and up) sort AFTER every ASCII letter, so an
//      accent-initial noun is pushed to the end instead of collating with its
//      base letter.
//    - Uppercase (U+0041...) sorts before lowercase (U+0061...), so casing
//      alone reorders items even in English.
//  The correct idiom is `localizedStandardCompare(_:) == .orderedAscending`
//  (Finder-style, locale-aware, case- and accent-insensitive).
//
//  There is NO production seam: the sort is an inline closure inside an async
//  menu-building method, so this test cannot drive the real menu. It instead
//  proves the IDIOM is wrong by showing that the two comparators produce
//  different orderings for realistic localized permission names, and that only
//  localizedStandardCompare yields the human-expected order.
//

import XCTest
@testable import iTerm2SharedARC

final class PermissionSortLocalizationTests: XCTestCase {

    private func sortedWithLessThan(_ names: [String]) -> [String] {
        // Mirrors the production idiom: permissions.keys.sorted { a.displayName < b.displayName }
        return names.sorted { $0 < $1 }
    }

    private func sortedLocalized(_ names: [String]) -> [String] {
        // The corrected idiom.
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // NOTE: the 4-name set from the finding description
    // (["Localização","Câmera","Microfone","Notificações"]) happens NOT to
    // diverge, because its first letters C < L < M < N are already monotonic
    // under both comparators. Divergence appears whenever an accent-initial
    // noun or a case difference is present, which real localized permission
    // sets do contain. We use an accent-initial name ("Áudio", i.e. the head of
    // the pt-BR "Reprodução de Áudio" family reduced to its accented word) to
    // expose the bug.
    func testAccentInitialNameMisordersUnderLessThanButNotLocalized() {
        let names = ["Localização", "Áudio", "Câmera"]

        let lessThan = sortedWithLessThan(names)
        let localized = sortedLocalized(names)

        // The two idioms genuinely disagree: this is the core proof the
        // production `<` idiom is wrong.
        XCTAssertNotEqual(lessThan, localized,
                          "`<` and localizedStandardCompare must diverge for accented names; got identical \(lessThan)")

        // `<` shoves the accented word to the end (U+00C1 > every ASCII letter).
        XCTAssertEqual(lessThan, ["Câmera", "Localização", "Áudio"])

        // Locale collation folds the accent so Áudio collates with 'A' and comes first.
        XCTAssertEqual(localized, ["Áudio", "Câmera", "Localização"])
    }

    // The finding also flags an English-only impact: `<` is case-sensitive, so
    // an all-uppercase or mixed-case display name reorders relative to a
    // lowercase one even with no accents involved.
    func testCaseSensitivityReordersEvenInEnglish() {
        let names = ["Camera", "audio", "Video"]

        let lessThan = sortedWithLessThan(names)
        let localized = sortedLocalized(names)

        XCTAssertNotEqual(lessThan, localized)
        // `<`: uppercase 'C'/'V' (0x43/0x56) precede lowercase 'a' (0x61).
        XCTAssertEqual(lessThan, ["Camera", "Video", "audio"])
        // localized: case-insensitive alphabetical.
        XCTAssertEqual(localized, ["audio", "Camera", "Video"])
    }

    // Sanity anchor: localizedStandardCompare produces the order a human reads
    // as alphabetical for a mixed accented set (Câmera before Localização),
    // which the finding cites as the expected outcome.
    func testLocalizedYieldsExpectedAlphabeticalOrder() {
        let localized = sortedLocalized(["Localização", "Câmera", "Notificações", "Microfone"])
        XCTAssertEqual(localized, ["Câmera", "Localização", "Microfone", "Notificações"])
    }
}
