//
//  ChatFindableCellView.swift
//  iTerm2
//
//  Adopted by message cell views so the in-conversation find feature can
//  locate and highlight matches inside their text. The order of
//  findableTextViews MUST match the order of segments produced for the
//  same message by ChatViewController.findSegments(for:) so a match's
//  segment index selects the correct text view.
//

import AppKit

protocol ChatFindableCellView: AnyObject {
    var findableTextViews: [NSTextView] { get }
}

extension NSResponder {
    // Walk the responder chain to the ChatViewController that owns this
    // responder. Used by focused text views to forward Find actions to the
    // conversation instead of handling them locally.
    var enclosingChatViewController: ChatViewController? {
        var responder: NSResponder? = nextResponder
        while let current = responder {
            if let controller = current as? ChatViewController {
                return controller
            }
            responder = current.nextResponder
        }
        return nil
    }
}
