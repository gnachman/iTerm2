//
//  TerminalButton.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/26/23.
//

import Foundation

@available(macOS 11, *)
@objc(iTermTerminalButton)
class TerminalButton: NSObject {
    private(set) var backgroundImage: NSImage
    private(set) var foregroundImage: NSImage
    @objc var action: ((NSPoint) -> ())?
    private var lastForegroundColor: NSColor?
    private var lastBackgroundColor: NSColor?
    private var lastForegroundImage: NSImage?
    private var lastBackgroundImage: NSImage?
    private let aspectRatio: CGFloat
    @objc let absCoord: VT100GridAbsCoord
    // Clients can use this as they like
    @objc var desiredFrame = NSRect.zero
    @objc var pressed: Bool {
        switch state {
        case .normal: return false
        case .pressedInside, .pressedOutside: return true
        }
    }
    enum State {
        case normal
        case pressedOutside
        case pressedInside
    }
    private var state = State.normal
    @objc let id: Int

    init(id: Int, backgroundImage: NSImage, foregroundImage: NSImage, absCoord: VT100GridAbsCoord) {
        self.id = id
        self.backgroundImage = backgroundImage
        self.foregroundImage = foregroundImage
        self.absCoord = absCoord
        aspectRatio = foregroundImage.size.height / foregroundImage.size.width;
    }

    private func tinted(_ cachedImage: NSImage?, _ baseImage: NSImage, _ cachedColor: NSColor?, _ color: NSColor) -> NSImage {
        if color == cachedColor, let cachedImage {
            return cachedImage
        }
        return baseImage.it_image(withTintColor: color)
    }

    private func images(backgroundColor: NSColor,
                        foregroundColor: NSColor) -> (NSImage, NSImage) {
        let result = (tinted(lastForegroundImage, foregroundImage, lastForegroundColor, foregroundColor),
                      tinted(lastBackgroundImage, backgroundImage, lastBackgroundColor, backgroundColor))
        lastForegroundColor = foregroundColor
        lastForegroundImage = result.0
        lastBackgroundColor = backgroundColor
        lastBackgroundImage = result.1
        return result
    }

    private func size(cellSize: NSSize) -> NSSize {
        let width = cellSize.width * 2
        var result = NSSize(width: width, height: aspectRatio * width);
        let scale = cellSize.height / result.height
        if scale < 1 {
            result.width *= scale
            result.height *= scale
        }
        return result
    }

    @objc(frameWithX:minAbsLine:cumulativeOffset:cellSize:)
    func frame(x: CGFloat,
               minAbsLine: Int64,
               cumulativeOffset: Int64,
               cellSize: NSSize) -> NSRect {
        let size = size(cellSize: cellSize)
        return NSRect(x: x,
                      y: CGFloat(max(minAbsLine, absCoord.y) - cumulativeOffset) * cellSize.height,
                      width: size.width,
                      height: size.height)
    }

    @objc(drawWithBackgroundColor:foregroundColor:frame:virtualOffset:)
    func draw(backgroundColor: NSColor,
              foregroundColor: NSColor,
              frame rect: NSRect,
              virtualOffset: CGFloat) {
        
        let (foregroundImage, backgroundImage) = switch state {
        case .normal, .pressedOutside:
            images(backgroundColor: backgroundColor, foregroundColor: foregroundColor)
        case .pressedInside:
            images(backgroundColor: foregroundColor, foregroundColor: backgroundColor)
        }
        backgroundImage.it_draw(in: rect, virtualOffset: virtualOffset)
        foregroundImage.it_draw(in: rect, virtualOffset: virtualOffset)
    }

    func image(backgroundColor: NSColor,
               foregroundColor: NSColor,
               cellSize: CGSize) -> NSImage {
        let size = self.size(cellSize: cellSize)
        return NSImage(size: size,
                       flipped: false) { [weak self] _ in
            self?.draw(backgroundColor: backgroundColor,
                       foregroundColor: foregroundColor,
                       frame: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                       virtualOffset: 0)
            return true
        }
    }
    var selected: Bool {
        switch state {
        case .normal, .pressedOutside:
            return false
        case .pressedInside:
            return true
        }
    }

    @objc
    func mouseDownInside() -> Bool {
        let wasSelected = selected
        state = .pressedInside
        return selected != wasSelected
    }

    @objc
    func mouseDownOutside() -> Bool {
        let wasSelected = selected
        state = .pressedOutside
        return selected != wasSelected
    }

    @objc
    @discardableResult
    func mouseUp(locationInWindow: NSPoint) -> Bool {
        let wasSelected = selected
        switch state {
        case .pressedInside:
            action?(locationInWindow)
            state = .normal
        case .pressedOutside:
            state = .normal
        case .normal:
            break
        }
        return selected != wasSelected
    }

    @objc
    func mouseExited() {
        switch state {
        case .pressedInside:
            state = .pressedOutside
        case .pressedOutside, .normal:
            state = .normal
        }
    }
}

@available(macOS 11, *)
@objc(iTermTerminalCopyButton)
class TerminalCopyButton: TerminalButton {
    @objc let blockID: String

    @objc(initWithID:blockID:absCoord:)
    init?(id: Int, blockID: String, absCoord: VT100GridAbsCoord) {
        self.blockID = blockID
        guard let bg = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: nil),
              let fg = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) else {
            return nil
        }
        super.init(id: id,
                   backgroundImage: bg,
                   foregroundImage: fg,
                   absCoord: absCoord)
    }
}
