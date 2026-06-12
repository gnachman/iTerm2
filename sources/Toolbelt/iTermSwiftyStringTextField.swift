//
//  iTermSwiftyStringTextField.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

@objc(iTermSwiftyStringTextField)
class iTermSwiftyStringTextField: NSTextField {
    private var swiftyString: iTermSwiftyString?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    convenience init(labelWithString string: String) {
        self.init(frame: NSRect.zero)

        self.stringValue = string
        self.isEditable = false
        self.isSelectable = false
        self.isBezeled = false
        self.drawsBackground = false
        self.lineBreakMode = .byTruncatingTail
        self.alignment = .natural
        self.font = .labelFont(ofSize: NSFont.labelFontSize)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

extension iTermSwiftyStringTextField {
    func set(interpolatedString: String, scope: iTermVariableScope) {
        swiftyString?.invalidate()
        swiftyString = iTermSwiftyString(string: interpolatedString,
                                         scope: scope,
                                         sideEffectsAllowed: false,
                                         observer: { [weak self] newValue, error in
            if let error {
                DLog("\(error) for \(d(self?.swiftyString))")
                return newValue
            }
            let string = if let newValue, let s = newValue as? String {
                s
            } else {
                ""
            }
            self?.stringValue = string
            return newValue
        })
    }
}
