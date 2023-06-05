//
//  SyntaxHighlighter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/23.
//

import Foundation

@objc(iTermSyntaxHighlighting)
protocol SyntaxHighlighting {
    @objc func highlight(range: NSRange)
}

@objc(iTermSyntaxHighlighter)
class iTermSyntaxHighlighter: NSObject, SyntaxHighlighting {
    private let instance: SyntaxHighlighter

    @objc
    init(_ value: NSMutableAttributedString,
         colorMap: iTermColorMapReading,
         fontTable: FontTable,
         fileChecker: FileChecker) {
        instance = SyntaxHighlighter(value,
                                     colorMap: colorMap,
                                     fontTable: fontTable,
                                     fileChecker: fileChecker)
    }

    @objc
    func highlight(range: NSRange) {
        instance.highlight(range: Range(range)!)
    }
}

fileprivate struct Colors {
    var regular: NSColor
    var command: NSColor
    var quoted: NSColor
    var argument: NSColor
    var quotationMark: NSColor
    var error: NSColor
    var parenthesized: NSColor
    var existingFile: NSColor
    let colorMap: iTermColorMapReading

    init(colorMap: iTermColorMapReading) {
        self.colorMap = colorMap

        let background = colorMap.color(forKey: kColorMapBackground) ?? NSColor.white
        let contrasting = { color in
            NSColor.colorWithContrast(background: background,
                                      foreground: color,
                                      minimumBrightnessDifference: 35)
        }
        regular = contrasting(colorMap.color(forKey: kColorMapForeground))
        command = contrasting(colorMap.color(forKey: kColorMapAnsiBlue))
        quoted = contrasting(colorMap.color(forKey: kColorMapAnsiGreen))
        argument = contrasting(colorMap.color(forKey: kColorMapAnsiCyan))
        quotationMark = contrasting(colorMap.color(forKey: kColorMapAnsiGreen))
        error = contrasting(colorMap.color(forKey: kColorMapAnsiRed))
        parenthesized = contrasting(colorMap.color(forKey: kColorMapAnsiBlue))
        existingFile = contrasting(colorMap.color(forKey: kColorMapAnsiMagenta))
    }

    mutating func reload() {
        self = Colors(colorMap: colorMap)
    }
}

class SyntaxHighlighter {
    private let value: NSMutableAttributedString
    private let fontTable: FontTable
    private let colors: Colors
    private let fileChecker: FileChecker

    init(_ value: NSMutableAttributedString,
         colorMap: iTermColorMapReading,
         fontTable: FontTable,
         fileChecker: FileChecker) {
        self.value = value
        self.fontTable = fontTable
        self.fileChecker = fileChecker
        colors = Colors(colorMap: colorMap)
    }

    func highlight(range rangeToModify: Range<Int>) {
        let maxLength = 1024
        if rangeToModify.count > 1024 {
            removeForegroundColorAndFontAttributes(range: maxLength..<rangeToModify.upperBound)
            highlight(range: rangeToModify.lowerBound..<(rangeToModify.lowerBound + maxLength))
            return
        }
        removeForegroundColorAndFontAttributes(range: rangeToModify)
        let escapes = [unichar(Character("n")): "\n",
                       unichar(Character("a")): "\u{7}",
                       unichar(Character("t")): "\t",
                       unichar(Character("r")): "\r"]
        guard let sub = value.string.substring(with: rangeToModify) else {
            return
        }
        let parser = CommandParser(command: sub as NSString, escapes: escapes)
        let annotated = parser.attributedString
        DLog(annotated.debugDescription)
        annotated.enumerateRoles { role, nsrange in
            guard let range = Range(nsrange) else {
                return
            }
            let shiftedRange = range.shifted(by: rangeToModify.lowerBound).clamped(to: rangeToModify)
            DLog("Consider <<\(String(value.string.substringWithUTF16Range(shiftedRange)!))>> with role \(role)")
            switch role {
            case .command:
                DLog("Command in \(shiftedRange)")
                highlightCommand(shiftedRange)
            case .whitespace, .placeholder:
                break
            case .quoted:
                DLog("Quoted in \(shiftedRange)")
                highlightQuoted(shiftedRange)
            case .other:
                DLog("Argument in \(shiftedRange)")
                highlightArgument(shiftedRange)
            case .quotationMark:
                DLog("Quotation mark in \(shiftedRange)")
                highlightQuotationMark(shiftedRange)
            case .unbalancedQuotationMark, .unbalancedParen:
                DLog("Unbalanced quote/paren in \(shiftedRange)")
                highlightError(shiftedRange)
            case .paren, .subshell:
                DLog("Paren/subshell command in \(shiftedRange)")
                highlightParenthesized(shiftedRange)
            }
            value.addAttributes([.commandParserRole: role], range: NSRange(shiftedRange))
        }
        DLog(value.debugDescription)
    }

