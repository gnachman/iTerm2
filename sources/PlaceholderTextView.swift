//
//  PlaceholderTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/23/24.
//

import Foundation
import Cocoa

class PlaceholderTextView: NSTextView {
    @objc var shiftEnterPressed: (() -> ())?

    // Placeholder string that will be displayed when the text view is empty.
    //
    // Did you know that NSTextView actually implements placeholders privately? Do
    // @objc var placeholderString: String { didSet { self.needsDisplay.true } } and it just works.
    // Since that's a private API I guess I won't but it's very tempting.
    @objc var it_placeholderString: String? {
        didSet {
            self.needsDisplay = true
        }
    }

    // Custom initialization of the text view.
    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self, 
                                               selector: #selector(it_textDidChange),
                                               name: NSText.didChangeNotification,
                                               object: self)
    }

    // Handling the text change notification.
    @objc private func it_textDidChange(notification: Notification) {
        self.needsDisplay = true
    }

    // Drawing the placeholder string when appropriate.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Check if the text view is empty and if a placeholder is set.
        if self.string.isEmpty, let placeholder = it_placeholderString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = self.alignment
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .paragraphStyle: paragraphStyle
            ]
            let rect = self.bounds.insetBy(dx: 5, dy: 0)
            placeholder.draw(in: rect, withAttributes: attrs)
        }
    }

    override func insertNewline(_ sender: Any?) {
        if iTermApplication.shared().it_modifierFlags.contains(.shift) {
            shiftEnterPressed?()
        }
        super.insertNewline(sender)
    }
}
