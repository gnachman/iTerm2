//
//  iTermWeakObserverList.swift
//  iTerm2
//
//  A thread-safe list of change callbacks, each kept only as long as its
//  subscriber holds the token it was given.
//

import Foundation
import os

/// Callbacks to run when something changes. Subscribing returns a token; the
/// list holds it weakly, so dropping the token unsubscribes. Safe to use from
/// any thread.
final class WeakObserverList: Sendable {
    private final class Observer: Sendable {
        let changed: @Sendable () -> Void
        init(changed: @escaping @Sendable () -> Void) {
            self.changed = changed
        }
    }

    private struct WeakObserver: Sendable {
        weak var observer: Observer?
    }

    private let observers = OSAllocatedUnfairLock(initialState: [WeakObserver]())

    /// Keep the returned token to stay subscribed.
    func add(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
        let observer = Observer(changed: changed)
        observers.withLock { $0.append(WeakObserver(observer: observer)) }
        return observer
    }

    /// Whether nothing is subscribed any more.
    var isEmpty: Bool {
        return live().isEmpty
    }

    /// Call every subscriber, synchronously, on the calling thread, in the
    /// order they subscribed. The lock is not held while they run, so a
    /// callback may subscribe or drop its token.
    func notify() {
        for observer in live() {
            observer.changed()
        }
    }

    private func live() -> [Observer] {
        return observers.withLock { observers -> [Observer] in
            observers.removeAll { $0.observer == nil }
            return observers.compactMap { $0.observer }
        }
    }
}
