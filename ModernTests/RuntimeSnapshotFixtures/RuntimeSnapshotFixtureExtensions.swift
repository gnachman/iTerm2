//
//  RuntimeSnapshotFixtureExtensions.swift
//  ModernTests
//
//  Swift extensions of the Objective-C fixtures in RuntimeSnapshotFixtures.h,
//  and a Swift fixture class.
//

import Foundation
import RuntimeSnapshotFixtures

extension RuntimeSnapshotFixture {
    // A method added from Swift, as an incremental port does.
    @objc(swiftExtensionMethodWithString:)
    func swiftExtensionMethod(with string: String) -> Int {
        return string.count
    }
}

extension RuntimeSnapshotDuplicateFixture {
    // The same selector as -duplicatedMethod in RuntimeSnapshotFixtures.m.
    @objc
    func duplicatedMethod() -> String {
        return "Swift"
    }

    // The same selector as +duplicatedClassMethod in RuntimeSnapshotFixtures.m.
    @objc
    class func duplicatedClassMethod() -> String {
        return "Swift"
    }
}

// A class declared in Swift. Swift records no ownership code for a `let`, as
// clang does not for a readonly property.
@objc(RuntimeSnapshotSwiftFixture)
final class RuntimeSnapshotSwiftFixture: NSObject {
    @objc let constant: NSString = "constant"
    @objc var variable: NSString = "variable"
}

// Every kind of Swift property that the Objective-C runtime can see.
@objc(RuntimeSnapshotSwiftOwnershipFixture)
final class RuntimeSnapshotSwiftOwnershipFixture: NSObject {
    @objc weak var weakObject: NSObject?
    @objc unowned var unownedObject: NSObject
    @objc unowned(unsafe) var unownedUnsafeObject: NSObject
    @objc var computed: NSObject {
        get {
            return unownedObject
        }
        set {
            unownedObject = newValue
        }
    }
    @objc var computedReadonly: NSObject {
        return unownedObject
    }
    @NSCopying @objc var copied: NSString = ""
    @objc var string: String = ""

    init(object: NSObject) {
        unownedObject = object
        unownedUnsafeObject = object
        super.init()
    }
}

// A Swift subclass of an Objective-C class, which is a Swift class.
@objc(RuntimeSnapshotSwiftSubclassFixture)
final class RuntimeSnapshotSwiftSubclassFixture: RuntimeSnapshotFixtureBase {
    override func baseMethod() {
    }
}

// A Swift class with no Objective-C name. class_getName and NSStringFromClass
// call it ModernTests.RuntimeSnapshotUnnamedSwiftFixture, and NSClassFromString
// also finds it by its mangled name,
// _TtC11ModernTests34RuntimeSnapshotUnnamedSwiftFixture.
final class RuntimeSnapshotUnnamedSwiftFixture: NSObject {
    @objc var value = 0
}

extension RuntimeSnapshotAccessorFixture {
    // A property with a custom getter name, added by an extension as an
    // incremental port adds one. Swift writes no G code for it.
    @objc var extensionNamed: Bool {
        @objc(isExtensionNamed) get {
            return true
        }
    }
}

// A Swift class with a property whose getter has a custom Objective-C name.
// Swift writes no G code for it.
@objc(RuntimeSnapshotSwiftAccessorFixture)
final class RuntimeSnapshotSwiftAccessorFixture: NSObject {
    @objc var named: Bool {
        @objc(isNamed) get {
            return true
        }
    }
}

// Identical except that one property is dynamic, which the runtime does not
// record.
@objc(RuntimeSnapshotSwiftStaticFixture)
final class RuntimeSnapshotSwiftStaticFixture: NSObject {
    @objc var value = 0
}

@objc(RuntimeSnapshotSwiftDynamicFixture)
final class RuntimeSnapshotSwiftDynamicFixture: NSObject {
    @objc dynamic var value = 0
}
