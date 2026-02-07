//
//  iTermBrowserView.swift
//  iTerm2
//
//  Created by George Nachman on 8/13/25.
//

@MainActor
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
    weak var viewController: NSViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Enable transparency for see-through background
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Register for the same drag types as SessionView to allow drag events to be forwarded
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(iTermMovePaneDragType),
            NSPasteboard.PasteboardType("com.iterm2.psm.controlitem")
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        // Enable transparency for see-through background
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        registerForDraggedTypes([
            NSPasteboard.PasteboardType(iTermMovePaneDragType),
            NSPasteboard.PasteboardType("com.iterm2.psm.controlitem")
        ])
    }

    // Forward drag events to superview (SessionView)
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return superview?.draggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return superview?.draggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        superview?.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return superview?.performDragOperation(sender) ?? false
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        // Notify the view controller to relayout subviews
        if let viewController = self.nextResponder as? iTermBrowserViewController {
            viewController.viewDidLayout()
        }
    }

    // This horrific thing is necessary because I don't have a NSViewController as a parent of
    // iTermBrowserViewController. I guess I would have discovered the problem fifteen years ago
    // if PTYSession had been an NSViewController as it always should have been. I think what happens
    // is that when the view hierarchy is moved to a different window, the view controller never
    // finds out so its next responder remains incorrectly pointing at an ancestor view in its
    // original window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewController?.nextResponder = superview
    }
}

