//
//  RailroadText.swift
//  iTerm2
//
//  Swift port of nodes/text.rs from the railroad crate 0.3.12
//  (https://github.com/lukaslueg/railroad), Copyright (c) 2018 Lukas Lueg,
//  MIT License.
//
//  RailroadTextWidth is a Swift port of lookup.rs and width_info.rs from the
//  unicode-width crate 0.2.3 (https://github.com/unicode-rs/unicode-width),
//  Copyright (c) 2015 The Rust Project Developers, MIT License.
//  See ThirdParty/Licenses.txt.
//

import Foundation

/// Terminal-column width of a string. Port of `UnicodeWidthStr::width` from
/// the unicode-width crate 0.2.3 (lookup.rs and width_info.rs, non-CJK), which
/// the railroad crate uses to size labels. Like the crate, it walks the string
/// backwards so emoji, ZWJ, and ligature sequences can see what follows them.
/// The per-code-point data is in RailroadWidthTable.swift.
enum RailroadTextWidth {
    static func columns(_ s: String) -> Int {
        var sum = 0
        var next = Info.default
        for c in s.unicodeScalars.reversed() {
            let (add, info) = widthInStr(c.value, next)
            sum += add
            next = info
        }
        return sum
    }

    struct Flag: OptionSet {
        let rawValue: UInt32
        static let ligatureTransparent = Flag(rawValue: 1 << 0)
        static let startsEmojiPresentationSeq = Flag(rawValue: 1 << 1)
        static let startsNonIdeographicTextPresentationSeq = Flag(rawValue: 1 << 2)
        static let emojiModifierBase = Flag(rawValue: 1 << 3)
        static let joiningGroupLam = Flag(rawValue: 1 << 4)
        static let transparentZeroWidth = Flag(rawValue: 1 << 5)
    }

    struct Properties {
        var width: Int
        var info: Info
        var flags: Flag
    }

