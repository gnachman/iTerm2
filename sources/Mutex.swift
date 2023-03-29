//
//  Mutex.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/21.
//
// Eventually I may need to import Atomics, but for now I'd rather not have a big dependency.

import Foundation

class Mutex {
    // See http://www.russbishop.net/the-law for why pointers are used here.
    private var unfairLock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        unfairLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deallocate()
    }

    private func lock() {
        os_unfair_lock_lock(unfairLock)
    }

    private func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }

    func sync<T>(_ closure: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try closure()
    }
}

// Provides atomic access to an object.
class MutableAtomicObject<T> {
    private let mutex = Mutex()
    private var _value: T

    var value: T {
        set {
            mutex.sync { _value = newValue }
        }
        get {
            return mutex.sync { _value }
        }
    }

    init(_ value: T) {
        _value = value
    }

    // Atomically set the value and return its original value.
    func getAndSet(_ newValue: T) -> T {
        return mutex.sync {
            let original = _value
            _value = newValue
            return original
        }
    }

    @discardableResult
    func mutate(_ block:(T) -> T) -> T {
        return mutex.sync {
            let result = block(_value)
            _value = result
            return result
        }
    }

    func set(_ newValue: T) {
        mutex.sync {
            _value = newValue
        }
    }

    @discardableResult
    func access<Result>(_ block: (T) -> Result) -> Result {
        return mutex.sync {
            return block(_value)
        }
    }

    @discardableResult
    func mutableAccess<Result>(_ block: (inout T) -> Result) -> Result {
        return mutex.sync {
            return block(&_value)
        }
    }
}

// Provides atomic access to an object.
class AtomicQueue<T> {
    private var values = [T]()
    private let mutex = Mutex()
    private let sema = DispatchSemaphore(value: 0)

    func enqueue(_ value: T) {
        mutex.sync {
            values.append(value)
        }
        sema.signal()
    }

    func dequeue() -> T {
        while true {
            sema.wait()
            if let value = tryDequeue() {
                return value
            }
        }
    }

    func tryDequeue() -> T? {
        return mutex.sync { () -> T? in
            guard let value = values.first else {
                return nil
            }
            values.removeFirst()
            return value
        }
    }
}
