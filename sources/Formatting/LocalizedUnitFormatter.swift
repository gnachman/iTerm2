//
//  LocalizedUnitFormatter.swift
//  iTerm2SharedARC
//
//  Formats byte counts and durations with units in the UI language.
//

import Foundation

// English keeps iTerm2’s hand-written unit strings (“7 bytes”, “10 ms”). Any other UI language
// defers to MeasurementFormatter so the units are translated (“10 мс”, “7 Byte”). The language is
// the actual UI localization, not the region, matching NSDateFormatter’s relative-time strings.
@objc(iTermLocalizedUnitFormatter)
final class LocalizedUnitFormatter: NSObject {
    // nil when the UI is English. The UI language is fixed for the life of the process.
    @objc static let nonEnglishUILanguage: String? = nonEnglishLanguage(Bundle.main.preferredLocalizations.first)

    static func nonEnglishLanguage(_ language: String?) -> String? {
        let language = language ?? "en"
        if language == "Base" || language == "en" || language.hasPrefix("en-") || language.hasPrefix("en_") {
            return nil
        }
        return language
    }

    // Formats `value` in `unit` (no conversion) for `language`.
    @objc(stringForValue:unit:minimumFractionDigits:maximumFractionDigits:language:)
    static func string(value: Double,
                       unit: Unit,
                       minimumFractionDigits: Int,
                       maximumFractionDigits: Int,
                       language: String) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.minimumFractionDigits = minimumFractionDigits
        formatter.numberFormatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: Measurement(value: value, unit: unit))
    }

    // Byte, kilobyte, megabyte, … for exponent 0, 1, 2, …
    @objc(informationStorageUnitForExponent:)
    static func informationStorageUnit(exponent: Int) -> UnitInformationStorage {
        let units: [UnitInformationStorage] = [.bytes, .kilobytes, .megabytes, .gigabytes, .terabytes,
                                               .petabytes, .exabytes, .zettabytes, .yottabytes]
        return units[max(0, min(exponent, units.count - 1))]
    }

    // A chunk size in the Advanced Paste panel. Powers of 1024, labeled kB, MB, ….
    @objc(chunkSizeDescription:language:)
    static func chunkSizeDescription(_ bytes: Double, language: String?) -> String {
        let multiplier = 1024.0
        let maxExponent = 8
        var value = bytes
        var exponent = 0
        while value >= multiplier && exponent < maxExponent {
            value /= multiplier
            exponent += 1
        }
        if let language {
            return string(value: value,
                          unit: informationStorageUnit(exponent: exponent),
                          minimumFractionDigits: 0,
                          maximumFractionDigits: 2,
                          language: language)
        }
        let prefixes = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
        return "\(decimalString(value)) \(prefixes[exponent])B"
    }

    // A delay between chunks in the Advanced Paste panel. The units come from the string catalog
    // because MeasurementFormatter’s duration units are not reliably translated in-process.
    @objc(durationDescription:language:)
    static func durationDescription(_ duration: TimeInterval, language: String?) -> String {
        let bundle = language.flatMap { localizationBundle(language: $0) } ?? Bundle.main
        let numberLocale = language.map { Locale(identifier: $0) }
        if duration < 0.000001 {
            let number = decimalString(duration / 0.000001, locale: numberLocale)
            return String(localized: "AdvancedPaste.Delay.Microseconds",
                          defaultValue: "\(number) µs",
                          bundle: bundle,
                          comment: "Delay between chunks in Advanced Paste, in microseconds; the placeholder is a number")
        } else if duration < 1 {
            let number = decimalString(duration / 0.001, locale: numberLocale)
            return String(localized: "AdvancedPaste.Delay.Milliseconds",
                          defaultValue: "\(number) ms",
                          bundle: bundle,
                          comment: "Delay between chunks in Advanced Paste, in milliseconds; the placeholder is a number")
        } else if duration < 60 {
            let number = decimalString(duration, locale: numberLocale)
            return String(localized: "AdvancedPaste.Delay.Seconds",
                          defaultValue: "\(number) sec",
                          bundle: bundle,
                          comment: "Delay between chunks in Advanced Paste, in seconds; the placeholder is a number")
        } else {
            let number = decimalString(duration / 60, locale: numberLocale)
            return String(localized: "AdvancedPaste.Delay.Minutes",
                          defaultValue: "\(number) min",
                          bundle: bundle,
                          comment: "Delay between chunks in Advanced Paste, in minutes; the placeholder is a number")
        }
    }

    // The app’s .lproj for `language`, so tests can format for a language other than the UI’s.
    static func localizationBundle(language: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static func decimalString(_ value: Double, locale: Locale? = nil) -> String {
        let formatter = NumberFormatter()
        if let locale {
            formatter.locale = locale
        }
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
