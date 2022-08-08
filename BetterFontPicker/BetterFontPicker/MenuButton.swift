//
//  MenuButton.swift
//  BetterFontPicker
//
//  Created by George Nachman on 8/6/22.
//  Copyright © 2022 George Nachman. All rights reserved.
//

import Foundation

fileprivate protocol MenuButtonProtocol {
    var menuForMenuButton: NSMenu? { get }
}

@objc
class MenuButtonCell: NSButtonCell {
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView, untilMouseUp flag: Bool) -> Bool {
        guard let control = controlView as? MenuButtonProtocol,
              let menu = control.menuForMenuButton,
              let fakeEvent = NSEvent.mouseEvent(with: event.type,
                                                 location: controlView.convert(NSPoint(x: cellFrame.midX,
                                                                                       y: cellFrame.midY),
                                                                               to: nil),
                                                 modifierFlags: event.modifierFlags,
                                                 timestamp: event.timestamp,
                                                 windowNumber: event.windowNumber,
                                                 context: nil,
                                                 eventNumber: event.eventNumber,
                                                 clickCount: event.clickCount,
                                                 pressure: event.pressure) else {
            return super.trackMouse(with: event, in: cellFrame, of: controlView, untilMouseUp: flag)
        }

        NSMenu.popUpContextMenu(menu, with: fakeEvent, for: controlView)
        return true
    }
}

@objc
class MenuButton: NSButton, MenuButtonProtocol {
    public var menuForMenuButton: NSMenu?

    init() {
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        cell = MenuButtonCell()
        bezelStyle = .regularSquare
        isBordered = false
    }
}

@objc
class AccessoryWrapper: NSView {
    let child: NSView

    init(_ child: NSView, height: CGFloat) {
        self.child = child
        super.init(frame: NSRect(x: 0, y: 0, width: child.bounds.width, height: height))
        addSubview(child)
        child.frame = NSRect(x: 0, y: (height - child.bounds.height) / 2.0, width: child.bounds.width, height: child.bounds.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var fittingSize: NSSize {
        return bounds.size
    }
}