    func removeForegroundColorAndFontAttributes(range: Range<Int>) {
        setFont(range: range, font: fontTable.asciiFont.font)
        setTextColor(range: range, color: colors.regular)
    }

    private func highlightCommand(_ range: Range<Int>) {
        // TODO: It'd be nice to check if the command is valid but I'm not sure how best to handle builtins, aliases, etc.
        setTextColor(range: range, color: colors.command)
        setBold(range: range)
    }

    private func highlightQuoted(_ range: Range<Int>) {
        setTextColor(range: range, color: colors.quoted)
    }

    private func highlightArgument(_ range: Range<Int>) {
        if let path = value.string.substringWithUTF16Range(range) {
            switch fileChecker.cachedCheckIfFileExists(path: String(path)) {
            case .true:
                setTextColor(range: range, color: colors.existingFile)
            case .false:
                setTextColor(range: range, color: colors.argument)
            case .other:
                let uniqueID = UUID().uuidString
                setTextColor(range: range, color: colors.argument)
                value.addAttribute(NSAttributedString.Key.syntaxHighlighterPendingFileCheck,
                                   value: uniqueID,
                                   range: NSRange(range))

                // Asynchronously update the color if the file is discovered to exist. This might
                // go over ssh or a slow filesystem so it must be async.
                Self.check(fileChecker: fileChecker,
                           path: String(path),
                           uniqueID: uniqueID,
                           attributedString: value,
                           colorMap: colors.colorMap)
            @unknown default:
                fatalError()
            }
        } else {
            setTextColor(range: range, color: colors.argument)
        }
    }

    private static func check(fileChecker: FileChecker,
                              path: String,
                              uniqueID: String,
                              attributedString: NSMutableAttributedString,
                              colorMap: iTermColorMapReading) {
        fileChecker.checkIfFileExists(path: path) { [weak attributedString] exists in
            switch exists {
            case .false:
                return
            case .true:
                let color = Colors(colorMap: colorMap).existingFile
                attributedString?.replaceAttribute(
                    key: NSAttributedString.Key.syntaxHighlighterPendingFileCheck,
                    value: uniqueID,
                    newAttributes: [.foregroundColor: color ])
            case .other:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak attributedString] in
                    guard let attributedString else {
                        return
                    }
                    guard attributedString.hasAttribute(key: .syntaxHighlighterPendingFileCheck, value: uniqueID as NSString) else {
                        return
                    }
                    check(fileChecker: fileChecker,
                          path: path,
                          uniqueID: uniqueID,
                          attributedString: attributedString,
                          colorMap: colorMap)
                }
            @unknown default:
                fatalError()
            }
        }
    }

    private func highlightQuotationMark(_ range: Range<Int>) {
        setTextColor(range: range, color: colors.quotationMark)
    }

    private func highlightError(_ range: Range<Int>) {
        setTextColor(range: range, color: colors.error)
    }

    private func highlightParenthesized(_ range: Range<Int>) {
        setTextColor(range: range, color: colors.parenthesized)
    }

    private func setBold(range: Range<Int>) {
        setFont(range: range, font: fontTable.asciiFont.boldVersion?.font ?? fontTable.asciiFont.font)
    }

    private func setFont(range: Range<Int>, font: NSFont) {
        value.addAttribute(.font,
                           value: font,
                           range: NSRange(range))
    }

    private func setTextColor(range: Range<Int>, color: NSColor) {
        value.addAttribute(.foregroundColor,
                           value: color,
                           range: NSRange(range))
    }
}

