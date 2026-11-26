//
//  NSNull+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

import Foundation

extension NSNull {
    // NSNull is already safe in JSON. This overrides the method of the same
    // name that NSObject (iTerm) declares.
    @objc(it_jsonSafeValue)
    public override func it_jsonSafeValue() -> Any {
        return self
    }
}
