//
//  iTermLocaleGuesser.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/22.
//

import Foundation

struct SimpleCache<KeyType: Hashable, ValueType> {
    private var dict = [KeyType: ValueType]()

    mutating func getOrSet(key: KeyType, setter: () -> ValueType) -> ValueType {
        if let value = dict[key] {
            return value
        }
        let value = setter()
        dict[key] = value
        return value
    }
}

@objc
class iTermLocaleGuesser: NSObject {
    struct Config {
        private static var lowerCaseEncodings: [String: Bool] = {
            guard let plistFile = Bundle(for: iTermLocaleGuesser.self).path(forResource: "EncodingsWithLowerCase", ofType: "plist") else {
                return [:]
            }
            return NSDictionary(contentsOfFile: plistFile) as? [String: Bool] ?? [:]
        }()

        var fallbackLCCType: String?
        var doNotSetCtype: Bool
        var lowerCaseEncodings: Set<String> = Set(Config.lowerCaseEncodings.keys)
    }

    private let preferredLanguages: [String]
    private let currentLocaleIdentifier: String
    private let countryCode: String?
    private let encoding: String.Encoding
    private let config: Config

    private static var titleCache = SimpleCache<String, String>()

    @objc(titleForLocale:)
    static func title(for locale: String?) -> String? {
        guard let locale else {
            return nil
        }
        return titleCache.getOrSet(key: locale) {
            LocaleComponents(locale).title
        }
    }

    @objc(initWithEncoding:)
    convenience init(encoding: UInt) {
        let locale = NSLocale.current
        self.init(preferredLanguages: NSLocale.preferredLanguages,
                  currentLocaleIdentifier: locale.identifier,
                  countryCode: (locale as NSLocale).object(forKey: NSLocale.Key.countryCode) as? String,
                  encoding: String.Encoding(rawValue: encoding),
                  config: Config(fallbackLCCType: iTermAdvancedSettingsModel.fallbackLCCType(),
                                 doNotSetCtype: iTermAdvancedSettingsModel.doNotSetCtype()))
    }

    init(preferredLanguages: [String],
         currentLocaleIdentifier: String,
         countryCode: String?,
         encoding: String.Encoding,
         config: Config) {
        self.preferredLanguages = preferredLanguages
        self.currentLocaleIdentifier = currentLocaleIdentifier
        self.countryCode = countryCode
        self.encoding = encoding
        self.config = config
    }

    @objc
    func dictionaryWithLANG() -> [String: String]? {
        if let lang = valueForLanguageEnvironmentVariable() {
            DLog("Have value for LANG")
            return ["LANG": lang]
        }
        return nil
    }

    @objc
    func dictionaryWithLC_CTYPE() ->  [String: String]? {
        if let fallback = config.fallbackLCCType, !fallback.isEmpty {
            DLog("Have fallback LC_CTYPE")
            return ["LC_CTYPE": fallback]
        }

        // Try just the encoding by itself, which might work.
        let encName = encodingName()
        DLog("encName=\(encName ?? "(nil)")")

        if let encName, localeIsSupported(encName) {
            DLog("Using encoding name")
            return ["LC_CTYPE": encName]
        }

        return nil
    }

    private func dictionary() -> [String: String]? {
        if let result = dictionaryWithLANG() {
            return result
        }
        guard shouldSetCTYPE else {
            DLog("Not setting CTYPE")
            return nil
        }
        if let result = dictionaryWithLC_CTYPE() {
            return result
        }

        DLog("Failed to find anything")
        return nil
    }

    private var shouldSetCTYPE: Bool {
        !config.doNotSetCtype
    }

    @objc
    func valueForLanguageEnvironmentVariable() -> String? {
        return self.candidates().first { candidate in
            DLog("Check if \(candidate) is supported")
            return localeIsSupported(candidate)
        }
    }

    private func languageCodesUpToAndIncludingFirstTwoLetterCode(_ allCodes: [String]) -> [String] {
        if let lastIndexToInclude = allCodes.firstIndex(where: { candidate in
            candidate.utf8.count <= 2
        }) {
            return Array(allCodes[0..<lastIndexToInclude + 1])
        }
        return allCodes
    }

    private var preferredLanguageCodesByRemovingCountry: [String] {
        return preferredLanguages.map { language in
            DLog("Found preferred language: \(language)")
            if let hyphenRange = language.range(of: "-") {
                return String(language[language.startIndex..<hyphenRange.lowerBound])
            }
            return language
        }
    }

    private func locale(forLanguage languageCode: String?, country countryCode: String?) -> String {
        DLog("locale(forLanguage: \(languageCode ?? "(nil)"), country: \(countryCode ?? "(nil)"))")
        if let languageCode, let countryCode {
            return "\(languageCode)_\(countryCode)"
        }
        if let languageCode {
            return languageCode
        }
        return currentLocaleIdentifier
    }

