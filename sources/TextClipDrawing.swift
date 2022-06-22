//
//  TextClipDrawing.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/20/22.
//

import Foundation
import AppKit

// Draw a bit of text for the find indicator. Exactly matches the legacy drawing but all text is
// black and it has a yellow background with a bit of extra yellow padding.
@objc(iTermTextClipDrawing)
class TextClipDrawing: NSObject {
    @objc static let padding = NSSize(width: 4, height: 2.5)

    private let drawingHelper: iTermTextDrawingHelper
    private let colorMap: iTermColorMap
    private let lines: [ScreenCharArray]
    private let originalDelegate: iTermTextDrawingHelperDelegate
    private let firstLine: Int32
    private let numHistoryLines: Int32
    private let width: Int32
    private let emptyLine: ScreenCharArray
    private var matches = [Data]()

    // Saves and restores iTermTextDrawingHelper state.
    private struct SavedState {
        var showStripes: Bool
        var cursorBlinking: Bool
        var excess: Double
        var selection: iTermSelection?
        var hasBackgroundImage: Bool
        var cursorGuideColor: NSColor?
        var cursorCoord: VT100GridCoord
        var cursorVisible: Bool
        var reverseVideo: Bool
        var textViewIsActiveSession: Bool
        var isInKeyWindow: Bool
        var shouldDrawFilledInCursor: Bool
        var isFrontTextView: Bool
        var transparencyAlpha: Double
        var drawMarkIndicators: Bool
        var showSearchingCursor: Bool
        var copyMode: Bool
        var passwordInput: Bool
        var shouldShowTimestamps: Bool
        var colorMap: iTermColorMapReading
        var delegate: iTermTextDrawingHelperDelegate?

        private init(_ helper: iTermTextDrawingHelper) {
            showStripes = helper.showStripes
            cursorBlinking = helper.cursorBlinking
            excess = helper.excess
            selection = helper.selection
            hasBackgroundImage = helper.hasBackgroundImage
            cursorGuideColor = helper.cursorGuideColor
            cursorCoord = helper.cursorCoord
            cursorVisible = helper.cursorVisible
            reverseVideo = helper.reverseVideo
            textViewIsActiveSession = helper.textViewIsActiveSession
            isInKeyWindow = helper.isInKeyWindow
            shouldDrawFilledInCursor = helper.shouldDrawFilledInCursor
            isFrontTextView = helper.isFrontTextView
            transparencyAlpha = helper.transparencyAlpha
            drawMarkIndicators = helper.drawMarkIndicators
            showSearchingCursor = helper.showSearchingCursor
            copyMode = helper.copyMode
            passwordInput = helper.passwordInput
            shouldShowTimestamps = helper.shouldShowTimestamps
            colorMap = helper.colorMap
            delegate = helper.delegate
        }

        private func restore(_ helper: iTermTextDrawingHelper) {
            helper.showStripes = showStripes
            helper.cursorBlinking = cursorBlinking
            helper.excess = excess
            helper.selection = selection
            helper.hasBackgroundImage = hasBackgroundImage
            helper.cursorGuideColor = cursorGuideColor
            helper.cursorCoord = cursorCoord
            helper.cursorVisible = cursorVisible
            helper.reverseVideo = reverseVideo
            helper.textViewIsActiveSession = textViewIsActiveSession
            helper.isInKeyWindow = isInKeyWindow
            helper.shouldDrawFilledInCursor = shouldDrawFilledInCursor
            helper.isFrontTextView = isFrontTextView
            helper.transparencyAlpha = transparencyAlpha
            helper.drawMarkIndicators = drawMarkIndicators
            helper.showSearchingCursor = showSearchingCursor
            helper.copyMode = copyMode
            helper.passwordInput = passwordInput
            helper.shouldShowTimestamps = shouldShowTimestamps
            helper.colorMap = colorMap
            helper.delegate = delegate
        }

        static func perform(_ helper: iTermTextDrawingHelper, block: () -> ()) {
            let state = SavedState(helper)
            block()
            state.restore(helper)
        }
    }

