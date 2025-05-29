//
//  Data+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

extension Data {
    var lossyString: String {
        return String(decoding: self, as: UTF8.self)
    }
}

