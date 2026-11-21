//
//  RuntimeSnapshotPortFixtures.swift
//  ModernTests
//
//  The Swift port of RuntimeSnapshotPortObjCFixture (RuntimeSnapshotPortFixtures.h),
//  written as a stage-one port (docs/swift-migration/translation-rules.md
//  section 7): an NSObject subclass with every member @objc, the same
//  selectors, and the same Foundation types. Then variants of it, each
//  wrong in one way that the comparison must catch, and the Swift sides of
//  the two Objective-C classes whose features Swift cannot reproduce.
//
//  Changing anything here changes the snapshot pairs under
//  tools/swift_migration/tests/fixtures/runtime_snapshot_compare/:
//  regenerate them with
//  tools/swift_migration/tests/make_runtime_snapshot_compare_fixtures.sh.
//

import AppKit
import Foundation
import RuntimeSnapshotFixtures

// The faithful port.
@objc(RuntimeSnapshotPortSwiftFixture)
class RuntimeSnapshotPortSwiftFixture: NSObject, RuntimeSnapshotPortFixtureProtocol, NSCopying {
    @objc var strongObject: NSObject?
    @objc weak var weakObject: NSObject?
    @NSCopying @objc var copiedString: NSString = ""
    @objc var count: Int
    @objc let readonlyString: NSString = ""
    @objc var enabled = false
    private var visibleStorage = false
    @objc var visible: Bool {
        @objc(isVisible) get {
            return visibleStorage
        }
        set {
            visibleStorage = newValue
        }
    }
    @objc var handler: (() -> Void)?
    @objc var frame = NSRect.zero
    private var privateCounter = 0

    @objc class var classValue: Int {
        return 7
    }

    @objc(fixtureWithCount:)
    class func fixture(count: Int) -> RuntimeSnapshotPortSwiftFixture {
        return RuntimeSnapshotPortSwiftFixture(count: count)
    }

    @objc init(count: Int) {
        self.count = count
        super.init()
    }

    @objc override convenience init() {
        self.init(count: 0)
    }

    @objc func describe(withPrefix prefix: NSString, count: Int) -> NSString {
        return "\(prefix) \(count) \(privateCounter)" as NSString
    }

    @objc func isReady() -> Bool {
        return true
    }

    @objc func takeBlock(_ block: (Int) -> Void) {
        block(count)
    }

    @objc func rect(byInsetting inset: CGFloat) -> NSRect {
        return frame.insetBy(dx: inset, dy: inset)
    }

    @objc func intValue() -> Int32 {
        return Int32(truncatingIfNeeded: count)
    }

    @objc func charValue() -> CChar {
        return CChar(truncatingIfNeeded: count)
    }

    @objc func protocolMethod() {
    }

    @objc func copy(with zone: NSZone? = nil) -> Any {
        return RuntimeSnapshotPortSwiftFixture(count: count)
    }
}

// Wrong: -charValue was dropped.
@objc(RuntimeSnapshotPortSwiftDroppedMethodFixture)
class RuntimeSnapshotPortSwiftDroppedMethodFixture: NSObject, RuntimeSnapshotPortFixtureProtocol, NSCopying {
    @objc var strongObject: NSObject?
    @objc weak var weakObject: NSObject?
    @NSCopying @objc var copiedString: NSString = ""
    @objc var count: Int
    @objc let readonlyString: NSString = ""
    @objc var enabled = false
    private var visibleStorage = false
    @objc var visible: Bool {
        @objc(isVisible) get {
            return visibleStorage
        }
        set {
            visibleStorage = newValue
        }
    }
    @objc var handler: (() -> Void)?
    @objc var frame = NSRect.zero
    private var privateCounter = 0

    @objc class var classValue: Int {
        return 7
    }

    @objc(fixtureWithCount:)
    class func fixture(count: Int) -> RuntimeSnapshotPortSwiftDroppedMethodFixture {
        return RuntimeSnapshotPortSwiftDroppedMethodFixture(count: count)
    }

    @objc init(count: Int) {
        self.count = count
        super.init()
    }

    @objc override convenience init() {
        self.init(count: 0)
    }

    @objc func describe(withPrefix prefix: NSString, count: Int) -> NSString {
        return "\(prefix) \(count) \(privateCounter)" as NSString
    }

    @objc func isReady() -> Bool {
        return true
    }

    @objc func takeBlock(_ block: (Int) -> Void) {
        block(count)
    }

    @objc func rect(byInsetting inset: CGFloat) -> NSRect {
        return frame.insetBy(dx: inset, dy: inset)
    }

    @objc func intValue() -> Int32 {
        return Int32(truncatingIfNeeded: count)
    }

    @objc func protocolMethod() {
    }

    @objc func copy(with zone: NSZone? = nil) -> Any {
        return RuntimeSnapshotPortSwiftDroppedMethodFixture(count: count)
    }
}

// Wrong: describe(_:count:) has Swift's default selector, describe:count:,
// instead of describeWithPrefix:count:; -intValue returns Int, so its
// encoding is q instead of i; and the class does not adopt
// RuntimeSnapshotPortFixtureProtocol although it still has its method.
@objc(RuntimeSnapshotPortSwiftChangedFixture)
class RuntimeSnapshotPortSwiftChangedFixture: NSObject, NSCopying {
    @objc var strongObject: NSObject?
    @objc weak var weakObject: NSObject?
    @NSCopying @objc var copiedString: NSString = ""
    @objc var count: Int
    @objc let readonlyString: NSString = ""
    @objc var enabled = false
    private var visibleStorage = false
    @objc var visible: Bool {
        @objc(isVisible) get {
            return visibleStorage
        }
        set {
            visibleStorage = newValue
        }
    }
    @objc var handler: (() -> Void)?
    @objc var frame = NSRect.zero
    private var privateCounter = 0

