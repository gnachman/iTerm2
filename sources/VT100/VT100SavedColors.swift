//
//  VT100SavedColors.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/6/21.
//

import Foundation

@objcMembers
@objc(VT100SavedColors)
final class SavedColors: NSObject {
    static let capacity = 256
    private(set) var used = 0
    private(set) var last = 0
    private(set) var slots = [Int: Slot]()

    override var debugDescription: String {
        return "<\(Self.self): \(it_addressString) \(repDescr)>"
    }

    var repDescr: String {
        let slotStrings = slots.keys.sorted().map { (i: Int) -> String in
            let description = slots[i]?.debugDescription ?? "(nil)"
            return "\(i): \(description)"
        }
        let joined = slotStrings.joined(separator: " ")
        return "used=\(used) last=\(last) slots=[\(joined)]"
    }

    func push(_ slot: Slot) {
        set(slot, at: used)
        /// xterm only updates its `last` variable on a regular push, not on direct assignment to a slot.
        /// I'm not thrilled about this, but I think it's better to replicate the bug than create a fork.
        last = max(last, used)
    }

    @objc(setSlot:at:) func set(_ slot: Slot, at index: Int) {
        guard index >= 0 && index < Self.capacity else {
            return
        }
        slots[index] = slot
        used = index + 1
    }

    func pop() -> Slot? {
        return slot(used - 1)
    }

    @objc(slotAt:) func slot(_ index: Int) -> Slot? {
        guard index >= 0 && index < Self.capacity else {
            return nil
        }
        guard let slot = slots[index] else {
            return nil
        }
        /// This is intentional. xterm updates `used` on pop, even when directly accessing by index.
        used = index
        return slot
    }

    func peek(_ index: Int) -> Slot? {
        guard index >= 0 && index < Self.capacity else {
            return nil
        }
        return slots[index]
    }
}

extension SavedColors: Encodable {
    var plist: Data? {
        return try? PropertyListEncoder().encode(self)
    }
}

extension SavedColors: Decodable {
    static func from(data: Data?) -> SavedColors? {
        guard let data = data else {
            return nil
        }
        return try? PropertyListDecoder().decode(self, from: data)
    }
}

extension SavedColors {
    typealias Slot = SavedColorsSlot
}

@objcMembers
@objc(VT100SavedColorsSlot)
public class SavedColorsSlot: NSObject, Codable {
    private static let numberOfIndexedColors = 256

    // The four colors are nil when the color map lacked them, which happens when a profile's
    // value for one is not a color dictionary (the map then has no entry for its key).
    private let _text: CodableColor?
    var text: NSColor? { return _text?.color }

    private let _background: CodableColor?
    var background: NSColor? { return _background?.color }

    private let _selectionText: CodableColor?
    var selectionText: NSColor? { return _selectionText?.color }

    private let _selectionBackground: CodableColor?
    var selectionBackground: NSColor? { return _selectionBackground?.color }

    private let _indexedColors: [CodableColor]
    var indexedColors: [NSColor] { return _indexedColors.map { $0.color } }

    @objc var indexedColorsDictionary: [NSNumber: NSColor] {
        var result = [NSNumber: NSColor]()
        for (i, color) in _indexedColors.enumerated() {
            let n = NSNumber(integerLiteral: i + Int(kColorMap8bitBase))
            result[n] = color.color
        }
        return result
    }
    override public var debugDescription: String {
        // A present color prints as it did when these were non-optional.
        func describe(_ color: NSColor?) -> String {
            return color.map { String(describing: $0) } ?? "nil"
        }
        return "<Slot text=\(describe(text)) background=\(describe(background)) selectionText=\(describe(selectionText)) selectionBackground=\(describe(selectionBackground)) indexedColors=\(indexedColors.map { $0.debugDescription }.joined(separator: ","))>"
    }

    @objc(initWithTextColor:backgroundColor:selectionTextColor:selectionBackgroundColor:indexedColorProvider:)
    init(text: NSColor?,
         background: NSColor?,
         selectionText: NSColor?,
         selectionBackground: NSColor?,
         indexedColorProvider: (Int) -> (NSColor)) {
        let indexedColors = (0..<Self.numberOfIndexedColors).map {
            CodableColor(indexedColorProvider($0))
        }
        _text = text.map { CodableColor($0) }
        _background = background.map { CodableColor($0) }
        _selectionText = selectionText.map { CodableColor($0) }
        _selectionBackground = selectionBackground.map { CodableColor($0) }
        _indexedColors = indexedColors
    }

    // The keys, order and form of what the synthesized conformance wrote when the colors were
    // non-optional. Stored slots must stay readable by other versions (stored-state.md).
    private enum CodingKeys: String, CodingKey {
        case _text
        case _background
        case _selectionText
        case _selectionBackground
        case _indexedColors
    }

    // Every color is required, as before, so a slot written with a missing color (see
    // MissingColor) still fails to decode.
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _text = try container.decode(CodableColor.self, forKey: ._text)
        _background = try container.decode(CodableColor.self, forKey: ._background)
        _selectionText = try container.decode(CodableColor.self, forKey: ._selectionText)
        _selectionBackground = try container.decode(CodableColor.self, forKey: ._selectionBackground)
        _indexedColors = try container.decode([CodableColor].self, forKey: ._indexedColors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(_text, forKey: ._text, in: &container)
        try Self.encode(_background, forKey: ._background, in: &container)
        try Self.encode(_selectionText, forKey: ._selectionText, in: &container)
        try Self.encode(_selectionBackground, forKey: ._selectionBackground, in: &container)
        try container.encode(_indexedColors, forKey: ._indexedColors)
    }

    private static func encode(_ color: CodableColor?,
                               forKey key: CodingKeys,
                               in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if let color {
            try container.encode(color, forKey: key)
        } else {
            try container.encode(MissingColor(), forKey: key)
        }
    }

    // What a missing color has always been written as: CodableColor's fallback form holding the
    // keyed archive of a nil color, which has nothing in it. It does not decode.
    private struct MissingColor: Encodable {
        enum CodingKeys: String, CodingKey {
            case fallback
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(NSKeyedArchiver(requiringSecureCoding: true).encodedData,
                                 forKey: .fallback)
        }
    }

    @objc var plist: Data? {
        return try? PropertyListEncoder().encode(self)
    }

    @objc static func from(data: Data?) -> SavedColorsSlot? {
        guard let data = data else {
            return nil
        }
        return try? PropertyListDecoder().decode(self, from: data)
    }
}
