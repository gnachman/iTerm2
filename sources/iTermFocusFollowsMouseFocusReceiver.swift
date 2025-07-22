//
//  iTermFocusFollowsMouseFocusReceiver.swift
//  iTerm2
//
//  Created by George Nachman on 7/21/25.
//

@objc
@MainActor
protocol iTermFocusFollowsMouseFocusReceiver: AnyObject {
    // Allows a new split pane to become focused even though the mouse pointer is elsewhere.
    // Records the mouse position. Refuses first responder as long as the mouse doesn't move.
    @objc(refuseFirstResponderAtCurrentMouseLocation)
    func refuseFirstResponderAtCurrentMouseLocation()
}
