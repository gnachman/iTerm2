//
//  Bijection.swift
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

@objc(iTermUntypedBijection)
class ObjCBijection: NSObject {
    private var guts = Bijection<AnyHashable, AnyHashable>()

    @objc(link:to:)
    func link(_ left: AnyHashable, _ right: AnyHashable) {
        guts.set(left, to: right)
    }

    @objc(objectForLeft:)
    func object(forLeft value: AnyHashable) -> AnyHashable? {
        return guts[left: value]
    }

    @objc(objectForRight:)
    func object(forRight value: AnyHashable) -> AnyHashable? {
        return guts[right: value]
    }
}

struct Bijection<LeftType, RightType> where LeftType: Hashable, RightType: Hashable {
    private var forwards = [LeftType: RightType]()
    private var backwards = [RightType: LeftType]()

    mutating func set(_ left: LeftType, to right: RightType) {
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
