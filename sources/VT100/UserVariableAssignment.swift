//
//  UserVariableAssignment.swift
//  iTerm2
//
//  Created by George Nachman on 10/4/26.
//

import Foundation

// The payload of OSC 1337;SetUserVar, which is name=base64 to set a user variable or just name
// to unset it.
@objc(iTermUserVariableAssignment)
class UserVariableAssignment: NSObject {
    // The full variable name, such as user.host_name.
    @objc let name: String
    // nil means to unset the variable.
    @objc let value: String?

    @objc(initWithPayload:)
    init?(payload: String) {
        let key: String
        if let kvp = (payload as NSString).keyValuePair(),
           let first = kvp.firstObject as String? {
            key = first
            value = kvp.secondObject?.byBase64DecodingString(withEncoding: String.Encoding.utf8.rawValue)
        } else {
            key = payload
            value = nil
        }
        if key.contains(".") {
            DLog("key contains a ., which is not allowed. payload=\(payload)")
            return nil
        }
        name = "user." + key
        super.init()
    }
}
