//
//  OffscreenCommandLine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/15/23.
//

import Foundation

fileprivate func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
    return min(maxValue, max(minValue, value))
}

struct OffscreenCommandLine {
    var characters: ScreenCharArray
    var absoluteLineNumber: Int64
    var date: Date
    private var color: NSColor? = nil

    mutating func setBackgroundColor(_ color: NSColor) {
        if color == self.color {
            return
        }
        self.color = color
        let (red, green, blue) = (UInt32(color.redComponent * 255),
                                  UInt32(color.greenComponent * 255),
                                  UInt32(color.blueComponent * 255))
        var mutableData = characters.mutableLineData()
        var bufferPointer = UnsafeMutableBufferPointer<screen_char_t>(start: mutableData.mutableBytes.assumingMemoryBound(to: screen_char_t.self),
                                                                      count: Int(characters.length))
        for i in 0..<characters.length {
            bufferPointer[Int(i)].backgroundColorMode = UInt32(ColorMode24bit.rawValue)
            bufferPointer[Int(i)].backgroundColor = clamp(red, min: 0, max: 255)
            bufferPointer[Int(i)].bgGreen = clamp(green, min: 0, max: 255)
            bufferPointer[Int(i)].bgBlue = clamp(blue, min: 0, max: 255)
        }
        characters = ScreenCharArray(data: mutableData as Data,
                                     metadata: characters.metadata,
                                     continuation: characters.continuation)
    }

    init(characters: ScreenCharArray,
         absoluteLineNumber: Int64,
         date: Date) {
        self.characters = characters
        self.absoluteLineNumber = absoluteLineNumber
        self.date = date
    }

}

@objc class iTermOffscreenCommandLine: NSObject {
    private var state: OffscreenCommandLine
    @objc var characters: ScreenCharArray { state.characters }
    @objc var absoluteLineNumber: Int64 { state.absoluteLineNumber }
    @objc var date: Date { state.date }

    @objc
    init(characters: ScreenCharArray,
         absoluteLineNumber: Int64,
         date: Date){
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        var temp = ScreenCharArray(data: characters.mutableLineData() as Data,
                                   metadata: iTermMetadataMakeImmutable(iTermMetadataDefault()),
                                   continuation: continuation)
        state = OffscreenCommandLine(characters: temp,
                                     absoluteLineNumber: absoluteLineNumber,
                                     date: date)
    }

    @objc func setBackgroundColor(_ color: NSColor) {
        state.setBackgroundColor(color)
    }
}
