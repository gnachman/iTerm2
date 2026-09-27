//
//  LocalizationFormatSpecifierParityTests.swift
//  ModernTests
//
//  Guards against a translation silently dropping (or adding) a printf-style
//  argument relative to the English source. This caught the zh-Hans value for
//  ShellIntegrationInstaller.Discovered, which dropped the %@ for the detected
//  shell name so Chinese users never saw which shell was found.
//
//  It reads the source catalog (sources/Localizable.xcstrings) directly, because
//  the source language (en) is stored inline there rather than compiled to an
//  en.lproj/Localizable.strings. Only plain single-value entries are compared;
//  plural and substitution entries carry their own per-category structure and are
//  out of scope for this lint.
//

import XCTest

final class LocalizationFormatSpecifierParityTests: XCTestCase {
    // Number of distinct printf arguments a format string references. Positional
    // specifiers (%1$@) are counted by distinct index; %% (a literal percent) is
    // not an argument.
    private func argumentCount(_ s: String) -> Int {
        let pattern = "%(?:([0-9]+)\\$)?(?:hh|ll|h|l|q|L|z|t|j)?([@%diouxXfeEgGscpaA])"
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = s as NSString
        var positional = Set<Int>()
        var nonPositional = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let conv = ns.substring(with: m.range(at: 2))
            if conv == "%" {
                continue  // literal %%
            }
            let idxRange = m.range(at: 1)
            if idxRange.location != NSNotFound, let n = Int(ns.substring(with: idxRange)) {
                positional.insert(n)
            } else {
                nonPositional += 1
            }
        }
        return positional.isEmpty ? nonPositional : positional.count
    }

    private func catalogURL() -> URL {
        // .../ModernTests/<thisFile>.swift -> repo root is two directories up.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ModernTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("sources/Localizable.xcstrings")
    }

    // The plain string value of a localization, or nil if it uses plural variations
    // or substitutions (out of scope for this simple parity check).
    private func plainValue(_ localization: [String: Any]) -> String? {
        if localization["substitutions"] != nil || localization["variations"] != nil {
            return nil
        }
        guard let unit = localization["stringUnit"] as? [String: Any] else { return nil }
        return unit["value"] as? String
    }

    func testTranslationsPreserveFormatArgumentCount() throws {
        let data = try Data(contentsOf: catalogURL())
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]

        var mismatches: [String] = []
        for (key, entryAny) in strings {
            guard let entry = entryAny as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any],
                  let en = locs["en"] as? [String: Any],
                  let enValue = plainValue(en) else {
                continue
            }
            let enCount = argumentCount(enValue)
            for (loc, locEntryAny) in locs where loc != "en" {
                guard let locEntry = locEntryAny as? [String: Any],
                      let value = plainValue(locEntry) else {
                    continue
                }
                let count = argumentCount(value)
                if count != enCount {
                    mismatches.append("[\(loc)] \(key): en has \(enCount) arg(s) \"\(enValue)\", translation has \(count) \"\(value)\"")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "Format-argument drift between English and a translation:\n" + mismatches.joined(separator: "\n"))
    }
}
