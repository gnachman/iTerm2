//
//  RoundedTextField.swift
//  iTerm2
//
//  Created by George Nachman on 2/19/25.
//

import Cocoa

fileprivate let extraHeight = CGFloat(8)
fileprivate let horizontalInset = CGFloat(6)

class RoundedTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set { }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        customizeAppearance()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        customizeAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        customizeAppearance()
    }

    private func customizeAppearance() {
        isBezeled = false
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        focusRingType = .none
    }

    override var intrinsicContentSize: NSSize {
        let originalSize = super.intrinsicContentSize
        return NSSize(width: originalSize.width, height: originalSize.height + extraHeight)
    }
}

class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var newRect = super.drawingRect(forBounds: rect)
        newRect.origin.y += extraHeight / 2
        newRect.origin.x += horizontalInset
        newRect.size.width -= horizontalInset * 2
        newRect.size.height -= extraHeight
        return newRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        var newRect = rect
        newRect.origin.y += extraHeight / 2
        newRect.origin.x += horizontalInset
        newRect.size.width -= horizontalInset * 2
        newRect.size.height -= extraHeight
        super.edit(withFrame: newRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        var newRect = rect
        newRect.origin.y += extraHeight / 2
        newRect.origin.x += horizontalInset
        newRect.size.width -= horizontalInset * 2
        newRect.size.height -= extraHeight
        super.select(withFrame: newRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
