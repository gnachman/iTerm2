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

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        // Call the existing help method
        it_showWarning(withMarkdown: helpText)
        return super.sendAction(action, to: target)
    }
}
