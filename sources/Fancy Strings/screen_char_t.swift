//  screen_char_t.swift
//  StyleMap
//
//  Created by George Nachman on 4/7/25.
//

import AppKit

extension VT100TerminalColorValue: Equatable {
    public static func == (lhs: VT100TerminalColorValue, rhs: VT100TerminalColorValue) -> Bool {
        return lhs.red == rhs.red && lhs.green == rhs.green && lhs.blue == rhs.blue && lhs.mode == rhs.mode
    }
}

extension screen_char_t {
    var underlineStyle: VT100UnderlineStyle {
        get {
            return VT100UnderlineStyle(rawValue: underlineStyle0 | (underlineStyle1 << 2)) ?? .single
        }
        set {
            underlineStyle0 = newValue.rawValue & 3
            underlineStyle1 = (newValue.rawValue >> 2) & 1
        }
    }
}

extension VT100UnderlineStyle {
    var part0: UInt32 {
        rawValue & 3
    }
    var part1: UInt32 {
        (rawValue >> 2) & 1
    }
}