    @objc
    static func drawClip(drawingHelper: iTermTextDrawingHelper,
                         numHistoryLines: Int32,
                         range: VT100GridCoordRange) {
        guard let delegate = drawingHelper.delegate else {
            return
        }
        let width = drawingHelper.gridSize.width
        var lines = (range.start.y...range.end.y).map { i -> ScreenCharArray in
            let line = delegate.drawingHelperLine(at: i)
            let sca = ScreenCharArray(copyOfLine: line,
                                      length: width,
                                      continuation: line[Int(width)])
            return sca
        }
        lines[0] = lines[0].copy(byZeroingRange: NSRange(0..<range.start.x))
        lines[lines.count - 1] = lines[lines.count - 1].copy(byZeroingRange: NSRange(range.end.x..<width))
        SavedState.perform(drawingHelper) {
            let instance = TextClipDrawing(drawingHelper: drawingHelper,
                                           firstLine: range.start.y,
                                           numHistoryLines: numHistoryLines,
                                           lines: lines)
            instance.draw(range: range)
        }
    }

    private init(drawingHelper: iTermTextDrawingHelper,
                 firstLine: Int32,
                 numHistoryLines: Int32,
                 lines: [ScreenCharArray]) {
        self.drawingHelper = drawingHelper
        self.firstLine = firstLine
        self.numHistoryLines = numHistoryLines
        self.lines = lines
        width = drawingHelper.gridSize.width
        emptyLine = ScreenCharArray.emptyLine(ofLength: width)

        colorMap = iTermColorMap()
        colorMap.mutingAmount = 0
        colorMap.dimmingAmount = 0
        colorMap.minimumContrast = 0
        let black = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
        let yellow = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
        colorMap.setColor(black, forKey: kColorMapForeground)
        colorMap.setColor(yellow, forKey: kColorMapBackground)
        colorMap.setColor(black, forKey: kColorMapUnderline)
        colorMap.setColor(black, forKey: kColorMapLink)
        colorMap.setColor(black, forKey: kColorMapSelectedText)
        colorMap.setColor(yellow, forKey: kColorMapSelection)
        colorMap.setColor(black, forKey: kColorMapCursorText)
        colorMap.setColor(yellow, forKey: kColorMapCursor)

        drawingHelper.showStripes = false
        drawingHelper.cursorBlinking = false
        drawingHelper.excess = 0
        drawingHelper.selection = nil
        drawingHelper.hasBackgroundImage = false
        drawingHelper.cursorGuideColor = nil
        drawingHelper.cursorCoord = VT100GridCoord(x: 0, y: 0)
        drawingHelper.cursorVisible = false
        drawingHelper.reverseVideo = false
        drawingHelper.textViewIsActiveSession = true
        drawingHelper.isInKeyWindow = true
        drawingHelper.shouldDrawFilledInCursor = true
        drawingHelper.isFrontTextView = true
        drawingHelper.transparencyAlpha = 1.0
        drawingHelper.drawMarkIndicators = false
        drawingHelper.showSearchingCursor = false
        drawingHelper.copyMode = false
        drawingHelper.passwordInput = false
        drawingHelper.shouldShowTimestamps = false
        drawingHelper.colorMap = colorMap;
        originalDelegate = drawingHelper.delegate!

        super.init()

        drawingHelper.delegate = self
    }

    private func draw(range: VT100GridCoordRange) {
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        var minX = range.start.x
        var maxX = range.end.x
        if range.start.y != range.end.y {
            minX = 0;
            maxX = drawingHelper.gridSize.width;
        }
        let rows = range.end.y - range.start.y + 1

        let rect = NSRect(x: Double(minX) * drawingHelper.cellSize.width,
                          y: Double(range.start.y) * drawingHelper.cellSize.height,
                          width: Double(maxX - minX) * drawingHelper.cellSize.width,
                          height: Double(rows) * drawingHelper.cellSize.height)
        var rects = [rect]
        let virtualOffset = rect.minY

        matches = (0..<rows).map { i -> Data in
            var result = Data()
            result.setBits(0..<width)
            if i == 0 {
                result.clearBits(0..<range.start.x)
            }
            if i + 1 == rows {
                result.clearBits(range.end.x..<width)
            }
            return result
        }

        drawingHelper.drawTextViewContent(in: rect,
                                          rectsPtr: &rects,
                                          rectCount: 1,
                                          virtualOffset: virtualOffset)
    }
}

