//
//  HighlightrRenderer.swift
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
    private func fgColorHex(_ darkKey: iTermColorMapKey, _ lightKey: iTermColorMapKey) -> String {
        let key = backgroundColor.isDark ? darkKey : lightKey
        return (colorMap.color(forKey: key) ?? textColor).srgbHexString()
    }

    var themeString: String {
        let bg = backgroundColor.srgbHexString()
        let fg = textColor.srgbHexString()
        let dim = fgColorHex(kColorMapAnsiWhite, kColorMapAnsiBlack + kColorMapAnsiBrightModifier)
        let red = fgColorHex(kColorMapAnsiRed + kColorMapAnsiBrightModifier, kColorMapAnsiRed)
        let blue = fgColorHex(kColorMapAnsiBlue + kColorMapAnsiBrightModifier,
                                kColorMapAnsiBlue)
        let yellow = fgColorHex(kColorMapAnsiYellow + kColorMapAnsiBrightModifier,
                                kColorMapAnsiYellow)
        let green = fgColorHex(kColorMapAnsiGreen + kColorMapAnsiBrightModifier,
                               kColorMapAnsiGreen)
        let magenta = fgColorHex(kColorMapAnsiMagenta + kColorMapAnsiBrightModifier,
                                 kColorMapAnsiMagenta)
        let fontFamily = font.familyName ?? NSFont.userFixedPitchFont(ofSize: 12)!.familyName!
        return """
.hljs {
  background: \(bg);
  color: \(fg);
}

.hljs-comment,
.hljs-quote {
  color: \(dim);
}

.hljs-variable,
.hljs-template-variable,
.hljs-tag,
.hljs-name,
.hljs-selector-id,
.hljs-selector-class,
.hljs-regexp,
.hljs-link,
.hljs-meta {
  color: \(red);
}

.hljs-number,
.hljs-built_in,
.hljs-literal,
.hljs-type,
.hljs-params,
.hljs-deletion {
  color: \(blue);
}

.hljs-title,
.hljs-section,
.hljs-attribute {
  color: \(yellow);
}

.hljs-string,
.hljs-symbol,
.hljs-bullet,
.hljs-addition {
  color: \(green);
}

.hljs-keyword,
.hljs-selector-tag {
  color: \(magenta);
}

.hljs-emphasis {
  font-style: italic;
  font-family: \(fontFamily)
}

.hljs-strong {
  font-weight: bold;
  font-family: \(fontFamily)
}
""".minified
    }
}
class HighlightrRenderer: TextViewPortholeRenderer {
    enum Specializations: String {
        case markdown = "markdown"
        case json = "json"
    }
    let identifier = "Highlightr"
    static let identifier = "Highlightr"
    let text: String
    let _languages: Set<String>
    private var markdownRenderer: MarkdownPortholeRenderer?
    private var jsonRenderer: JSONPortholeRenderer?
    var languages: Set<String> {
        guard let db = FileExtensionDB.instance else {
            return _languages
        }
        return Set(_languages.compactMap { db.shortNameToLanguage[$0] })
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
            if let db = FileExtensionDB.instance {
                if db.languages.contains(result.language) {
                    language = FileExtensionDB.instance?.languageToShortName[result.language]
                } else {
                    language = result.language
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
}

