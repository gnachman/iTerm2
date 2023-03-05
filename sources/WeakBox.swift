//
//  WeakBox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/5/22.
//

import Foundation

class WeakBox<T> {
    private weak var _value: AnyObject?
    var value: T? {
        _value as? T
    }
    init(_ value: T?) {
        _value = value as AnyObject?
    }
}

// The purpose of a UniqueWeakBox is to make it possible to create a Set of weakly held objects.
// Objects in a set can't change their hash or identity (for the purposes of ==) once added. Weak
// objects can become nil at which point you can't compare them any more. It isn't generally safe
// to use a weak object's address for equality after it's been dealloced since a new one might be
// allocated later with the same address. A UniqueWeakBox is different form a WeakBox in that there
// is only one box for a given object, so there's a 1:1 mapping between objects and their boxes,
// even after the object is freed. The UniqueWeakBox's address is a good proxy for the boxed
// object's address.
//
// In order to correctly conform to UniqueWeakBoxable you need to implement `uniqueWeakBox` as a
// lazy property. Here's a sample of the simplest possible UniqueWeakBoxable class:
//
//    @objc
//    class UWBoxable: UniqueWeakBoxable {
//        lazy var uniqueWeakBox: UniqueWeakBox<UWBoxable> = {
//            UniqueWeakBox(self)
//        }()
//    }
//
// This ensures there is no more than one unique weak box for a given instance.

protocol UniqueWeakBoxable: AnyObject {
    associatedtype BoxedType: UniqueWeakBoxable
    var uniqueWeakBox: UniqueWeakBox<BoxedType> { get }
}

class UniqueWeakBox<T: UniqueWeakBoxable>: WeakBox<T>, Hashable {
    static func == (lhs: UniqueWeakBox<T>, rhs: UniqueWeakBox<T>) -> Bool {
        return lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}
