//
//  CopyOnWrite.swift
//  StyleMap
//
//  Created by George Nachman on 4/18/25.
//

// usage:
// class Rope {
//   @CopyOnWrite private var storage: RopeStorage
//
//   init(text: String) {
//     storage = RopeStorage(/*…*/)
//   }
//
//   func append(_ s: String) {
//     storage.append(s)   // wrapper’s getter ensures uniqueness
//   }
//
//   // Never read and write a field of Storage in the same statement. You will end up assigning
//   // to an "original" value that got copied-on-write but the resulting value will be a pre-
//   // assignment clone.
//   func set(s: String, atIndex i: Int) {
//     let replacement = storage.substrings.set(s: s, atIndex: i)
//     storage.substrings = replacement
// }

protocol Cloning {
    func clone() -> Self
}

@propertyWrapper
struct CopyOnWrite<Storage: AnyObject & Cloning> {
    private let mutex = Mutex()
    private var box: Storage
    init(wrappedValue value: Storage) { box = value }
    var wrappedValue: Storage {
        mutating get {
            return mutex.sync {
                if !isKnownUniquelyReferenced(&box) {
                    box = box.clone()
                }
                return box
            }
        }
        set {
            mutex.sync {
                if !isKnownUniquelyReferenced(&box) {
                    box = newValue.clone()
                } else {
                    box = newValue
                }
            }
        }
    }
}

