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
