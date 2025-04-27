//  screen_char_t.swift
//  StyleMap
//
//  Created by George Nachman on 4/7/25.
//

import AppKit

struct UnifiedCharacterStyle: Equatable {
    var sct = screen_char_t()
    var underlineColor: VT100TerminalColorValue?
    var blockIDs: String?
    var controlCode: Int32?
    var url: iTermURL?

    var externalAttributes: iTermExternalAttribute? {
        if underlineColor == nil &&
            blockIDs == nil &&
            controlCode == nil &&
            url == nil {
            return nil
        }
        return iTermExternalAttribute(havingUnderlineColor: underlineColor != nil,
                                      underlineColor: underlineColor ?? VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: blockIDs,
                                      controlCode: controlCode.map { NSNumber(value: $0)})
    }
}

extension VT100TerminalColorValue: Equatable {
    public static func == (lhs: VT100TerminalColorValue, rhs: VT100TerminalColorValue) -> Bool {
        return lhs.red == rhs.red && lhs.green == rhs.green && lhs.blue == rhs.blue && lhs.mode == rhs.mode
    }
}