extension Data {
    private func bytes(forBits bits: Int32) -> Int32 {
        return (bits / 8) + ((bits & 7) == 0 ? 0 : 1)
    }

    private func byteIndex(bit: Int32) -> Int {
        return Int(bit) / 8
    }

    mutating func clearBits(_ range: Range<Int32>) {
        extend(bytes(forBits: range.upperBound))
        for i in range {
            set(bit: i, value: false)
        }
    }

    mutating func setBits(_ range: Range<Int32>) {
        extend(bytes(forBits: range.upperBound))
        for i in range {
            set(bit: i, value: true)
        }
    }

    mutating func set(bit: Int32, value: Bool) {
        let i = Int(byteIndex(bit: bit))
        var byte = self[i]
        let mask = UInt8(1 << (bit % 8))
        if value {
            byte |= mask
        } else {
            byte &= ~mask
        }
        self[i] = byte
    }

    mutating func extend(_ minSize: Int32) {
        let n = Int(minSize) - count
        if n <= 0 {
            return
        }
        append(contentsOf: Array(repeating: UInt8(0), count: n))
    }
}

extension TextClipDrawing: iTermTextDrawingHelperDelegate {
    func drawingHelperDrawBackgroundImage(in rect: NSRect, blendDefaultBackground: Bool, virtualOffset: CGFloat) {
    }

    func drawingHelperMark(onLine line: Int32) -> VT100ScreenMarkReading? {
        return nil
    }

    func drawingHelperLine(at line: Int32) -> UnsafePointer<screen_char_t> {
        let adjusted = Int(line - firstLine)
        if adjusted < 0 || adjusted >= lines.count {
            return emptyLine.line
        }
        return lines[adjusted].line
    }

    func drawingHelperLine(atScreenIndex line: Int32) -> UnsafePointer<screen_char_t> {
        return drawingHelperLine(at: line + numHistoryLines)
    }

    func drawingHelperTextExtractor() -> iTermTextExtractor? {
        return nil
    }

    func drawingHelperCharactersWithNotes(onLine line: Int32) -> [Any]? {
        return nil
    }

    func drawingHelperUpdateFindCursorView() {
    }

    func drawingHelperTimestamp(forLine line: Int32) -> Date? {
        return nil
    }

    func drawingHelperColor(forCode theIndex: Int32,
                            green: Int32,
                            blue: Int32,
                            colorMode theMode: ColorMode,
                            bold isBold: Bool,
                            faint isFaint: Bool,
                            isBackground: Bool) -> NSColor {
        return isBackground ? NSColor(red: 1, green: 1, blue: 0, alpha: 1) : NSColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    func drawingHelperFont(forChar ch: UniChar,
                           isComplex: Bool,
                           renderBold: UnsafeMutablePointer<ObjCBool>,
                           renderItalic: UnsafeMutablePointer<ObjCBool>) -> PTYFontInfo {
        return originalDelegate.drawingHelperFont(forChar: ch,
                                                  isComplex: isComplex,
                                                  renderBold: renderBold,
                                                  renderItalic: renderItalic)
    }

    func drawingHelperMatches(onLine line: Int32) -> Data? {
        let adjusted = Int(line - firstLine)
        if adjusted < 0 || adjusted >= lines.count {
            return nil
        }
        return matches[Int(adjusted)]
    }

    func drawingHelperDidFindRunOfAnimatedCellsStarting(at coord: VT100GridCoord, ofLength length: Int32) {
    }

    func drawingHelperLabelForDropTarget(onLine line: Int32) -> String? {
        return nil
    }

    func textDrawingHelperVisibleRect() -> NSRect {
        return originalDelegate.textDrawingHelperVisibleRect()
    }

    func drawingHelperExternalAttributes(onLine lineNumber: Int32) -> iTermExternalAttributeIndexReading? {
        return originalDelegate.drawingHelperExternalAttributes(onLine: lineNumber)
    }

    func frame() -> NSRect {
        return originalDelegate.frame()
    }

    func enclosingScrollView() -> NSScrollView? {
        return originalDelegate.enclosingScrollView()
    }

    func drawingHelperShouldPadBackgrounds(_ padding: UnsafeMutablePointer<NSSize>) -> Bool {
        padding.pointee = Self.padding
        return true
    }
}

