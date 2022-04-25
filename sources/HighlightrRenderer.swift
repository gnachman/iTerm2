//
//  HighlightrRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/22.
//

import Foundation
import Highlightr

class HighlightrRenderer: TextViewPortholeRenderer {
    let identifier = "Highlightr"
    static let identifier = "Highlightr"
    let text: String
    let languages: Set<String>
    var language: String?

    static var allLanguages: Set<String> {
        return FileExtensionDB.instance?.languages ?? Set()
    }

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        let highlightr = Highlightr()!
        highlightr.setTheme(to: visualAttributes.backgroundColor.isDark ? "paraiso-dark" : "paraiso-light")
        if let language = language {
            return highlightr.highlight(text, as: language, fastRender: true) ?? NSAttributedString()
        }
        let subset: [String]?
        if languages.isEmpty {
            subset = Array(FileExtensionDB.instance?.languages ?? ["plaintext"])
        } else {
            subset = Array(languages)
        }
        if let result = highlightr.highlightAuto(text, languageSubset: subset) {
            if let db = FileExtensionDB.instance {
                if db.languages.contains(result.language) {
                    language = result.language
                } else {
                    language = FileExtensionDB.instance?.languageForShortName(result.language)
                }
            }
            return result.attributedString
        }
        return highlightr.highlight(text, as: nil, fastRender: true) ?? NSAttributedString()
    }

    init(_ text: String, mimeType: String?, filename: String?, language: String?) {
        self.text = text
        if let language = language,
           let knownLanguages = FileExtensionDB.instance?.languages,
           knownLanguages.contains(language) {
            self.language = language
            languages = Set([language])
            return
        }
        if let mimeType = mimeType,
           let language = FileExtensionDB.instance?.languageForMimeType(mimeType) {
            self.language = language
            languages = Set([language])
            return
        }
        if let filename = filename,
           let languages = FileExtensionDB.instance?.languagesForPath(filename) {
            self.languages = languages
        } else {
            self.languages = Set()
        }
        self.language = nil
    }
}

