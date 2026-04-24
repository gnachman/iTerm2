//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import AppKit
import Foundation
import SwiftyMarkdown

class MarkdownPortholeRenderer {
    private let markdown: String

    static func wants(_ text: String) -> Bool {
        return text.range(of: "^# .", options: .regularExpression) != nil
    }

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
        md.code.fontName = visualAttributes.font.fontName

        let points = visualAttributes.font.pointSize
        md.setFontSizeForAllStyles(with: points)
        // I couldn't find a definitive source to map headings to ems. I used this, which looks fine.
        // https://stackoverflow.com/questions/5410066/what-are-the-default-font-sizes-in-pixels-for-the-html-heading-tags-h1-h2
        md.h1.fontSize = max(4, round(points * 2))
        md.h2.fontSize = max(4, round(points * 1.5))
        md.h3.fontSize = max(4, round(points * 1.3))
        md.h4.fontSize = max(4, round(points * 1.0))
        md.h5.fontSize = max(4, round(points * 0.8))
        md.h6.fontSize = max(4, round(points * 0.7))

        md.setFontColorForAllStyles(with: textColor)

        return md.attributedString()
    }

    init(_ text: String) {
        markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


