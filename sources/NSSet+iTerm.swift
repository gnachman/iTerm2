//
//  NSSet+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/23.
//

import Foundation

extension Set {
    var allCombinations: Set<Set<Element>> {
        guard let element = first else {
            let array = [self]
            let setOfSets = Set<Set<Element>>(array)
            return setOfSets
        }
        let temp = Set<Element>(dropFirst())
        let combos = temp.allCombinations
        let array = combos.map { $0.union(Set([element])) }
        let combosPlus = Set<Set<Element>>(array)
        return combos.union(combosPlus)
    }
}

extension NSSet {
    @objc var allCombinations: NSSet {
        return (self as Set).allCombinations as NSSet
    }
}
