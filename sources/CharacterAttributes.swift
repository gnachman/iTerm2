//
//  CharacterAttributes.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/15/22.
//

import AppKit

// Used when making a NSAttributedString from a selection. This gives the attributes dictionary for a character.
@objc(iTermCharacterAttributesProvider)
class CharacterAttributesProvider: NSObject {
    private let colorMap: iTermColorMapReading
    private let useCustomBoldColor: Bool
    private let brightenBold: Bool
    private let useBoldFont: Bool
    private let useItalicFont: Bool
    private let useNonAsciiFont: Bool
    private let copyBackgroundColor: Bool  // Advanced pref
    private let excludeBackgroundColorsFromCopiedStyle: Bool  // Advanced pref
    private let fontTable: FontTable

    private lazy var paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        return style
    }()

    @objc
    init(colorMap: iTermColorMap,
         useCustomBoldColor: Bool,
         brightenBold: Bool,
         useBoldFont: Bool,
         useItalicFont: Bool,
         useNonAsciiFont: Bool,
         copyBackgroundColor: Bool,
         excludeBackgroundColorsFromCopiedStyle: Bool,
         fontTable: FontTable) {
        self.colorMap = colorMap
        self.useCustomBoldColor = useCustomBoldColor
        self.brightenBold = brightenBold
        self.useBoldFont = useBoldFont
        self.useItalicFont = useItalicFont
        self.useNonAsciiFont = useNonAsciiFont
        self.copyBackgroundColor = copyBackgroundColor
        self.excludeBackgroundColorsFromCopiedStyle = excludeBackgroundColorsFromCopiedStyle
        self.fontTable = fontTable
    }

    func attributes(_ c: screen_char_t, externalAttributes: iTermExternalAttribute) -> [AnyHashable: Any] {
        var isBold = ObjCBool(c.bold != 0)
        let isFaint = c.faint != 0
        var bgColor = colorMap.color(forCode: Int32(c.backgroundColor),
                                     green: Int32(c.bgGreen),
                                     blue: Int32(c.bgBlue),
                                     colorMode: ColorMode(rawValue: c.backgroundColorMode),
                                     bold: false,
                                     faint: false,
                                     isBackground: true,
                                     useCustomBoldColor: useCustomBoldColor,
                                     brightenBold: brightenBold)!
        let fgColor: NSColor
        if c.invisible != 0 {
            fgColor = bgColor
        } else {
            fgColor = colorMap.color(forCode: Int32(c.foregroundColor),
                                     green: Int32(c.fgGreen),
                                     blue: Int32(c.fgBlue),
                                     colorMode: ColorMode(rawValue: c.foregroundColorMode),
                                     bold: isBold.boolValue,
                                     faint: isFaint,
                                     isBackground: false,
                                     useCustomBoldColor: useCustomBoldColor,
                                     brightenBold: brightenBold)!.premultiplyingAlpha(with: bgColor)
        }
        let underlineStyle: NSUnderlineStyle = (externalAttributes.urlCode != 0 || c.underline != 0) ? [.single, .byWord] : []
        var isItalic = ObjCBool(c.italic != 0)

        var remapped = UTF32Char(0)
        let fontInfo = fontTable.fontForCharacter(c.baseCharacter,
                                                  useBoldFont: useBoldFont,
                                                  useItalicFont: useItalicFont,
                                                  renderBold: &isBold,
                                                  renderItalic: &isItalic,
                                                  remapped: &remapped)
        if !copyBackgroundColor &&
            c.backgroundColorMode == ColorModeAlternate.rawValue &&
            c.backgroundColor == ALTSEM_DEFAULT {
            bgColor = NSColor.clear
        }
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: fgColor,
                                                         .backgroundColor: bgColor,
                                                         .font: font(fontInfo, bold: c.bold != 0),
                                                         .paragraphStyle: paragraphStyle,
                                                         .underlineStyle: underlineStyle.rawValue]
        if remapped > 0 {
            attributes[.iTermReplacementBaseCharacterAttributeName] = NSNumber(value: remapped)
        }
        
        if externalAttributes.hasUnderlineColor {
            let color = colorMap.color(forCode: externalAttributes.underlineColor.red,
                                       green: externalAttributes.underlineColor.green,
                                       blue: externalAttributes.underlineColor.blue,
                                       colorMode: externalAttributes.underlineColor.mode,
                                       bold: isBold.boolValue,
                                       faint: isFaint,
                                       isBackground: false,
                                       useCustomBoldColor: useCustomBoldColor,
                                       brightenBold: brightenBold)
            attributes[.underlineColor] = color
        }
        if excludeBackgroundColorsFromCopiedStyle {
            attributes.removeValue(forKey: .backgroundColor)
        }
        if externalAttributes.urlCode != 0 {
            if let url = iTermURLStore.sharedInstance().url(forCode: externalAttributes.urlCode) {
                attributes[.link] = url
            }
        }
        return attributes;
    }

    private func font(_ fontInfo: PTYFontInfo?, bold: Bool) -> NSFont {
        if let font = fontInfo?.font {
            return font
        }
        // Ordinarily fontInfo would never be nil, but it is in unit tests. It's useful to distinguish
        // bold from regular in tests, so we ensure that attribute is correctly set in this test-only
        // path.
        let size = NSFont.systemFontSize
        if bold {
            return NSFont.boldSystemFont(ofSize: size)
        }
        return NSFont.systemFont(ofSize: size)
    }
}
