//
//  IdempotentOperationJoiner.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/21.
//

import Foundation

@objc(iTermIdempotentOperationScheduler)
protocol IdempotentOperationScheduler: AnyObject {
    func scheduleIdempotentOperation(_ closure: @escaping () -> Void)
}

// Simplifies setNeedsUpdate/updateIfNeeded. Performs the last closure given to setNeedsUpdate(_:)
// when updateIfNeeded() is called. Thread-safe.
//
// Sample usage:
//
// class Example {
//     private joiner = IdempotentOperationJoiner.asyncJoiner(.main)
//     func scheduleRedraw() {
//         joiner.setNeedsUpdate { [weak self] in redraw() }
//     }
//     func redraw() {
//         …do something expensive…
//     }
// }

@objc(iTermIdempotentOperationJoiner)
class IdempotentOperationJoiner: NSObject {
    typealias Closure = () -> Void
    private var lastClosure = MutableAtomicObject<Closure?>(nil)
    private var invalidated = false

    // This closure's job is to cause updateIfNeeded() to be called eventually. It is run when
    // lastClosure goes from nil to nonnil.
    private let scheduler: ((IdempotentOperationJoiner) -> Void)

    // Schedules updates to run on the next spin of the main loop.
    @objc
    static func asyncJoiner(_ queue: DispatchQueue) -> IdempotentOperationJoiner {
        return IdempotentOperationJoiner() { joiner in
            queue.async {
                joiner.updateIfNeeded()
            }
        }
    }

    @objc(joinerWithScheduler:)
    static func joiner(_ scheduler: IdempotentOperationScheduler) -> IdempotentOperationJoiner {
        return IdempotentOperationJoiner() { [weak scheduler] joiner in
            scheduler?.scheduleIdempotentOperation {
                joiner.updateIfNeeded()
            }
        }
    }

    private override init() {
        it_fatalError()
    }

    private init(_ scheduler: @escaping (IdempotentOperationJoiner) -> Void) {
        self.scheduler = scheduler
    }

    @objc(setNeedsUpdateWithBlock:)
    func setNeedsUpdate(_ closure: @escaping Closure) {
        let previous = lastClosure.getAndSet(closure)
        if previous == nil {
            scheduler(self)
        }
    }

    @objc
    func updateIfNeeded() {
        guard !invalidated else {
            return
        }
        guard let maybeClosure = lastClosure.getAndSet(nil) else {
            return
        }
        maybeClosure()
    }

    @objc
    func invalidate() {
        invalidated = true
    }
}