    static func properties(_ cp: UInt32) -> Properties {
        // Find the last run starting at or before cp.
        var lo = 0
        var hi = runs.count
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if UInt32(runs[mid] >> 32) <= cp {
                lo = mid
            } else {
                hi = mid
            }
        }
        let packed = UInt32(truncatingIfNeeded: runs[lo])
        return Properties(width: Int(packed & 3),
                          info: Info(rawValue: UInt16((packed >> 2) & 0xFFFF)),
                          flags: Flag(rawValue: packed >> 18))
    }

    /// Port of `WidthInfo`.
    struct Info: Equatable {
        var rawValue: UInt16

        static let `default` = Info(rawValue: 0)
        static let lineFeed = Info(rawValue: 0b0000000000000001)
        static let emojiModifier = Info(rawValue: 0b0000000000000010)
        static let regionalIndicator = Info(rawValue: 0b0000000000000011)
        static let severalRegionalIndicator = Info(rawValue: 0b0000000000000100)
        static let emojiPresentation = Info(rawValue: 0b0000000000000101)
        static let zwjEmojiPresentation = Info(rawValue: 0b0001000000000110)
        static let vs16ZwjEmojiPresentation = Info(rawValue: 0b1001000000000110)
        static let keycapZwjEmojiPresentation = Info(rawValue: 0b0001000000000111)
        static let vs16KeycapZwjEmojiPresentation = Info(rawValue: 0b1001000000000111)
        static let regionalIndicatorZwjPresentation = Info(rawValue: 0b0000000000001001)
        static let evenRegionalIndicatorZwjPresentation = Info(rawValue: 0b0000000000001010)
        static let oddRegionalIndicatorZwjPresentation = Info(rawValue: 0b0000000000001011)
        static let tagEndZwjEmojiPresentation = Info(rawValue: 0b0000000000010000)
        static let tagD1EndZwjEmojiPresentation = Info(rawValue: 0b0000000000010001)
        static let tagD2EndZwjEmojiPresentation = Info(rawValue: 0b0000000000010010)
        static let tagD3EndZwjEmojiPresentation = Info(rawValue: 0b0000000000010011)
        static let tagA1EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011001)
        static let tagA2EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011010)
        static let tagA3EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011011)
        static let tagA4EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011100)
        static let tagA5EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011101)
        static let tagA6EndZwjEmojiPresentation = Info(rawValue: 0b0000000000011110)
        static let kiratRaiVowelSignE = Info(rawValue: 0b0000000000100000)
        static let kiratRaiVowelSignAI = Info(rawValue: 0b0000000000100001)
        static let variationSelector1_2_or_3 = Info(rawValue: 0b0000001000000000)
        static let variationSelector15 = Info(rawValue: 0b0100000000000000)
        static let variationSelector16 = Info(rawValue: 0b1000000000000000)
        static let joiningGroupAlef = Info(rawValue: 0b0011000011111111)
        static let zwjHebrewLetterLamed = Info(rawValue: 0b0011110000000000)
        static let zwjBugineseLetterYa = Info(rawValue: 0b0011110000000001)
        static let bugineseVowelSignIZwjLetterYa = Info(rawValue: 0b0011110000000010)
        static let tifinaghConsonant = Info(rawValue: 0b0011100000000011)
        static let zwjTifinaghConsonant = Info(rawValue: 0b0011110000000011)
        static let tifinaghJoinerConsonant = Info(rawValue: 0b0011110000000100)
        static let lisuToneLetterMyaNaJeu = Info(rawValue: 0b0011110000000101)
        static let zwjOldTurkicLetterOrkhonI = Info(rawValue: 0b0011110000000110)
        static let khmerCoengEligibleLetter = Info(rawValue: 0b0011110000000111)

        private static let ligatureTransparentMask: UInt16 = 0b0010_0000_0000_0000
        private var hasLigatureTransparentMask: Bool {
            rawValue & Self.ligatureTransparentMask == Self.ligatureTransparentMask
        }

        var isLigatureTransparent: Bool { rawValue & 0b0000_1000_0000_0000 != 0 }
        func settingZwjBit() -> Info { Info(rawValue: rawValue | 0b0000_0100_0000_0000) }

        var isEmojiPresentation: Bool { rawValue & Self.variationSelector16.rawValue != 0 }
        var isZwjEmojiPresentation: Bool { rawValue & 0b1011_0000_0000_0000 == 0b1001_0000_0000_0000 }
        func settingEmojiPresentation() -> Info {
            // Rust's `a | b & !c & !d` parses as `a | (b & !c & !d)`, which is `a | b` here.
            if hasLigatureTransparentMask || rawValue & 0b1001_0000_0000_0000 == 0b0001_0000_0000_0000 {
                return Info(rawValue: rawValue | Self.variationSelector16.rawValue)
            }
            return .variationSelector16
        }
        func unsettingEmojiPresentation() -> Info {
            hasLigatureTransparentMask ? Info(rawValue: rawValue & ~Self.variationSelector16.rawValue) : .default
        }

        var isTextPresentation: Bool { rawValue & Self.variationSelector15.rawValue != 0 }
        func settingTextPresentation() -> Info {
            hasLigatureTransparentMask ? Info(rawValue: rawValue | Self.variationSelector15.rawValue) : .variationSelector15
        }
        func unsettingTextPresentation() -> Info {
            Info(rawValue: rawValue & ~Self.variationSelector15.rawValue)
        }

        var isVS1_2_3: Bool { rawValue & Self.variationSelector1_2_or_3.rawValue != 0 }
        func settingVS1_2_3() -> Info {
            hasLigatureTransparentMask ? Info(rawValue: rawValue | Self.variationSelector1_2_or_3.rawValue) : .variationSelector1_2_or_3
        }
        func unsettingVS1_2_3() -> Info {
            Info(rawValue: rawValue & ~Self.variationSelector1_2_or_3.rawValue)
        }
    }

    private static let regionalIndicators: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF
    private static let tagLetters: ClosedRange<UInt32> = 0xE0061...0xE007A
    private static let tagDigits: ClosedRange<UInt32> = 0xE0030...0xE0039

    private static func isTifinaghConsonant(_ c: UInt32) -> Bool {
        (0x2D31...0x2D65).contains(c) || c == 0x2D6F
    }

    /// Port of `width_in_generic::<false>`: the width `c` adds given what
    /// follows it, and what it tells the character before it.
    private static func widthInStr(_ c: UInt32, _ nextInfo: Info) -> (Int, Info) {
        var next = nextInfo
        if next.isEmojiPresentation {
            if properties(c).flags.contains(.startsEmojiPresentationSeq) {
                return (next.isZwjEmojiPresentation ? 0 : 2, .emojiPresentation)
            }
            next = next.unsettingEmojiPresentation()
        }

        if c <= 0xA0 {
            if c == 0x0A {
                return (1, .lineFeed)
            }
            if c == 0x0D && next == .lineFeed {
                return (0, .default)
            }
            return (1, .default)
        }

        if next != .default {
            if c == 0xFE0F {
                return (0, next.settingEmojiPresentation())
            }
            if c == 0xFE01 {
                return (0, next.settingVS1_2_3())
            }
            if c == 0xFE0E {
                return (0, next.settingTextPresentation())
            }
            if next.isTextPresentation {
                if properties(c).flags.contains(.startsNonIdeographicTextPresentationSeq) {
                    return (1, .default)
                }
                next = next.unsettingTextPresentation()
            }
            if next.isVS1_2_3 {
                if [0x2018, 0x2019, 0x201C, 0x201D].contains(c) {
                    return (2, .default)
                }
                next = next.unsettingVS1_2_3()
            }
            if next.isLigatureTransparent {
                if c == 0x200D {
                    return (0, next.settingZwjBit())
                }
                if properties(c).flags.contains(.ligatureTransparent) {
                    return (0, next)
                }
            }
            if let result = sequenceWidth(c, next) {
                return result
            }
        }

        let props = properties(c)
        return (props.width, props.info)
    }

    /// The `match (next_info, c)` arms of `width_in_generic` that apply
    /// without the cjk feature.
    private static func sequenceWidth(_ c: UInt32, _ next: Info) -> (Int, Info)? {
        let flags = properties(c).flags
        switch next {
        case .joiningGroupAlef:
            // Arabic Lam-Alef ligature
            if flags.contains(.joiningGroupLam) {
                return (0, .default)
            }
            if flags.contains(.transparentZeroWidth) {
                return (0, .joiningGroupAlef)
            }
        case .zwjHebrewLetterLamed where c == 0x05D0:
            return (0, .default)
        case .khmerCoengEligibleLetter where c == 0x17D2:
            return (-1, .default)
        case .zwjBugineseLetterYa where c == 0x1A17:
            return (0, .bugineseVowelSignIZwjLetterYa)
        case .bugineseVowelSignIZwjLetterYa where c == 0x1A15:
            return (0, .default)
        case .tifinaghConsonant where c == 0x2D7F:
            return (1, .tifinaghJoinerConsonant)
        case .zwjTifinaghConsonant:
            if c == 0x2D7F {
                return (1, .tifinaghJoinerConsonant)
            }
            if isTifinaghConsonant(c) {
                return (0, .default)
            }
        case .tifinaghJoinerConsonant where isTifinaghConsonant(c):
            return (-1, .default)
        case .lisuToneLetterMyaNaJeu where (0xA4F8...0xA4FB).contains(c):
            return (0, .default)
        case .zwjOldTurkicLetterOrkhonI where c == 0x10C32:
            return (0, .default)
        default:
            break
        }

        // Emoji modifier
        if next == .emojiModifier && flags.contains(.emojiModifierBase) {
            return (0, .emojiPresentation)
        }
        // Regional indicator
        if (next == .regionalIndicator || next == .severalRegionalIndicator) && regionalIndicators.contains(c) {
            return (1, .severalRegionalIndicator)
        }
        // ZWJ emoji
        if c == 0x200D && [.emojiPresentation, .severalRegionalIndicator, .evenRegionalIndicatorZwjPresentation,
                           .oddRegionalIndicatorZwjPresentation, .emojiModifier].contains(next) {
            return (0, .zwjEmojiPresentation)
        }
        if next == .zwjEmojiPresentation && c == 0x20E3 {
            return (0, .keycapZwjEmojiPresentation)
        }
        if next == .vs16ZwjEmojiPresentation && flags.contains(.startsEmojiPresentationSeq) {
            return (0, .emojiPresentation)
        }
        if next == .vs16KeycapZwjEmojiPresentation && ((0x30...0x39).contains(c) || c == 0x23 || c == 0x2A) {
            return (0, .emojiPresentation)
        }
        if next == .zwjEmojiPresentation && regionalIndicators.contains(c) {
            return (1, .regionalIndicatorZwjPresentation)
        }
        if (next == .regionalIndicatorZwjPresentation || next == .oddRegionalIndicatorZwjPresentation)
            && regionalIndicators.contains(c) {
            return (-1, .evenRegionalIndicatorZwjPresentation)
        }
        if next == .evenRegionalIndicatorZwjPresentation && regionalIndicators.contains(c) {
            return (3, .oddRegionalIndicatorZwjPresentation)
        }
        if next == .zwjEmojiPresentation && (0x1F3FB...0x1F3FF).contains(c) {
            return (0, .emojiModifier)
        }
        if next == .zwjEmojiPresentation && c == 0xE007F {
            return (0, .tagEndZwjEmojiPresentation)
        }
        if tagLetters.contains(c) {
            let successors: [(Info, Info)] = [
                (.tagEndZwjEmojiPresentation, .tagA1EndZwjEmojiPresentation),
                (.tagA1EndZwjEmojiPresentation, .tagA2EndZwjEmojiPresentation),
                (.tagA2EndZwjEmojiPresentation, .tagA3EndZwjEmojiPresentation),
                (.tagA3EndZwjEmojiPresentation, .tagA4EndZwjEmojiPresentation),
                (.tagA4EndZwjEmojiPresentation, .tagA5EndZwjEmojiPresentation),
                (.tagA5EndZwjEmojiPresentation, .tagA6EndZwjEmojiPresentation),
            ]
            if let match = successors.first(where: { $0.0 == next }) {
                return (0, match.1)
            }
        }
        if tagDigits.contains(c) {
            if [.tagEndZwjEmojiPresentation, .tagA1EndZwjEmojiPresentation, .tagA2EndZwjEmojiPresentation,
                .tagA3EndZwjEmojiPresentation, .tagA4EndZwjEmojiPresentation].contains(next) {
                return (0, .tagD1EndZwjEmojiPresentation)
            }
            if next == .tagD1EndZwjEmojiPresentation {
                return (0, .tagD2EndZwjEmojiPresentation)
            }
            if next == .tagD2EndZwjEmojiPresentation {
                return (0, .tagD3EndZwjEmojiPresentation)
            }
        }
        if c == 0x1F3F4 && [.tagA3EndZwjEmojiPresentation, .tagA4EndZwjEmojiPresentation,
                            .tagA5EndZwjEmojiPresentation, .tagA6EndZwjEmojiPresentation,
                            .tagD3EndZwjEmojiPresentation].contains(next) {
            return (0, .emojiPresentation)
        }
        if next == .zwjEmojiPresentation && properties(c).info == .emojiPresentation {
            return (0, .emojiPresentation)
        }

        if next == .kiratRaiVowelSignE {
            switch c {
            case 0x16D63: return (0, .default)
            case 0x16D67: return (0, .kiratRaiVowelSignAI)
            case 0x16D68: return (1, .kiratRaiVowelSignE)
            case 0x16D69: return (0, .default)
            default: break
            }
        }
        if next == .kiratRaiVowelSignAI && c == 0x16D63 {
            return (0, .default)
        }
        return nil
    }
}

