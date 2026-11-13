//
//  UILanguageCase.swift
//  iTerm2SharedARC
//
//  Changes the case of translated text using the rules of the UI language. Plain uppercasing uses
//  language-neutral rules, which turn Turkish “i” into “I” instead of “İ”. The language is the
//  actual UI localization, not the region, so a Turkish UI on an English-region Mac still gets
//  Turkish rules.
//

import Foundation

@objc(iTermUILanguageCase)
final class UILanguageCase: NSObject {
    // The UI language is fixed for the life of the process.
    @objc static let uiLocale = locale(forLocalization: Bundle.main.preferredLocalizations.first)

    static func locale(forLocalization localization: String?) -> Locale {
        guard let localization, localization != "Base" else {
            return Locale(identifier: "en")
        }
        return Locale(identifier: localization)
    }

    @objc(uppercase:locale:)
    static func uppercase(_ string: String, locale: Locale) -> String {
        return string.uppercased(with: locale)
    }

    @objc(capitalizingFirstLetter:locale:)
    static func capitalizingFirstLetter(_ string: String, locale: Locale) -> String {
        guard let first = string.first else {
            return string
        }
        return String(first).uppercased(with: locale) + string.dropFirst()
    }
}
