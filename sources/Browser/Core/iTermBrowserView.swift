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

