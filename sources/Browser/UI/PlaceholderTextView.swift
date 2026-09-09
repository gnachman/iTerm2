//
//  PlaceholderTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/23/24.
//

import Foundation
import Cocoa

@objc(iTermPlaceholderTextView)
class PlaceholderTextView: NSTextView {
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

    // Give this editor its own undo stack so ⌘Z (which iTerm routes to the focused
    // editor's own undo manager) is scoped to this field and doesn't share the
    // window's stack with other editors. This also keeps text-edit undo actions
    // from outliving the view in the window's undo manager. See
    // NSTextView+iTermUndoSafety and iTermApplicationDelegate's undo: routing.
    private lazy var privateUndoManager = UndoManager()
    override var undoManager: UndoManager? { privateUndoManager }

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
}

@objc(iTermShiftEnterTextView)
class ShiftEnterTextView: PlaceholderTextView {
    @objc var shiftEnterPressed: (() -> ())?

    override func insertNewline(_ sender: Any?) {
        if iTermApplication.shared().it_modifierFlags.contains(.shift) {
            shiftEnterPressed?()
        }
        super.insertNewline(sender)
    }
}
