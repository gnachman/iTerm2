//
//  iTermSwiftyStringTextField.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

@objc(iTermSwiftyStringTextField)
class iTermSwiftyStringTextField: NSTextField {
    // Internal (not private) so tests can pin the reuse contract in
    // set(interpolatedString:scope:): reuse is observable only as object
    // identity, since a rebuilt evaluator renders an identical field.
    var swiftyString: iTermSwiftyString?

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
    // Stops evaluating the current interpolated string (if any) and
    // empties the field. Without invalidating, a recycled field's old
    // observer could repopulate it after the caller blanked it.
    func clear() {
        swiftyString?.invalidate()
        swiftyString = nil
        stringValue = ""
    }

    func set(interpolatedString: String, scope: iTermVariableScope) {
        // A live swifty string for the same string and scope is already
        // showing the current value and is still observing its
        // dependencies, so rebuilding it would produce an identical
        // field at the cost of tearing an evaluator down and standing a
        // new one up. Table reloads re-set every visible cell, so most
        // calls land here.
        if let swiftyString,
           swiftyString.stringToEvaluate == interpolatedString,
           swiftyString.scope === scope {
            return
        }
        swiftyString?.invalidate()
        swiftyString = iTermSwiftyString(string: interpolatedString,
                                         scope: scope,
                                         sideEffectsAllowed: false,
                                         observer: { [weak self] newValue, error in
            if let error {
                RLog("\(error) for \(d(self?.swiftyString))")
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
