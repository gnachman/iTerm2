//
//  MutableArrayOfWeakObjects.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/24.
//

import Foundation

@objc(iTermMutableArrayOfWeakObjects)
class MutableArrayOfWeakObjects: NSObject {
    private var array = [WeakBox<NSObject>]()

    @objc var isEmpty: Bool {
        return array.isEmpty || !array.anySatisfies { $0.value != nil }
    }
    @objc var strongObjects: [NSObject] {
        return array.compactMap { $0.value }
    }

    @objc(removeObjectsPassingTest:)
    func removeAll(where closure: (NSObject) -> (Bool)) {
        array.removeAll { box in
            if let value = box.value {
                return closure(value)
            }
            return true
        }
    }

    @objc(removeAllObjects)
    func removeAll() {
        array = []
    }

    @objc(addObject:)
    func append(_ object: NSObject) {
        array.append(WeakBox(object))
    }

    @objc var count: Int {
        array.count
    }

    @objc
    func prune() {
        array.removeAll { box in
            box.value == nil
        }
    }

    @objc(compactMap:)
    func compactMap(_ closure: (NSObject) -> (NSObject?)) -> MutableArrayOfWeakObjects {
        let result = MutableArrayOfWeakObjects()
        for box in array {
            if let value = box.value, let mapped = closure(value) {
                result.append(mapped)
            }
        }
        return result
    }

    @objc(firstObjectPassingTest:)
    func first(where closure: (NSObject) -> (Bool)) -> NSObject? {
        return array.first { box in
            guard let obj = box.value else {
                return false
            }
            return closure(obj)
        }?.value
    }

    @objc(lastObjectPassingTest:)
    func last(where closure: (NSObject) -> (Bool)) -> NSObject? {
        return array.last { box in
            guard let obj = box.value else {
                return false
            }
            return closure(obj)
        }?.value
    }
}

