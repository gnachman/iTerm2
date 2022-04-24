//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import AppKit
import Foundation
import SwiftyMarkdown

class MarkdownPortholeRenderer: TextViewPortholeRenderer {
    static let identifier = "Markdown"
    var identifier: String { return Self.identifier }
    private let markdown: String

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return Self.attributedString(markdown: markdown,
                                     visualAttributes: visualAttributes)
    }

    private static func attributedString(markdown: String,
                                         visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        let md = SwiftyMarkdown(string: markdown)
        if let fixedPitchFontName = NSFont.userFixedPitchFont(ofSize: 12)?.fontName {
            md.code.fontName = fixedPitchFontName
        }
        let textColor = visualAttributes.textColor
        md.setFontNameForAllStyles(with: visualAttributes.font.fontName)
        md.setFontSizeForAllStyles(with: visualAttributes.font.pointSize)
        md.setFontColorForAllStyles(with: textColor)

        return md.attributedString()
    }

    init(_ text: String) {
        markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


