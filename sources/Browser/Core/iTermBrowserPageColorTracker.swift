//
//  iTermBrowserPageColorTracker.swift
//  iTerm2
//
//  Decides when a change to the web view's page background color
//  (underPageBackgroundColor) should be forwarded to the session for the minimal
//  theme's tab tint. Kept free of WebKit so it is unit testable.
//
//  WebKit reports transient values while a page loads (its light default before the
//  page is parsed), so changes during a load are ignored. It also updates the color
//  after didFinish, on a later rendering update, so reading it only at didFinish yields
//  the previous page's color. Changes observed once the load has settled are forwarded.
//

import AppKit

struct iTermBrowserPageColorTracker {
    // True once the most recent main-frame navigation has finished or failed.
    private(set) var settled = false
    // The last color forwarded, in sRGB. Repeats are not forwarded, so a stale value at
    // didFinish does not use up the session's rate limit and delay the real color.
    private var lastForwarded: NSColor?

    // A main-frame navigation started. Changes reported until it settles are transient.
    mutating func navigationDidStart() {
        settled = false
    }

    // The navigation finished. Returns the color to forward now, or nil if it is
    // unchanged. It may still be the previous page's color; the page's real color then
    // arrives through observedColorDidChange.
    mutating func navigationDidSettle(currentColor: NSColor?) -> NSColor? {
        settled = true
        return forward(currentColor)
    }

    // The navigation failed, leaving the current document in place. Resume following
    // its color without forwarding anything now.
    mutating func navigationDidFail() {
        settled = true
    }

    // The web view reported a new color. Returns the color to forward, or nil to ignore.
    // isLoading is the web view's isLoading. It guards against a late finish or failure
    // of a superseded navigation marking a newer, still-loading one as settled.
    mutating func observedColorDidChange(_ color: NSColor?, isLoading: Bool) -> NSColor? {
        guard settled, !isLoading else {
            return nil
        }
        return forward(color)
    }

    private mutating func forward(_ color: NSColor?) -> NSColor? {
        guard let color else {
            return nil
        }
        // Compare in sRGB so a dynamic color is judged by what it resolves to now. If it
        // can't be converted, always forward it.
        let resolved = color.usingColorSpace(.sRGB)
        if let resolved, resolved == lastForwarded {
            return nil
        }
        lastForwarded = resolved
        return color
    }
}
