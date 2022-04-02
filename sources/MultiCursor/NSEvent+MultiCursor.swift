//
//  NSEvent+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 4/1/22.
//

import AppKit

extension NSEvent {
    var onlyControlAndShiftPressed: Bool {
        return modifierFlags.intersection([.command, .option, .shift, .control]) == [.control, .shift]
    }
}
