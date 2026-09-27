//
//  SetTabStatusTriggerSuggestionPriorityTests.swift
//  ModernTests
//
//  Regression tests for the finding:
//  "Set Tab Status trigger suggests localized statuses that never match the
//   English priority patterns."
//
//  SetTabStatusTrigger.comboBoxItems() (sources/Triggers/SetTabStatusTrigger.swift)
//  offers three LOCALIZED status suggestions (Working/Waiting/Idle). Before the
//  fix, picking one wrote the localized display string verbatim into
//  VT100TabStatusUpdate.status, and Session Status priority is decided by
//  StatusPrioritySettings.priority(for:) using the rule
//
//      statusText.lowercased().contains(pattern.lowercased())
//
//  against the FIXED English defaultPatterns ["wait", "work", "idle"]
//  (sources/Toolbelt/StatusPrioritySettings.swift). A pt-BR user who picked
//  "Trabalhando"/"Aguardando"/"Ocioso" (or a zh-Hans user who picked
//  "工作中"/"等待中"/"空闲") stored a status that contains none of wait/work/idle,
//  so it fell through to the unmatched priority.
//
//  THE FIX (maintainer decision): the STORED/canonical status value is the
//  lowercase English WIRE token ("work"/"wait"/"idle") so it matches
//  defaultPatterns; the UI DISPLAYS a localized capitalized string.
//  param(byReplacingComboBoxValue:) maps the picked localized display back to
//  its wire value; comboBoxValue(inParam:) maps a stored wire value forward to
//  the localized display.
//
//  INVARIANT under test: whatever the trigger stores when a user (in any
//  shipped localization) picks a suggestion is a wire canonical that a default
//  priority pattern matches under the lowercased-contains rule, and a stored
//  wire value gets a defined (non-unmatched) priority.

import XCTest
@testable import iTerm2SharedARC

final class SetTabStatusTriggerSuggestionPriorityTests: XCTestCase {

    // The three String Catalog keys behind comboBoxItems(), in order.
    private static let suggestionKeys = [
        "SetTabStatusTrigger.Working",
        "SetTabStatusTrigger.Waiting",
        "SetTabStatusTrigger.Idle",
    ]

    // English defaults, in case a localization has no translation (falls back).
    private static let englishDefaults = [
        "SetTabStatusTrigger.Working": "Working",
        "SetTabStatusTrigger.Waiting": "Waiting",
        "SetTabStatusTrigger.Idle": "Idle",
    ]

    // The wire canonical each suggestion (by position) is stored as. Mirrors the
    // canonical table in SetTabStatusTrigger.
    private static let canonicalWireByIndex = ["work", "wait", "idle"]

    // The parameter separator used by SetTabStatusTrigger to pack
    // dotColor <sep> textColor <sep> statusText. Kept in sync with the source.
    private static let paramSeparator = "\u{1}"

    // The exact match rule from StatusPrioritySettings.priority(for:):
    //   statusText.lowercased().contains(pattern.lowercased())
    private func matchesAnyDefaultPattern(_ value: String) -> Bool {
        let lower = value.lowercased()
        for pattern in StatusPrioritySettings.defaultPatterns {
            let p = pattern.lowercased()
            if !p.isEmpty && lower.contains(p) {
                return true
            }
        }
        return false
    }

    // The statusText (3rd component) the trigger actually stored in a param.
    private func storedStatusText(_ param: Any?) -> String {
        guard let str = param as? String else { return "" }
        let parts = str.components(separatedBy: Self.paramSeparator)
        return parts.count > 2 ? parts[2] : ""
    }

    private func makeTrigger() -> SetTabStatusTrigger? {
        let dict: [String: Any] = [
            "action": "iTermSetTabStatusTrigger",
            "parameter": "",
            "regex": "",
            "matchType": NSNumber(value: iTermTriggerMatchType.regex.rawValue),
        ]
        return Trigger(fromUntrustedDict: dict) as? SetTabStatusTrigger
    }

    // Load a specific localization's Localizable table via its .lproj, resolving
    // each suggestion key. Foundation returns the key when the table/entry is
    // missing (value: ""), so treat a key echo as "untranslated" and fall back
    // to the English default value the user would actually see.
    private func suggestions(forLocalization localization: String) -> [String]? {
        guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return Self.suggestionKeys.map { key in
            let value = bundle.localizedString(forKey: key, value: "", table: "Localizable")
            if value.isEmpty || value == key {
                return Self.englishDefaults[key] ?? key
            }
            return value
        }
    }

    // MARK: - Round-trip through the real trigger surface (current locale)

    // Picking any suggestion the trigger offers, in whatever locale the test
    // host runs, must store a wire canonical that a default pattern matches.
    // This is the core regression: before the fix, a non-English host stored the
    // localized display verbatim and matched nothing.
    func testPickingASuggestionStoresAMatchableWireValue() {
        guard let trigger = makeTrigger() else {
            XCTFail("Could not construct SetTabStatusTrigger")
            return
        }
        let items = trigger.comboBoxItems()
        XCTAssertFalse(items.isEmpty, "comboBoxItems() returned nothing")
        for display in items {
            let stored = storedStatusText(trigger.param(byReplacingComboBoxValue: display, inParam: ""))
            XCTAssertTrue(matchesAnyDefaultPattern(stored),
                          "Picking suggestion “\(display)” stored “\(stored)”, which matches no " +
                          "default priority pattern \(StatusPrioritySettings.defaultPatterns).")
        }
    }

