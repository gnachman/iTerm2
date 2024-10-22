//
//  ConditionVariable.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

class ConditionVariable<T> {
    var value: T
    private let condition = NSCondition()

    init(_ value: T) {
        self.value = value
    }

    func wait<U>(test: (inout T) -> U?) -> U {
        condition.lock()
        defer {
            condition.unlock()
        }
        while true {
            if let result = test(&value) {
                return result
            }
            condition.wait()
        }
    }

    func mutate<U>(_ closure: (inout T) -> U) -> U {
        condition.lock()
        defer {
            condition.unlock()
        }
        let result = closure(&value)
        condition.signal()
        return result
    }

    func sync<U>(_ closure: (inout T) -> U) -> U {
        condition.lock()
        let result = closure(&value)
        condition.unlock()
        return result
    }
}
