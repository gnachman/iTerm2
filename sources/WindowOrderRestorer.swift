//
//  WindowOrderPreservationController.swift
//  iTerm2
//
//  Created by George Nachman on 12/15/24.
//

@objc(iTermWindowOrderRestorer)
class WindowOrderRestorer: NSObject {
    // Weak because we don't want windows to be kept around solely to be reordered later.
    private let weakWindowOrder: [WeakBox<NSWindow>]

    @objc
    override init() {
        weakWindowOrder = NSApp.orderedWindows.map { WeakBox($0) }
        super.init()
    }

    @objc
    func restore() {
        reorderWindows(to: desiredOrder())
    }

    private func desiredOrder() -> [NSWindow] {
        let orderedWindows = NSApp.orderedWindows
        return weakWindowOrder.compactMap {
            $0.value
        }.filter {
            orderedWindows.contains($0)
        }
    }

    func reorderWindows(to desiredOrder: [NSWindow]) {
        for (i, window) in desiredOrder.enumerated() {
            guard window.isOnActiveSpace else {
                continue
            }
            if let below = desiredOrder[safe: i - 1] {
                window.order(.below, relativeTo: below.windowNumber)
            } else if let above = desiredOrder[safe: i + 1] {
                window.order(.above, relativeTo: above.windowNumber)
            }
        }
    }
}