    // A stored wire value is shown to the user as the current-locale display
    // string (the reverse mapping), so the combo box keeps reading naturally.
    func testStoredWireValueDisplaysAsLocalizedSuggestion() {
        guard let trigger = makeTrigger() else {
            XCTFail("Could not construct SetTabStatusTrigger")
            return
        }
        let items = trigger.comboBoxItems()
        XCTAssertEqual(items.count, Self.canonicalWireByIndex.count)
        for (i, wire) in Self.canonicalWireByIndex.enumerated() {
            let param = [Self.paramSeparator, Self.paramSeparator, wire].joined()
            XCTAssertEqual(trigger.comboBoxValue(inParam: param), items[i],
                           "Stored wire value “\(wire)” should display as “\(items[i])”.")
        }
    }

    // Free text is stored verbatim and displayed verbatim (no spurious mapping).
    func testFreeTextIsStoredAndDisplayedUnchanged() {
        guard let trigger = makeTrigger() else {
            XCTFail("Could not construct SetTabStatusTrigger")
            return
        }
        let freeText = "Deploying"
        let param = trigger.param(byReplacingComboBoxValue: freeText, inParam: "")
        XCTAssertEqual(storedStatusText(param), freeText)
        XCTAssertEqual(trigger.comboBoxValue(inParam: param), freeText)
    }

    // MARK: - Stored wire value gets a defined priority via the real settings

    // Feed the default patterns into StatusPrioritySettings and confirm the wire
    // value the trigger stores for each suggestion resolves to a defined
    // (non-unmatched) priority.
    func testStoredWireValueGetsDefinedPriorityThroughSettings() {
        guard let trigger = makeTrigger() else {
            XCTFail("Could not construct SetTabStatusTrigger")
            return
        }
        let settings = StatusPrioritySettings.shared
        let saved = settings.entries
        defer { settings.restoreEntries(saved) }
        settings.restoreEntries(StatusPrioritySettings.defaultPatterns.map { StatusPriorityEntry(pattern: $0) })

        for display in trigger.comboBoxItems() {
            let stored = storedStatusText(trigger.param(byReplacingComboBoxValue: display, inParam: ""))
            let priority = settings.priority(for: stored)
            XCTAssertLessThan(priority, settings.unmatchedPriority,
                              "Stored status “\(stored)” (from suggestion “\(display)”) resolves to the " +
                              "fallback priority \(priority) of \(settings.unmatchedPriority).")
        }
    }

    // MARK: - Localization sweep

    // For every shipped localization, the suggestion the trigger offers maps (by
    // position) to a wire canonical that a default pattern matches and that gets
    // a defined priority. This covers the locales a single-locale test host does
    // not itself run in (e.g. pt-BR "Trabalhando", zh-Hans "工作中").
    func testEveryLocalizationSuggestionMapsToAMatchableWireValue() {
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        XCTAssertFalse(localizations.isEmpty, "No shipped localizations found in the test host bundle")

        let settings = StatusPrioritySettings.shared
        let saved = settings.entries
        defer { settings.restoreEntries(saved) }
        settings.restoreEntries(StatusPrioritySettings.defaultPatterns.map { StatusPriorityEntry(pattern: $0) })

        for localization in localizations {
            guard let suggestions = suggestions(forLocalization: localization) else {
                continue
            }
            XCTAssertEqual(suggestions.count, Self.canonicalWireByIndex.count,
                           "\(localization) returned \(suggestions.count) suggestions")
            for (i, suggestion) in suggestions.enumerated() {
                XCTAssertFalse(suggestion.isEmpty, "\(localization) suggestion \(i) is empty")
                let wire = Self.canonicalWireByIndex[i]
                XCTAssertTrue(matchesAnyDefaultPattern(wire),
                              "Wire canonical “\(wire)” for \(localization) suggestion “\(suggestion)” " +
                              "matches no default pattern \(StatusPrioritySettings.defaultPatterns).")
                XCTAssertLessThan(settings.priority(for: wire), settings.unmatchedPriority,
                                  "Wire canonical “\(wire)” for \(localization) suggestion “\(suggestion)” " +
                                  "resolves to the unmatched priority.")
            }
        }
    }

    // MARK: - Direct pt-BR check (explicit, ground-truth strings)

    // Pins pt-BR so the coverage is unambiguous: its suggestions map to wire
    // canonicals that a default pattern matches.
    func testBrazilianPortugueseSuggestionsMapToAMatchableWireValue() {
        guard let suggestions = suggestions(forLocalization: "pt-BR") else {
            XCTFail("pt-BR.lproj not found in the test host bundle; cannot validate pt-BR suggestions")
            return
        }
        XCTAssertEqual(suggestions.count, Self.canonicalWireByIndex.count)
        for (i, suggestion) in suggestions.enumerated() {
            let wire = Self.canonicalWireByIndex[i]
            XCTAssertTrue(matchesAnyDefaultPattern(wire),
                          "pt-BR suggestion “\(suggestion)” maps to wire “\(wire)”, which matches no " +
                          "default priority pattern \(StatusPrioritySettings.defaultPatterns).")
        }
    }
}
