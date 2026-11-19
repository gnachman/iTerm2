import Foundation

// class NotAClass: Bar { } in a comment must not count.

extension Foo {
    @objc func swiftyThing() { }
    @objc var point: Int { 0 }
    @objc(plainEnum) func pe() -> Int { 0 }
}

@objc(iTermSwiftBar)
final class SwiftBar: Bar {
    override var title: String! { get { "" } set { } }
}

class GenericThing<T>: NSObject where T: Equatable {
    class func make() -> Int { 1 }
}

extension iTermThing {
    @objc func extra() { }
}

class SwiftPair: Base, NSCopying {
    func copy(with zone: NSZone? = nil) -> Any { self }
}
