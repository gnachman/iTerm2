//
//  RuntimeSnapshotCrossLanguageTests.swift
//  ModernTests
//
//  Tests of the comparison of a class that moves from Objective-C to Swift,
//  by the rule "identical in meaning" (RuntimeSnapshotComparison.swift,
//  docs/swift-migration/phase0.md section 9). The real snapshot pairs are
//  tested by tools/swift_migration/tests/test_compare_runtime_snapshots.py;
//  these tests cover each rule on its own with small hand-written sections,
//  and the Swift behavior the rules rely on with the port fixtures.
//

import XCTest
import RuntimeSnapshotFixtures

final class RuntimeSnapshotCrossLanguageTests: XCTestCase {
    private var header: String {
        return RuntimeSnapshot.headerLines(architecture: "arm64", buildConfiguration: "Development", buildVariant: "ASan")
            .joined(separator: "\n") + "\n"
    }

    private func section(_ language: String, _ members: [String], superclass: String = "NSObject", image: String = "ModernTests") -> String {
        let body = ["language " + language, "superclass " + superclass, "image " + image,
                    "ivar-arc-flag set", "strong-ivar-layout", "weak-ivar-layout"] + members
        return "class C\n" + body.map { "  " + $0 + "\n" }.joined() + "end class C\n"
    }

    private func port(_ before: [String], _ after: [String],
                      beforeSuperclass: String = "NSObject", afterSuperclass: String = "NSObject",
                      afterImage: String = "ModernTests") -> RuntimeSnapshotComparisonResult {
        let result = RuntimeSnapshotComparison.compare(before: header + section("objc", before, superclass: beforeSuperclass),
                                                       after: header + section("swift", after, superclass: afterSuperclass, image: afterImage))
        XCTAssertEqual(result.errors, [], result.report)
        XCTAssertEqual(result.crossLanguageClasses, ["C"])
        XCTAssertEqual(result.languageChanges, [])
        return result
    }

    // The class-level check every ported class gets, about members Swift
    // callers dispatch directly (not marked dynamic).
    private let dynamicCheckText = "not marked dynamic"

    private func memberChecks(_ result: RuntimeSnapshotComparisonResult) -> [String] {
        return result.checks.filter { !$0.contains(dynamicCheckText) }
    }

    private let property = "instance-property p type=@\"NSObject\" ownership=strong nonatomic ivar=_p raw=T@\"NSObject\",&,N,V_p"
    private let swiftProperty = "instance-property p type=@\"NSObject\" ownership=strong nonatomic ivar=p raw=T@\"NSObject\",N,&,Vp"

    func testIdenticalLinesPass() {
        let result = port(["instance-method -foo types=v16@0:8"], ["instance-method -foo types=v16@0:8"])
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(memberChecks(result), [])
        XCTAssertEqual(result.checks.count, 1, "the class-level check about dynamic dispatch")
        XCTAssertEqual(result.classified, [])
        XCTAssertTrue(result.report.contains("PASS: the snapshots match, and the classes that moved to Swift are identical in meaning apart from the expected differences, with 1 item to check against the source"), result.report)
    }

    func testSuperclassAndImageMustMatch() {
        XCTAssertFalse(port([], [], afterSuperclass: "NSResponder").passed)
        XCTAssertFalse(port([], [], afterImage: "iTerm2").passed)
    }

    func testCxxDestructIsClassified() {
        let added = port([], ["instance-method -.cxx_destruct types=v16@0:8"])
        XCTAssertTrue(added.passed, added.report)
        XCTAssertEqual(added.classified.count, 1)
        let removed = port(["instance-method -.cxx_destruct types=v16@0:8"], [])
        XCTAssertTrue(removed.passed, removed.report)
    }

    func testAddedInitIsACheck() {
        let result = port([], ["instance-method -init types=@16@0:8 also-implemented-by=-NSObject"])
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(memberChecks(result).count, 1)
        XCTAssertTrue(memberChecks(result)[0].contains("may be a stub that Swift synthesizes"), result.report)
    }

