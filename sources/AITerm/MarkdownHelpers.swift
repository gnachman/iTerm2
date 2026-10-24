//
//  MarkdownHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

import SwiftyMarkdown

private let fenceLineRegex = try! NSRegularExpression(pattern: "^ *(```[a-z]*)[ \\t]*$")

// Returns the bare fence (``` plus any info string) if the line is a code
// fence, or nil otherwise. SwiftyMarkdown only accepts an opening fence
// matching ^```[a-z]*$ and a closing fence equal to ```, while CommonMark
// also allows leading spaces and trailing whitespace. Streamed replies often
// end in “``` ” because the server sends a space after the last word.
private func normalizedFence(_ line: String) -> String? {
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = fenceLineRegex.firstMatch(in: line, options: [], range: range),
          let fenceRange = Range(match.range(at: 1), in: line) else {
        return nil
    }
    return String(line[fenceRange])
}

// Prepares message markdown for SwiftyMarkdown, one line at a time. It
// reduces code fences to the bare form SwiftyMarkdown recognizes and empties
// whitespace-only lines outside code blocks. SwiftyMarkdown treats a
// whitespace-only line as a setext heading underline, turning the line above
// it (for example, the last line of a code block followed by a streamed
// trailing space) into a heading. CommonMark treats such a line as blank.
func sanitizeMarkdownLines(_ input: String) -> String {
    var inCodeBlock = false
    return input.components(separatedBy: "\n").map { line in
        if let fence = normalizedFence(line) {
            // Mirrors SwiftyMarkdown: any fence opens a block; only a bare
            // ``` closes one.
            if !inCodeBlock {
                inCodeBlock = true
                return fence
            }
            if fence == "```" {
                inCodeBlock = false
                return fence
            }
            // An opening fence inside a block is code, not markup.
            return line
        }
        if !inCodeBlock && !line.isEmpty && line.trimmingCharacters(in: .whitespaces).isEmpty {
            return ""
        }
        return line
    }.joined(separator: "\n")
}

private func SwiftyMarkdownForMessage(string unsafeString: String,
                                      linkColor: NSColor?,
                                      textColor: NSColor?) -> SwiftyMarkdown {
    let massagedValue = sanitizeMarkdownLines(unsafeString)

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

func AttributedStringForSystemMessagePlain(_ text: String,
                                           textColor: NSColor) -> NSAttributedString {
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: textColor
    ]

    return NSAttributedString(string: text, attributes: textAttributes)
}

func AttributedStringForStatusUpdate(_ statusUpdate: LLM.Message.StatusUpdate,
                                     textColor: NSColor) -> NSAttributedString {
    let md = SwiftyMarkdownForMessage(
        string: statusUpdate.displayMarkdownString,
        linkColor: NSColor(fromHexString: "#2020f0"),
        textColor: textColor)
    return AttributedStringForMessage(md, didCopy: nil)
}

func AttributedStringForFilename(_ filename: String,
                                 textColor: NSColor) -> NSAttributedString {
    // Create the filename text with 11 point system font
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: textColor
    ]

    return NSAttributedString(string: filename, attributes: textAttributes)
}

extension LLM.Message.StatusUpdate {
    // displayString and subpartsForDisplay are shared with the iOS companion
    // app and live in LLM.swift; this markdown variant is Mac-only.
    var displayMarkdownString: String {
        switch self {
        case .webSearchStarted:
            String(localized: "StatusUpdate.WebSearchStarted", defaultValue: "Searching the web…", comment: "Status shown while a web search is running")
        case .webSearchFinished(let query):
            if let query {
                String(localized: "StatusUpdate.WebSearchFinishedQuery", defaultValue: "Finished searching the web for **\(query.escapedForMarkdown)**.", comment: "Status shown after a web search, including the query")
            } else {
                String(localized: "StatusUpdate.WebSearchFinished", defaultValue: "Finished searching the web.", comment: "Status shown after a web search with no query")
            }
        case .codeInterpreterStarted:
            String(localized: "StatusUpdate.CodeInterpreterStarted", defaultValue: "Executing code…", comment: "Status shown while the code interpreter is running")
        case .codeInterpreterFinished:
            String(localized: "StatusUpdate.CodeInterpreterFinished", defaultValue: "Finished executing code", comment: "Status shown after the code interpreter finishes")
        case .reasoningSummaryUpdate(let text): text
        case .multipart(let subparts):
            Self.subpartsForDisplay(subparts).map { $0.displayMarkdownString }.joined(separator: "\n")
        }
    }
}

func AttributedStringForCode(_ string: String,
                             textColor: NSColor) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle,
        .font: NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    ]
    return NSAttributedString(
        string: string,
        attributes: attributes
    )
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
    let image = NSImage(systemSymbolName: SFSymbol.docOnDoc.rawValue, accessibilityDescription: iTermLocalizedCopy())!
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
                ToastWindowController.showToast(withMessage: String(localized: "MarkdownHelpers.CopiedToast", defaultValue: "Copied", comment: "Toast shown after copying a code block"), duration: 1, screenCoordinate: point, pointSize: 12)
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
}
