//
//  TextViewPortholeRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/22.
//

import Foundation
import Highlightr

fileprivate extension String {
    var minified: String {
        return replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    }
}

fileprivate extension TextViewPorthole.VisualAttributes {
    private func fgColorHex(_ key: iTermColorMapKey) -> String {
        return (colorMap.color(forKey: key) ?? textColor).srgbHexString()
    }

    var themeString: String {
        let filename: String
        let dark = backgroundColor.isDark
        if dark {
            filename = iTermAdvancedSettingsModel.nativeRenderingCSSDark()
        } else {
            filename = iTermAdvancedSettingsModel.nativeRenderingCSSLight()
        }
        let template: String
        if !filename.isEmpty, let string = try? String(contentsOf: URL(fileURLWithPath: filename)) {
            template = string
        } else if let url = Bundle(for: TextViewPorthole.self).url(forResource: "TextViewPortholeRenderer-\(dark ? "dark" : "light")",
                                                                   withExtension: "css"),
                  let content = try? String(contentsOf: url) {
            template = content
        } else {
            return dark ? "paraiso-dark" : "paraiso-light"
        }

        let subs = [
            "${bg}": backgroundColor.srgbHexString(),
            "${fg}": textColor.srgbHexString(),
            "${black}": fgColorHex(kColorMapAnsiBlack),
            "${red}": fgColorHex(kColorMapAnsiRed),
            "${green}": fgColorHex(kColorMapAnsiGreen),
            "${yellow}": fgColorHex(kColorMapAnsiYellow),
            "${blue}": fgColorHex(kColorMapAnsiBlue),
            "${magenta}": fgColorHex(kColorMapAnsiMagenta),
            "${cyan}": fgColorHex(kColorMapAnsiCyan),
            "${white}": fgColorHex(kColorMapAnsiWhite),
            "${brightBlack}": fgColorHex(kColorMapAnsiBlack + kColorMapAnsiBrightModifier),
            "${brightRed}": fgColorHex(kColorMapAnsiRed + kColorMapAnsiBrightModifier),
            "${brightGreen}": fgColorHex(kColorMapAnsiGreen + kColorMapAnsiBrightModifier),
            "${brightYellow}": fgColorHex(kColorMapAnsiYellow + kColorMapAnsiBrightModifier),
            "${brightBlue}": fgColorHex(kColorMapAnsiBlue + kColorMapAnsiBrightModifier),
            "${brightMagenta}": fgColorHex(kColorMapAnsiMagenta + kColorMapAnsiBrightModifier),
            "${brightCyan}": fgColorHex(kColorMapAnsiCyan + kColorMapAnsiBrightModifier),
            "${brightWhite}": fgColorHex(kColorMapAnsiWhite + kColorMapAnsiBrightModifier),
            "${fontFamily}": font.familyName ?? NSFont.userFixedPitchFont(ofSize: 12)!.familyName!,
        ]

        let css = (template as NSString).performingSubstitutions(subs)!
        return css.minified
    }
}

class TextViewPortholeRenderer {
    enum Specializations: String {
        case markdown = "markdown"
        case json = "json"
    }
    static let identifier = "TextViewPortholeRenderer"
    let text: String
    let _languages: Set<String>
    private var markdownRenderer: MarkdownPortholeRenderer?
    private var jsonRenderer: JSONPortholeRenderer?
    // display names
    var languages: Set<String> {
        guard let db = FileExtensionDB.instance else {
            return _languages
        }
        return Set(_languages.compactMap { db.shortNameToLanguage[$0] })
    }
    var languageCandidateShortNames: [String] {
        return Array(_languages)
    }
    var language: String?

    static var allLanguages: Set<String> {
        return FileExtensionDB.instance?.languages ?? Set()
    }

    func renderIfSpecialized(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString? {
        guard let language = language else {
            return nil
        }

        switch Specializations(rawValue: language) {
        case .markdown:
            if markdownRenderer == nil {
                markdownRenderer = MarkdownPortholeRenderer(text)
            }
            return markdownRenderer!.render(visualAttributes: visualAttributes)
        case .json:
            if jsonRenderer == nil {
                jsonRenderer = JSONPortholeRenderer(text)
            }
            return jsonRenderer!.render(visualAttributes: visualAttributes)
        case .none:
            return nil
        }
    }

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        if let result = renderIfSpecialized(visualAttributes: visualAttributes) {
            return result
        }

        let highlightr = Highlightr()!
        highlightr.theme = Theme(themeString: visualAttributes.themeString)
        highlightr.theme.setCodeFont(visualAttributes.font)
        if let language = language {
            return highlightr.highlight(text, as: language, fastRender: true) ?? NSAttributedString()
        }
        let subset: [String]?
        if _languages.isEmpty {
            subset = Array(FileExtensionDB.instance?.languages ?? ["plaintext"])
        } else {
            subset = Array(_languages)
        }
        if let result = highlightr.highlightAuto(text, languageSubset: subset) {
            let resultLanguage: String
            if result.language == "undefined" {
                resultLanguage = "plaintext"
            } else {
                resultLanguage = result.language
            }
            if let db = FileExtensionDB.instance {
                if db.languages.contains(resultLanguage) {
                    language = FileExtensionDB.instance?.languageToShortName[resultLanguage]
                } else {
                    language = resultLanguage
                }
                if let spec = renderIfSpecialized(visualAttributes: visualAttributes) {
                    return spec
                }
            }
            return result.attributedString
        }
        return highlightr.highlight(text, as: nil, fastRender: true) ?? NSAttributedString()
    }

    init(_ text: String, type: String?, filename: String?) {
        self.text = text
        if let language = language,
           let db = FileExtensionDB.instance,
           let short = db.shortNameToLanguage[language] {
            self.language = short
            _languages = Set([short])
            return
        }
        if let type = type,
           let languages = FileExtensionDB.instance?.languagesForTypeHint(type) {
            self._languages = languages
            if languages.count == 1 {
                language = languages.first!
            }
            return
        }
        if let filename = filename,
           let languages = FileExtensionDB.instance?.languagesForPath(filename) {
            self._languages = languages
        } else {
            self._languages = Set()
        }
        if MarkdownPortholeRenderer.wants(text) {
            language = "markdown"
        } else if JSONPortholeRenderer.wants(text) {
            language = "json"
        } else {
            self.language = nil
        }
    }

    init(_ text: String, language: String?, languages: [String]?) {
        self.text = text
        self.language = language
        _languages = languages.map { Set($0) } ?? Set()
    }
}