    // An initializer the Objective-C class also had is still a check: when
    // the Swift port does not declare or inherit it, Swift's version is a
    // stub that traps, although the line is identical.
    func testKeptInitializersAreChecks() {
        let initLine = "instance-method -init types=@16@0:8 also-implemented-by=-NSObject"
        let frameLine = "instance-method -initWithFrame: types=@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16"
        let result = port([initLine, frameLine], [initLine, frameLine])
        XCTAssertTrue(result.passed, result.report)
        let checks = memberChecks(result)
        XCTAssertEqual(checks.count, 2, result.report)
        XCTAssertTrue(checks[0].hasPrefix("class C: initializer instance-method -init is in the Swift class"), checks[0])
        XCTAssertTrue(checks[1].hasPrefix("class C: initializer instance-method -initWithFrame: is in the Swift class"), checks[1])
        XCTAssertTrue(checks[0].contains("Use of unimplemented initializer"), checks[0])
    }

    // The reviewer's pair: a kept -init and -initWithFrame:, and an int *
    // that became a pointer to a 64-bit integer.
    func testReviewersPair() {
        let result = port(["instance-method -getCount: types=v24@0:8^i16",
                           "instance-method -init types=@16@0:8 also-implemented-by=-NSObject",
                           "instance-method -initWithFrame: types=@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16"],
                          ["instance-method -getCount: types=v24@0:8^q16",
                           "instance-method -init types=@16@0:8 also-implemented-by=-NSObject",
                           "instance-method -initWithFrame: types=@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16"])
        XCTAssertFalse(result.passed, result.report)
        XCTAssertEqual(result.differences, ["class C: changed instance-method -getCount:\n      before: types=v24@0:8^i16\n      after:  types=v24@0:8^q16"])
        XCTAssertEqual(memberChecks(result).count, 2, result.report)
    }

