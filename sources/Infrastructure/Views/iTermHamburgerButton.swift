//
//  iTermHamburgerButton.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/30/20.
//

import AppKit

// A control that can supply a menu for iTermHamburgerButtonCell to pop up.
@objc(iTermHamburgerButtonCellControl)
fileprivate protocol iTermHamburgerButtonCellControl: NSObjectProtocol {
    func hamburgerMenu() -> NSMenu?
}

// No class adopts this protocol. It declares
// +[NSMenu popUpContextMenu:withEvent:forView:] with optional arguments so
// that the method can be sent to the NSMenu class object through AnyObject.
// The method's Swift signature does not accept nil, but the menu provider may
// return nil, and NSEvent's factory method returns an optional event.
@objc fileprivate protocol iTermHamburgerContextMenuPresenter {
    @objc(popUpContextMenu:withEvent:forView:)
    func popUpHamburgerContextMenu(_ menu: NSMenu?, with event: NSEvent?, for view: NSView?)
}

// A button cell that, when its control view can supply a menu, pops up that
// menu on mouse down instead of tracking the mouse. The menu is shown as a
// context menu, placed as if the click were at the center of the cell. With
// any other control view it tracks the mouse as NSButtonCell does.
@objc(iTermHamburgerButtonCell)
fileprivate class iTermHamburgerButtonCell: NSButtonCell {
    override func trackMouse(with event: NSEvent,
                             in cellFrame: NSRect,
                             of controlView: NSView,
                             untilMouseUp flag: Bool) -> Bool {
        guard let control = controlView as? iTermHamburgerButtonCellControl else {
            return super.trackMouse(with: event, in: cellFrame, of: controlView, untilMouseUp: flag)
        }
        let centerPoint = controlView.convert(NSPoint(x: cellFrame.midX, y: cellFrame.midY), to: nil)
        let fakeEvent = NSEvent.mouseEvent(with: event.type,
                                           location: centerPoint,
                                           modifierFlags: event.modifierFlags,
                                           timestamp: event.timestamp,
                                           windowNumber: event.windowNumber,
                                           context: nil,
                                           eventNumber: event.eventNumber,
                                           clickCount: event.clickCount,
                                           pressure: event.pressure)
        (NSMenu.self as AnyObject).popUpHamburgerContextMenu?(control.hamburgerMenu(),
                                                              with: fakeEvent,
                                                              for: controlView)
        return true
    }
}

// A borderless button showing an ellipsis image that opens a menu when it is
// pressed. The menu comes from menuProvider, which is asked again on every
// press.
@objc(iTermHamburgerButton)
class iTermHamburgerButton: NSButton {
    @objc var menuProvider: () -> NSMenu?

    @objc(initWithMenuProvider:)
    init(menuProvider: @escaping () -> NSMenu?) {
        self.menuProvider = menuProvider
        super.init(frame: .zero)
        cell = iTermHamburgerButtonCell()
        bezelStyle = .flexiblePush
        isBordered = false
        image = NSImage.it_hamburger(for: type(of: self))
        imagePosition = .imageOnly
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }
}

extension iTermHamburgerButton: iTermHamburgerButtonCellControl {
    @objc fileprivate func hamburgerMenu() -> NSMenu? {
        return menuProvider()
    }
}
