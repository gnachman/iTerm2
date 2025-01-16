//
//  NonDefaultIndicator.swift
//  iTerm2
//
//  Created by George Nachman on 1/15/25.
//

import ColorPicker

@objc(iTermNonDefaultIndicator)
class NonDefaultIndicator: NSView {
    private var xOffset = CGFloat(0)
    private var superviewEnabledObserver: NSKeyValueObservation?

    override func draw(_ rect: NSRect) {
        NSColor.orange.set()
        rect.intersection(bounds).fill()
    }

    override var frame: NSRect {
        get {
            super.frame
        }
        set {
            super.frame = newValue
            it_assert(newValue.width == 2)
        }
    }

    private func updateFrame() {
        guard let superview else {
            return
        }
        frame = NSRect(x: xOffset, y: 0, width: 2, height: superview.frame.height)
    }

    private static func xOffset(for view: NSView) -> CGFloat {
        if let popUpButton = view as? NSPopUpButton {
            if popUpButton.pullsDown {
                -3
            } else {
                if (view as? NSControl)?.controlSize == .regular {
                    -3
                } else {
                    -2
                }
            }
        } else if let button = view as? NSButton, button.bezelStyle == .regularSquare && button.imagePosition == .imageLeft {
            -4
        } else if view is NSMatrix {
            -3
        } else if view is NSComboBox {
            -5
        } else if view is NSTextField {
            -6
        } else if view is NSTextView {
            0
        } else if view is iTermSlider {
            -4
        } else if view is CPKColorWell {
            -4
        } else if view is iTermShortcutInputView {
            -4
        } else {
            0
        }
    }

    override func viewDidMoveToSuperview() {
        if let superview {
            xOffset = Self.xOffset(for: superview)
            updateFrame()
            if let control = superview as? NSControl {
                superviewEnabledObserver = control.observe(\.isEnabled, options: [.initial, .new]) { [weak self] superview, change in
                    self?.isHidden = !((self?.superview as? NSControl)?.isEnabled ?? false)
                }
            }
        }
        super.viewDidMoveToSuperview()
    }

    override func resize(withOldSuperviewSize size: NSSize) {
        updateFrame()
        super.resize(withOldSuperviewSize: size)
    }
}
