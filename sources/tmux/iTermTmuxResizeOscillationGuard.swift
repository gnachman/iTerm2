//
//  iTermTmuxResizeOscillationGuard.swift
//  iTerm2SharedARC
//
//  Stops iTerm2 and tmux from resizing each other forever.
//

import Foundation

// When a tmux layout doesn't fit its tab, iTerm2 asks tmux for a size that does. If the layout tmux
// sends back makes iTerm2 want the previous size again, the two would resize each other forever,
// pinning the CPU and starving input. This notices a window's requested size flipping back and
// forth between the same values in quick succession and refuses further requests until the flipping
// stops for a while or something other than a layout change (e.g., the user resizing the window)
// resets it.
@objc(iTermTmuxResizeOscillationGuard)
class TmuxResizeOscillationGuard: NSObject {
    private struct History {
        // Most recent last.
        var sizes = [NSSize]()
        var lastRequestTime: TimeInterval = 0
        var flips = 0
        var refused = false
    }

    // Requests further apart than this are not considered part of a ping-pong.
    @objc let interval: TimeInterval
    // How many times a window may return to the size it had two requests ago before requests are
    // refused.
    private let maximumFlips: Int
    private var histories = [Int32: History]()
    // Whether a refusal has already used up its retry. See shouldRetryAfterRefusal().
    private var retried = false

    @objc
    init(interval: TimeInterval, maximumFlips: Int) {
        self.interval = interval
        self.maximumFlips = maximumFlips
    }

    @objc
    override convenience init() {
        self.init(interval: 3.0, maximumFlips: 1)
    }

    // Returns whether iTerm2 may ask tmux to make `window` `size` because of a layout change. Call
    // only when the request will actually be sent. `now` is a time in seconds.
    @objc(shouldRequestSize:forWindow:now:)
    func shouldRequest(size: NSSize, window: Int32, now: TimeInterval) -> Bool {
        var history = histories[window] ?? History()
        if now - history.lastRequestTime > interval {
            history = History()
        }
        if history.sizes.count >= 2,
           history.sizes[history.sizes.count - 2] == size,
           history.sizes[history.sizes.count - 1] != size {
            if history.flips >= maximumFlips {
                if !history.refused {
                    // Sizes are not private, and this is rare enough to be worth keeping.
                    RLog("Refusing to ask tmux to make window \(window) \(size): its size is ping-ponging between \(history.sizes)")
                    history.refused = true
                }
                histories[window] = history
                return false
            }
            history.flips += 1
        }
        history.sizes = Array((history.sizes + [size]).suffix(2))
        history.lastRequestTime = now
        histories[window] = history
        return true
    }

    // Call after a refusal. Returns true if the caller should fit the windows again once
    // `interval` has passed. A refused request may be the one that fits, and if the flipping has
    // stopped nothing else would send it, leaving tmux and iTerm2 disagreeing about the size. It
    // returns true only once until the next reset, so a loop that is still going can't keep
    // retrying in the background.
    @objc
    func shouldRetryAfterRefusal() -> Bool {
        if retried {
            return false
        }
        retried = true
        return true
    }

    // Call when the size changes for a reason other than a tmux layout change, such as the user
    // resizing the window.
    @objc
    func reset() {
        histories.removeAll()
        retried = false
    }
}
