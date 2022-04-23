//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import AppKit
import Foundation
import SwiftyMarkdown

class MarkdownPorthole: BaseTextViewPorthole {
    private static func attributedString(markdown: String, colors: SavedColors) -> NSAttributedString {
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

    override init(_ config: PortholeConfig,
                  uuid: String? = nil) {
        super.init(config,
                   uuid: uuid)
        let attributedString = Self.attributedString(markdown: config.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     colors: savedColors)
        textStorage.setAttributedString(attributedString)
    }

    private static let markdownDictionaryKey = "markdown"

    static func from(_ dictionary: [String: AnyObject],
                     colorMap: iTermColorMap) -> MarkdownPorthole? {
        guard let uuid = dictionary[Self.uuidDictionaryKey] as? String,
              let markdown = dictionary[Self.markdownDictionaryKey] as? String else {
            return nil
        }
        return MarkdownPorthole(PortholeConfig(text: markdown,
                                               colorMap: colorMap,
                                               baseDirectory: dictionary[Self.baseDirectoryKey] as? URL),
                                uuid: uuid)
    }

    override var dictionaryValue: [String: AnyObject] {
        var result = super.dictionaryValue
        result[Self.markdownDictionaryKey] = config.text as NSString
        return result
    }

    override func updateColors() {
        super.updateColors()
        textView.textStorage?.setAttributedString(Self.attributedString(markdown: config.text,
                                                                        colors: savedColors))
    }
}


