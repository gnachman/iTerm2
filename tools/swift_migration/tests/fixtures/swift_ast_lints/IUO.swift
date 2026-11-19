import Foundation

class FixMine {
    var prop: NSString!
}

func implicitlyUnwrapped(_ old: FixOld, mine: FixMine, visible: FixObjCVisible) {
    let count = old.name.count
    let described: String = old.describe("x")
    let viaClass = FixOld.shared().name
    let viaFunction = FixOldFunction().count
    if let name = old.name { _ = name }
    let chained = old.name?.count
    let kept: String? = old.name
    let swiftSide = mine.prop.length
    let chain = FixOld
        .shared()
        .items()
        .count
    let objcVisible = visible.outlet.length
    let explicit = old.name!
    _ = (count, described, viaClass, viaFunction, chained, kept, swiftSide, chain, objcVisible, explicit)
}

// Written in Swift and visible to Objective-C: its USR is Clang-style (c:@M@...), but it is not from Objective-C.
@objc class FixObjCVisible: NSObject {
    @objc var outlet: NSString!
}
