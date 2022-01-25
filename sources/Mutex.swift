//
//  Mutex.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/21.
//
// Eventually I may need to import Atomics, but for now I'd rather not have a big dependency.

import Foundation

class Mutex {
    private let sema = DispatchSemaphore(value: 1)
    private func lock() {
        sema.wait()
    }
    private func unlock() {
        sema.signal()
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
}