    // Swift lists a stub initWithFrame: (and initWithCoder:) for an NSView
    // subclass that declares only init(foo:); a stub the Objective-C class
    // did not list, overriding a superclass's initializer, is a check, not
    // a new selector.
    func testAddedInheritedInitializerIsACheck() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotPortViewSwiftFixture"])
        XCTAssertTrue(snapshot.contains("\n  instance-method -initWithFrame: types=@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16 also-implemented-by=-NSView\n"), snapshot)
        let result = port([], ["instance-method -initWithFrame: types=@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16 also-implemented-by=-NSView"],
                          beforeSuperclass: "NSView", afterSuperclass: "NSView")
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(memberChecks(result).count, 1, result.report)
        // A new initializer that overrides nothing is a new selector.
        XCTAssertFalse(port([], ["instance-method -initWithFoo: types=@24@0:8q16"]).passed)
    }

    func testInitializerFamily() {
        for selector in ["-init", "-initWithFrame:", "-init:", "-initX", "+new", "+newWithCount:"] {
            XCTAssertTrue(RuntimeSnapshotComparison.isInitializer(selector), selector)
        }
        for selector in ["-initialize", "-initials", "+initialize", "-new", "+newly", "+init", "-foo"] {
            XCTAssertFalse(RuntimeSnapshotComparison.isInitializer(selector), selector)
        }
    }

    // Swift lists -init even for a class whose only initializer takes an
    // argument, which is the case the check above warns about.
    func testSwiftListsInitForAClassWithoutInit() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotPortInitSwiftFixture"])
        XCTAssertTrue(snapshot.contains("\n  instance-method -init types=@16@0:8 also-implemented-by=-NSObject\n"), snapshot)
        XCTAssertTrue(snapshot.contains("\n  instance-method -initWithCount: types=@24@0:8q16\n"), snapshot)
    }

    func testAddedOrRemovedMethodsFail() {
        XCTAssertFalse(port(["instance-method -foo types=v16@0:8"], []).passed)
        XCTAssertFalse(port([], ["instance-method -foo types=v16@0:8"]).passed)
        XCTAssertFalse(port(["class-method +load types=v16@0:8 also-implemented-by=+NSObject"], []).passed)
        XCTAssertFalse(port(["class-method +initialize types=v16@0:8 also-implemented-by=+NSObject"], []).passed)
        XCTAssertFalse(port(["instance-method -foo types=v16@0:8"], ["instance-method -foo types=v16@0:8 also-implemented-by=-NSView"]).passed)
        XCTAssertFalse(port(["instance-method -foo types=v16@0:8"], ["instance-method -foo types=v16@0:8 image=Other"]).passed)
    }

    func testPointeeOnlyEncodingDifferenceIsClassified() {
        let result = port(["instance-method -copyWithZone: types=@24@0:8^{_NSZone=}16"],
                          ["instance-method -copyWithZone: types=@24@0:8^v16"])
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(result.classified.count, 1)
        // What swiftc emits (tmp experiment, recorded in the comparison's
        // comment): ^v for NSZone * and for OpaquePointer, where clang writes
        // a pointer to an incomplete struct, and r^{__CFString=} for
        // CFString, where clang writes ^{__CFString=}.
        XCTAssertTrue(port(["instance-method -f: types=v24@0:8^{Opaque=}16"], ["instance-method -f: types=v24@0:8^v16"]).passed)
        XCTAssertTrue(port(["instance-method -f: types=v24@0:8^{__CFString=}16"], ["instance-method -f: types=v24@0:8r^{__CFString=}16"]).passed)
        // Any other change of pointee fails: its size or type, an object
        // pointee (an out parameter whose ownership matters), a complete
        // struct, or the depth.
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^i16"], ["instance-method -f: types=v24@0:8^q16"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^@16"], ["instance-method -f: types=v24@0:8^v16"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^{Known=i}16"], ["instance-method -f: types=v24@0:8^v16"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^^{_NSZone=}16"], ["instance-method -f: types=v24@0:8^v16"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^i16"], ["instance-method -f: types=v24@0:8^v16"]).passed)
        XCTAssertTrue(port(["instance-method -f: types=v24@0:8^^{_NSZone=}16"], ["instance-method -f: types=v24@0:8^^v16"]).passed)
        // A pointer that became an object, or a changed offset, still fails.
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^v16"], ["instance-method -f: types=v24@0:8@16"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=v24@0:8^v16"], ["instance-method -f: types=v28@0:8^v20"]).passed)
        XCTAssertFalse(port(["instance-method -f: types=c16@0:8"], ["instance-method -f: types=B16@0:8"]).passed)
    }

    func testEncodingComponents() {
        let components = RuntimeSnapshotComparison.encodingComponents("{CGRect={CGPoint=dd}{CGSize=dd}}40@0:8^{_NSZone=}16@\"NSString\"24@?32r*40[3i]48b3")
        XCTAssertEqual(components?.map { $0.type }, ["{CGRect={CGPoint=dd}{CGSize=dd}}", "@", ":", "^{_NSZone=}", "@\"NSString\"", "@?", "r*", "[3i]", "b3"])
        XCTAssertEqual(components?.map { $0.offset }, ["40", "0", "8", "16", "24", "32", "40", "48", ""])
        XCTAssertNil(RuntimeSnapshotComparison.encodingComponents("{CGRect=dd"))
        XCTAssertTrue(RuntimeSnapshotComparison.encodingsDifferOnlyInPointees("v24@0:8^{S=}16", "v24@0:8^v16"))
        XCTAssertFalse(RuntimeSnapshotComparison.encodingsDifferOnlyInPointees("v24@0:8^{S=i}16", "v24@0:8^v16"))
        XCTAssertFalse(RuntimeSnapshotComparison.encodingsDifferOnlyInPointees("v24@0:8^v16", "v24@0:8^v16"))
    }

    func testIvarsVanishAsChecksAndAppearClassified() {
        let result = port(["ivar _p types=@\"NSObject\" ownership=strong layout=s", property],
                          ["ivar p types=@\"NSObject\" ownership=swift layout=", swiftProperty])
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(memberChecks(result).count, 1)
        XCTAssertTrue(memberChecks(result)[0].hasPrefix("class C: Objective-C ivar _p (types=@\"NSObject\" ownership=strong layout=s) is gone"), result.checks[0])
        XCTAssertTrue(result.classified.contains { $0.hasPrefix("class C: Swift storage p ") }, "\(result.classified)")
    }

    // An atomic property becomes nonatomic in every Swift port, because a
    // Swift property is never atomic. The prescribed port stores it in a
    // MutableAtomicObject (concurrency.md section 3), which the runtime cannot
    // see, so the change is one check per property, not a failure.
    func testAtomicBecomingNonatomicIsACheck() {
        let result = port(["instance-property p type=q ownership=assign atomic ivar=_p raw=Tq,V_p",
                           "instance-property o type=@\"NSObject\" ownership=strong atomic ivar=_o raw=T@\"NSObject\",&,V_o"],
                          ["instance-property p type=q ownership=assign nonatomic ivar= raw=Tq,N",
                           "instance-property o type=@\"NSObject\" ownership=strong nonatomic ivar= raw=T@\"NSObject\",N,&"])
        XCTAssertTrue(result.passed, result.report)
        XCTAssertEqual(result.differences, [])
        let checks = memberChecks(result)
        XCTAssertEqual(checks.count, 2, result.report)
        XCTAssertTrue(checks.first?.hasPrefix("class C: changed instance-property o\n") ?? false, result.report)
        XCTAssertTrue(checks.first?.contains("check: property o was atomic: Swift properties are not; check that the port stores it in a MutableAtomicObject and reads and writes it through its value (concurrency.md section 3), or that the dossier shows it was atomic by accident") ?? false, result.report)
        XCTAssertTrue(checks.last?.hasPrefix("class C: changed instance-property p\n") ?? false, result.report)
        XCTAssertTrue(checks.last?.contains("check: property p was atomic: ") ?? false, result.report)
        // The other differences of the property (the backing ivar, the order
        // of the attribute codes) are still classified.
        XCTAssertTrue(result.classified.contains { $0.hasPrefix("class C: changed instance-property p\n") && $0.contains("backing ivar _p became (none)") },
                      result.report)
    }

    // Atomic to nonatomic is a check only when nothing else about the
    // property changed in a way that fails; the failure then names both.
    func testAtomicBecomingNonatomicWithAnotherChangeFails() {
        let atomic = "instance-property p type=q ownership=assign atomic ivar=_p raw=Tq,V_p"
        for after in ["instance-property p type=q ownership=assign nonatomic readonly ivar= raw=Tq,N,R",
                      "instance-property p type=i ownership=assign nonatomic ivar= raw=Ti,N",
                      "instance-property p type=q ownership=strong nonatomic ivar= raw=Tq,N,&"] {
            let result = port([atomic], [after])
            XCTAssertFalse(result.passed, after)
            XCTAssertEqual(result.differences.count, 1, result.report)
            XCTAssertTrue(result.differences.first?.contains("atomic became nonatomic") ?? false, result.report)
            XCTAssertEqual(memberChecks(result), [], result.report)
        }
        // A dropped setter fails as a method; the property's own change is
        // still only a check.
        let droppedSetter = port([atomic, "instance-method -setP: types=v24@0:8q16"],
                                 ["instance-property p type=q ownership=assign nonatomic ivar= raw=Tq,N"])
        XCTAssertFalse(droppedSetter.passed)
        XCTAssertEqual(droppedSetter.differences, ["class C: removed instance-method -setP: types=v24@0:8q16"], droppedSetter.report)
    }

    // A Swift property is never atomic, so nonatomic becoming atomic in a
    // port cannot come from a Swift class: it fails.
    func testNonatomicBecomingAtomicFails() {
        let result = port(["instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p"],
                          ["instance-property p type=q ownership=assign atomic ivar= raw=Tq"])
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.differences.first?.contains("nonatomic became atomic") ?? false, result.report)
        XCTAssertEqual(memberChecks(result), [], result.report)
    }

    func testPropertyRules() {
        // Readonly, type and ownership changes fail.
        XCTAssertFalse(port(["instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p"],
                            ["instance-property p type=q ownership=assign nonatomic readonly ivar= raw=Tq,N,R"]).passed)
        XCTAssertFalse(port(["instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p"],
                            ["instance-property p type=i ownership=assign nonatomic ivar=p raw=Ti,N,Vp"]).passed)
        XCTAssertFalse(port([property], ["instance-property p type=@\"NSObject\" ownership=copy nonatomic ivar=p raw=T@\"NSObject\",N,C,Vp"]).passed)
        // An unretained property has no Swift form the runtime can tell from
        // weak, so it fails (owner queue R5).
        XCTAssertFalse(port(["instance-property p type=@\"NSObject\" ownership=unsafe_unretained nonatomic ivar=_p raw=T@\"NSObject\",N,V_p"],
                            ["instance-property p type=@\"NSObject\" ownership=weak-or-unowned nonatomic ivar=p raw=T@\"NSObject\",N,W,Vp"]).passed)
        // Weak to weak-or-unowned, and unrecorded on either side, are checks.
        let weak = port(["instance-property p type=@\"NSObject\" ownership=weak nonatomic ivar=_p raw=T@\"NSObject\",W,N,V_p"],
                        ["instance-property p type=@\"NSObject\" ownership=weak-or-unowned nonatomic ivar=p raw=T@\"NSObject\",N,W,Vp"])
        XCTAssertTrue(weak.passed, weak.report)
        XCTAssertEqual(memberChecks(weak).count, 1)
        let unrecorded = port(["instance-property p type=@\"NSObject\" ownership=unrecorded nonatomic readonly ivar=_p raw=T@\"NSObject\",R,N,V_p"],
                              ["instance-property p type=@\"NSObject\" ownership=strong nonatomic readonly ivar=p raw=T@\"NSObject\",N,R,&,Vp"])
        XCTAssertTrue(unrecorded.passed, unrecorded.report)
        XCTAssertEqual(memberChecks(unrecorded).count, 1)
        // A custom getter name that Swift does not write is classified only
        // when the getter method is there.
        let getterBefore = "instance-property v type=B ownership=assign nonatomic getter=isV ivar=_v raw=TB,N,GisV,V_v"
        let getterAfter = "instance-property v type=B ownership=assign nonatomic ivar= raw=TB,N"
        XCTAssertTrue(port([getterBefore, "instance-method -isV types=B16@0:8"], [getterAfter, "instance-method -isV types=B16@0:8"]).passed)
        XCTAssertFalse(port([getterBefore], [getterAfter]).passed)
        // A property Swift adds fails; the NSObject protocol's properties and
        // optional protocol properties that it drops are classified.
        XCTAssertFalse(port([], [swiftProperty]).passed)
        XCTAssertFalse(port([property], []).passed)
        XCTAssertTrue(port(["instance-property hash type=Q ownership=assign atomic readonly ivar= raw=TQ,R"], []).passed)
        XCTAssertTrue(port(["instance-property o type=q ownership=assign nonatomic readonly optional ivar= raw=Tq,?,R,N"], []).passed)
        XCTAssertFalse(port(["instance-property hash type=Q ownership=assign atomic ivar= raw=TQ"], []).passed, "a readwrite hash is not the protocol's")
        // A protocol listed once per adopting list is classified; a dropped
        // one fails.
        XCTAssertTrue(port(["protocol P", "protocol P"], ["protocol P"]).passed)
        XCTAssertFalse(port(["protocol P"], []).passed)
    }

    // Swift writes no getter code for a custom getter name, never writes an
    // atomic property, and exposes the setter of an @objc private(set) var,
    // which the faithful port therefore avoids. These facts, which the rules
    // rely on, hold for the fixtures.
    func testSwiftFactsTheRulesRelyOn() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotPortSwiftFixture", "RuntimeSnapshotPortAtomicSwiftFixture"])
        XCTAssertTrue(snapshot.contains("\n  instance-property visible type=B ownership=assign nonatomic ivar= raw=TB,N\n"), snapshot)
        XCTAssertTrue(snapshot.contains("\n  instance-method -isVisible types=B16@0:8\n"), snapshot)
        XCTAssertTrue(snapshot.contains("instance-property atomicObject type=@\"NSObject\" ownership=strong nonatomic "), snapshot)
        XCTAssertTrue(snapshot.contains("\n  instance-method -copyWithZone: types=@24@0:8^v16\n"), snapshot)
    }

    // Every ported class gets one check about dynamic dispatch, because the
    // runtime does not say which Swift members are dynamic.
    func testDynamicDispatchIsAClassLevelCheck() {
        let result = port([], [])
        XCTAssertEqual(result.checks.count, 1)
        XCTAssertTrue(result.checks[0].contains("Swift callers bypass key-value observing and swizzling for members not marked dynamic"), result.checks[0])
    }

    // A dropped -dealloc fails: Swift lists -dealloc only for a class that
    // declares deinit, so its absence means the port has no deinit.
    func testDroppedDeallocFails() {
        let result = port(["instance-method -dealloc types=v16@0:8 also-implemented-by=-NSObject"], [])
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.differences[0].contains("Swift lists -dealloc only for a class that declares deinit"), result.report)
        XCTAssertTrue(port(["instance-method -dealloc types=v16@0:8 also-implemented-by=-NSObject"],
                           ["instance-method -dealloc types=v16@0:8 also-implemented-by=-NSObject"]).passed)
    }
}
