//
//  Bijection.swift
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

// An object that decides for itself which instances are the same object for the purposes of
// a bijection. Use this when the class's own -isEqual: and -hash can't be dictionary keys, or
// don't describe the identity the bijection needs. Objects with equal identities map to the
// same counterpart. The identity must not change while the object is in a bijection.
protocol BijectionIdentifiable {
    var bijectionIdentity: AnyHashable { get }
}

@objc(iTermUntypedBijection)
class ObjCBijection: NSObject {
    // Keyed by identity (see BijectionIdentifiable).
    private var guts = Bijection<AnyHashable, AnyHashable>()
    // Identity -> the object that was linked, so lookups return objects rather than identities.
    private var leftObjects = [AnyHashable: AnyHashable]()
    private var rightObjects = [AnyHashable: AnyHashable]()

    private func identity(_ value: AnyHashable) -> AnyHashable {
        if let identifiable = value.base as? BijectionIdentifiable {
            return identifiable.bijectionIdentity
        }
        return value
    }

    @objc(link:to:)
    func link(_ left: AnyHashable, _ right: AnyHashable) {
        let leftIdentity = identity(left)
        let rightIdentity = identity(right)
        if let existingRight = guts[left: leftIdentity] {
            rightObjects.removeValue(forKey: existingRight)
        }
        if let existingLeft = guts[right: rightIdentity] {
            leftObjects.removeValue(forKey: existingLeft)
        }
        guts.set(leftIdentity, to: rightIdentity)
        leftObjects[leftIdentity] = left
        rightObjects[rightIdentity] = right
    }

    @objc(objectForLeft:)
    func object(forLeft value: AnyHashable) -> AnyHashable? {
        guard let rightIdentity = guts[left: identity(value)] else {
            return nil
        }
        return rightObjects[rightIdentity]
    }

    @objc(objectForRight:)
    func object(forRight value: AnyHashable) -> AnyHashable? {
        guard let leftIdentity = guts[right: identity(value)] else {
            return nil
        }
        return leftObjects[leftIdentity]
    }
}

// Maintains a 1:1 correspondance between values. Not thread safe.
struct Bijection<LeftType, RightType> where LeftType: Hashable, RightType: Hashable {
    private var forwards = [LeftType: RightType]()
    private var backwards = [RightType: LeftType]()

    mutating func set(_ left: LeftType, to right: RightType) {
        if let existingRight = forwards[left] {
            backwards.removeValue(forKey: existingRight)
        }
        if let existingLeft = backwards[right] {
            forwards.removeValue(forKey: existingLeft)
        }
        forwards[left] = right
        backwards[right] = left
    }

    subscript(left left: LeftType) -> RightType? {
        forwards[left]
    }

    subscript(right right: RightType) -> LeftType? {
        backwards[right]
    }
}
