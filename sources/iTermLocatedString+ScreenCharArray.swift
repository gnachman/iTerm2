//
//  iTermLocatedString+ScreenCharArray.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/8/26.
//

import Foundation

extension iTermLocatedString {
    /// Build a located string from a `ScreenCharArray`, mapping each string
    /// character to its grid x coordinate on row `y`.  The conversion mirrors
    /// `ScreenCharArray.stringValue`: images, DWC_RIGHT, and other PUA
    /// characters are skipped, and a null terminates the string.
    @objc
    convenience init(screenCharArray sca: ScreenCharArray, y: Int32 = 0) {
        self.init()
        let line = sca.line
        let privateRange = unichar(ITERM2_PRIVATE_BEGIN)...unichar(ITERM2_PRIVATE_END)
        for i in 0..<Int(sca.length) {
            var c = line[i]
            if c.image != 0 {
                continue
            }
            if c.complexChar == 0 {
                if privateRange.contains(c.code) {
                    continue
                }
                if c.code == 0 {
                    break
                }
            }
            if let str = ScreenCharToStr(&c) {
                appendString(str, at: VT100GridCoord(x: Int32(i), y: y))
            }
        }
    }
}
