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

private func ReadableParagraphStyle(lineHeightMultiple: CGFloat = 1.3,
                                    paragraphSpacing: CGFloat = 8) -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineHeightMultiple = lineHeightMultiple
    paragraphStyle.paragraphSpacing = paragraphSpacing
    return paragraphStyle
}

private func ApplyReadableParagraphStyle(_ attributedString: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    result.enumerateAttribute(
        .paragraphStyle,
        in: NSRange(location: 0, length: result.length),
        options: []) { value, range, _ in
            let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? ReadableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineHeightMultiple = max(paragraphStyle.lineHeightMultiple, 1.3)
            paragraphStyle.paragraphSpacing = max(paragraphStyle.paragraphSpacing, 8)
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    if result.length > 0,
       result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil {
        result.addAttribute(.paragraphStyle,
                            value: ReadableParagraphStyle(),
                            range: NSRange(location: 0, length: result.length))
    }
    return result
}

private func ApplyChatCodeBlockStyle(_ attributedString: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    let range = NSRange(location: 0, length: result.length)
    let backgroundColor = NSColor.it_dynamicColor(
        forLightMode: NSColor(fromHexString: "#eeeeee")!,
        darkMode: NSColor(fromHexString: "#181818")!)
    let textColor = NSColor.it_dynamicColor(
        forLightMode: NSColor(fromHexString: "#1f1f1f")!,
        darkMode: NSColor(fromHexString: "#f6f6f6")!)
    let font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
        ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                       weight: .regular)

    result.enumerateAttribute(
        NSAttributedString.Key.swiftyMarkdownLineStyle,
        in: range,
        options: []) { value, codeRange, _ in
            guard value as? String == "codeblock" else {
                return
            }
            let paragraphStyle = (result.attribute(.paragraphStyle,
                                                   at: codeRange.location,
                                                   effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle
                ?? ReadableParagraphStyle(lineHeightMultiple: 1.2,
                                          paragraphSpacing: 0)
            paragraphStyle.lineBreakMode = .byCharWrapping
            paragraphStyle.lineHeightMultiple = 1.2
            paragraphStyle.paragraphSpacingBefore = 0
            paragraphStyle.paragraphSpacing = 0
            paragraphStyle.firstLineHeadIndent = max(paragraphStyle.firstLineHeadIndent, 8)
            paragraphStyle.headIndent = max(paragraphStyle.headIndent, 8)

            result.addAttributes([
                .backgroundColor: backgroundColor,
                .foregroundColor: textColor,
                .font: font,
                .paragraphStyle: paragraphStyle
            ], range: codeRange)
        }
    return result
}

func AttributedStringForSystemMessageMarkdown(_ unsafeString: String,
                                              linkColor: NSColor? = nil,
                                              didCopy: (() -> ())?) -> NSAttributedString {
    let md = SwiftyMarkdownForMessage(
        string: unsafeString,
        linkColor: linkColor,
        textColor: .it_dynamicColor(forLightMode: NSColor(fromHexString: "#202020")!,
                                    darkMode: NSColor(fromHexString: "#f2f2f2")!))
    return AttributedStringForMessage(md, didCopy: didCopy)
}

func AttributedStringForSystemMessagePlain(_ text: String,
                                           textColor: NSColor) -> NSAttributedString {
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: textColor,
        .paragraphStyle: ReadableParagraphStyle()
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
    private static func subpartsForDisplay(_ subparts: [LLM.Message.StatusUpdate]) -> [LLM.Message.StatusUpdate] {
        // Keep the last "long" update plus everything after it
        var singlePartUpdates = subparts.flatMap { $0.exploded }

        let lastReasoningSummaryUpdateIndex = singlePartUpdates.lastIndex(where: { $0.isReasoningSummaryUpdate })
        let lastWebSearchFinishedIndex = singlePartUpdates.lastIndex(where: { $0.isWebSearchFinished })
        let lastCodeInterpreterFinishedIndex = singlePartUpdates.lastIndex(where: { $0 == .codeInterpreterFinished })
        let keepStart = [lastReasoningSummaryUpdateIndex,
                         lastWebSearchFinishedIndex,
                         lastCodeInterpreterFinishedIndex].compactMap { $0 }.max()
        if let keepStart {
            singlePartUpdates.removeSubrange(..<keepStart)
        }
        return singlePartUpdates
    }

    var displayString: String {
        switch self {
        case .webSearchStarted:
            "Searching the web…"
        case .webSearchFinished(let query):
            if let query {
                "Finished searching the web for \(query)."
            } else {
                "Finished searching the web."
            }
        case .codeInterpreterStarted:
            "Executing code…"
        case .codeInterpreterFinished:
            "Finished executing code"
        case .reasoningSummaryUpdate:
            "Thought for a few seconds \u{203A}"
        case .multipart(let subparts):
            Self.subpartsForDisplay(subparts).map { $0.displayString }.joined(separator: "\n")
        }
    }

    var displayMarkdownString: String {
        switch self {
        case .webSearchStarted:
            "Searching the web…"
        case .webSearchFinished(let query):
            if let query {
                "Finished searching the web for **\(query.escapedForMarkdown)**."
            } else {
                "Finished searching the web."
            }
        case .codeInterpreterStarted:
            "Executing code…"
        case .codeInterpreterFinished:
            "Finished executing code"
        case .reasoningSummaryUpdate:
            "Thought for a few seconds \u{203A}"
        case .multipart(let subparts):
            Self.subpartsForDisplay(subparts).map { $0.displayMarkdownString }.joined(separator: "\n")
        }
    }
}

func AttributedStringForCode(_ string: String,
                             textColor: NSColor) -> NSAttributedString {
    let paragraphStyle = ReadableParagraphStyle(lineHeightMultiple: 1.2,
                                                paragraphSpacing: 6)
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
    return ApplyChatCodeBlockStyle(
        ApplyReadableParagraphStyle(md.attributedString()))
}
