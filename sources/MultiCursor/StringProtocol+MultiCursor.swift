//
//  StringProtocol+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 4/1/22.
//

import Foundation

extension StringProtocol {
    var firstCapitalized: String { prefix(1).capitalized + dropFirst() }
}

