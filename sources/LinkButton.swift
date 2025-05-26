//
//  LinkButton.swift
//  iTerm2
//
//  Created by George Nachman on 5/25/25.
//

import AppKit

@IBDesignable
@objc(iTermLinkButton)
class LinkButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited,
                                               .activeAlways,
                                               .inVisibleRect,
                                               .cursorUpdate]
        trackingArea = NSTrackingArea(rect: bounds,
                                      options: options,
                                      owner: self,
                                      userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    private func setupAppearance() {
        let title = self.title
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: font
        ]
        self.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        self.isBordered = false
        self.setButtonType(.momentaryChange)
    }
}

