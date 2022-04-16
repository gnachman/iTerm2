//
//  SaneButton.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

// This button makes the cursor becomes an arrow on hover, even if the button is over an NSTextView.
// AppKit is a garbage fire.
// https://stackoverflow.com/questions/16287624/how-to-force-the-cursor-to-be-an-arrowcursor-when-it-hovers-a-nsbutton-that-is
class SaneButton: NSButton {
    private var trackingArea: NSTrackingArea? = nil

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    deinit {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
    }
}


class SanePopUpButton: NSPopUpButton {
    private var trackingArea: NSTrackingArea? = nil

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    deinit {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
    }
}