    @objc class var classValue: Int {
        return 7
    }

    @objc(fixtureWithCount:)
    class func fixture(count: Int) -> RuntimeSnapshotPortSwiftChangedFixture {
        return RuntimeSnapshotPortSwiftChangedFixture(count: count)
    }

    @objc init(count: Int) {
        self.count = count
        super.init()
    }

    @objc override convenience init() {
        self.init(count: 0)
    }

    @objc func describe(_ prefix: NSString, count: Int) -> NSString {
        return "\(prefix) \(count) \(privateCounter)" as NSString
    }

    @objc func isReady() -> Bool {
        return true
    }

    @objc func takeBlock(_ block: (Int) -> Void) {
        block(count)
    }

    @objc func rect(byInsetting inset: CGFloat) -> NSRect {
        return frame.insetBy(dx: inset, dy: inset)
    }

    @objc func intValue() -> Int {
        return count
    }

    @objc func charValue() -> CChar {
        return CChar(truncatingIfNeeded: count)
    }

    @objc func protocolMethod() {
    }

    @objc func copy(with zone: NSZone? = nil) -> Any {
        return RuntimeSnapshotPortSwiftChangedFixture(count: count)
    }
}

// Wrong: count is get-only, so Objective-C sees a readonly property and no
// -setCount:.
@objc(RuntimeSnapshotPortSwiftReadonlyFixture)
class RuntimeSnapshotPortSwiftReadonlyFixture: NSObject, RuntimeSnapshotPortFixtureProtocol, NSCopying {
    @objc var strongObject: NSObject?
    @objc weak var weakObject: NSObject?
    @NSCopying @objc var copiedString: NSString = ""
    // A get-only property: Objective-C sees it readonly, with no setter.
    // (A private(set) var would not do: @objc exposes its setter to
    // Objective-C as -setCount: although Swift code cannot call it.)
    private var countStorage: Int
    @objc var count: Int {
        return countStorage
    }
    @objc let readonlyString: NSString = ""
    @objc var enabled = false
    private var visibleStorage = false
    @objc var visible: Bool {
        @objc(isVisible) get {
            return visibleStorage
        }
        set {
            visibleStorage = newValue
        }
    }
    @objc var handler: (() -> Void)?
    @objc var frame = NSRect.zero
    private var privateCounter = 0

    @objc class var classValue: Int {
        return 7
    }

    @objc(fixtureWithCount:)
    class func fixture(count: Int) -> RuntimeSnapshotPortSwiftReadonlyFixture {
        return RuntimeSnapshotPortSwiftReadonlyFixture(count: count)
    }

    @objc init(count: Int) {
        countStorage = count
        super.init()
    }

    @objc override convenience init() {
        self.init(count: 0)
    }

    @objc func describe(withPrefix prefix: NSString, count: Int) -> NSString {
        return "\(prefix) \(count) \(privateCounter)" as NSString
    }

    @objc func isReady() -> Bool {
        return true
    }

    @objc func takeBlock(_ block: (Int) -> Void) {
        block(count)
    }

    @objc func rect(byInsetting inset: CGFloat) -> NSRect {
        return frame.insetBy(dx: inset, dy: inset)
    }

    @objc func intValue() -> Int32 {
        return Int32(truncatingIfNeeded: count)
    }

    @objc func charValue() -> CChar {
        return CChar(truncatingIfNeeded: count)
    }

    @objc func protocolMethod() {
    }

    @objc func copy(with zone: NSZone? = nil) -> Any {
        return RuntimeSnapshotPortSwiftReadonlyFixture(count: count)
    }
}

// The port of RuntimeSnapshotPortLoadObjCFixture: Swift rejects +load and
// +initialize ("defines Objective-C class method 'load', which is not
// permitted by Swift"), so the port has neither.
@objc(RuntimeSnapshotPortLoadSwiftFixture)
class RuntimeSnapshotPortLoadSwiftFixture: NSObject {
    @objc func method() {
    }
}

// The port of RuntimeSnapshotPortAtomicObjCFixture: Swift has no atomic
// properties.
@objc(RuntimeSnapshotPortAtomicSwiftFixture)
class RuntimeSnapshotPortAtomicSwiftFixture: NSObject {
    @objc var atomicObject: NSObject?
}

// A class with a designated initializer that takes an argument and no
// init(), as many ports have, to show whether Swift lists -init for it.
@objc(RuntimeSnapshotPortInitSwiftFixture)
class RuntimeSnapshotPortInitSwiftFixture: NSObject {
    @objc var count: Int

    @objc init(count: Int) {
        self.count = count
        super.init()
    }
}

// An NSView subclass with only init(foo:) and the required init(coder:).
// Swift lists -initWithFrame: for it, a stub that traps, because the class
// does not override the inherited designated initializer.
@objc(RuntimeSnapshotPortViewSwiftFixture)
class RuntimeSnapshotPortViewSwiftFixture: NSView {
    @objc var foo: Int

    @objc init(foo: Int) {
        self.foo = foo
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        foo = 0
        super.init(coder: coder)
    }
}