/// A rounded box with literal text. Port of `Terminal`.
struct RailroadTerminal: RailroadNode {
    var label: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 11 }
    var height: Int { entryHeight * 2 }
    var width: Int { Railroad.textWidth(label) * 8 + 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.group(class: "terminal", attributes: attributes) {
            out.textBox(x: x, y: y, width: width, height: height, entryHeight: entryHeight, label: label, rounded: true)
        }
    }
}

/// A square box naming another rule. Port of `NonTerminal`.
struct RailroadNonTerminal: RailroadNode {
    var label: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 11 }
    var height: Int { entryHeight * 2 }
    var width: Int { Railroad.textWidth(label) * 8 + 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.group(class: "nonterminal", attributes: attributes) {
            out.textBox(x: x, y: y, width: width, height: height, entryHeight: entryHeight, label: label, rounded: false)
        }
    }
}

/// Free text without a box. Port of `Comment`.
struct RailroadComment: RailroadNode {
    var text: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 10 }
    var height: Int { 20 }
    var width: Int { Railroad.textWidth(text) * 7 + 10 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let tag = out.startElement("text")
        tag.attrs(attributes)
        tag.attr("class", "comment")
        tag.attr("x", x + width / 2)
        tag.attr("y", y + 15)
        tag.finish()
        out.writeText(text)
        out.endElement("text")
    }
}
