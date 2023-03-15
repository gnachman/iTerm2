//
//  FontTable.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/23.
//

import Foundation

@objc(iTermFontTable)
class FontTable: NSObject {
    @objc static let unicodeLimit = 0x110000
    private let tree = IntervalTree()

    private class FontBox: NSObject, IntervalTreeObject {
        weak var entry: IntervalTreeEntry?
        var font: PTYFontInfo {
            didSet {
                font.boldVersion = font.computedBoldVersion()
                font.italicVersion = font.computedItalicVersion()
                font.boldItalicVersion = font.computedBoldItalicVersion()
            }
        }

        static var defaultFont: PTYFontInfo {
            return PTYFontInfo(font: NSFont.userFixedPitchFont(ofSize: 0))
        }

        required init(dictionary dict: [AnyHashable : Any]) {
            guard let name = dict["name"] as? String,
                  let size = dict["size"] as? CGFloat else {
                font = Self.defaultFont
                return
            }
            if let nsfont = NSFont(name: name, size: size) {
                font = PTYFontInfo(font: nsfont)
            } else {
                font = Self.defaultFont
            }
        }

        func fakeBold(italic: Bool) -> Bool {
            var fakeBold = ObjCBool(true)
            var fakeItalic = ObjCBool(italic)
            _ = PTYFontInfo.font(forAsciiCharacter: true,
                                 asciiFont: font,
                                 nonAsciiFont: nil,
                                 useBoldFont: true,
                                 useItalicFont: italic,
                                 usesNonAsciiFont: false,
                                 renderBold: &fakeBold,
                                 renderItalic: &fakeItalic)
            return fakeBold.boolValue
        }

        func fakeItalic(bold: Bool) -> Bool {
            var fakeBold = ObjCBool(bold)
            var fakeItalic = ObjCBool(true)
            _ = PTYFontInfo.font(forAsciiCharacter: true,
                                 asciiFont: font,
                                 nonAsciiFont: nil,
                                 useBoldFont: bold,
                                 useItalicFont: true,
                                 usesNonAsciiFont: false,
                                 renderBold: &fakeBold,
                                 renderItalic: &fakeItalic)
            return fakeItalic.boolValue
        }

        func dictionaryValue() -> [AnyHashable : Any] {
            return [ "name": font.font.familyName!, "size": font.font.pointSize ]
        }

        func copyOf() -> Self {
            return FontBox(font) as! Self
        }

        func doppelganger() -> IntervalTreeObject {
            return FontBox(font)
        }

        func progenitor() -> IntervalTreeObject? {
            return nil
        }

        init(_ font: PTYFontInfo) {
            self.font = font
        }
    }

    @objc
    let asciiFont: PTYFontInfo

    @objc
    let defaultNonASCIIFont: PTYFontInfo?

    @objc
    let anyASCIIDefaultLigatures: Bool

    @objc
    let anyNonASCIIDefaultLigatures: Bool

    @objc
    var fontForCharacterSizeCalculations: NSFont {
        return asciiFont.font
    }

    @objc
    override convenience init() {
        self.init(ascii: FontBox.defaultFont, nonAscii: nil)
    }

    @objc
    convenience init(ascii: PTYFontInfo, nonAscii: PTYFontInfo?) {
        self.init(defaultFont: ascii, nonAsciiFont: nonAscii, config: nil)
    }

    struct Entry: Codable, Equatable, Hashable {
        var start: Int
        var count: Int
        var fontName: String
        var pointSize: CGFloat?

        func font(defaultPointSize: CGFloat) -> PTYFontInfo {
            return PTYFontInfo(font: NSFont(name: fontName,
                                            size: pointSize ?? defaultPointSize))
        }

        func byAddingPointSize(_ delta: CGFloat) -> Entry {
            if let pointSize {
                return Entry(start: start,
                             count: count,
                             fontName: fontName,
                             pointSize: pointSize + delta)
            } else {
                return self
            }
        }
    }

    struct Config: Codable, Equatable, Hashable {
        static let latestKnownVersion = 1
        var entries: [Entry]
        var version = Self.latestKnownVersion

        init(entries: [Entry]) {
            self.entries = entries
        }

        func byAddingPointSize(_ delta: CGFloat) -> Config {
            return Config(entries: entries.map { $0.byAddingPointSize(delta)})
        }

        var stringValue: String {
            let encoder = JSONEncoder()
            let data = try! encoder.encode(self)
            return String(data: data, encoding: .utf8)!
        }

        init?(string: String) {
            guard !string.isEmpty else {
                return nil
            }
            let decoder = JSONDecoder()
            do {
                self = try decoder.decode(Config.self, from: string.data(using: .utf8)!)
            } catch {
                return nil
            }
        }

        static func makeTuple(_ configString: String?) -> (String, Config)? {
            guard let configString,
                  let parsed = Config(string: configString) else {
                return nil
            }
            return (configString, parsed)
        }
    }

    private let config: Config?
    @objc let configString: String?

    @objc let configHash: String

    @objc
    convenience init(defaultFont: PTYFontInfo,
                     nonAsciiFont: PTYFontInfo?,
                     configString: String?) {
        self.init(defaultFont: defaultFont,
                  nonAsciiFont: nonAsciiFont,
                  config: Config.makeTuple(configString))
    }

