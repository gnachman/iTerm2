//
//  Array+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

extension Array {
    func anySatisfies(_ closure: (Element) throws -> Bool) rethrows -> Bool {
        return try first { try closure($0) } != nil
    }
}

