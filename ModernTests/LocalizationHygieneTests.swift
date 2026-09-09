//
//  LocalizationHygieneTests.swift
//  ModernTests
//
//  Lint-style guards over the String Catalogs. Each test asserts a "clean"
//  invariant that the catalogs currently violate, so the failure message
//  enumerates the offending keys. These read the catalog JSON directly, the
//  same way LocalizationFormatSpecifierParityTests does.
//
//  The em dash (U+2014), the right/closing double quote (U+201D) and the ESC
//  based SGR marker are all referenced here by escape rather than literal so
//  the test source itself stays free of the very characters it forbids.
//

import XCTest

final class LocalizationHygieneTests: XCTestCase {
    // MARK: - Catalog loading

    private func repoRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ModernTests
            .deletingLastPathComponent()   // repo root
    }

    private func loadCatalog(_ relativePath: String) throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func mainStrings() throws -> [String: Any] {
        let json = try loadCatalog("sources/Localizable.xcstrings")
        return json["strings"] as! [String: Any]
    }

    // Every concrete string value in one localization entry: the plain value plus
    // any plural variation values and any substitution variation values.
    private func allValues(_ localization: [String: Any]) -> [String] {
        var out: [String] = []
        func harvestVariations(_ variations: [String: Any]) {
            for (_, byCategoryAny) in variations {
                guard let byCategory = byCategoryAny as? [String: Any] else { continue }
                for (_, catEntryAny) in byCategory {
                    if let catEntry = catEntryAny as? [String: Any],
                       let unit = catEntry["stringUnit"] as? [String: Any],
                       let value = unit["value"] as? String {
                        out.append(value)
                    }
                }
            }
        }
        if let unit = localization["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String {
            out.append(value)
        }
        if let variations = localization["variations"] as? [String: Any] {
            harvestVariations(variations)
        }
        if let substitutions = localization["substitutions"] as? [String: Any] {
            for (_, subAny) in substitutions {
                guard let sub = subAny as? [String: Any] else { continue }
                if let variations = sub["variations"] as? [String: Any] {
                    harvestVariations(variations)
                }
                if let unit = sub["stringUnit"] as? [String: Any],
                   let value = unit["value"] as? String {
                    out.append(value)
                }
            }
        }
        return out
    }

    private func enPlainValue(_ entry: [String: Any]) -> String? {
        guard let locs = entry["localizations"] as? [String: Any],
              let en = locs["en"] as? [String: Any],
              let unit = en["stringUnit"] as? [String: Any] else {
            return nil
        }
        return unit["value"] as? String
    }

    // MARK: - Finding 1: stray OK / Ok / Cancel button keys

    // Every catalog key whose English value is exactly an OK/Cancel button label
    // must funnel through the shared General.OK / General.Cancel entries (which
    // back iTermLocalizedOK()/iTermLocalizedCancel()). Minting a private duplicate
    // fragments the translation and, as with SCPFile.Ok, ships a miscapitalized
    // "Ok".
    func testNoStrayOKCancelButtonKeys() throws {
        let allowed: Set<String> = ["General.OK", "General.Cancel"]
        let buttonLabels: Set<String> = ["OK", "Ok", "Cancel"]
        var offenders: [String] = []
        for (key, entryAny) in try mainStrings() {
            guard let entry = entryAny as? [String: Any],
                  let value = enPlainValue(entry),
                  buttonLabels.contains(value),
                  !allowed.contains(key) else {
                continue
            }
            offenders.append("\(key) = \"\(value)\"")
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Catalog keys duplicating an OK/Cancel button label instead of using General.OK/General.Cancel:\n"
                        + offenders.sorted().joined(separator: "\n"))
    }

    // MARK: - Finding 2: em dashes and a reversed opening quote

    func testNoEmDashInAnyCatalogValue() throws {
        let emDash = "\u{2014}"
        // These em dashes predate the localization work (they were in the original
        // feature text, verified via git history) and the maintainer keeps them; the
        // lint only guards against em dashes newly introduced by localization.
        let accepted: Set<String> = [
            "ClaudeCode.HookUnreadable",
            "ClaudeCode.HookWriteFailed",
            "GeneralPrefs.DefaultModelManualTitle",
            "Donate.CallToAction4",
            "ImageWell.NoImageSelected",
            "PTYSession.CantSwitchProfileWrongType",
            "MenuTip.Composer",
            "ToolStatus.HelpMarkdown",
            "AdvancedSetting.bufferDepth",
        ]
        var offenders: [String] = []
        for (key, entryAny) in try mainStrings() where !accepted.contains(key) {
            guard let entry = entryAny as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any] else {
                continue
            }
            for (loc, locEntryAny) in locs {
                guard let locEntry = locEntryAny as? [String: Any] else { continue }
                for value in allValues(locEntry) where value.contains(emDash) {
                    offenders.append("[\(loc)] \(key)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Catalog values containing an em dash (U+2014):\n"
                        + offenders.sorted().joined(separator: "\n"))
    }

    // The English source opens the quoted script name with a CLOSING double quote
    // (U+201D) on both sides, e.g. U+201D%1$@U+201D, where it should open with
    // U+201C and close with U+201D.
    func testSignatureVerifiedBodyUsesOpeningQuote() throws {
        guard let entry = try mainStrings()["ScriptImporter.SignatureVerifiedBody"] as? [String: Any],
              let value = enPlainValue(entry) else {
            return XCTFail("ScriptImporter.SignatureVerifiedBody missing from catalog")
        }
        let closingQuote = "\u{201D}"
        // A well formed value opens the first argument with U+201C, so the closing
        // mark must never appear immediately before %1$@.
        let reversedOpen = "\(closingQuote)%1$@"
        XCTAssertFalse(value.contains(reversedOpen),
                       "ScriptImporter.SignatureVerifiedBody opens the quoted name with a closing quote (U+201D): \"\(value)\"")
    }

    // MARK: - Finding 3: live escape sequence baked into a translatable string

    // CommandRunner.OutputTruncated and SemanticHistory.OutputTruncated stored a
    // string like "\n%c[m;[output truncated]\n" in the catalog. The call sites feed
    // %c the value 27 (ESC), so "%c[m" is a live SGR reset control sequence sitting
    // inside translatable text where a translator can reorder or corrupt it.
    func testNoLiveEscapeSequenceInCatalogValues() throws {
        var offenders: [String] = []
        for (key, entryAny) in try mainStrings() {
            guard let entry = entryAny as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any] else {
                continue
            }
            for (loc, locEntryAny) in locs {
                guard let locEntry = locEntryAny as? [String: Any] else { continue }
                for value in allValues(locEntry) where value.contains("%c[") {
                    offenders.append("[\(loc)] \(key)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Catalog values embedding a live escape sequence (\"%c[\" fed ESC):\n"
                        + offenders.sorted().joined(separator: "\n"))
    }

    // MARK: - Finding 4a: pt-BR coverage for code-referenced keys

    // Keys that are referenced from code but ship with no Brazilian Portuguese
    // translation. pt-BR otherwise has full catalog coverage, so each of these is
    // a visible gap where a pt-BR user sees English.
    func testPtBRCoverageForCodeReferencedKeys() throws {
        // Debug/stat labels (Count, Mean, Start, End, %.0fµs, "Count: %lld") were
        // intentionally un-localized (developer-facing) and are no longer in the
        // catalog, so they are excluded here.
        let expectedPtBR: [String] = [
            "BrowserToolbar.ResetPermission",
            "BuiltInFunction.MissingSessionID",
            "BuiltInFunction.NoSuchSession",
            "ChatFindBarView.ModeIgnoreCase",
            "ChatFindBarView.ModeMatchCase",
            "ChatFindBarView.ModeRegularExpression",
            "ChatViewController.NeedsLiveSessionBrowser",
            "ChatViewController.NeedsLiveSessionTerminal",
            "ChatViewController.NoLinkedSessionUserNoticeBrowser",
            "ChatViewController.NoLinkedSessionUserNoticeTerminal",
            "ChatViewController.NotLinkedNoticeBrowser",
            "ChatViewController.NotLinkedNoticeTerminal",
            "CorruptApplication.LoadSettingError",
            "CorruptApplication.SignatureMismatch",
            "CorruptApplication.SignatureUnverifiable",
            "CorruptApplication.SignatureValidUnexpected",
            "CorruptApplication.Title",
            "MenuItemPopup.DefaultTitle",
            "PTYAnnotation.NamedMark",
            "SmartSelection.PrecisionHighPhrase",
            "SmartSelection.PrecisionLowPhrase",
            "SmartSelection.PrecisionNormalPhrase",
            "SmartSelection.PrecisionUndefinedPhrase",
            "SmartSelection.PrecisionVeryHighPhrase",
            "SmartSelection.PrecisionVeryLowPhrase",
            "Trigger.AfterFractionalSeconds",
            "Workgroup.SessionTree.MainSession",
            "Workgroup.SessionTree.Peer",
            "Workgroup.SessionTree.SplitHorizontal",
            "Workgroup.SessionTree.SplitVertical",
            "Workgroup.SessionTree.Tab",
        ]
        let strings = try mainStrings()
        var missing: [String] = []
        for key in expectedPtBR {
            guard let entry = strings[key] as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any],
                  locs["pt-BR"] != nil else {
                missing.append(key)
                continue
            }
        }
        XCTAssertTrue(missing.isEmpty,
                      "Code-referenced keys with no pt-BR translation:\n"
                        + missing.sorted().joined(separator: "\n"))
    }

    // MARK: - Finding 4b: the import-status catalog is unlocalized

    // iTerm2ImportStatus/mul.lproj/ImportingWindowController.xcstrings has three
    // XIB-derived title keys and only ships English (state "new"), so it has no
    // pt-BR (nor any other) translation.
    func testImportingWindowControllerHasPtBR() throws {
        let json = try loadCatalog("iTerm2ImportStatus/mul.lproj/ImportingWindowController.xcstrings")
        let strings = json["strings"] as! [String: Any]
        var missing: [String] = []
        for (key, entryAny) in strings {
            guard let entry = entryAny as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any],
                  locs["pt-BR"] != nil else {
                missing.append(key)
                continue
            }
        }
        XCTAssertTrue(missing.isEmpty,
                      "ImportingWindowController.xcstrings keys with no pt-BR translation:\n"
                        + missing.sorted().joined(separator: "\n"))
    }

    // Finding 5a (pt-BR plurals missing the CLDR "many" category) was validated as a
    // catalog-completeness lint, not a correctness bug: for the integer counts these
    // strings format, "many" is only selected for exact multiples of 1,000,000 and the
    // runtime falls back to "other" (grammatically correct). Per the maintainer it is
    // not enforced, so no test guards it.

    // MARK: - Finding 6: SmartSelection note localization key drift guard
    //
    // sources/Settings/SmartSelectionController.m localizes the DISPLAY of built-in
    // smart-selection rule notes (the table cell and playground result) via
    // iTermLocalizedSmartSelectionNote(). It no longer keeps a hand-maintained
    // English -> localized dictionary; instead each built-in rule in
    // SmartSelectionRules.plist carries a stable "notesLocalizationKey", and the
    // function derives an English-note -> key map from the plist at load and
    // localizes off the key. On a miss (a user-authored note not in the plist) it
    // falls back to the raw stored value.
    //
    // The remaining drift risk is a plist rule that lacks a notesLocalizationKey, or
    // whose key is missing from the String Catalog: either way the built-in note
    // shows English in every non-English UI with no compile-time or runtime error.
    // This test reads the plist and the catalog and pins that every built-in rule
    // has a notesLocalizationKey and that the catalog carries that key. Adding or
    // renaming a rule without wiring up its key fails this test.

    private func smartSelectionPlistRules() throws -> [[String: Any]] {
        let url = repoRoot().appendingPathComponent("plists/SmartSelectionRules.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        return plist["Rules"] as! [[String: Any]]
    }

    func testSmartSelectionNoteKeysCoverEveryPlistRule() throws {
        let rules = try smartSelectionPlistRules()
        XCTAssertFalse(rules.isEmpty, "SmartSelectionRules.plist yielded no rules")

        let catalog = try mainStrings()

        var missingKey: [String] = []
        var missingCatalogEntry: [String] = []
        for rule in rules {
            let note = (rule["notes"] as? String) ?? "(no notes)"
            guard let localizationKey = rule["notesLocalizationKey"] as? String,
                  !localizationKey.isEmpty else {
                missingKey.append(note)
                continue
            }
            if catalog[localizationKey] == nil {
                missingCatalogEntry.append("\(localizationKey) (note \"\(note)\")")
            }
        }

        XCTAssertTrue(missingKey.isEmpty,
                      "SmartSelectionRules.plist rules missing a notesLocalizationKey (they will display in English in every non-English UI). Add a notesLocalizationKey to each rule:\n"
                        + missingKey.sorted().joined(separator: "\n"))
        XCTAssertTrue(missingCatalogEntry.isEmpty,
                      "SmartSelection notesLocalizationKey values with no entry in Localizable.xcstrings (they will display in English in every non-English UI). Add the catalog entries:\n"
                        + missingCatalogEntry.sorted().joined(separator: "\n"))
    }
}
