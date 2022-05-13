//
//  URL+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/13/22.
//

import Foundation

extension URL {
    enum PathArithmeticException: Error {
        case invalidPrefix
    }
    func pathByRemovingPrefix(_ prefix: String) throws -> String {
        if !path.hasPrefix(prefix) {
            throw PathArithmeticException.invalidPrefix
        }
        return String(path.dropFirst(prefix.count))
    }
}
