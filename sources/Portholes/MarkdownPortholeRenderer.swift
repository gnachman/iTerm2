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

    func render(visualAttributes: TextViewPorthole.VisualAttributes,
                imageLoader: MarkdownImageLoader?) -> NSAttributedString {
        return Self.attributedString(markdown: markdown,
                                     font: visualAttributes.font,
                                     textColor: visualAttributes.textColor,
                                     backgroundColor: visualAttributes.backgroundColor,
                                     imageLoader: imageLoader)
    }

    static func attributedString(markdown: String,
                                 font: NSFont,
                                 textColor: NSColor,
                                 backgroundColor: NSColor,
                                 imageLoader: MarkdownImageLoader?) -> NSAttributedString {
        let preprocessed = MarkdownPreprocessor.process(markdown)
        let md = SwiftyMarkdown(string: preprocessed.text)
        md.code.fontName = font.fontName
        md.bullet = "•"

        let points = font.pointSize
        md.setFontSizeForAllStyles(with: points)
        for (level, style) in [md.h1, md.h2, md.h3, md.h4, md.h5, md.h6].enumerated() {
            style.fontSize = max(4, round(points * MarkdownPortholeStyler.headingScale(level + 1)))
            style.fontStyle = .bold
        }

        md.setFontColorForAllStyles(with: textColor)
        md.tableStyle.borderColor = textColor.withAlphaComponent(0.3)
        md.tableStyle.cellPadding = round(points * 0.4)
        md.tableHeader.color = textColor
        md.tableCell.color = textColor

        let styler = MarkdownPortholeStyler(points: points,
                                            bodyFont: NSFont.systemFont(ofSize: points),
                                            codeFont: font,
                                            textColor: textColor,
                                            backgroundColor: backgroundColor,
                                            images: preprocessed.images,
                                            imageLoader: imageLoader)
        return styler.style(md.attributedString())
    }

    init(_ text: String) {
        markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
