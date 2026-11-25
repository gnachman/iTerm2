//
//  NSNull+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

import Foundation

extension NSNull {
    // NSNull is already safe in JSON. NSObject (iTerm) declares the same
    // selector; NSNull keeps its own implementation, as before.
    // No thread assertion: it returns the receiver and touches no state.
    @objc(it_jsonSafeValue)
    public override func it_jsonSafeValue() -> Any {
        return self
    }
}
