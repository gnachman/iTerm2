//
//  NSAttributedString+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/22.
//

import Foundation

class AttributeToControlSequenceConverter {
    private var currentCodes = [String]()

    func convert(_ string: String, attributes: [NSAttributedString.Key : Any]) -> String {
        let codes = convert(attributes)
        if codes == currentCodes {
            return string
        }
        currentCodes = codes
        return "\u{1b}[" + Array(codes).sorted().joined(separator: ";") + "m" + string
    }

    // Returns SGR codes
    private func convert(_ attributes: [NSAttributedString.Key : Any]) -> [String] {
        var c = screen_char_t()
        if let fgColor = attributes[.foregroundColor] as? NSColor,
           let srgb = fgColor.usingColorSpace(NSColorSpace.sRGB) {
            c.foregroundColorMode = ColorMode24bit.rawValue
            c.foregroundColor = UInt32(UInt8(srgb.redComponent * 255))
            c.fgGreen = UInt32(UInt8(srgb.greenComponent * 255))
            c.fgBlue = UInt32(UInt8(srgb.blueComponent * 255))
        } else {
            c.foregroundColorMode = ColorModeAlternate.rawValue
            c.foregroundColor = UInt32(ALTSEM_DEFAULT)
        }

        if let bgColor = attributes[.backgroundColor] as? NSColor,
           let srgb = bgColor.usingColorSpace(NSColorSpace.sRGB) {
            c.backgroundColorMode = ColorMode24bit.rawValue
            c.backgroundColor = UInt32(UInt8(srgb.redComponent * 255))
            c.bgGreen = UInt32(UInt8(srgb.greenComponent * 255))
            c.bgBlue = UInt32(UInt8(srgb.blueComponent * 255))
        } else {
            c.backgroundColorMode = ColorModeAlternate.rawValue
            c.backgroundColor = UInt32(ALTSEM_DEFAULT)
        }

        if let font = attributes[.font] as? NSFont {
            if NSFontManager().weight(of: font) > 5 {
                c.bold = 1
            } else {
                c.bold = 0
            }
            if font.fontDescriptor.symbolicTraits.contains(.italic) {
                c.italic = 1
            } else {
                c.italic = 0
            }
        } else {
            c.bold = 0
        }

        if let underlineStyle = attributes[.underlineStyle] as? NSUnderlineStyle {
            switch underlineStyle {
            case .single:
                c.underline = 1
                c.underlineStyle = .single
            case .double:
                c.underline = 1
                c.underlineStyle = .double
            case .patternDash, .patternDot, .patternDashDot, .patternDashDotDot:
                c.underline = 1
                c.underlineStyle = .curly
            default:
                c.underline = 0
            }
        } else {
            c.underline = 0
        }
        if attributes[.strikethroughStyle] != nil {
            c.strikethrough = 1
        } else {
            c.strikethrough = 0
        }

        c.inverse = 0
        if let fgColor = attributes[.foregroundColor] as? NSColor, fgColor.alphaComponent <= 0.5 {
            c.faint = 1
        } else {
            c.faint = 0
        }

        let underlineColor: VT100TerminalColorValue?
        if let unsafeColor = attributes[.underlineColor] as? NSColor,
            let srgb = unsafeColor.usingColorSpace(.sRGB) {
            underlineColor = VT100TerminalColorValue(red: Int32(UInt32(UInt8(srgb.redComponent * 255))),
                                                     green: Int32(UInt8(srgb.greenComponent * 255)),
                                                     blue: Int32(UInt8(srgb.blueComponent * 255)),
                                                     mode: ColorMode24bit)
        } else {
            underlineColor = nil
        }

        let urlCode = { () -> UInt32 in
            let href: URL? = { () -> URL? in
                if let link = attributes[.link] {
                    if let url = link as? URL {
                        return url
                    } else if let url = link as? String {
                        return URL(string: url)
                    }
                }
                return nil
            }()
            guard let href = href else {
                return 0
            }
            return iTermURLStore.sharedInstance().code(for: href, withParams: nil)
        }()
        let ea = iTermExternalAttribute(havingUnderlineColor: underlineColor != nil,
                                        underlineColor: underlineColor ?? VT100TerminalColorValue(),
                                        urlCode: urlCode,
                                        blockID: nil)
        return VT100Terminal.sgrCodes(forCharacter: c, externalAttributes: ea).array as! [String]
    }
}

