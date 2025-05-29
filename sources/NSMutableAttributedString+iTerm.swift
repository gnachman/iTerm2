//
//  NSMutableAttributedString+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

extension NSMutableAttributedString {
    func makeLinks() {
        let baseAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single,
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.cursor: NSCursor.pointingHand
        ]
        while let info = firstAnchorInfo() {
            if let url = URL(string: info.href) {
                var attributes = baseAttributes
                attributes[.link] = url
                replace(range: info.range,
                        with: info.anchorText,
                        attributes:attributes)
            }
        }
    }

    private func replace(range: Range<Int>, with replacement: String, attributes: [NSAttributedString.Key: Any]) {
        self.replaceAttributes(in: NSRange(range), withAttributes: attributes)
        self.replaceCharacters(in: NSRange(range), with: replacement)
    }

    private struct AnchorInfo {
        var range: Range<Int>
        var href: String
        var anchorText: String
    }

    private func firstAnchorInfo() -> AnchorInfo? {
        let pattern = #"(<a[^>]+href=\"(.*?)\"[^>]*>)(.*?)(</a>)"#
        guard let regex = try? RegexCache.instance.get(pattern) else {
            return nil
        }
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: string.count)) else {
            return nil
        }

        let hrefRange = match.range(at: 2)
        let anchorRange = match.range(at: 3)
        return AnchorInfo(range: Range(match.range)!,
                          href: string.substring(nsrange: hrefRange),
                          anchorText: string.substring(nsrange: anchorRange))
    }
}

