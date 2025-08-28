//
//  PopoverHelpButton.swift
//  iTerm2
//
//  Created by George Nachman on 12/18/24.
//

import AppKit

@objc(iTermPopoverHelpButton)
@IBDesignable
class PopoverHelpButton: NSButton {
    @IBInspectable var helpText: String = ""

    @objc
    init(helpText: String) {
        self.helpText = helpText
        super.init(frame: .zero)
        bezelStyle = .helpButton
        setButtonType(.momentaryPushIn)
        isBordered = true
        target = self
        action = #selector(clicked(_:))
        title = ""
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(clicked(_:))
        title = ""
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    @objc
    private func clicked(_ sender: Any?) {
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        // Call the existing help method
        it_showWarning(withMarkdown: helpText)
        return super.sendAction(action, to: target)
    }
}
