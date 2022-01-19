//
//  JournalingIntervalTree.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/18/22.
//

import Foundation

@objc(iTermJournalingIntervalTreeSideEffectPerformer)
protocol JournalingIntervalTreeSideEffectPerformer: AnyObject {
    @objc(addJournalingIntervalTreeSideEffect:)
    func addSideEffect(_ closure: @escaping () -> ())
}

@objc(iTermJournalingIntervalTree)
class JournalingIntervalTree: IntervalTree {
    private weak var sideEffectPerformer: JournalingIntervalTreeSideEffectPerformer?
    @objc let derivative: IntervalTree

    @objc(initWithSideEffectPerformer:derivativeIntervalTree:)
    init(_ sideEffectPerformer: JournalingIntervalTreeSideEffectPerformer,
         derivative: IntervalTree) {
        self.derivative = derivative
        self.sideEffectPerformer = sideEffectPerformer
        super.init()
    }

    @objc(initWithDictionary:sideEffectPerformer:derivativeIntervalTree:)
    init(dictionary: [AnyHashable : Any],
         sideEffectPerformer: JournalingIntervalTreeSideEffectPerformer,
         derivative: IntervalTree) {
        self.derivative = derivative
        self.sideEffectPerformer = sideEffectPerformer
        super.init(dictionary: dictionary)
    }

    @available(*, unavailable)
    override init(dictionary: [AnyHashable : Any]) {
        fatalError()
    }

    @objc
    override func add(_ object: IntervalTreeObject, with interval: Interval) {
        super.add(object, with: interval)
        addSideEffect(object) { doppelganger, derivative in
            derivative.add(doppelganger, with: interval)
        }
    }

    @objc
    override func remove(_ object: IntervalTreeObject) {
        super.remove(object)
        addSideEffect(object) { doppelganger, derivative in
            derivative.remove(doppelganger)
        }
    }

    @objc
    override func removeAllObjects() {
        super.removeAllObjects()
        sideEffectPerformer?.addSideEffect { [weak self] in
            self?.derivative.removeAllObjects()
        }
    }

    @objc(mutateObject:block:)
    func mutate(_ object: IntervalTreeImmutableObject,
                closure: @escaping (IntervalTreeObject) -> ()) {
        closure(object as! IntervalTreeObject)
        addSideEffect(object as! IntervalTreeObject) { doppelganger, _ in
            closure(doppelganger)
        }
    }

    @objc(bulkMutateObjects:block:)
    func bulkMutate(_ objects: [IntervalTreeImmutableObject],
                    closure: @escaping (IntervalTreeObject) -> ()) {
        for object in objects {
            closure(object as! IntervalTreeObject)
        }
        addBulkSideEffect(objects as! [IntervalTreeObject]) { doppelganger, _ in
            closure(doppelganger)
        }
    }

    private func addSideEffect(_ object: IntervalTreeObject,
                               closure: @escaping (IntervalTreeObject, IntervalTree) -> ()) {
        let doppelganger = object.doppelganger()
        sideEffectPerformer?.addSideEffect { [weak self] in
            if let self = self {
                closure(doppelganger, self.derivative)
            }
        }
    }

    private func addBulkSideEffect(_ objects: [IntervalTreeObject],
                                   closure: @escaping (IntervalTreeObject, IntervalTree) -> ()) {
        let doppelgangers = objects.map { $0.doppelganger() }
        sideEffectPerformer?.addSideEffect { [weak self] in
            if let self = self {
                for doppelganger in doppelgangers {
                    closure(doppelganger, self.derivative)
                }
            }
        }
    }
}
