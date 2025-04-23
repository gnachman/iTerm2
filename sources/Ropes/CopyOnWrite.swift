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
// }

protocol Cloning {
    func clone() -> Self
}

@propertyWrapper
struct CopyOnWrite<Storage: AnyObject & Cloning> {
  private var box: Storage
  init(wrappedValue value: Storage) { box = value }
  var wrappedValue: Storage {
    mutating get {
      if !isKnownUniquelyReferenced(&box) {
        box = box.clone()
      }
      return box
    }
    set {
      if !isKnownUniquelyReferenced(&box) {
        box = newValue.clone()
      } else {
        box = newValue
      }
    }
  }
}

