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
                                        urlCode: urlCode)
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
