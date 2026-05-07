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

    // For ColorModeExternal cells with a valid dual-mode entry on the EA,
    // returns the appearance-resolved variant; otherwise returns the cell's
    // stored fallback in its native mode.
    private func resolvedCellColor(red: Int32,
                                   green: Int32,
                                   blue: Int32,
                                   cellMode: UInt32,
                                   dual: iTermDualModeColor) -> (Int32, Int32, Int32, ColorMode) {
        if cellMode == ColorModeExternal.rawValue && dual.valid.boolValue {
            let v = colorMap.resolvedDualModeColor(dual)
            return (v.red, v.green, v.blue, v.mode)
        }
        return (red, green, blue, ColorMode(rawValue: cellMode))
    }

    @objc
    func attributes(_ c: screen_char_t, externalAttributes: iTermExternalAttribute, metadata: UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable: Any] {
        var isBold = ObjCBool(c.bold != 0)
        let isFaint = c.faint != 0
        let (bgRed, bgGreen, bgBlue, bgMode) =
            resolvedCellColor(red: Int32(c.backgroundColor),
                              green: Int32(c.bgGreen),
                              blue: Int32(c.bgBlue),
                              cellMode: c.backgroundColorMode,
                              dual: externalAttributes.dualModeBackground)
        var bgColor = colorMap.color(forCode: bgRed,
                                     green: bgGreen,
                                     blue: bgBlue,
                                     colorMode: bgMode,
                                     bold: false,
                                     faint: false,
                                     isBackground: true,
                                     useCustomBoldColor: useCustomBoldColor,
                                     brightenBold: brightenBold)!
        let fgColor: NSColor
        if c.invisible != 0 {
            fgColor = bgColor
        } else {
            let (fgRed, fgGreen, fgBlue, fgMode) =
                resolvedCellColor(red: Int32(c.foregroundColor),
                                  green: Int32(c.fgGreen),
                                  blue: Int32(c.fgBlue),
                                  cellMode: c.foregroundColorMode,
                                  dual: externalAttributes.dualModeForeground)
            fgColor = colorMap.color(forCode: fgRed,
                                     green: fgGreen,
                                     blue: fgBlue,
                                     colorMode: fgMode,
                                     bold: isBold.boolValue,
                                     faint: isFaint,
                                     isBackground: false,
                                     useCustomBoldColor: useCustomBoldColor,
                                     brightenBold: brightenBold)!.premultiplyingAlpha(with: bgColor)
        }
        let underlineStyle: NSUnderlineStyle = (externalAttributes.url != nil || c.underline != 0) ? [.single, .byWord] : []
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
        var selectedFont = font(fontInfo, bold: c.bold != 0)
        // For DECDHL pairs (double-height), scale the font to 2x.
        if let metadata, metadata.pointee.lineAttribute == .doubleHeightTop {
            selectedFont = NSFont(descriptor: selectedFont.fontDescriptor,
                                  size: selectedFont.pointSize * 2) ?? selectedFont
        }
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: fgColor,
                                                         .backgroundColor: bgColor,
                                                         .font: selectedFont,
                                                         .paragraphStyle: paragraphStyle,
                                                         .underlineStyle: underlineStyle.rawValue]
        if remapped > 0 {
            attributes[.iTermReplacementBaseCharacterAttributeName] = NSNumber(value: remapped)
        }
        
        if externalAttributes.hasUnderlineColor {
            // Resolve any dual-mode variant against the current background.
            let uc = colorMap.resolvedColorValue(externalAttributes.underlineColor)
            let color = colorMap.color(forCode: uc.red,
                                       green: uc.green,
                                       blue: uc.blue,
                                       colorMode: uc.mode,
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
        if let url = externalAttributes.url {
            attributes[.link] = url.url
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
