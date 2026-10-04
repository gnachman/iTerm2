//
//  WeakReferenceTests.swift
//  iTerm2
//
//  Ported from the legacy iTermWeakReferenceTest.m. Exercises iTermWeakReference,
//  the NSProxy-based weak reference that forwards messages to its target.
//

import XCTest
@testable import iTerm2SharedARC

// A weakly referenceable object with an ObjC-visible property that the proxy can forward.
private final class WeakReferenceProbe: NSObject, iTermWeaklyReferenceable {
    @objc var label: String = ""

    func weakSelf() -> Any! {
        return iTermWeakReference<WeakReferenceProbe>(object: self)
    }
}

// Records, during its own deinit, whether the weak reference it holds had already been nullified.
private final class DeinitObservingProbe: NSObject, iTermWeaklyReferenceable {
    var reference: iTermWeakReference<DeinitObservingProbe>?
    var onDeinit: ((Bool) -> Void)?

    func weakSelf() -> Any! {
        return iTermWeakReference<DeinitObservingProbe>(object: self)
    }

    deinit {
        let nullified = reference?.weaklyReferencedObject == nil
        onDeinit?(nullified)
    }
}

final class WeakReferenceTests: XCTestCase {
    private func makeReference(_ object: WeakReferenceProbe) throws -> iTermWeakReference<WeakReferenceProbe> {
        return try XCTUnwrap(object.weakSelf() as? iTermWeakReference<WeakReferenceProbe>)
    }

    // MARK: - Lifetime

    func testWeaklyReferencedObjectIsAvailableBeforeDealloc() throws {
        let object = WeakReferenceProbe()
        let reference = try makeReference(object)
        XCTAssertTrue(reference.weaklyReferencedObject === object)
    }

    func testWeaklyReferencedObjectIsNilAfterDealloc() throws {
        var object: WeakReferenceProbe? = WeakReferenceProbe()
        let reference = try makeReference(try XCTUnwrap(object))
        object = nil
        XCTAssertNil(reference.weaklyReferencedObject)
    }

    func testWeaklyReferencedObjectDoesNotLeakThroughAutoreleasePool() throws {
        var object: WeakReferenceProbe? = WeakReferenceProbe()
        let reference = try makeReference(try XCTUnwrap(object))
        autoreleasepool {
            XCTAssertTrue(reference.weaklyReferencedObject === object)
            object = nil
        }
        XCTAssertNil(reference.weaklyReferencedObject)
    }

    func testTwoWeakReferencesToSameObjectBothNullify() throws {
        var object: WeakReferenceProbe? = WeakReferenceProbe()
        let reference1 = try makeReference(try XCTUnwrap(object))
        let reference2 = try makeReference(try XCTUnwrap(object))
        XCTAssertTrue(reference1.weaklyReferencedObject === object)
        XCTAssertTrue(reference2.weaklyReferencedObject === object)

        object = nil
        XCTAssertNil(reference1.weaklyReferencedObject)
        XCTAssertNil(reference2.weaklyReferencedObject)
    }

    func testReleasingWeakReferenceBeforeObjectLeavesObjectAlive() {
        let object = WeakReferenceProbe()
        weak let weakObject: WeakReferenceProbe? = object
        var reference: iTermWeakReference<WeakReferenceProbe>? = iTermWeakReference(object: object)
        XCTAssertNotNil(reference)
        reference = nil
        XCTAssertNotNil(weakObject)
        XCTAssertTrue(weakObject === object)
    }

    func testReleasingTwoWeakReferencesBeforeObjectLeavesObjectAlive() {
        let object = WeakReferenceProbe()
        weak let weakObject: WeakReferenceProbe? = object
        var reference1: iTermWeakReference<WeakReferenceProbe>? = iTermWeakReference(object: object)
        var reference2: iTermWeakReference<WeakReferenceProbe>? = iTermWeakReference(object: object)
        XCTAssertNotNil(reference1)
        XCTAssertNotNil(reference2)
        reference1 = nil
        reference2 = nil
        XCTAssertNotNil(weakObject)
        XCTAssertTrue(weakObject === object)
    }

    func testReferenceIsNullifiedBeforeObjectDeinitRuns() throws {
        var object: DeinitObservingProbe? = DeinitObservingProbe()
        let reference = try XCTUnwrap(object?.weakSelf() as? iTermWeakReference<DeinitObservingProbe>)
        object?.reference = reference
        var deinitRan = false
        var nullifiedDuringDeinit = false
        object?.onDeinit = { nullified in
            deinitRan = true
            nullifiedDuringDeinit = nullified
        }

        object = nil

        XCTAssertTrue(deinitRan)
        XCTAssertNil(reference.weaklyReferencedObject, "Reference's object not nullified")
        XCTAssertTrue(nullifiedDuringDeinit, "Reference's object nullified after start of object's deinit")
    }

    // MARK: - Forwarding

    func testProxyForwardsExistingMethods() throws {
        let object = WeakReferenceProbe()
        object.label = "1234"
        let reference = try makeReference(object)

        let result = reference.perform(#selector(getter: WeakReferenceProbe.label))?.takeUnretainedValue()
        XCTAssertEqual(result as? String, "1234")
    }

    func testProxyRaisesExceptionOnNonexistentMethods() throws {
        let object = WeakReferenceProbe()
        let reference = try makeReference(object)
        let bogus = Selector(("thisSelectorDoesNotExistAnywhere"))

        XCTAssertThrowsError(try ObjCTry {
            _ = reference.perform(bogus)
        })
    }

    func testProxyReturnsNilForFreedObject() throws {
        var object: WeakReferenceProbe? = WeakReferenceProbe()
        object?.label = "1234"
        let reference = try makeReference(try XCTUnwrap(object))
        object = nil

        let result = reference.perform(#selector(getter: WeakReferenceProbe.label))
        XCTAssertNil(result)
    }

    func testRespondsToSelector() throws {
        let object = WeakReferenceProbe()
        let reference = try makeReference(object)

        // Method from the proxied class.
        XCTAssertTrue(reference.responds(to: #selector(getter: WeakReferenceProbe.label)))
        // Method from iTermWeakReference itself.
        XCTAssertTrue(reference.responds(to: #selector(getter: iTermWeakReference<WeakReferenceProbe>.weaklyReferencedObject)))
        // Method from NSObject.
        XCTAssertTrue(reference.responds(to: #selector(NSObject.isEqual(_:))))
        // Method that does not exist.
        XCTAssertFalse(reference.responds(to: Selector(("thisSelectorDoesNotExistAnywhere"))))
    }
}