    private init(defaultFont: PTYFontInfo,
                 nonAsciiFont: PTYFontInfo?,
                 config tuple: (String, Config)?) {
        if let tuple {
            configString = tuple.0
            config = tuple.1
            configHash = String(tuple.1.hashValue)
        } else {
            configString = nil
            config = nil
            configHash = ""
        }
        asciiFont = defaultFont
        struct FontInfo: Hashable {
            var fontName: String
            var pointSize: CGFloat
        }
        // Max number of code points
        let asciiLimit = 128
        var unassignedCodePoints = IndexSet(integersIn: 0..<FontTable.unicodeLimit)
        if let config {
            for entry in config.entries {
                let font = entry.font(defaultPointSize: defaultFont.font.pointSize)
                tree.add(FontBox(font),
                         with: Interval(location: Int64(entry.start),
                                        length: Int64(entry.count)))
                let range = entry.start..<(entry.start + entry.count)
                unassignedCodePoints.remove(integersIn: range)
            }
        }
        defaultNonASCIIFont = nonAsciiFont ?? defaultFont

        for range in unassignedCodePoints.rangeView {
            let asciiRange = range.clamped(to: 0..<asciiLimit)
            if !asciiRange.isEmpty {
                tree.add(FontBox(defaultFont),
                         with: Interval(location: Int64(asciiRange.lowerBound),
                                        length: Int64(asciiRange.count)))
            }
            let nonASCIIRange = range.clamped(to: asciiLimit..<FontTable.unicodeLimit)
            if !nonASCIIRange.isEmpty {
                tree.add(FontBox(nonAsciiFont ?? defaultFont),
                         with: Interval(location: Int64(nonASCIIRange.lowerBound),
                                        length: Int64(nonASCIIRange.count)))
            }
        }
        anyASCIIDefaultLigatures = Self.treeHasLigatures(tree: tree, ascii: true)
        anyNonASCIIDefaultLigatures = Self.treeHasLigatures(tree: tree, ascii: false)

        super.init()
    }

    private static func treeHasLigatures(tree: IntervalTree, ascii: Bool) -> Bool {
        let enumerator = ascii ? tree.forwardLimitEnumerator(at: 128) : tree.reverseLimitEnumerator(at: 127)
        for entries in enumerator {
            for box in (entries as! [FontBox]) {
                if box.font.hasDefaultLigatures {
                    return true
                }
            }
        }
        return false
    }

    private func font(for c: Character) -> PTYFontInfo {
        return font(for: UniChar(c.unicodeScalars.first!.value))
    }

    @objc
    func font(for codePoint: UniChar) -> PTYFontInfo {
        let obj = tree.objects(in: Interval(location: Int64(codePoint),
                                            length: 1)).first! as! FontBox
        return obj.font
    }

    @objc
    var baselineOffset: CGFloat {
        return asciiFont.baselineOffset
    }

    @objc
    var underlineOffset: CGFloat {
        return asciiFont.underlineOffset
    }

    // use{Bold,Italic}Font: Use a different font if one is available
    // render{Bold,Italic}: On input, whether the character is {bold,italic} and on output whether it needs to be rendered as fake {bold,italic}.
    @objc
    func fontForCharacter(_ char: UniChar,
                          useBoldFont: Bool,
                          useItalicFont: Bool,
                          renderBold: UnsafeMutablePointer<ObjCBool>,
                          renderItalic:UnsafeMutablePointer<ObjCBool>) -> PTYFontInfo {
        return PTYFontInfo.font(forAsciiCharacter: true,
                                asciiFont: font(for: char),
                                nonAsciiFont: nil,
                                useBoldFont: useBoldFont,
                                useItalicFont: useItalicFont,
                                usesNonAsciiFont: false,
                                renderBold: renderBold,
                                renderItalic: renderItalic)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FontTable else {
            return false
        }
        if !other.asciiFont.font.isEqual(asciiFont.font) {
            return false
        }
        if other.config != config {
            return false
        }
        guard let otherNonASCII = other.defaultNonASCIIFont,
              let nonASCII = defaultNonASCIIFont else {
            return (other.defaultNonASCIIFont == nil) && (defaultNonASCIIFont == nil)
        }
        return otherNonASCII == nonASCII
    }

    @objc
    func fontTable(grownBy delta: CGFloat) -> FontTable {
        if delta == 0 {
            return self
        }
        return FontTable(
            defaultFont: PTYFontInfo(font: asciiFont.font.it_fontByAdding(toPointSize: delta)),
            nonAsciiFont: defaultNonASCIIFont.map {
                PTYFontInfo(font: $0.font.it_fontByAdding(toPointSize: delta))
            },
            config: config.map { ($0.stringValue, $0.byAddingPointSize(delta)) })
    }

    @objc(fontTableForProfile:)
    static func fontTable(forProfile profile: [AnyHashable : Any]) -> FontTable {
        let asciiFont = iTermProfilePreferences.font(forKey: KEY_NORMAL_FONT,
                                                     inProfile: profile)
        let nonASCIIFont = iTermProfilePreferences.font(forKey: KEY_NON_ASCII_FONT,
                                                        inProfile: profile)

        return FontTable(
            defaultFont: PTYFontInfo(font: asciiFont),
            nonAsciiFont: PTYFontInfo(font: nonASCIIFont),
            configString: iTermProfilePreferences.string(forKey: KEY_FONT_CONFIG, inProfile: profile))
    }

    @objc
    var uniqueIdentifier: [AnyObject] {
        return [asciiFont.font,
                asciiFont.boldVersion.font ?? NSNull(),
                asciiFont.italicVersion.font ?? NSNull(),
                asciiFont.boldItalicVersion ?? NSNull(),

                defaultNonASCIIFont?.font ?? NSNull(),
                defaultNonASCIIFont?.boldVersion.font ?? NSNull(),
                defaultNonASCIIFont?.italicVersion.font ?? NSNull(),
                defaultNonASCIIFont?.boldItalicVersion ?? NSNull(),

                configHash as NSString]
    }
}
