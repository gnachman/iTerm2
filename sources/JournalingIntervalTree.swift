//
//  EventuallyConsistentIntervalTree.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/18/22.
//

import Foundation

@objc(iTermEventuallyConsistentIntervalTreeSideEffectPerformer)
protocol EventuallyConsistentIntervalTreeSideEffectPerformer: AnyObject {
    @objc(addEventuallyConsistentIntervalTreeSideEffect:)
    func addSideEffect(_ closure: @escaping () -> ())
}

// The design of the interval tree is not obvious.
//
// The mutation thread has an instance of this class on which it performs additions, removals,
// and mutations.
//
// The main thread has an immutable instance of the "derivative" tree. It does not admit mutations.
// Internally, a mutable instance of the derivative tree is held. It is modified as a side-effect.
// Consequently, the derivative tree is an eventually-consistent copy of this tree. It is
// updated by some external code that performs side-effects and deals with synchronization so that
// the side-effects occur in a critical section where both the main and mutation threads are
// synchronized.
//
// Objects in the interval tree conform to IntervalTreeObject. They are capable of producing a
// "doppelganger" which is the main-thread copy of that object. An object's doppelganger is stable:
// once created, there is a 1:1 correspondance between the "progenitor" object (the original one)
// and its doppelganger.
//
// To modify an object already in the tree and have the change reflected in the doppelganger, use
// the `mutate(_:, closure)` method.
@objc(iTermEventuallyConsistentIntervalTree)
class EventuallyConsistentIntervalTree: IntervalTree {
    private weak var sideEffectPerformer: EventuallyConsistentIntervalTreeSideEffectPerformer?
    @objc var derivative: IntervalTreeReading {
        return _derivative
    }
    private let _derivative: IntervalTree

    @objc(initWithSideEffectPerformer:derivativeIntervalTree:)
    init(_ sideEffectPerformer: EventuallyConsistentIntervalTreeSideEffectPerformer,
         derivative: IntervalTree) {
        self._derivative = derivative
        self.sideEffectPerformer = sideEffectPerformer
        super.init()
    }

    @objc(initWithDictionary:sideEffectPerformer:derivativeIntervalTree:)
    init(dictionary: [AnyHashable : Any],
         sideEffectPerformer: EventuallyConsistentIntervalTreeSideEffectPerformer,
         derivative: IntervalTree) {
        self._derivative = derivative
        self.sideEffectPerformer = sideEffectPerformer
        super.init(dictionary: dictionary)
    }

    @available(*, unavailable)
    override init(dictionary: [AnyHashable : Any]) {
        it_fatalError()
    }

    @objc
    override func add(_ object: IntervalTreeObject, with interval: Interval) {
        super.add(object, with: interval)
        let copyOfInterval = interval.copy(with: nil) as! Interval
        addSideEffect(object) { doppelganger, derivative in
            derivative.add(doppelganger, with: copyOfInterval)
        }
    }

    // Returns whether the object was actually removed.
    @objc
    @discardableResult
    override func remove(_ object: IntervalTreeObject) -> Bool {
        let result = super.remove(object)
        addSideEffect(object) { doppelganger, derivative in
            derivative.remove(doppelganger)
        }
        return result
    }

    // This is faster than calling `remove(_:)` on each object in the tree.
    @objc
    override func removeAllObjects() {
        super.removeAllObjects()
        sideEffectPerformer?.addSideEffect { [weak self] in
            self?._derivative.removeAllObjects()
        }
    }

    // The `closure` gets called twice: once (synchronously) with `object` and a second time (maybe
    // asynchronously) as its doppelganger. As long as all mutations to objects in the interval tree
    // happen through this method, eventual consistency is guaranteed.
    @objc(mutateObject:block:)
    func mutate(_ object: IntervalTreeImmutableObject,
                closure: @escaping (IntervalTreeObject) -> ()) {
#if DEBUG
        super.sanityCheck()
#endif
        closure(object as! IntervalTreeObject)
#if DEBUG
        super.sanityCheck()
#endif
        addSideEffect(object as! IntervalTreeObject) { doppelganger, _ in
            closure(doppelganger)
        }
    }

    // If you know you're making lots of changes at one time, this is a faster version of
    // `mutate(_:, closure)` that only creates one side-effect instead of N.
    @objc(bulkMutateObjects:block:)
    func bulkMutate(_ objects: [IntervalTreeImmutableObject],
                    closure: @escaping (IntervalTreeObject) -> ()) {
        for object in objects {
#if DEBUG
            super.sanityCheck()
#endif
            closure(object as! IntervalTreeObject)
#if DEBUG
            super.sanityCheck()
#endif
        }
        addBulkSideEffect(objects as! [IntervalTreeObject]) { _, doppelganger, _ in
            closure(doppelganger)
        }
    }

    @objc(bulkRemoveObjects:)
    func bulkRemoveObjects(_ objects: [IntervalTreeImmutableObject]) {
        DLog("Will bulk remove. Tree has:\n\(allObjects())")
#if DEBUG
        sanityCheck()
#endif
        for object in objects {
            let ito = object as! IntervalTreeObject
            DLog("->Will remove \(ito.description). Tree has:\n\(allObjects())")
#if DEBUG
            sanityCheck()
#endif
            super.remove(ito)
#if DEBUG
            sanityCheck()
#endif
            DLog("->Did remove \(ito.description). Tree has:\n\(allObjects())")
        }
#if DEBUG
        sanityCheck()
#endif
        addBulkSideEffect(objects as! [IntervalTreeObject]) { i, ito, tree in
            DLog("Running bulk removal side effect on \(ito.description)")
            tree.remove(ito)
        }
        DLog("After bulk remove tree has:\n\(allObjects())")
    }

    @objc(bulkMoveObjects:block:)
    func bulkMoveObjects(_ objects: [IntervalTreeImmutableObject],
                         closure: (IntervalTreeObject) -> Interval) {
        let newIntervals = objects.map { closure($0 as! IntervalTreeObject) }
        for (object, interval) in zip(objects, newIntervals) {
            let ito = object as! IntervalTreeObject
#if DEBUG
super.sanityCheck()
#endif
            super.remove(ito)
            super.add(ito, with: interval)
#if DEBUG
super.sanityCheck()
#endif
        }
        addBulkSideEffect(objects as! [IntervalTreeObject]) { i, ito, tree in
            tree.remove(ito)
            tree.add(ito, with: newIntervals[i])
        }
    }

    private func addSideEffect(_ object: IntervalTreeObject,
                               closure: @escaping (IntervalTreeObject, IntervalTree) -> ()) {
        let doppelganger = object.doppelganger()
        sideEffectPerformer?.addSideEffect { [weak self] in
            if let self = self {
                closure(doppelganger, self._derivative)
            }
        }
    }

    private func addBulkSideEffect(_ objects: [IntervalTreeObject],
                                   closure: @escaping (Int, IntervalTreeObject, IntervalTree) -> ()) {
        let doppelgangers = objects.map { $0.doppelganger() }
        sideEffectPerformer?.addSideEffect { [weak self] in
            if let self = self {
                for (i, doppelganger) in doppelgangers.enumerated() {
                    closure(i, doppelganger, self._derivative)
                }
            }
        }
    }
}
