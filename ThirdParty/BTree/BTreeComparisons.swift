//
//  BTreeComparator.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-03-04.
//  Copyright © 2016–2017 Károly Lőrentey.
//

extension BTree {
    //MARK: Comparison

    /// Return `true` iff `self` and `other` contain equivalent elements, using `isEquivalent` as the equivalence test.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the 
    /// two trees are divergent mutations originating from the same value.
    ///
    /// - Requires: `isEquivalent` is an [equivalence relation].
    /// - Complexity:  O(`count`)
    ///
    /// [equivalence relation]: https://en.wikipedia.org/wiki/Equivalence_relation
    public func elementsEqual(_ other: BTree, by isEquivalent: (Element, Element) throws -> Bool) rethrows -> Bool {
        if self.root === other.root { return true }
        if self.count != other.count { return false }

        var a = BTreeStrongPath(startOf: self.root)
        var b = BTreeStrongPath(startOf: other.root)
        while !a.isAtEnd { // No need to check b: the trees have the same length, and each iteration moves equal steps in both trees.
            if a.node === b.node && a.slot == b.slot {
                // Ascend to first ancestor that isn't shared.
                repeat {
                    a.ascendOneLevel()
                    b.ascendOneLevel()
                } while !a.isAtEnd && a.node === b.node && a.slot == b.slot
                if a.isAtEnd { break }
                a.ascendToKey()
                b.ascendToKey()
            }
            if try !isEquivalent(a.element, b.element) {
                return false
            }
            a.moveForward()
            b.moveForward()
        }
        return true
    }
}

extension BTree where Value: Equatable {
    /// Return `true` iff `self` and `other` contain equal elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two trees are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public func elementsEqual(_ other: BTree) -> Bool {
        return self.elementsEqual(other, by: { $0.0 == $1.0 && $0.1 == $1.1 })
    }

    /// Return `true` iff `a` and `b` contain equal elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two trees are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public static func == (a: BTree, b: BTree) -> Bool {
        return a.elementsEqual(b)
    }

    /// Return `true` iff `a` and `b` do not contain equal elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two trees are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public static func != (a: BTree, b: BTree) -> Bool {
        return !(a == b)
    }
}

extension BTree {
    /// Returns true iff this tree has no elements whose keys are also in `tree`.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func isDisjoint(with tree: BTree) -> Bool {
        var a = BTreeStrongPath(startOf: self.root)
        var b = BTreeStrongPath(startOf: tree.root)
        if !a.isAtEnd && !b.isAtEnd {
            outer: while true {
                if a.key == b.key {
                    return false
                }
                while a.key < b.key {
                    a.nextPart(until: .excluding(b.key))
                    if a.isAtEnd { break outer }
                }
                while b.key < a.key {
                    b.nextPart(until: .excluding(a.key))
                    if b.isAtEnd { break outer }
                }
            }
        }
        return true
    }

    /// Returns true iff all keys in `self` are also in `tree`.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func isSubset(of tree: BTree, by strategy: BTreeMatchingStrategy) -> Bool {
        return isSubset(of: tree, by: strategy, strict: false)
    }

    /// Returns true iff all keys in `self` are also in `tree`,
    /// but `tree` contains at least one key that isn't in `self`.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSubset(of tree: BTree, by strategy: BTreeMatchingStrategy) -> Bool {
        return isSubset(of: tree, by: strategy, strict: true)
    }

    /// Returns true iff all keys in `tree` are also in `self`.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func isSuperset(of tree: BTree, by strategy: BTreeMatchingStrategy) -> Bool {
        return tree.isSubset(of: self, by: strategy, strict: false)
    }

    /// Returns true iff all keys in `tree` are also in `self`,
    /// but `self` contains at least one key that isn't in `tree`.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSuperset(of tree: BTree, by strategy: BTreeMatchingStrategy) -> Bool {
        return tree.isSubset(of: self, by: strategy, strict: true)
    }

    internal func isSubset(of tree: BTree, by strategy: BTreeMatchingStrategy, strict: Bool) -> Bool {
        var a = BTreeStrongPath(startOf: self.root)
        var b = BTreeStrongPath(startOf: tree.root)
        var knownStrict = false
        outer: while !a.isAtEnd && !b.isAtEnd {
            while a.key == b.key {
                if a.node === b.node && a.slot == b.slot {
                    // Ascend to first ancestor that isn't shared.
                    repeat {
                        a.ascendOneLevel()
                        b.ascendOneLevel()
                    } while !a.isAtEnd && a.node === b.node && a.slot == b.slot
                    if a.isAtEnd || b.isAtEnd { break outer }
                    a.ascendToKey()
                    b.ascendToKey()
                }
                let key = a.key
                switch strategy {
                case .groupingMatches:
                    while !a.isAtEnd && a.key == key {
                        a.nextPart(until: .including(key))
                    }
                    while !b.isAtEnd && b.key == key {
                        b.nextPart(until: .including(key))
                    }
                    if a.isAtEnd || b.isAtEnd { break outer }
                case .countingMatches:
                    var acount = 0
                    while !a.isAtEnd && a.key == key {
                        acount += a.nextPart(until: .including(key)).count
                    }
                    var bcount = 0
                    while !b.isAtEnd && b.key == key {
                        bcount += b.nextPart(until: .including(key)).count
                    }
                    if acount > bcount {
                        return false
                    }
                    if acount < bcount {
                        knownStrict = true
                    }
                    if a.isAtEnd || b.isAtEnd { break outer }
                }
            }
            if a.key < b.key {
                return false
            }
            while b.key < a.key {
                knownStrict = true
                b.nextPart(until: .excluding(a.key))
                if b.isAtEnd { return false }
            }
        }

        if a.isAtEnd {
            if !b.isAtEnd {
                return true
            }
        }
        else if b.isAtEnd {
            return false
        }
        return !strict || knownStrict
    }
}
