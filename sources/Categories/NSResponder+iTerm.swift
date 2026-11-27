//
//  NSResponder+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/18.
//

import AppKit

// Default answers that responders override to opt in to behavior.
extension NSResponder {
    // AppKit does not call scrollWheel: for the “changed” and “ended”
    // momentum phases. A responder that returns true here receives those
    // events through it_scrollWheelMomentum(_:) instead.
    @objc
    func it_wantsScrollWheelMomentumEvents() -> Bool {
        return false
    }

    @objc(it_scrollWheelMomentum:)
    func it_scrollWheelMomentum(_ event: NSEvent?) {
    }

    // A text view returns its delegate's answer when the delegate implements
    // it_preferredFirstResponder, whether or not the delegate is a responder.
    // Every other responder returns false.
    @objc
    func it_preferredFirstResponder() -> Bool {
        guard let textView = self as? NSTextView else {
            return false
        }
        return (textView.delegate as AnyObject?)?.it_preferredFirstResponder?() ?? false
    }

    @objc
    func it_isTerminalResponder() -> Bool {
        return false
    }
}
