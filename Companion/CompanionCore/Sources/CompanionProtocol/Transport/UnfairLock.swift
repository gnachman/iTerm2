//
//  UnfairLock.swift
//  CompanionCore
//
//  Public so the transport and Noise layers can both serialize with it.
//  A minimal os_unfair_lock wrapper whose `withLock` is an ordinary synchronous
//  method. NSLock.lock()/unlock() are annotated unavailable in async contexts
//  (a hard error under the Swift 6 language mode); routing critical sections
//  through this wrapper keeps the locking synchronous and out of async scopes.
//  We never hold the lock across a suspension point.
//

import Foundation

public final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t

    public init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    @discardableResult
    public func withLock<R>(_ body: () -> R) -> R {
        os_unfair_lock_lock(pointer)
        defer { os_unfair_lock_unlock(pointer) }
        return body()
    }
}