extension NSAttributedString {
    var asStringWithControlSequences: String {
        let string = self.string as NSString
        var result = ""
        let converter = AttributeToControlSequenceConverter()
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, stop in
            result.append(converter.convert(string.substring(with: range), attributes: attributes))
        }
        return result
    }

    @objc
    func mapAttributes(_ transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString: self)

        let range = NSRange(location: 0, length: length)
        mutableAttributedString.enumerateAttributes(in: range, options: []) { (attributes, range, _) in
            let newAttributes = transform(attributes)
            mutableAttributedString.setAttributes(newAttributes, range: range)
        }

        return NSAttributedString(attributedString: mutableAttributedString)
    }

    // The HTML parser built in to NSAttributedString is unusable because it sets an sRGB color for
    // the default text color, breaking light/dark mode. I <3 AppKit
    @objc(attributedStringWithHTML:font:paragraphStyle:)
    class func attributedString(html htmlString: String, font: NSFont, paragraphStyle: NSParagraphStyle) -> NSAttributedString? {
        let attributedString = NSMutableAttributedString(string: "")
        attributedString.addAttributes([.font: font, .paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: 0))

        var currentIndex = htmlString.startIndex

        while currentIndex < htmlString.endIndex {
            if htmlString[currentIndex] == "<", let endIndex = htmlString[currentIndex...].range(of: ">")?.upperBound, let tagRange = htmlString[currentIndex..<endIndex].range(of: "<a href=\""), tagRange.lowerBound == currentIndex {
                let urlStart = htmlString.index(tagRange.upperBound, offsetBy: 0)
                let urlEnd = htmlString[urlStart...].firstIndex(of: "\"") ?? htmlString.endIndex
                let url = String(htmlString[urlStart..<urlEnd])

                let textStart = htmlString.index(urlEnd, offsetBy: 2)
                let textEnd = htmlString[textStart...].range(of: "</a>")?.lowerBound ?? htmlString.endIndex

                let text = String(htmlString[textStart..<textEnd])

                let linkAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                    .link: url,
                    .cursor: NSCursor.pointingHand
                ]

                attributedString.append(NSAttributedString(string: text, attributes: linkAttributes))
                currentIndex = htmlString.index(textEnd, offsetBy: 4)
            } else {
                let nextIndex = htmlString[currentIndex...].range(of: "<")?.lowerBound ?? htmlString.endIndex
                let text = String(htmlString[currentIndex..<nextIndex])

                attributedString.append(NSAttributedString(string: text, attributes: [.font: font,
                                                                                      .paragraphStyle: paragraphStyle,
                                                                                      .foregroundColor: NSColor.textColor]))
                currentIndex = nextIndex
            }
        }

        return attributedString
    }
}

extension Array where Element: NSAttributedString {
    func joined(separator: NSAttributedString) -> NSAttributedString {
        let combined = NSMutableAttributedString()
        for part in self {
            if part != first {
                combined.append(separator)
            }
            combined.append(part)
        }
        return combined
    }
}

extension NSMutableAttributedString {
    typealias Change = (NSRange, [NSAttributedString.Key : Any]) -> ()
    func editAttributes(_ closure: (Change) -> ()) {
        var replacements = [NSRange: [NSAttributedString.Key : Any]]()
        closure { range, newAttributes in
            replacements[range] = newAttributes
        }
        for (range, attrs) in replacements {
            setAttributes(attrs, range: range)
        }
    }
}

@objc
class iTermTableCellView: NSTableCellView {
    @objc
    var strongTextField: NSTextField? {
        didSet {
            self.textField = strongTextField
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            if let textField = self.textField {
                switch backgroundStyle {
                case .normal:
                    textField.attributedStringValue = textField.attributedStringValue.mapAttributes({ attrs in
                        var result = attrs
                        if result[.foregroundColor] as? NSColor == NSColor.selectedMenuItemTextColor {
                            result[.foregroundColor] = NSColor.textColor
                        }
                        return result
                    })
                case .emphasized:
                    textField.attributedStringValue = textField.attributedStringValue.mapAttributes({ attrs in
                        var result = attrs
                        if result[.foregroundColor] as? NSColor == NSColor.textColor {
                            result[.foregroundColor] = NSColor.selectedMenuItemTextColor
                        }
                        return result
                    })
                default:
                    break
                }
            }
        }
    }
}
