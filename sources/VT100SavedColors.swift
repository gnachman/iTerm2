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
    @objcMembers
    @objc(VT100SavedColorsSlot)
    class Slot: NSObject, Codable {
        private static let numberOfIndexedColors = 256

        private let _text: CodableColor
        var text: NSColor { return _text.color }

        private let _background: CodableColor
        var background: NSColor { return _background.color }

        private let _selectionText: CodableColor
        var selectionText: NSColor { return _selectionText.color }

        private let _selectionBackground: CodableColor
        var selectionBackground: NSColor { return _selectionBackground.color }

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
        override var debugDescription: String {
            return "<Slot text=\(text) background=\(background) selectionText=\(selectionText) selectionBackground=\(selectionBackground) indexedColors=\(indexedColors.map { $0.debugDescription }.joined(separator: ","))>"
        }

        @objc(initWithTextColor:backgroundColor:selectionTextColor:selectionBackgroundColor:indexedColorProvider:)
        init(text: NSColor,
             background: NSColor,
             selectionText: NSColor,
             selectionBackground: NSColor,
             indexedColorProvider: (Int) -> (NSColor)) {
            let indexedColors = (0..<Self.numberOfIndexedColors).map {
                CodableColor(indexedColorProvider($0))
            }
            _text = CodableColor(text)
            _background = CodableColor(background)
            _selectionText = CodableColor(selectionText)
            _selectionBackground = CodableColor(selectionBackground)
            _indexedColors = indexedColors
        }

        @objc var plist: Data? {
            return try? PropertyListEncoder().encode(self)
        }

        @objc static func from(data: Data?) -> Slot? {
            guard let data = data else {
                return nil
            }
            return try? PropertyListDecoder().decode(self, from: data)
        }
    }
}
