//
//  SettingsSecureTextField.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/24.
//

import Foundation

@objc(iTermSettingsSecureTextField)
class iTermSettingsSecureTextField: NSSecureTextField {
    @objc var textFieldDidBecomeFirstResponder: ((iTermSettingsSecureTextField) -> ())?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            textFieldDidBecomeFirstResponder?(self)
        }
        return result
    }
}

