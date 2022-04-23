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

    func render(colors: TextViewPorthole.SavedColors) -> NSAttributedString {
        return Self.attributedString(markdown: markdown, colors: colors)
    }

    private static func attributedString(markdown: String, colors: TextViewPorthole.SavedColors) -> NSAttributedString {
        let md = SwiftyMarkdown(string: markdown)
        if let fixedPitchFontName = NSFont.userFixedPitchFont(ofSize: 12)?.fontName {
            md.code.fontName = fixedPitchFontName
        }
        let textColor = colors.textColor
        md.h1.color = textColor
        md.h2.color = textColor
        md.h3.color = textColor
        md.h4.color = textColor
        md.h5.color = textColor
        md.h6.color = textColor
        md.body.color = textColor
        md.blockquotes.color = textColor
        md.link.color = textColor
        md.bold.color = textColor
        md.italic.color = textColor
        md.code.color = textColor
        return md.attributedString()
    }

    init(_ text: String) {
        markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