extension String {
    func substring(with utf16Range: Range<Int>) -> String? {
        guard let startIndex = utf16.index(utf16.startIndex, offsetBy: utf16Range.lowerBound, limitedBy: utf16.endIndex),
              let endIndex = utf16.index(utf16.startIndex, offsetBy: utf16Range.upperBound, limitedBy: utf16.endIndex)
        else {
            return nil
        }

        let range = Range(uncheckedBounds: (startIndex, endIndex))
        return String(self[range])
    }
}

extension Range where Bound == Int {
    func shifted(by n: Int) -> Range<Int> {
        return (lowerBound + n)..<(upperBound + n)
    }
}

extension String {
    func substringWithUTF16Range(_ range: Range<Int>) -> Substring? {
        let utf16View = self.utf16
        guard let start = utf16View.index(utf16View.startIndex, offsetBy: range.lowerBound, limitedBy: utf16View.endIndex),
              let end = utf16View.index(utf16View.startIndex, offsetBy: range.upperBound, limitedBy: utf16View.endIndex)
        else {
            return nil
        }
        return Substring(utf16View[start..<end])
    }
}

extension NSColor {
    static func colorWithContrast(background unsafeBg: NSColor,
                                  foreground unsafeFg: NSColor,
                                  minimumBrightnessDifference: Double) -> NSColor {
        guard let background = unsafeBg.usingColorSpace(.sRGB),
              let foreground = unsafeFg.usingColorSpace(.sRGB) else {
            return unsafeFg
        }

        // Convert the background and foreground colors to iTermSRGBColor instances
        let bgSRGB = iTermSRGBColor(r: background.redComponent,
                                    g: background.greenComponent,
                                    b: background.blueComponent)
        let fgSRGB = iTermSRGBColor(r: foreground.redComponent,
                                    g: foreground.greenComponent,
                                    b: foreground.blueComponent)

        // Convert the background color to iTermLABColor
        let bgLAB = iTermLABFromSRGB(bgSRGB)

        // Calculate the minimum brightness difference that can be achieved with the given background color
        let darkMax = max(0, bgLAB.l - minimumBrightnessDifference)
        let brightMin = min(100, bgLAB.l + minimumBrightnessDifference)

        // Find the closest possible color to the foreground color that satisfies the minimum brightness difference requirement
        var fgLAB = iTermLABFromSRGB(fgSRGB)
        if fgLAB.l > darkMax && fgLAB.l < brightMin {
            // Adjustment is needed. Make it brighter if that would do the job, otherwise make it darker.
            if fgLAB.l + minimumBrightnessDifference <= 100 {
                fgLAB.l += minimumBrightnessDifference
            } else {
                fgLAB.l -= minimumBrightnessDifference
            }
        }

        // Convert the iTermLABColor instances back to iTermSRGBColor
        let fgSRGBNew = iTermSRGBFromLAB(fgLAB)

        // Convert the iTermSRGBColor back to NSColor
        return NSColor(calibratedRed: fgSRGBNew.r, green: fgSRGBNew.g, blue: fgSRGBNew.b, alpha: 1.0)
    }
}

extension NSAttributedString.Key {
    static let syntaxHighlighterPendingFileCheck: NSAttributedString.Key = .init("syntaxHighlighterPendingFileCheck")
}

extension NSMutableAttributedString {
    func replaceAttribute<T: Equatable>(key: NSAttributedString.Key,
                                        value: T,
                                        newAttributes: [NSAttributedString.Key: Any]) {
        let rangeToSearch = NSRange(location: 0, length: length)
        enumerateAttribute(key, in: rangeToSearch) { found, range, stop in
            if found as? T != value {
                return
            }
            removeAttribute(key, range: range)
            addAttributes(newAttributes, range: range)
        }
    }
}

extension NSAttributedString {
    // Method to check if a particular combination of attribute key and value is present
    func hasAttribute(key: NSAttributedString.Key, value: Any) -> Bool {
        // Iterate over the attributes in the NSAttributedString
        var hasAttribute = false
        self.enumerateAttributes(in: NSRange(location: 0, length: self.length), options: []) { (attributes, _, stop) in
            // Check if the attribute key and value match the provided parameters
            for (attributeKey, attributeValue) in attributes {
                if attributeKey == key,
                   let attributeValue = attributeValue as? NSObject,
                   attributeValue.isEqual(value) {
                    hasAttribute = true
                    stop.pointee = true
                    break
                }
            }
        }
        return hasAttribute
    }
}
