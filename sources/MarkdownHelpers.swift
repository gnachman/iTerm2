//
//  MarkdownHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

import SwiftyMarkdown

func sanitizeMarkdown(_ input: String) -> String {
    // Regular expression pattern to match leading spaces followed by ``` and optional lowercase letters till the end of the string
    let pattern = "^ *```[a-z]*$"

    // Create a regular expression object
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return input
    }

    // Check if the input matches the pattern
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    let matches = regex.matches(in: input, options: [], range: range)

    // If there's a match, remove the leading spaces
    if let match = matches.first, match.range.length > 0 {
        let result = input.replacingOccurrences(of: " ", with: "", options: [], range: input.startIndex..<input.index(input.startIndex, offsetBy: match.range.length))
        return result
    }

    // Return the original string if there's no match
    return input
}

private func SwiftyMarkdownForMessage(string unsafeString: String,
                                      linkColor: NSColor?,
                                      textColor: NSColor?) -> SwiftyMarkdown {
    let massagedValue = unsafeString.components(separatedBy: "\n").map { sanitizeMarkdown($0) }.joined(separator: "\n")

    let md = SwiftyMarkdown(string: massagedValue)
    let pointSize = NSFont.systemFontSize
    if let fixedPitchFontName = NSFont.userFixedPitchFont(ofSize: pointSize)?.fontName {
        md.code.fontName = fixedPitchFontName
    }
    md.setFontSizeForAllStyles(with: pointSize)

    md.h1.fontSize = max(4, round(pointSize * 2))
    md.h2.fontSize = max(4, round(pointSize * 1.5))
    md.h3.fontSize = max(4, round(pointSize * 1.3))
    md.h4.fontSize = max(4, round(pointSize * 1.0))
    md.h5.fontSize = max(4, round(pointSize * 0.8))
    md.h6.fontSize = max(4, round(pointSize * 0.7))

    if let textColor {
        md.setFontColorForAllStyles(with: textColor)
    } else {
        md.setFontColorForAllStyles(with: NSColor.textColor)
    }

    if let linkColor {
        md.link.color = linkColor
        md.link.underlineColor = linkColor
    }
    md.underlineLinks = true
    return md
}

func AttributedStringForSystemMessageMarkdown(_ unsafeString: String,
                                              linkColor: NSColor? = nil,
                                              didCopy: (() -> ())?) -> NSAttributedString {
    let md = SwiftyMarkdownForMessage(
        string: unsafeString,
        linkColor: linkColor,
        textColor: .it_dynamicColor(forLightMode: NSColor(fromHexString: "#202020")!,
                                    darkMode: NSColor(fromHexString: "#ffffc0")!))
    return AttributedStringForMessage(md, didCopy: didCopy)
}

func AttributedStringForGPTMarkdown(_ unsafeString: String,
                                    linkColor: NSColor,
                                    textColor: NSColor,
                                    didCopy: (() -> ())?) -> NSAttributedString {
    let md = SwiftyMarkdownForMessage(string: unsafeString,
                                      linkColor: linkColor,
                                      textColor: textColor)
    return AttributedStringForMessage(md, didCopy: didCopy)
}

private func AttributedStringForMessage(_ md: SwiftyMarkdown,
                                        didCopy: (() -> ())?) -> NSAttributedString {
    let attributedString = md.attributedString()
    if #available(macOS 11.0, *) {
        let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!
        let modified = attributedString.mutableCopy() as! NSMutableAttributedString
        var ranges = [NSRange]()
        let utf16String = attributedString.string.utf16
        attributedString.enumerateAttribute(
            NSAttributedString.Key.swiftyMarkdownLineStyle,
            in: NSRange(from: 0, to: attributedString.length)) { value, range, stopPtr in
            guard value as? String == "codeblock" else {
                return
            }
            if let previous = ranges.last {
                let startIndex = utf16String.index(utf16String.startIndex, offsetBy: previous.upperBound)
                let endIndex = utf16String.index(utf16String.startIndex, offsetBy: range.lowerBound)
                let utf16CodeUnits = Array(utf16String[startIndex..<endIndex])
                let substringToCheck = String(utf16CodeUnits: utf16CodeUnits, count: utf16CodeUnits.count)
                if substringToCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // The area between this range and the last contains contains only whitespace characters
                    ranges.removeLast()
                    ranges.append(NSRange(location: previous.location,
                                          length: range.upperBound - previous.location))
                    return
                }
            }
            ranges.append(range)
        }
        if let didCopy {
            for range in ranges.reversed() {
                modified.insertButton(withImage: DynamicImage(image: image, dark: .white, light: .black), at: range.location) { point in
                    NSPasteboard.general.declareTypes([.string], owner: NSApp)
                    NSPasteboard.general.setString(attributedString.string.substring(nsrange: range), forType: .string)
                    ToastWindowController.showToast(withMessage: "Copied", duration: 1, screenCoordinate: point, pointSize: 12)
                    didCopy()
                }
                modified.insert(
                    NSAttributedString(
                        string: " ",
                        attributes: modified.attributes(
                            at: range.location + 1,
                            effectiveRange: nil)),
                    at: range.location + 1)
            }
        }
        return modified
    } else {
        return attributedString
    }
}
