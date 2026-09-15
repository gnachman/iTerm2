import XCTest
@testable import iTerm2SharedARC

// VALIDATION regression tests for the finding:
// "Session Status default priorities are broken in every language, including
//  English."
//
// StatusPrioritySettings.defaultPatterns (sources/Toolbelt/StatusPrioritySettings.swift)
// derives its out-of-box priority patterns by asking each shipped localization
// bundle for the SetTabStatusTrigger status suggestions:
//
//   for localization in Bundle.main.localizations where localization != "Base" {
//       ...
//       let value = bundle.localizedString(forKey: key, value: "", table: "Localizable")
//       ...
//   }
//
// Two structural problems make this wrong for the English strings a user
// actually sees:
//
//  1. en.lproj in the built app ships only Localizable.stringsdict, with no
//     Localizable.strings (the source language relies on the defaultValue: at
//     each call site). So for the "en" bundle,
//       localizedString(forKey: "SetTabStatusTrigger.Waiting", value: "", table: "Localizable")
//     returns the KEY "SetTabStatusTrigger.Waiting" (Foundation returns the key
//     when the table is missing and value is empty). The English default
//     patterns are therefore raw keys, not the words "Waiting"/"Working"/"Idle".
//
//  2. Order (and thus which pattern lands at index 0, the only priority
//     isHighestPriority(for:) accepts) depends on Bundle.main.localizations
//     enumeration order, not on any deliberate English-first choice.
//
//  3. The historical master defaults were the substrings ["wait","work","idle"],
//     which matched "please wait" and similar. The new full-word / raw-key
//     defaults no longer do.
//
// These tests assert the INTENDED-CORRECT behavior and are expected to FAIL
// against the current code, demonstrating the bug.
final class StatusPriorityDefaultsTest: XCTestCase {

    // Sub-issue 1: the default patterns must never contain a raw localization
    // key. A pattern like "SetTabStatusTrigger.Waiting" leaks straight into the
    // user-visible priority table and matches no real status text.
    func testDefaultPatternsContainNoRawLocalizationKeys() {
        let defaults = StatusPrioritySettings.defaultPatterns
        XCTAssertFalse(defaults.isEmpty, "Default priority patterns should not be empty")
        for pattern in defaults {
            XCTAssertFalse(pattern.contains("SetTabStatusTrigger."),
                           "Default priority pattern \"\(pattern)\" is a raw localization key, not a human-readable word. en.lproj has no Localizable.strings so the English lookup falls through to the key.")
        }
    }

    // Sub-issue 1 + 3: the English status words a user actually sees
    // ("Waiting"/"Working"/"Idle") must be covered by the default patterns,
    // using the exact lowercased-substring rule the app applies in
    // priority(for:) and shouldNotify(for:).
    func testEnglishStatusWordsMatchADefaultPattern() {
        let defaults = StatusPrioritySettings.defaultPatterns.map { $0.lowercased() }
        for english in ["Waiting", "Working", "Idle"] {
            let lower = english.lowercased()
            let matched = defaults.contains { !$0.isEmpty && lower.contains($0) }
            XCTAssertTrue(matched,
                          "English status \"\(english)\" matches no default priority pattern. Patterns are \(defaults).")
        }
    }

    // Sub-issue 1: exercise the real app API. With the default patterns loaded,
    // an English "Waiting" status must get a defined (non-fallback) priority.
    // priority(for:) returns unmatchedPriority (== entries.count) when nothing
    // matches, so a defined priority is strictly less than unmatchedPriority.
    func testEnglishWaitingGetsDefinedPriority() {
        let settings = StatusPrioritySettings.shared
        let saved = settings.entries
        defer { settings.restoreEntries(saved) }

        settings.restoreEntries(StatusPrioritySettings.defaultPatterns.map { StatusPriorityEntry(pattern: $0) })

        let priority = settings.priority(for: "Waiting")
        XCTAssertLessThan(priority, settings.unmatchedPriority,
                          "English \"Waiting\" resolves to the fallback (unmatched) priority \(priority) of \(settings.unmatchedPriority). The default patterns do not cover the English words the user sees.")
    }

    // Sub-issue 2: determinism. The intended top priority is "waiting", so an
    // English "Waiting" status must be the highest priority regardless of
    // Bundle.main.localizations enumeration order. isHighestPriority(for:) only
    // returns true for priority == 0 (index 0), and index 0 is currently
    // whichever localization sorts first in Bundle.main.localizations, so this
    // fails for an English "Waiting".
    //
    // Note: full reorder-independence (feeding a permuted localization list)
    // is not unit-testable without dependency injection into defaultPatterns,
    // since Bundle.main.localizations order is fixed by the OS/bundle. This
    // test pins the observable symptom instead.
    func testEnglishWaitingIsHighestPriority() {
        let settings = StatusPrioritySettings.shared
        let saved = settings.entries
        defer { settings.restoreEntries(saved) }

        settings.restoreEntries(StatusPrioritySettings.defaultPatterns.map { StatusPriorityEntry(pattern: $0) })

        XCTAssertTrue(settings.isHighestPriority(for: "Waiting"),
                      "English \"Waiting\" is not the highest-priority status. Index 0 currently depends on Bundle.main.localizations order, so the Dock waiting badge cannot fire for an English \"Waiting\".")
    }

    // Sub-issue 2 (determinism, pure form): the first (highest-priority)
    // default pattern must correspond to the English "Waiting" status, not to
    // whatever localization happens to sort first. "waiting" must contain the
    // lowercased first pattern under the app's substring rule.
    func testFirstDefaultPatternCorrespondsToEnglishWaiting() {
        let defaults = StatusPrioritySettings.defaultPatterns
        XCTAssertFalse(defaults.isEmpty, "Default priority patterns should not be empty")
        let first = defaults[0].lowercased()
        XCTAssertTrue(!first.isEmpty && "waiting".contains(first),
                      "The first (highest-priority) default pattern is \"\(defaults[0])\", which does not correspond to the English \"Waiting\" status. index 0 is currently whatever localization sorts first in Bundle.main.localizations.")
    }
}
