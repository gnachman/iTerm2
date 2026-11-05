//
//  PromptRepaintLookahead.swift
//  iTerm2
//
//  Created by George Nachman on 11/2/26.
//

import Foundation

// Some line editors (reedline, used by nushell) repaint the whole prompt line on every keystroke:
// hide the cursor, erase, OSC 133;A, the prompt, OSC 133;B, the command, show the cursor. They send
// it in one write, so when the cursor is hidden the rest of the repaint has usually been parsed
// already and is waiting in the token queue. A sync partway through draws the line with the command
// erased, which makes typing blink.
//
// This decides from those queued tokens whether hiding the cursor begins such a repaint and whether
// the cursor will be shown again at its end. Only then is it safe to keep drawing the screen as it
// was until the cursor comes back.
enum PromptRepaintLookahead {
    // A reasonable bound on how far ahead to look. A prompt repaint is a few dozen tokens.
    static let tokenLimit = 1024

    // `enumerate` calls its argument with each token in order until it returns false.
    static func repaintShowsCursor(enumeratingWith enumerate: ((VT100Token) -> Bool) -> Void) -> Bool {
        var scanner = Scanner()
        var result = false
        enumerate { token in
            switch scanner.consider(token) {
            case .undecided:
                return true
            case .proven:
                result = true
                return false
            case .disproven:
                return false
            }
        }
        return result
    }

    private struct Scanner {
        enum Verdict {
            case undecided
            case proven
            case disproven
        }

        private var sawPromptStart = false

        mutating func consider(_ token: VT100Token) -> Verdict {
            switch token.type {
            case XTERMCC_FINAL_TERM:
                if Self.isCommandBoundary(token.string) {
                    // A command ran or finished, so this is the next prompt, not a repaint of the
                    // command line.
                    return .disproven
                }
                if Self.isPromptStart(token.string) {
                    sawPromptStart = true
                }
                return .undecided
            case VT100CSI_DECSET:
                guard token.csiParametersContain(25) else {
                    return .undecided
                }
                // Shown before the prompt was redrawn means this isn't a prompt repaint.
                return sawPromptStart ? .proven : .disproven
            case VT100CSI_DECRST:
                guard token.csiParametersContain(25) else {
                    return .undecided
                }
                // Before the prompt start this is the hide being executed. After it, the cursor is
                // hidden again before ever being shown, so this isn't one self-contained repaint.
                return sawPromptStart ? .disproven : .undecided
            default:
                return .undecided
            }
        }

        private static func isPromptStart(_ string: String?) -> Bool {
            return isCommand("A", string)
        }

        private static func isCommandBoundary(_ string: String?) -> Bool {
            return isCommand("C", string) || isCommand("D", string)
        }

        private static func isCommand(_ command: String, _ string: String?) -> Bool {
            guard let string else {
                return false
            }
            return string == command || string.hasPrefix(command + ";")
        }
    }
}
