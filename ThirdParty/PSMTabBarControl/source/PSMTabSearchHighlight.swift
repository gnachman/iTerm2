//
//  PSMTabSearchHighlight.swift
//  iTerm2SharedARC
//
//  During a tab bar search, matches in tab text are drawn as black text on
//  yellow. Styles apply this to whatever text they draw for a tab: titles,
//  subtitles and rich content lines.
//

import AppKit

@objc(PSMTabSearchHighlight)
final class PSMTabSearchHighlight: NSObject {
    @objc static let backgroundColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 1)
    @objc static let textColor = NSColor.black

    /// The string with every match of the query highlighted, ignoring case and
    /// accents as the search does. The same object when there is nothing to
    /// highlight.
    @objc(highlightingAttributedString:query:)
    static func highlighting(_ string: NSAttributedString, query: String?) -> NSAttributedString {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return string
        }
        let text = string.string as NSString
        var result: NSMutableAttributedString?
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if found.location == NSNotFound || found.length == 0 {
                break
            }
            if result == nil {
                result = NSMutableAttributedString(attributedString: string)
            }
            result?.addAttributes([.backgroundColor: backgroundColor,
                                   .foregroundColor: textColor],
                                  range: found)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return result ?? string
    }
}
