//
//  TerminalContentSnapshot.swift
//  iTerm2
//
//  Created by George Nachman on 2/16/22.
//

import Foundation

@objc(iTermTerminalContentSnapshot)
class TerminalContentSnapshot: NSObject, iTermTextDataSource {
    private let _width: Int32
    func width() -> Int32 {
        return _width
    }
    private let gridStartIndex: Int32
    private let _numberOfLines: Int32
    func numberOfLines() -> Int32 {
        return _numberOfLines
    }
    let lineBuffer: LineBuffer
    let cumulativeOverflow: Int64

    @objc
    init(lineBuffer: LineBufferReading,
         grid: VT100GridReading,
         cumulativeOverflow: Int64) {
        _width = grid.size.width;
        gridStartIndex = lineBuffer.numberOfWrappedLines(withWidth: _width)
        _numberOfLines = gridStartIndex + grid.size.height
        self.cumulativeOverflow = cumulativeOverflow
        self.lineBuffer = lineBuffer.copy()
        grid.appendLines(grid.size.height, to: self.lineBuffer)
        self.lineBuffer.commitLastBlock()
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        return lineBuffer.maybeScreenCharArray(forLine: line,
                                               width: _width,
                                               paddedTo: _width,
                                               eligibleForDWC: false) ?? ScreenCharArray.emptyLine(ofLength: _width)
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        return lineBuffer.wrappedLine(at: gridStartIndex + index, width: _width).padded(toLength: _width, eligibleForDWC: false)
    }

    func totalScrollbackOverflow() -> Int64 {
        return cumulativeOverflow
    }

    func externalAttributeIndex(forLine y: Int32) -> iTermExternalAttributeIndexReading? {
        let metadata = lineBuffer.metadata(forLineNumber: y, width: _width)
        return iTermImmutableMetadataGetExternalAttributesIndex(metadata)
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        let line = lineBuffer.wrappedLine(at: line, width: _width)
        return block(line)
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        lineBuffer.metadata(forLineNumber: lineNumber, width: _width)
    }

    func date(forLine line: Int32) -> Date? {
        let timestamp = lineBuffer.metadata(forLineNumber: line, width: _width).timestamp
        if timestamp == 0 {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    func commandMark(at coord: VT100GridCoord, 
                     mustHaveCommand: Bool,
                     range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> VT100ScreenMarkReading? {
        return nil
    }
}
