//
//  String+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

extension String {
    func containsCaseInsensitive(_ substring: String) -> Bool {
        if substring.isEmpty {
            return true
        }
        return range(of: substring, options: .caseInsensitive, range: nil, locale:nil) != nil
    }
}

