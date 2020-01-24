//
//  SearchableComboViewStringAdditions.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import Foundation

extension String {
    var tokens: [String] {
        var words: [String] = []
        enumerateSubstrings(
            in: startIndex..<endIndex,
            options: .byWords) {
                (substring, substringRange, enclosingRange, stop) in
                if let substring = substring {
                    words.append(substring.localizedLowercase)
                }
        }
        return words
    }
}
