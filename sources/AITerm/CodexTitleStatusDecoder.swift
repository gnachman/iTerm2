//
//  CodexTitleStatusDecoder.swift
//  iTerm2SharedARC
//
//  Pure decoder for Codex CLI's working-state signal.
//
//  Codex (OpenAI) emits its working/idle state through the terminal title
//  (OSC 0/1/2), not through iTerm's OSC 21337 status protocol. When working,
//  it prefixes the title with a single braille-spinner glyph followed by a
//  space, e.g.
//
//    "⠙ iTerm2"  (working — spinner frame)
//    "iTerm2"    (idle, or blocked on the user — spinner stops)
//
//  Captured frames from a real Codex 0.134.0 session were ⠸ ⠏ ⠙ ⠹ ⠇, which
//  matches the standard Rust `indicatif` "dots" spinner set. To stay tolerant
//  of future Codex versions picking a different indicatif spinner that still
//  lives in the same Unicode block, this decoder accepts any glyph in
//  U+2800..U+28FF (Braille Patterns). False positives are unlikely given the
//  caller gates on the foreground job being `codex`.
//
//  This decoder reports whether a given title string indicates the active
//  working state. It does not look at process ancestry; the caller gates
//  on that.
//

import Foundation

@objc(iTermCodexTitleStatusDecoder)
final class CodexTitleStatusDecoder: NSObject {
    /// Returns true iff the title indicates Codex is actively working
    /// (first character is a Braille Patterns spinner glyph followed by a space).
    @objc(isWorkingTitle:)
    static func isWorkingTitle(_ title: String) -> Bool {
        var scalars = title.unicodeScalars.makeIterator()
        guard let first = scalars.next() else { return false }
        guard (0x2800...0x28FF).contains(first.value) else { return false }
        guard let second = scalars.next(), second == " " else { return false }
        return true
    }
}
