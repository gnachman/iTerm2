//
//  GPBEnumArray+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/19.
//

import Foundation

extension GPBEnumArray {
    // Compares each element's value(at:), which is
    // kGPBUnrecognizedEnumeratorValue for a raw value the array's validation
    // function rejects, as the Objective-C did.
    // No thread assertion: it only reads the receiver, which belongs to the
    // caller.
    @objc(it_contains:)
    func it_contains(_ value: Int32) -> Bool {
        return (0..<count).contains { self.value(at: $0) == value }
    }
}
