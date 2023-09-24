//
//  MultiIntervalTree.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/23.
//

import Foundation

@objc
class MultiIntervalTree: NSObject {
    // Maps a class name to a tree.
    var trees = [String: IntervalTree]()
    
    @objc var count: Int {
        return trees.values.reduce(0) { $0 + $1.count }
    }
    @objc var mutableObjects: Array<IntervalTreeObject> {
        return trees.values.flatMap { $0.mutableObjects }
    }

    private let treesKey = "trees"
    private let classNameKey = "className"
    private let encodedTreeKey = "encodedTree"
    
    @objc(initWithDictionary:)
    init(dictionary: [String: AnyObject]) {
        guard let treeDicts = dictionary[treesKey] as? [NSDictionary] else {
            return
        }
        for treeDict in treeDicts {
            if let className = treeDict[classNameKey] as? String,
               let encodedTree = treeDict[encodedTreeKey] as? [AnyHashable: Any] {
                trees[className] = IntervalTree(dictionary: encodedTree)
            }
        }
    }
    
    @objc(addObject:withInterval:)
    func add(object: IntervalTreeObject, interval: Interval) {
        let className = String(describing: type(of: object))
        let preexistingTree = trees[className]
        let tree = preexistingTree ?? IntervalTree()
        tree.add(object, with: interval)
        if preexistingTree == nil {
            trees[className] = tree
        }
    }
    
    @objc(removeObject:)
    func remove(object: IntervalTreeObject) {
        let className = String(describing: type(of: object))
        trees[className]?.remove(object)
    }

    @objc(mutableObjectsInInterval:)
    func objects(in interval: Interval) -> [IntervalTreeObject] {
        let unsorted = trees.values.flatMap {
            $0.mutableObjects(in: interval)
        }
        return unsorted.sorted { lhs, rhs in
            (lhs.entry?.interval.location ?? Int64.min) < (rhs.entry?.interval.location ?? Int64.min)
        }
    }

    @objc(removeAllObjects)
    func removeAllObjects() {
        // We need to leave the entry set on objects so we can't just replace the trees dict.
        for tree in trees.values {
            tree.removeAllObjects()
        }
    }
    
    @objc
    func sanityCheck() {
        for tree in trees.values {
            tree.sanityCheck()
        }
    }
}

extension MultiIntervalTree: IntervalTreeReading {
    var debugString: String {
        return trees.keys.map {
            "\($0): \(trees[$0]!.debugString)"
        }.joined(separator: "\n")
    }
    
    func allObjects() -> [IntervalTreeImmutableObject] {
        let unsorted = trees.values.flatMap { (tree: IntervalTree) in tree.allObjects() }
        return unsorted.sorted { lhs, rhs in
            (lhs.entry?.interval.location ?? Int64.min) < (rhs.entry?.interval.location ?? Int64.min)
        }
    }
    
    func contains(_ object: IntervalTreeImmutableObject?) -> Bool {
        return trees.values.contains { $0.contains(object) }
    }
    
    private func best(search: (IntervalTree) -> ([IntervalTreeImmutableObject]),
                      compare: ([IntervalTreeImmutableObject], [IntervalTreeImmutableObject]) -> Bool) -> [IntervalTreeImmutableObject] {
        let lists = trees.values.map { search($0) }
        return lists.max(by: compare) ?? []
    }
    
    func objectsWithLargestLimit() -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithLargestLimit() ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.limit ?? Int64.min) < (rhs.first?.entry?.interval.limit ?? Int64.min)
        })
    }
    
    func objectsWithSmallestLimit() -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithSmallestLimit() ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.limit ?? Int64.min) >= (rhs.first?.entry?.interval.limit ?? Int64.min)
        })
    }
    
    func objectsWithLargestLocation() -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithLargestLocation() ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.location ?? Int64.min) < (rhs.first?.entry?.interval.location ?? Int64.min)
        })
    }
    
    func objectsWithLargestLocation(before location: Int64) -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithLargestLocation(before: location) ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.location ?? Int64.min) < (rhs.first?.entry?.interval.location ?? Int64.min)
        })
    }
    
    func objectsWithLargestLimit(before limit: Int64) -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithLargestLimit() ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.limit ?? Int64.min) < (rhs.first?.entry?.interval.limit ?? Int64.min)
        })
    }
    
    func objectsWithSmallestLimit(after limit: Int64) -> [IntervalTreeImmutableObject]? {
        return best(search: { (tree: IntervalTree) -> [IntervalTreeImmutableObject] in
            tree.objectsWithSmallestLimit(after: limit) ?? []
        }, compare: { lhs, rhs in
            return (lhs.first?.entry?.interval.limit ?? Int64.min) >= (rhs.first?.entry?.interval.limit ?? Int64.min)
        })
    }
    
    func reverseEnumerator(at start: Int64) -> NSEnumerator & IntervalTreeImmutableObject {
        <#code#>
    }
    
    func reverseLimitEnumerator(at start: Int64) -> NSEnumerator & IntervalTreeImmutableObject {
        <#code#>
    }
    
    func forwardLimitEnumerator(at start: Int64) -> NSEnumerator & IntervalTreeImmutableObject {
        <#code#>
    }
    
    func reverseLimitEnumerator() -> NSEnumerator & IntervalTreeImmutableObject {
        <#code#>
    }
    
    func forwardLimitEnumerator() -> NSEnumerator & IntervalTreeImmutableObject {
        <#code#>
    }
    
    func dictionaryValue(withOffset offset: Int64) -> [AnyHashable : Any] {
        <#code#>
    }
    
    func enumerateLimits(after minimumLimit: Int64, block: @escaping (IntervalTreeObject, UnsafeMutablePointer<ObjCBool>) -> Void) {
        <#code#>
    }
    
    func objects(in interval: Interval) -> [IntervalTreeImmutableObject] {
        <#code#>
    }
    
    
}
