//
//  iTermIntegerNumberFormatter.swift
//  iTerm2
//
//  Created by George Nachman on 9/30/14.
//
//

import Foundation

// NumberFormatter is @unchecked Sendable, and Swift requires each subclass to
// restate that conformance. The two subclasses in this file add no state.

// Accepts a partial string while editing only if it is empty or, apart from
// surrounding whitespace, is one optionally signed run of decimal digits.
// Values outside the range of an int are accepted.
@objc(iTermIntegerNumberFormatter)
class iTermIntegerNumberFormatter: NumberFormatter, @unchecked Sendable {
    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if partialString.isEmpty {
            return true
        }
        // The scanner skips whitespace before the number, and isAtEnd is true
        // when only whitespace follows it. A number too large for an int still
        // scans.
        let scanner = Scanner(string: partialString)
        return scanner.scanInt32() != nil && scanner.isAtEnd
    }
}

// A number formatter for editable text fields. It accepts every partial
// string, so the user can type freely, and it edits a number as its
// stringValue and a string as itself.
@objc(iTermSaneNumberFormatter)
class iTermSaneNumberFormatter: NumberFormatter, @unchecked Sendable {
    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return true
    }

    override func editingString(for obj: Any) -> String? {
        // An Objective-C caller may pass nil, which arrives here as an empty
        // optional. Handing that to super would turn it into NSNull, so nil
        // goes to string(for:), which takes an optional and is the method
        // NSFormatter's editingString(for:) calls by default. NumberFormatter
        // does not override editingString(for:), so this gives the same
        // answer as the superclass would for nil.
        if case Optional<Any>.none = obj {
            return string(for: nil)
        }
        if let number = obj as? NSNumber {
            return number.stringValue
        }
        if let string = obj as? String {
            return string
        }
        return super.editingString(for: obj)
    }
}