    private func properlyCapitalizedIANAEncoding(for cfEncoding: CFStringEncoding) -> String? {
        precondition(!config.lowerCaseEncodings.isEmpty)

        guard let cf = CFStringConvertEncodingToIANACharSetName(cfEncoding) else {
            return nil
        }
        let ianaEncoding = String(cf)
        DLog("iana encoding is \(ianaEncoding)")

        guard ianaEncoding.rangeOfCharacter(from: CharacterSet.lowercaseLetters) != nil else {
            DLog("\(ianaEncoding) contains no lower case")
            return ianaEncoding
        }
        DLog("Checking if \(ianaEncoding) is allowed to have lower case")
        if !config.lowerCaseEncodings.contains(ianaEncoding) {
            // Some encodings are improperly returned as lower case. For instance,
            // "utf-8" instead of "UTF-8". If this isn't in the allowed list of
            // lower-case encodings, then uppercase it.
            let result = ianaEncoding.uppercased()
            DLog("Convert \(ianaEncoding) to upper case: \(result)")
            return result
        }

        DLog("Lower case allowed")
        return ianaEncoding
    }

    private func correctingPrefixes(_ ianaEncoding: String) -> String {
        return ianaEncoding.replacingOccurrences(of: "ISO-",
                                                 with: "ISO").replacingOccurrences(of: "EUC-",
                                                                                   with: "euc")
    }

    private func encodingName() -> String? {
        // Get the encoding, perhaps as a fully written out name.
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)

        // Convert it to the expected (IANA) format.
        guard let ianaEncoding = self.properlyCapitalizedIANAEncoding(for: cfEncoding) else {
            return nil
        }
        return correctingPrefixes(ianaEncoding)
    }

    // "en-US" -> "en_US"
    private func languageToLocale(_ code: String) -> String {
        return code.replacingOccurrences(of: "-", with: "_")
    }

    private func languagePlusCountryCodes(languageCodes: [String]) ->  [String] {
        guard let countryCode = self.countryCode else {
            return []
        }
        return languageCodes.map { language in
            self.locale(forLanguage: language, country: countryCode)
        }
    }

    private func localesByAppendingEncoding(_ strings: [String], encoding: String?) -> [String] {
        guard let encoding else {
            return []
        }
        return strings.map { $0 + "." + encoding }
    }

    private var sortedPreferredLanguages: [String] {
        return preferredLanguages.sorted { lhs, rhs in
            let lhsHasHyphen = lhs.contains("-")
            let rhsHasHyphen = rhs.contains("-")
            if lhsHasHyphen == rhsHasHyphen {
                return false
            }
            return lhsHasHyphen
        }
    }

    private func localeBasedCandidates(languages: [String], encoding: String?) -> [String] {
        guard let encoding else {
            return []
        }
        let locales = languages.map {
            return languageToLocale($0)
        }
        return localesByAppendingEncoding(locales, encoding: encoding)
    }

    private func candidates() -> [String] {
        DLog("Looking for a locale...");
        DLog("Preferred languages are: \(preferredLanguages)")
        let languageCodes = languageCodesUpToAndIncludingFirstTwoLetterCode(preferredLanguageCodesByRemovingCountry)
        DLog("Language codes are: \(languageCodes)");

        let languagePlusCountryCodes = self.languagePlusCountryCodes(languageCodes: languageCodes)
        DLog("Country code is \(countryCode ?? "(nil)"). Combos are \(languagePlusCountryCodes)")

        let encoding = encodingName()
        DLog("Encoding is \(encoding ?? "(nil)")")

        let languageCountryEncoding = localesByAppendingEncoding(languagePlusCountryCodes, encoding: encoding)
        DLog("Encoding is \(String(describing: encoding)). Combos are \(languageCountryEncoding)")

        // Sort non-hyphenated codes last so en_US always precedes en.
        let preferredLanguages = self.sortedPreferredLanguages
        DLog("Preferred languages are: \(preferredLanguages)")

        // Add locale-based candidates with encoding suffix
        let localeBasedCandidates = localeBasedCandidates(languages: preferredLanguages, encoding: encoding)
        DLog("Locale-based candidates: \(localeBasedCandidates)")

        let candidates = languageCountryEncoding + languagePlusCountryCodes + languageCodes + localeBasedCandidates

        DLog("Candidates are: \(candidates)")
        return candidates
    }

    private func localeIsSupported(_ locale: String) -> Bool {
        // Keep a copy of the current locale setting for this process
        let backupLocale = setlocale(LC_CTYPE, nil)

        // Try to set it to the proposed locale
        let supported = setlocale(LC_CTYPE, locale.cString(using: .utf8)) != nil
        DLog("localeIsSupported(\(locale))=\(supported)")
        // Restore locale and return
        setlocale(LC_CTYPE, backupLocale)

        return supported
    }
}
