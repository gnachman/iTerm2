//
//  MouseEventSynthesizer.swift
//  ModernTests
//
//  Builds mouse events and delivers them with -[NSWindow sendEvent:], so AppKit does the hit
//  testing and routes drags and the mouse-up to the view that took the mouse-down, as it does for
//  real input. Locations are in window coordinates.
//
//  Limitation: these events do not change global mouse state, so code that reads
//  +[NSEvent pressedMouseButtons] or +[NSEvent mouseLocation] sees the real pointer instead.
//

import AppKit
@testable import iTerm2SharedARC

struct MouseEventSynthesizer {
    let window: NSWindow

    private func event(_ type: NSEvent.EventType,
                       at point: NSPoint,
                       modifiers: NSEvent.ModifierFlags,
                       clickCount: Int) -> NSEvent {
        guard let event = NSEvent.mouseEvent(with: type,
                                             location: point,
                                             modifierFlags: modifiers,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             clickCount: clickCount,
                                             pressure: type == .leftMouseUp ? 0 : 1) else {
            it_fatalError("Could not create a \(type) event")
        }
        return event
    }

    func down(at point: NSPoint, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        window.sendEvent(event(.leftMouseDown, at: point, modifiers: modifiers, clickCount: clickCount))
    }

    func dragged(to point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        window.sendEvent(event(.leftMouseDragged, at: point, modifiers: modifiers, clickCount: 1))
    }

    func up(at point: NSPoint, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        window.sendEvent(event(.leftMouseUp, at: point, modifiers: modifiers, clickCount: clickCount))
    }

    func moved(to point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        window.sendEvent(event(.mouseMoved, at: point, modifiers: modifiers, clickCount: 0))
    }

    func click(at point: NSPoint, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        down(at: point, modifiers: modifiers, clickCount: clickCount)
        up(at: point, modifiers: modifiers, clickCount: clickCount)
    }

    func doubleClick(at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        click(at: point, modifiers: modifiers, clickCount: 1)
        click(at: point, modifiers: modifiers, clickCount: 2)
    }

    /// Mouse-down at `start`, `steps` drag events along a straight line, then mouse-up at `end`.
    func drag(from start: NSPoint,
              to end: NSPoint,
              steps: Int = 10,
              modifiers: NSEvent.ModifierFlags = []) {
        down(at: start, modifiers: modifiers)
        for i in 1...max(1, steps) {
            let t = CGFloat(i) / CGFloat(max(1, steps))
            dragged(to: NSPoint(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t),
                    modifiers: modifiers)
        }
        up(at: end, modifiers: modifiers)
    }
}
