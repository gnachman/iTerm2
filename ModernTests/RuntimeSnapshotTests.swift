//
//  RuntimeSnapshotTests.swift
//  ModernTests
//
//  Tests of the runtime snapshot tool (RuntimeSnapshot.swift and
//  RuntimeSnapshotComparison.swift) against the fixture classes in
//  RuntimeSnapshotFixtures/.
//

import MachO
import XCTest
import RuntimeSnapshotFixtures

final class RuntimeSnapshotTests: XCTestCase {
    // BOOL is a C bool on Apple silicon and a signed char on Intel, and the
    // encodings differ accordingly.
    #if arch(x86_64)
    private let bool = "c"
    #else
    private let bool = "B"
    #endif

    // A header line with no value has only its keyword.
    private var configurationLine: String {
        return "build-configuration" + (RuntimeSnapshot.buildConfiguration.map { " " + RuntimeSnapshotFormat.escape($0) } ?? "")
    }

    private var variantLine: String {
        return "build-variant" + (RuntimeSnapshot.buildVariant.map { " " + RuntimeSnapshotFormat.escape($0) } ?? "")
    }

    // The lines that start every snapshot taken on this machine's architecture.
    private var header: String {
        return "# Objective-C runtime snapshot, format 3\narchitecture \(architecture)\n\(configurationLine)\n\(variantLine)\n"
    }

    // A well-formed class section with the given member lines, which are
    // written without their indentation.
    private func section(_ name: String,
                         language: String = "objc",
                         superclass: String? = "NSObject",
                         image: String? = "ModernTests",
                         _ members: String...) -> String {
        let body = ["language " + language,
                    "superclass" + (superclass.map { " " + $0 } ?? ""),
                    "image" + (image.map { " " + $0 } ?? ""),
                    "ivar-arc-flag unknown",
                    "strong-ivar-layout",
                    "weak-ivar-layout"] + members
        return "class \(name)\n" + body.map { "  " + $0 + "\n" }.joined() + "end class \(name)\n"
    }

    private let fixtureClassNames = ["RuntimeSnapshotFixture",
                                     "RuntimeSnapshotFixtureBase",
                                     "RuntimeSnapshotDuplicateFixture",
                                     "RuntimeSnapshotPropertyRepeatFixture",
                                     "RuntimeSnapshotLoadFixture",
                                     "RuntimeSnapshotSwiftFixture",
                                     "RuntimeSnapshotSwiftOwnershipFixture",
                                     "RuntimeSnapshotFixtureSubclass",
                                     "RuntimeSnapshotAccessorFixture"]

    private var expectedFixtureSnapshot: String {
        return """
        # Objective-C runtime snapshot, format 3
        architecture \(architecture)
        \(configurationLine)
        \(variantLine)
        class RuntimeSnapshotFixture
          language objc
          superclass RuntimeSnapshotFixtureBase
          image ModernTests
          ivar-arc-flag set
          strong-ivar-layout 12113300
          weak-ivar-layout 3100
          protocol RuntimeSnapshotFixtureProtocol
          ivar _atomicAssign types=d ownership=scalar layout=
          ivar _atomicStrong types=@"NSObject" ownership=strong layout=s
          ivar _directValue types=q ownership=scalar layout=
          ivar _enabled types=\(bool) ownership=scalar layout=
          ivar _nonatomicAssign types=q ownership=scalar layout=
          ivar _nonatomicCopy types=@"NSString" ownership=strong layout=s
          ivar _nonatomicStrong types=@"NSObject" ownership=strong layout=s
          ivar _nonatomicUnretained types=@"NSObject" ownership=unretained-or-manual layout=
          ivar _nonatomicWeak types=@"NSObject" ownership=weak layout=w
          ivar _readonlyClass types=# ownership=strong layout=s
          ivar _readonlyObject types=@"NSObject" ownership=strong layout=s
          ivar _readwriteClass types=# ownership=strong layout=s
          class-method +baseClassMethod types=v16@0:8 also-implemented-by=+RuntimeSnapshotFixtureBase
          class-method +classMethodWithInteger: types=@20@0:8i16
          class-method +classProperty types=@16@0:8
          class-method +setClassProperty: types=v24@0:8@16
          instance-method -.cxx_destruct types=v16@0:8
          instance-method -atomicAssign types=d16@0:8
          instance-method -atomicStrong types=@16@0:8
          instance-method -instanceMethodWithInteger:object: types=@28@0:8i16@20
          instance-method -isEnabled types=\(bool)16@0:8
          instance-method -nonatomicAssign types=q16@0:8
          instance-method -nonatomicCopy types=@16@0:8
          instance-method -nonatomicStrong types=@16@0:8
          instance-method -nonatomicUnretained types=@16@0:8
          instance-method -nonatomicWeak types=@16@0:8
          instance-method -overriddenMethod types=q16@0:8 also-implemented-by=-RuntimeSnapshotFixtureBase
          instance-method -protocolMethod types=v16@0:8
          instance-method -readonlyClass types=#16@0:8
          instance-method -readonlyObject types=@16@0:8
          instance-method -readonlyValue types=q16@0:8
          instance-method -readwriteClass types=#16@0:8
          instance-method -setAtomicAssign: types=v24@0:8d16
          instance-method -setAtomicStrong: types=v24@0:8@16
          instance-method -setEnabled: types=v20@0:8\(bool)16
          instance-method -setNonatomicAssign: types=v24@0:8q16
          instance-method -setNonatomicCopy: types=v24@0:8@16
          instance-method -setNonatomicStrong: types=v24@0:8@16
          instance-method -setNonatomicUnretained: types=v24@0:8@16
          instance-method -setNonatomicWeak: types=v24@0:8@16
          instance-method -setReadwriteClass: types=v24@0:8#16
          instance-method -swiftExtensionMethodWithString: types=q24@0:8@16
          class-property classProperty type=@"NSString" ownership=copy nonatomic ivar= raw=T@"NSString",C,N
          instance-property atomicAssign type=d ownership=assign atomic ivar=_atomicAssign raw=Td,V_atomicAssign
          instance-property atomicStrong type=@"NSObject" ownership=strong atomic ivar=_atomicStrong raw=T@"NSObject",&,V_atomicStrong
          instance-property dynamicValue type=@"NSObject" ownership=strong nonatomic dynamic ivar= raw=T@"NSObject",&,D,N
          instance-property enabled type=\(bool) ownership=assign nonatomic getter=isEnabled ivar=_enabled raw=T\(bool),N,GisEnabled,V_enabled
          instance-property nonatomicAssign type=q ownership=assign nonatomic ivar=_nonatomicAssign raw=Tq,N,V_nonatomicAssign
          instance-property nonatomicCopy type=@"NSString" ownership=copy nonatomic ivar=_nonatomicCopy raw=T@"NSString",C,N,V_nonatomicCopy
          instance-property nonatomicStrong type=@"NSObject" ownership=strong nonatomic ivar=_nonatomicStrong raw=T@"NSObject",&,N,V_nonatomicStrong
          instance-property nonatomicUnretained type=@"NSObject" ownership=unsafe_unretained nonatomic ivar=_nonatomicUnretained raw=T@"NSObject",N,V_nonatomicUnretained
          instance-property nonatomicWeak type=@"NSObject" ownership=weak nonatomic ivar=_nonatomicWeak raw=T@"NSObject",W,N,V_nonatomicWeak
          instance-property optionalProtocolProperty type=q ownership=assign nonatomic readonly optional ivar= raw=Tq,?,R,N
          instance-property readonlyClass type=# ownership=unrecorded nonatomic readonly ivar=_readonlyClass raw=T#,R,N,V_readonlyClass
          instance-property readonlyObject type=@"NSObject" ownership=unrecorded nonatomic readonly ivar=_readonlyObject raw=T@"NSObject",R,N,V_readonlyObject
          instance-property readonlyValue type=q ownership=assign nonatomic readonly ivar= raw=Tq,R,N
          instance-property readwriteClass type=# ownership=strong nonatomic ivar=_readwriteClass raw=T#,&,N,V_readwriteClass
        end class RuntimeSnapshotFixture

        """
    }

    // MARK: - Snapshot

    // The whole snapshot of the main fixture, which covers instance and class
    // methods, atomic and nonatomic properties, every ownership, readonly, a
    // custom getter, @dynamic, an optional protocol property, a class
    // property, a protocol, an override, and a method added by a Swift
    // extension. The direct property and the direct method are absent because
    // the runtime never sees them.
    func testSnapshotOfFixture() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        XCTAssertEqual(actual, expectedFixtureSnapshot)
    }

    func testDirectMembersAreAbsent() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let lines = actual.components(separatedBy: "\n")
        // The direct property's storage is an ordinary ivar, which is listed.
        XCTAssertEqual(lines.filter { $0.contains("directValue") }, ["  ivar _directValue types=q ownership=scalar layout="])
        XCTAssertFalse(actual.contains("directMethod"))
    }

    // Class-method overrides are attributed to the metaclass that defines
    // them, or to the root class when only its instance method matches.
    func testSnapshotOfBaseClassReportsClassMethodOverrides() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotFixtureBase
              language objc
              superclass NSObject
              image ModernTests
              ivar-arc-flag unknown
              strong-ivar-layout
              weak-ivar-layout
              class-method +baseClassMethod types=v16@0:8
              class-method +initialize types=v16@0:8 also-implemented-by=+NSObject
              class-method +valueForKey: types=@24@0:8@16 also-implemented-by=-NSObject
              instance-method -baseMethod types=v16@0:8
              instance-method -overriddenMethod types=q16@0:8
            end class RuntimeSnapshotFixtureBase

            """)
    }

    // An Objective-C method and a Swift extension method with the same
    // selector both land in the class's method list.
    func testDuplicateSelectorIsReported() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotDuplicateFixture"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotDuplicateFixture
              DUPLICATE class-method +duplicatedClassMethod count=2
              DUPLICATE instance-method -duplicatedMethod count=2
              language objc
              superclass NSObject
              image ModernTests
              ivar-arc-flag unknown
              strong-ivar-layout
              weak-ivar-layout
              class-method +duplicatedClassMethod types=@16@0:8
              class-method +duplicatedClassMethod types=@16@0:8
              instance-method -duplicatedMethod types=@16@0:8
              instance-method -duplicatedMethod types=@16@0:8
            end class RuntimeSnapshotDuplicateFixture

            """)
    }

    // Repeated identical property metadata, which the compiler emits for the
    // NSObject protocol's properties and for the class property of a protocol
    // that both the class and its category adopt, is listed but is not a
    // duplicate. A protocol adopted by the class and again by the category is
    // listed twice.
    func testRepeatedIdenticalPropertiesAreNotDuplicates() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotPropertyRepeatFixture"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotPropertyRepeatFixture
              language objc
              superclass NSObject
              image ModernTests
              ivar-arc-flag unknown
              strong-ivar-layout
              weak-ivar-layout
              protocol RuntimeSnapshotFixtureObjectProtocol
              protocol RuntimeSnapshotFixtureObjectProtocol
              protocol RuntimeSnapshotFixtureOtherObjectProtocol
              class-property repeatedClassProperty type=q ownership=assign nonatomic readonly optional ivar= raw=Tq,?,R,N
              class-property repeatedClassProperty type=q ownership=assign nonatomic readonly optional ivar= raw=Tq,?,R,N
              instance-property debugDescription type=@"NSString" ownership=copy atomic readonly optional ivar= raw=T@"NSString",?,R,C
              instance-property debugDescription type=@"NSString" ownership=copy atomic readonly optional ivar= raw=T@"NSString",?,R,C
              instance-property description type=@"NSString" ownership=copy atomic readonly ivar= raw=T@"NSString",R,C
              instance-property description type=@"NSString" ownership=copy atomic readonly ivar= raw=T@"NSString",R,C
              instance-property hash type=Q ownership=assign atomic readonly ivar= raw=TQ,R
              instance-property hash type=Q ownership=assign atomic readonly ivar= raw=TQ,R
              instance-property superclass type=# ownership=unrecorded atomic readonly ivar= raw=T#,R
              instance-property superclass type=# ownership=unrecorded atomic readonly ivar= raw=T#,R
            end class RuntimeSnapshotPropertyRepeatFixture

            """)
    }

    // Repeats are compared as a count, so losing one is a difference.
    func testChangedRepeatCountFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotPropertyRepeatFixture"])
        var lines = before.components(separatedBy: "\n")
        let index = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("  instance-property hash ") })
        lines.remove(at: index)
        let after = lines.joined(separator: "\n")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.differences, [
            "class RuntimeSnapshotPropertyRepeatFixture: changed instance-property hash\n" +
            "      before: type=Q ownership=assign atomic readonly ivar= raw=TQ,R | type=Q ownership=assign atomic readonly ivar= raw=TQ,R\n" +
            "      after:  type=Q ownership=assign atomic readonly ivar= raw=TQ,R"])
    }

    func testDuplicateLines() {
        let entries = [(name: "-a", detail: "v16@0:8"),
                       (name: "-b", detail: "v16@0:8"),
                       (name: "-a", detail: "v16@0:8"),
                       (name: "-c", detail: "v16@0:8"),
                       (name: "-c", detail: "@16@0:8")]
        XCTAssertEqual(RuntimeSnapshot.duplicateLines(kind: "instance-method", entries: entries, onlyWhenDetailsDiffer: false),
                       ["DUPLICATE instance-method -a count=2", "DUPLICATE instance-method -c count=2"])
        XCTAssertEqual(RuntimeSnapshot.duplicateLines(kind: "instance-property", entries: entries, onlyWhenDetailsDiffer: true),
                       ["DUPLICATE instance-property -c count=2"])
    }

    func testSnapshotIsByteIdenticalAcrossRunsAndInputOrder() throws {
        let first = try RuntimeSnapshot.snapshot(classNames: fixtureClassNames)
        let second = try RuntimeSnapshot.snapshot(classNames: fixtureClassNames)
        let reordered = try RuntimeSnapshot.snapshot(classNames: fixtureClassNames.reversed() + ["RuntimeSnapshotFixture"])
        XCTAssertEqual(Data(first.utf8), Data(second.utf8))
        XCTAssertEqual(Data(first.utf8), Data(reordered.utf8))
    }

    func testUnknownClassThrows() {
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotNoSuchClass"]))
    }

    // MARK: - Comparison

    func testIdenticalSnapshotsPass() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture", "RuntimeSnapshotFixtureBase"])
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertTrue(result.passed, result.report)
        XCTAssertTrue(result.allowed.isEmpty)
    }

    func testMissingMethodFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = removingLines(containing: "-swiftExtensionMethodWithString:", from: before)
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.differences,
                       ["class RuntimeSnapshotFixture: removed instance-method -swiftExtensionMethodWithString: types=q24@0:8@16"])
    }

    func testChangedTypeEncodingFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = before.replacingOccurrences(of: "-nonatomicAssign types=q16@0:8",
                                                with: "-nonatomicAssign types=i16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.differences, [
            "class RuntimeSnapshotFixture: changed instance-method -nonatomicAssign\n" +
            "      before: types=q16@0:8\n" +
            "      after:  types=i16@0:8"])
    }

    func testAtomicToNonatomicFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = before.replacingOccurrences(
            of: "atomicStrong type=@\"NSObject\" ownership=strong atomic ivar=_atomicStrong raw=T@\"NSObject\",&,V_atomicStrong",
            with: "atomicStrong type=@\"NSObject\" ownership=strong nonatomic ivar=_atomicStrong raw=T@\"NSObject\",&,N,V_atomicStrong")
        XCTAssertNotEqual(before, after)
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(single(result.differences).hasPrefix("class RuntimeSnapshotFixture: changed instance-property atomicStrong\n"),
                      result.report)
        // Between two Objective-C snapshots the change is a failure only,
        // never the check a port to Swift gets (concurrency.md section 3).
        XCTAssertEqual(result.checks, [], result.report)
        XCTAssertEqual(result.crossLanguageClasses, [], result.report)
    }

    func testAddedMethodFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        let after = removingLines(containing: "+baseClassMethod", from: before)
        let result = RuntimeSnapshotComparison.compare(before: after, after: before)
        XCTAssertEqual(result.differences,
                       ["class RuntimeSnapshotFixtureBase: added class-method +baseClassMethod types=v16@0:8"])
    }

    // An allow-list used only to test the mechanism; the real list is empty.
    private let testAllowList = [
        RuntimeSnapshotAllowedDifference(kind: "instance-method", name: "-.cxx_destruct", reason: "test entry"),
    ]

    func testAllowListedDifferencePasses() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = removingLines(containing: "-.cxx_destruct", from: before)
        let result = RuntimeSnapshotComparison.compare(before: before, after: after, allowedDifferences: testAllowList)
        XCTAssertTrue(result.passed, result.report)
        XCTAssertTrue(single(result.allowed).hasPrefix("class RuntimeSnapshotFixture: removed instance-method -.cxx_destruct types=v16@0:8\n      allowed because: test entry"),
                      result.report)
    }

    func testAllowListIsEmpty() throws {
        // Adding an entry needs a real port that shows the difference is
        // harmless. Update this test deliberately when that happens.
        XCTAssertTrue(RuntimeSnapshotComparison.allowedDifferences.isEmpty)
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = removingLines(containing: "-.cxx_destruct", from: before)
        XCTAssertFalse(RuntimeSnapshotComparison.compare(before: before, after: after).passed)
    }

    func testAllowListDoesNotCoverOtherKinds() throws {
        // The same selector as a class method is not allowed.
        let before = header + section("C")
        let after = header + section("C", "class-method +.cxx_destruct types=v16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after, allowedDifferences: testAllowList)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.differences, ["class C: added class-method +.cxx_destruct types=v16@0:8"])
    }

    func testDuplicateFailsEvenWhenUnchanged() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotDuplicateFixture"])
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertEqual(result.duplicates, [
            "before: class RuntimeSnapshotDuplicateFixture: DUPLICATE class-method +duplicatedClassMethod count=2",
            "before: class RuntimeSnapshotDuplicateFixture: DUPLICATE instance-method -duplicatedMethod count=2",
            "after: class RuntimeSnapshotDuplicateFixture: DUPLICATE class-method +duplicatedClassMethod count=2",
            "after: class RuntimeSnapshotDuplicateFixture: DUPLICATE instance-method -duplicatedMethod count=2"])
        XCTAssertTrue(result.report.contains("DUPLICATES ("))
    }

    // A port that adds a Swift version of a method without deleting the
    // Objective-C one produces a duplicate, which is caught even though the
    // allow-list and the rest of the comparison would not notice anything else.
    func testIntroducedDuplicateFails() throws {
        let before = header + section("C", "instance-method -foo types=v16@0:8")
        let after = header + section("C",
                                     "DUPLICATE instance-method -foo count=2",
                                     "instance-method -foo types=v16@0:8",
                                     "instance-method -foo types=v16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.duplicates, ["after: class C: DUPLICATE instance-method -foo count=2"])
    }

    func testClassOnlyInOneSnapshotFails() throws {
        let both = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture", "RuntimeSnapshotFixtureBase"])
        let one = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let result = RuntimeSnapshotComparison.compare(before: both, after: one)
        XCTAssertEqual(result.differences, ["class RuntimeSnapshotFixtureBase: only in before"])
    }

    func testInputWithoutHeaderIsAnError() {
        let snapshot = "class C\n  superclass NSObject\nend class C\n"
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors.count, 2)
    }

    func testTruncatedInputIsAnError() {
        let complete = header + section("C")
        let truncated = header + "class C\n  language objc\n  superclass NSObject\n"
        let result = RuntimeSnapshotComparison.compare(before: complete, after: truncated)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["after: class C has no end line, so the snapshot is truncated"])
    }

    private var architecture: String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    private func lines(of className: String) throws -> [String] {
        return try RuntimeSnapshot.snapshot(classNames: [className]).components(separatedBy: "\n")
    }

    // Clang writes no ownership code for a readonly property that is strong,
    // by default or explicitly (it does write C, & and W for readonly copy,
    // retain and weak ones), so the snapshot does not claim one.
    func testReadonlyObjectPropertyOwnershipIsUnrecorded() throws {
        let lines = try lines(of: "RuntimeSnapshotFixture")
        XCTAssertTrue(lines.contains("  instance-property readonlyObject type=@\"NSObject\" ownership=unrecorded nonatomic readonly ivar=_readonlyObject raw=T@\"NSObject\",R,N,V_readonlyObject"),
                      lines.joined(separator: "\n"))
        XCTAssertFalse(lines.contains { $0.contains("readonlyObject") && $0.contains("unsafe_unretained") })
    }

    // A readwrite object property with no ownership code really is assign.
    func testReadwriteUnretainedPropertyIsReportedAsSuch() throws {
        let lines = try lines(of: "RuntimeSnapshotFixture")
        XCTAssertTrue(lines.contains("  instance-property nonatomicUnretained type=@\"NSObject\" ownership=unsafe_unretained nonatomic ivar=_nonatomicUnretained raw=T@\"NSObject\",N,V_nonatomicUnretained"),
                      lines.joined(separator: "\n"))
    }

    func testSnapshotOfSwiftFixture() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotSwiftFixture"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotSwiftFixture
              language swift
              superclass NSObject
              image ModernTests
              ivar-arc-flag set
              strong-ivar-layout
              weak-ivar-layout
              ivar constant types=@"NSString" ownership=swift layout=
              ivar variable types=@"NSString" ownership=swift layout=
              instance-method -.cxx_destruct types=v16@0:8
              instance-method -constant types=@16@0:8
              instance-method -init types=@16@0:8 also-implemented-by=-NSObject
              instance-method -setVariable: types=v24@0:8@16
              instance-method -variable types=@16@0:8
              instance-property constant type=@"NSString" ownership=unrecorded nonatomic readonly ivar=constant raw=T@"NSString",N,R,Vconstant
              instance-property variable type=@"NSString" ownership=strong nonatomic ivar=variable raw=T@"NSString",N,&,Vvariable
            end class RuntimeSnapshotSwiftFixture

            """)
    }

    // Every Swift property kind the runtime sees, including weak, unowned,
    // and unowned(unsafe), which it cannot tell apart, a computed property
    // (which Swift marks strong although it has no storage), @NSCopying, and a
    // String, whose ivar has no Objective-C type.
    func testSnapshotOfSwiftOwnershipFixture() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotSwiftOwnershipFixture"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotSwiftOwnershipFixture
              language swift
              superclass NSObject
              image ModernTests
              ivar-arc-flag set
              strong-ivar-layout
              weak-ivar-layout
              ivar copied types=@"NSString" ownership=swift layout=
              ivar string types=? ownership=swift layout=
              ivar unownedObject types=? ownership=swift layout=
              ivar unownedUnsafeObject types=? ownership=swift layout=
              ivar weakObject types=? ownership=swift layout=
              instance-method -.cxx_destruct types=v16@0:8
              instance-method -computed types=@16@0:8
              instance-method -computedReadonly types=@16@0:8
              instance-method -copied types=@16@0:8
              instance-method -init types=@16@0:8 also-implemented-by=-NSObject
              instance-method -setComputed: types=v24@0:8@16
              instance-method -setCopied: types=v24@0:8@16
              instance-method -setString: types=v24@0:8@16
              instance-method -setUnownedObject: types=v24@0:8@16
              instance-method -setUnownedUnsafeObject: types=v24@0:8@16
              instance-method -setWeakObject: types=v24@0:8@16
              instance-method -string types=@16@0:8
              instance-method -unownedObject types=@16@0:8
              instance-method -unownedUnsafeObject types=@16@0:8
              instance-method -weakObject types=@16@0:8
              instance-property computed type=@"NSObject" ownership=strong nonatomic ivar= raw=T@"NSObject",N,&
              instance-property computedReadonly type=@"NSObject" ownership=unrecorded nonatomic readonly ivar= raw=T@"NSObject",N,R
              instance-property copied type=@"NSString" ownership=copy nonatomic ivar=copied raw=T@"NSString",N,C,Vcopied
              instance-property string type=@"NSString" ownership=copy nonatomic ivar= raw=T@"NSString",N,C
              instance-property unownedObject type=@"NSObject" ownership=weak-or-unowned nonatomic ivar=unownedObject raw=T@"NSObject",N,W,VunownedObject
              instance-property unownedUnsafeObject type=@"NSObject" ownership=weak-or-unowned nonatomic ivar=unownedUnsafeObject raw=T@"NSObject",N,W,VunownedUnsafeObject
              instance-property weakObject type=@"NSObject" ownership=weak-or-unowned nonatomic ivar=weakObject raw=T@"NSObject",N,W,VweakObject
            end class RuntimeSnapshotSwiftOwnershipFixture

            """)
    }

    func testSnapshotOfSwiftSubclassFixture() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotSwiftSubclassFixture"])
        XCTAssertEqual(actual, """
            # Objective-C runtime snapshot, format 3
            architecture \(architecture)
            \(configurationLine)
            \(variantLine)
            class RuntimeSnapshotSwiftSubclassFixture
              language swift
              superclass RuntimeSnapshotFixtureBase
              image ModernTests
              ivar-arc-flag unknown
              strong-ivar-layout
              weak-ivar-layout
              instance-method -baseMethod types=v16@0:8 also-implemented-by=-RuntimeSnapshotFixtureBase
              instance-method -init types=@16@0:8 also-implemented-by=-NSObject
            end class RuntimeSnapshotSwiftSubclassFixture

            """)
    }

    func testSwiftLetOwnershipIsUnrecorded() throws {
        let lines = try lines(of: "RuntimeSnapshotSwiftFixture")
        let constant = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-property constant ") })
        XCTAssertTrue(constant.contains(" ownership=unrecorded "), constant)
        let variable = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-property variable ") })
        XCTAssertTrue(variable.contains(" ownership=strong "), variable)
    }

    func testHeaderRecordsArchitectureAndConfiguration() throws {
        let lines = try lines(of: "RuntimeSnapshotFixtureBase")
        guard lines.count >= 4 else {
            XCTFail("too few lines: \(lines)")
            return
        }
        // The expected values are worked out here from the test host's own
        // path, not taken from RuntimeSnapshot. The host is
        // <directory>/<configuration>/iTerm2.app. In the plain test build the
        // directory is Variant-<name> (Build/Variant-ASan/Development); the
        // builds of tools/swift_migration/sanitizer_tests.sh have none
        // (tmp/sanitizers/<mode>/Build/Development), and then the variant is
        // absent and its line is the bare keyword.
        let appURL = Bundle.main.bundleURL
        let components = appURL.pathComponents
        guard components.count >= 3 else {
            XCTFail("unexpected test host path: \(appURL.path)")
            return
        }
        let configuration = components[components.count - 2]
        let directory = components[components.count - 3]
        let variantPrefix = "Variant-"
        let variant: String? = directory.hasPrefix(variantPrefix) && directory.count > variantPrefix.count ? String(directory.dropFirst(variantPrefix.count)) : nil
        XCTAssertEqual(lines[0], "# Objective-C runtime snapshot, format 3")
        XCTAssertEqual(lines[1], "architecture " + architecture)
        XCTAssertEqual(lines[2], "build-configuration " + RuntimeSnapshotFormat.escape(configuration))
        XCTAssertEqual(lines[3], variant.map { "build-variant " + RuntimeSnapshotFormat.escape($0) } ?? "build-variant")
        XCTAssertFalse(configuration.isEmpty)
        XCTAssertEqual(RuntimeSnapshot.buildConfiguration, configuration)
        XCTAssertEqual(RuntimeSnapshot.buildVariant, variant)
        // A variant is recorded exactly when the host's path has a Variant-
        // directory.
        let pathHasVariant = components.contains { $0.hasPrefix(variantPrefix) && $0.count > variantPrefix.count }
        XCTAssertEqual(RuntimeSnapshot.buildVariant != nil, pathHasVariant, appURL.path)
    }

    // Header values are escaped, and an absent one leaves only the keyword.
    func testHeaderValuesAreEscaped() {
        XCTAssertEqual(RuntimeSnapshot.headerLines(architecture: "arm 64", buildConfiguration: "My Config%", buildVariant: "A\u{e9}San"),
                       ["# Objective-C runtime snapshot, format 3",
                        "architecture arm%2064",
                        "build-configuration My%20Config%25",
                        "build-variant A%C3%A9San"])
        XCTAssertEqual(RuntimeSnapshot.headerLines(architecture: "arm64", buildConfiguration: nil, buildVariant: nil),
                       ["# Objective-C runtime snapshot, format 3",
                        "architecture arm64",
                        "build-configuration",
                        "build-variant"])
    }

    // A header with no build configuration or variant parses, and differs
    // from one with them.
    func testHeaderWithoutConfigurationOrVariant() {
        let bare = "# Objective-C runtime snapshot, format 3\narchitecture \(architecture)\nbuild-configuration\nbuild-variant\n" + section("C")
        XCTAssertEqual(status(bare, bare), 0)
        let named = "# Objective-C runtime snapshot, format 3\narchitecture \(architecture)\nbuild-configuration Development\nbuild-variant ASan\n" + section("C")
        let result = RuntimeSnapshotComparison.compare(before: bare, after: named)
        XCTAssertEqual(result.errors, [
            "The snapshots were taken with different build-configuration: before (no value), after Development. Macros, and so methods, differ between build configurations, so they cannot be compared.",
            "The snapshots were taken with different build-variant: before (no value), after ASan. Sanitizer variants are built with different macros, so they cannot be compared."])
        XCTAssertEqual(status(bare, named), 2)
    }

    func testDifferentArchitecturesAreAnError() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        let other = architecture == "arm64" ? "x86_64" : "arm64"
        let after = before.replacingOccurrences(of: "architecture " + architecture, with: "architecture " + other)
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["The snapshots were taken with different architecture: before \(architecture), after \(other). Type encodings differ between architectures, so they cannot be compared."])
    }

    func testDifferentConfigurationsAreAnError() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        var lines = before.components(separatedBy: "\n")
        guard lines.count > 2, lines[2].hasPrefix("build-configuration ") else {
            XCTFail("unexpected header: \(before)")
            return
        }
        lines[2] = "build-configuration SomethingElse"
        let result = RuntimeSnapshotComparison.compare(before: before, after: lines.joined(separator: "\n"))
        XCTAssertFalse(result.passed)
        XCTAssertTrue(single(result.errors).hasPrefix("The snapshots were taken with different build-configuration: "), result.report)
    }

    func testMissingArchitectureIsAnError() {
        let snapshot = "# Objective-C runtime snapshot, format 3\nbuild-configuration Development\n" + section("C")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["before: no architecture line", "before: no build-variant line",
                                       "after: no architecture line", "after: no build-variant line"])
    }

    func testEmptyClassListThrows() {
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classNames: []))
        XCTAssertThrowsError(try RuntimeSnapshot.classNames(fromList: " , \n"))
        XCTAssertEqual(try RuntimeSnapshot.classNames(fromList: "A, B C"), ["A", "B", "C"])
    }

    func testSnapshotWithNoClassesIsAnError() {
        let empty = header
        let result = RuntimeSnapshotComparison.compare(before: empty, after: empty)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["before: the snapshot contains no classes", "after: the snapshot contains no classes"])
    }

    func testIvarsAreRecorded() throws {
        let lines = try lines(of: "RuntimeSnapshotFixture")
        XCTAssertTrue(lines.contains("  ivar _atomicStrong types=@\"NSObject\" ownership=strong layout=s"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  ivar _enabled types=\(bool) ownership=scalar layout="), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  ivar _directValue types=q ownership=scalar layout="), lines.joined(separator: "\n"))
    }

    func testRemovedIvarFails() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let after = removingLines(containing: "  ivar _nonatomicCopy ", from: before)
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertEqual(result.differences, ["class RuntimeSnapshotFixture: removed ivar _nonatomicCopy types=@\"NSString\" ownership=strong layout=s"])
    }

    func testImageOfClassAndForeignMethod() throws {
        let lines = try lines(of: "RuntimeSnapshotLoadFixture")
        XCTAssertTrue(lines.contains("  image ModernTests"), lines.joined(separator: "\n"))
        // Foundation and CoreFoundation decide which library implements
        // -[NSObject description], so only check that it is not ModernTests.
        let borrowed = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-method -borrowedDescription types=@16@0:8 image=") },
                                     lines.joined(separator: "\n"))
        XCTAssertFalse(borrowed.hasSuffix("image=ModernTests"), borrowed)
        XCTAssertFalse(borrowed.hasSuffix("image="), borrowed)
    }

    // The image line of a class from the app's own binary names that binary.
    // The class is found by enumerating the binary rather than by name, so
    // that editing any app class cannot change this test.
    func testImageOfAppClass() throws {
        let classes = appClasses()
        var images = [String: AnyClass]()
        for entry in classes where images[entry.image] == nil {
            images[entry.image] = entry.cls
        }
        XCTAssertFalse(images.isEmpty, "no binary in the app bundle's MacOS directory defines a class")
        for entry in images {
            let image = entry.key
            let cls: AnyClass = entry.value
            let lines = try RuntimeSnapshot.snapshot(classes: [cls]).components(separatedBy: "\n")
            // Debug builds put the app's code in iTerm2.debug.dylib.
            XCTAssertTrue(lines.contains("  image " + (image as NSString).lastPathComponent), lines.joined(separator: "\n"))
        }
    }

    // +load in a class and in its category both run, so they do not conflict.
    func testLoadInClassAndCategoryIsNotADuplicate() throws {
        let lines = try lines(of: "RuntimeSnapshotLoadFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("  class-method +load ") }.count, 2, lines.joined(separator: "\n"))
        XCTAssertFalse(lines.contains { $0.contains("DUPLICATE") }, lines.joined(separator: "\n"))
    }

    func testClassAppearingTwiceIsAnError() {
        let result = RuntimeSnapshotComparison.compare(before: header + section("C"), after: header + section("C") + section("C"))
        XCTAssertEqual(result.errors, ["after line 20: class C appears more than once"])
    }

    func testClassOpenedInsideClassIsAnError() {
        let snapshot = header + "class C\n  language objc\n" + section("D")
        let result = RuntimeSnapshotComparison.compare(before: header + section("D"), after: snapshot)
        XCTAssertEqual(result.errors, ["after line 7: class D begins before class C ends"])
    }

    func testLineOutsideClassIsAnError() {
        let good = header + section("C")
        let result = RuntimeSnapshotComparison.compare(before: good, after: good + "  instance-method -foo types=v16@0:8\n")
        XCTAssertEqual(result.errors, ["after line 13: “  instance-method -foo types=v16@0:8” is outside a class section"])
    }

    func testMismatchedEndIsAnError() {
        let good = header + section("C")
        let bad = header + section("C").replacingOccurrences(of: "end class C", with: "end class D")
        let result = RuntimeSnapshotComparison.compare(before: good, after: bad)
        XCTAssertEqual(result.errors, ["after line 12: “end class D” does not match the open class C"])
    }

    // MARK: - Ownership and language

    // Swift writes W for weak, unowned, and unowned(unsafe) alike, so for a
    // Swift class the snapshot must not claim weak.
    func testSwiftWeakAndUnownedAreNotCalledWeak() throws {
        let lines = try lines(of: "RuntimeSnapshotSwiftOwnershipFixture")
        for name in ["weakObject", "unownedObject", "unownedUnsafeObject"] {
            let line = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-property \(name) ") })
            XCTAssertTrue(line.contains(" ownership=weak-or-unowned "), line)
        }
    }

    func testLanguage() throws {
        XCTAssertTrue(try lines(of: "RuntimeSnapshotFixture").contains("  language objc"))
        XCTAssertTrue(try lines(of: "RuntimeSnapshotSwiftFixture").contains("  language swift"))
        XCTAssertTrue(try lines(of: "RuntimeSnapshotSwiftSubclassFixture").contains("  language swift"))
        XCTAssertTrue(try lines(of: NSStringFromClass(RuntimeSnapshotUnnamedSwiftFixture.self)).contains("  language swift"))
    }

    func testDifferentVariantsAreAnError() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        let after = before.replacingOccurrences(of: "\(variantLine)\n", with: "build-variant Other\n")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(single(result.errors).hasPrefix("The snapshots were taken with different build-variant: "), result.report)
    }

    func testClassMethodOverrideOfNonRootSuperclass() throws {
        let lines = try lines(of: "RuntimeSnapshotFixture")
        XCTAssertTrue(lines.contains("  class-method +baseClassMethod types=v16@0:8 also-implemented-by=+RuntimeSnapshotFixtureBase"),
                      lines.joined(separator: "\n"))
    }

    // An implementation made at run time is in no loaded binary.
    func testRuntimeMadeMethodHasUnknownImage() throws {
        let lines = try lines(of: "RuntimeSnapshotLoadFixture")
        XCTAssertTrue(lines.contains("  instance-method -blockMethod types=v16@0:8 image="), lines.joined(separator: "\n"))
    }

    // The allow-list covers .cxx_destruct appearing or disappearing, not any
    // other change to it.
    func testAllowListDoesNotCoverChangesToAPresentLine() throws {
        let before = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture"])
        let changed = before.replacingOccurrences(of: "-.cxx_destruct types=v16@0:8", with: "-.cxx_destruct types=v16@0:8 image=Foo")
        XCTAssertNotEqual(before, changed)
        XCTAssertFalse(RuntimeSnapshotComparison.compare(before: before, after: changed, allowedDifferences: testAllowList).passed)

        let line = "  instance-method -.cxx_destruct types=v16@0:8\n"
        let doubled = before.replacingOccurrences(of: line, with: line + line)
        XCTAssertNotEqual(before, doubled)
        let result = RuntimeSnapshotComparison.compare(before: before, after: doubled, allowedDifferences: testAllowList)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.allowed.isEmpty)
    }

    // A class that moves from Swift to Objective-C gets no verdict, and
    // fails.
    func testLanguageChangeFromSwiftIsNotAVerdict() {
        let before = header + """
            class C
              language objc
              superclass NSObject
              image ModernTests
              ivar-arc-flag set
              strong-ivar-layout 0100
              weak-ivar-layout
              ivar _obj types=@"NSObject" ownership=strong layout=s
              instance-property obj type=@"NSObject" ownership=strong nonatomic ivar=_obj raw=T@"NSObject",&,N,V_obj
            end class C

            """
        let after = header + """
            class C
              language swift
              superclass NSObject
              image ModernTests
              ivar-arc-flag set
              strong-ivar-layout
              weak-ivar-layout
              ivar obj types=@"NSObject" ownership=swift layout=
              instance-property obj type=@"NSObject" ownership=strong nonatomic ivar=obj raw=T@"NSObject",N,&,Vobj
            end class C

            """
        // From Objective-C to Swift, the same pair is compared by the rule
        // "identical in meaning" (RuntimeSnapshotCrossLanguageTests.swift).
        let port = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertTrue(port.passed, port.report)
        XCTAssertEqual(port.crossLanguageClasses, ["C"])
        let result = RuntimeSnapshotComparison.compare(before: after, after: before)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.languageChanges, ["class C changed language from swift to objc"])
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertEqual(result.unclassified.count, 4)
        XCTAssertTrue(result.report.hasPrefix("NO VERDICT for these classes:\n  class C changed language from swift to objc\n"), result.report)
        XCTAssertFalse(result.report.contains("PASS"))
        // No verdict is not a verdict of failure either.
        XCTAssertFalse(result.report.contains("FAIL:"), result.report)
        XCTAssertTrue(result.report.hasSuffix("NO VERDICT for some classes, so the comparison does not pass.\n"), result.report)
        XCTAssertEqual(RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "before", "after"],
                                                                readFile: { Data(($0 == "before" ? after : before).utf8) }).status, 1)
    }

    // A class that stays in one language is compared strictly even when
    // another class in the same files changed language.
    func testLanguageChangeOfOneClassLeavesOthersStrict() {
        let before = header + section("C", language: "swift") + section("D")
        let after = header + section("C") + section("D", superclass: "NSResponder")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertEqual(result.languageChanges, ["class C changed language from swift to objc"])
        XCTAssertTrue(single(result.differences).hasPrefix("class D: changed superclass"), result.report)
    }

    func testCommandLineExitCodes() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        let different = snapshot.replacingOccurrences(of: "  instance-method -baseMethod types=v16@0:8\n", with: "")
        XCTAssertNotEqual(snapshot, different)
        let files = ["same": snapshot, "different": different]
        let read: (String) throws -> Data = { path in
            guard let text = files[path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return Data(text.utf8)
        }
        let pass = RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "same"], readFile: read)
        XCTAssertEqual(pass.status, 0)
        XCTAssertTrue(pass.output.hasSuffix("PASS: the snapshots match.\n" + RuntimeSnapshotFormat.notCoveredByPass + "\n"), pass.output)
        XCTAssertEqual(RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "different"], readFile: read).status, 1)
        let missing = RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "missing"], readFile: read)
        XCTAssertEqual(missing.status, 2)
        XCTAssertTrue(missing.error.hasPrefix("Cannot read missing:"), missing.error)
        XCTAssertEqual(RuntimeSnapshotComparison.runCommandLine(arguments: ["x"], readFile: read).status, 2)
        XCTAssertEqual(RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "same", "same"], readFile: read).status, 2)
        // String(contentsOfFile:) would drop a byte-order mark, so the file
        // is read as bytes and one is refused.
        let withMark = RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "marked"], readFile: { path in
            path == "marked" ? Data([0xEF, 0xBB, 0xBF]) + Data(snapshot.utf8) : Data(snapshot.utf8)
        })
        XCTAssertEqual(withMark.status, 2, withMark.output + withMark.error)
        let invalid = RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "same", "invalid"], readFile: { path in
            path == "invalid" ? Data(snapshot.utf8) + Data([0xFF]) : Data(snapshot.utf8)
        })
        XCTAssertEqual(invalid.status, 2, invalid.output + invalid.error)
    }

    // The path from the environment to the output file, in process. That
    // xcodebuild forwards TEST_RUNNER_ variables is checked by running
    // runtime_snapshot.sh; a test cannot run xcodebuild from inside the host.
    func testToolWritesSnapshotFromEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("snapshot.txt").path
        let summary = try RuntimeSnapshotTool.writeRequestedSnapshot(environment: [
            RuntimeSnapshotTool.classesVariable: "RuntimeSnapshotFixtureBase, RuntimeSnapshotDuplicateFixture",
            RuntimeSnapshotTool.outputVariable: output])
        XCTAssertNotNil(summary)
        XCTAssertEqual(try String(contentsOfFile: output, encoding: .utf8),
                       try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotDuplicateFixture", "RuntimeSnapshotFixtureBase"]))

        // A failed run removes the earlier file and writes nothing.
        XCTAssertThrowsError(try RuntimeSnapshotTool.writeRequestedSnapshot(environment: [
            RuntimeSnapshotTool.classesVariable: " , ",
            RuntimeSnapshotTool.outputVariable: output]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output))

        XCTAssertThrowsError(try RuntimeSnapshotTool.writeRequestedSnapshot(environment: [
            RuntimeSnapshotTool.classesVariable: "RuntimeSnapshotFixtureBase",
            RuntimeSnapshotTool.outputVariable: "relative.txt"]))
        XCTAssertNil(try RuntimeSnapshotTool.writeRequestedSnapshot(environment: [:]))
    }

    // Converting a class to an object, as object_getClass(_:) does, runs
    // +initialize; the snapshot must not.
    // The flag is never reset, so this test can be repeated in one process
    // only while it keeps passing: once something has initialized the
    // fixture, every later run in that process fails too, which is the
    // right answer for a run after a failure.
    func testSnapshotDoesNotInitializeTheClass() throws {
        XCTAssertFalse(RuntimeSnapshotInitializeFixtureInitialized.boolValue, "something else initialized the fixture first")
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotInitializeFixture"])
        XCTAssertTrue(actual.contains("class-method +initialize "), actual)
        XCTAssertFalse(RuntimeSnapshotInitializeFixtureInitialized.boolValue)
    }

    func testLanguageOfClassMadeAtRunTime() throws {
        for (name, expected) in [("RuntimeSnapshot.MadeAtRunTime", "unknown"), ("RuntimeSnapshotMadeAtRunTime", "objc")] {
            let cls: AnyClass
            if let existing = NSClassFromString(name) {
                cls = existing
            } else {
                let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
                objc_registerClassPair(made)
                cls = made
            }
            XCTAssertEqual(RuntimeSnapshot.language(of: cls), expected, name)
            XCTAssertTrue(try RuntimeSnapshot.snapshot(classes: [cls]).contains("\n  language \(expected)\n"))
        }
    }

    // The comparison recounts repeated lines rather than trusting DUPLICATE
    // lines.
    func testRepeatedMethodWithoutDuplicateLineFails() {
        let snapshot = header + section("C", "instance-method -foo types=v16@0:8", "instance-method -foo types=v16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.duplicates, ["before: class C: instance-method -foo appears 2 times with no DUPLICATE line",
                                           "after: class C: instance-method -foo appears 2 times with no DUPLICATE line"])
    }

    func testRepeatedLoadAndIdenticalPropertiesWithoutDuplicateLinePass() {
        let snapshot = header + section("C",
                                        "class-method +load types=v16@0:8",
                                        "class-method +load types=v16@0:8",
                                        "instance-property hash type=Q ownership=assign atomic readonly ivar= raw=TQ,R",
                                        "instance-property hash type=Q ownership=assign atomic readonly ivar= raw=TQ,R")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertTrue(result.passed, result.report)
    }

    func testLanguageChangeWithNoOtherDifferenceSaysSo() {
        let before = header + section("C", language: "swift")
        let after = header + section("C")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.unclassified.isEmpty)
        XCTAssertFalse(result.report.contains("UNCLASSIFIED"), result.report)
        XCTAssertTrue(result.report.contains("No other differences were found in them"), result.report)
    }

    // MARK: - Unicode

    // NFC and NFD spellings of one name are different selectors to the
    // runtime, although Swift's String == says they are equal.
    private let nfc = "caf\u{e9}"
    private let nfd = "cafe\u{301}"

    func testComparisonDistinguishesNormalizationForms() {
        XCTAssertEqual(nfc, nfd, "the premise of this test")
        let before = header + section("C", "instance-method -\(RuntimeSnapshotFormat.escape(nfc)) types=v16@0:8")
        let after = header + section("C", "instance-method -\(RuntimeSnapshotFormat.escape(nfd)) types=v16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed, result.report)
        XCTAssertEqual(result.differences.count, 2, result.report)
        XCTAssertEqual(RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "before", "after"],
                                                                readFile: { Data(($0 == "before" ? before : after).utf8) }).status, 1)
    }

    func testComparisonDistinguishesNormalizationFormsOfClassNames() {
        let before = header + section(RuntimeSnapshotFormat.escape(nfc))
        let after = header + section(RuntimeSnapshotFormat.escape(nfd))
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed, result.report)
        XCTAssertEqual(result.differences.count, 2, result.report)
    }

    func testDuplicateLinesDistinguishNormalizationForms() {
        let entries = [(name: "-" + nfc, detail: "v16@0:8"), (name: "-" + nfd, detail: "v16@0:8")]
        XCTAssertEqual(RuntimeSnapshot.duplicateLines(kind: "instance-method", entries: entries, onlyWhenDetailsDiffer: false), [])
    }

    // A class whose two methods differ only in normalization form gets two
    // lines, no DUPLICATE line, in byte order.
    func testSnapshotDistinguishesNormalizationForms() throws {
        let name = "RuntimeSnapshotNormalizationFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let block: @convention(block) (AnyObject) -> Void = { _ in }
            for selector in [nfc, nfd] {
                XCTAssertTrue(class_addMethod(made, NSSelectorFromString(selector), imp_implementationWithBlock(block), "v16@0:8"))
            }
            objc_registerClassPair(made)
            cls = made
        }
        let lines = try RuntimeSnapshot.snapshot(classes: [cls]).components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("  instance-method ") }.map { Array($0.utf8) },
                       ["  instance-method -cafe%CC%81 types=v16@0:8", "  instance-method -caf%C3%A9 types=v16@0:8"].map { Array($0.utf8) })
        XCTAssertFalse(lines.contains { $0.contains("DUPLICATE") })
    }

    // MARK: - More coverage

    func testAlsoImplementedByNamesTheNearestSuperclass() throws {
        let lines = try lines(of: "RuntimeSnapshotFixtureSubclass")
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("  instance-method -overriddenMethod types=q16@0:8 also-implemented-by=-RuntimeSnapshotFixture"), text)
        XCTAssertTrue(lines.contains("  class-method +baseClassMethod types=v16@0:8 also-implemented-by=+RuntimeSnapshotFixture"), text)
    }

    func testDuplicateClassMethodIsReported() throws {
        let lines = try lines(of: "RuntimeSnapshotDuplicateFixture")
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("  DUPLICATE class-method +duplicatedClassMethod count=2"), text)
        XCTAssertEqual(lines.filter { $0.hasPrefix("  class-method +duplicatedClassMethod ") }.count, 2, text)
    }

    func testRepeatedClassMethodOtherThanLoadWithoutDuplicateLineFails() {
        let snapshot = header + section("C", "class-method +foo types=v16@0:8", "class-method +foo types=v16@0:8")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.duplicates, ["before: class C: class-method +foo appears 2 times with no DUPLICATE line",
                                           "after: class C: class-method +foo appears 2 times with no DUPLICATE line"])
    }

    func testRepeatedPropertyWithDifferentAttributesWithoutDuplicateLineFails() {
        let snapshot = header + section("C",
                                        "instance-property p type=q ownership=assign nonatomic ivar= raw=Tq,N",
                                        "instance-property p type=q ownership=assign atomic ivar= raw=Tq")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.duplicates, ["before: class C: instance-property p appears 2 times with no DUPLICATE line",
                                           "after: class C: instance-property p appears 2 times with no DUPLICATE line"])
    }

    func testClassPropertiesUseOnlyTheirAttributeCodes() throws {
        let lines = try lines(of: "RuntimeSnapshotFixture")
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(lines.contains { $0.hasPrefix("  instance-property readwriteClass type=# ownership=strong ") }, text)
        XCTAssertTrue(lines.contains { $0.hasPrefix("  instance-property readonlyClass type=# ownership=unrecorded ") }, text)
    }

    // MARK: - Language that gives no verdict

    private func status(_ before: String, _ after: String) -> Int32 {
        return RuntimeSnapshotComparison.runCommandLine(arguments: ["x", "before", "after"],
                                                        readFile: { Data(($0 == "before" ? before : after).utf8) }).status
    }

    // unknown means the snapshot cannot say which compiler's rules apply, so
    // two unknowns do not make a match: an unknown class's W property is
    // labeled weak-or-unowned, which would hide a change from weak to
    // unowned.
    func testUnknownLanguageOnBothSidesGetsNoVerdict() {
        let snapshot = header + section("C", language: "unknown", "instance-property p type=@ ownership=weak-or-unowned nonatomic ivar=p raw=T@,N,W,Vp")
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.unknownLanguages, ["class C: language unknown in both snapshots"])
        XCTAssertEqual(result.languageChanges, [])
        XCTAssertTrue(result.report.hasPrefix("NO VERDICT for these classes:\n  class C: language unknown in both snapshots\n"), result.report)
        XCTAssertTrue(result.report.contains("it cannot tell a weak property from an unowned one"), result.report)
        XCTAssertFalse(result.report.contains("PASS"), result.report)
        XCTAssertEqual(status(snapshot, snapshot), 1)
    }

    func testUnknownLanguageOnOneSideGetsNoVerdict() {
        let known = header + section("C", "instance-method -foo types=v16@0:8")
        let unknown = header + section("C", language: "unknown")
        let forward = RuntimeSnapshotComparison.compare(before: known, after: unknown)
        XCTAssertFalse(forward.passed)
        XCTAssertEqual(forward.unknownLanguages, ["class C: language objc before, unknown after"])
        XCTAssertEqual(forward.differences, [])
        XCTAssertEqual(forward.unclassified, ["class C: removed instance-method -foo types=v16@0:8"])
        XCTAssertEqual(status(known, unknown), 1)

        let backward = RuntimeSnapshotComparison.compare(before: unknown, after: header + section("C", language: "swift"))
        XCTAssertFalse(backward.passed)
        XCTAssertEqual(backward.unknownLanguages, ["class C: language unknown before, swift after"])
    }

    // The same check on real snapshots of fixture classes.
    func testUnknownLanguageInRealSnapshotGetsNoVerdict() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixture", "RuntimeSnapshotFixtureBase"])
        let unknown = snapshot.replacingOccurrences(of: "\n  language objc\n", with: "\n  language unknown\n")
        XCTAssertNotEqual(snapshot, unknown)
        let both = RuntimeSnapshotComparison.compare(before: unknown, after: unknown)
        XCTAssertFalse(both.passed, both.report)
        XCTAssertEqual(both.unknownLanguages, ["class RuntimeSnapshotFixture: language unknown in both snapshots",
                                               "class RuntimeSnapshotFixtureBase: language unknown in both snapshots"])
        XCTAssertEqual(status(unknown, unknown), 1)
        XCTAssertEqual(status(snapshot, unknown), 1)
        XCTAssertEqual(status(unknown, snapshot), 1)

        let missing = snapshot.replacingOccurrences(of: "\n  language objc\n", with: "\n")
        XCTAssertEqual(status(missing, missing), 2)
        XCTAssertFalse(RuntimeSnapshotComparison.compare(before: missing, after: missing).passed)
    }

    func testMissingLanguageOnBothSidesIsMalformed() {
        let snapshot = header + "class C\n  superclass NSObject\n  image ModernTests\n  ivar-arc-flag unknown\n  strong-ivar-layout\n  weak-ivar-layout\nend class C\n"
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["before: class C: 0 language lines, but a class section has exactly one",
                                       "after: class C: 0 language lines, but a class section has exactly one"])
        XCTAssertEqual(result.unknownLanguages, [])
        XCTAssertEqual(result.invalidLanguages, ["class C: no valid language line in either snapshot"])
        XCTAssertTrue(result.report.contains("see ERRORS"), result.report)
        XCTAssertFalse(result.report.contains("A class whose language is unknown"), result.report)
        XCTAssertEqual(status(snapshot, snapshot), 2)
    }

    func testMissingLanguageOnOneSideIsMalformed() {
        let good = header + section("C")
        let missing = header + "class C\n  superclass NSObject\n  image ModernTests\n  ivar-arc-flag unknown\n  strong-ivar-layout\n  weak-ivar-layout\nend class C\n"
        let result = RuntimeSnapshotComparison.compare(before: good, after: missing)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errors, ["after: class C: 0 language lines, but a class section has exactly one"])
        XCTAssertEqual(result.unknownLanguages, [])
        XCTAssertEqual(result.invalidLanguages, ["class C: no valid language line after"])
        XCTAssertEqual(status(good, missing), 2)
        XCTAssertEqual(status(missing, good), 2)
    }

    func testRepeatedOrUnrecognizedLanguageIsMalformed() {
        let good = header + section("C")
        let repeated = header + section("C", "language objc")
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: good, after: repeated).errors,
                       ["after: class C: 2 language lines, but a class section has exactly one"])
        XCTAssertEqual(status(good, repeated), 2)
        let unrecognized = header + section("C", language: "kotlin")
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: unrecognized, after: unrecognized).errors,
                       ["before: class C: language kotlin is not one of objc, swift, unknown",
                        "after: class C: language kotlin is not one of objc, swift, unknown"])
        XCTAssertEqual(status(unrecognized, unrecognized), 2)
    }

    func testMissingSuperclassOrImageIsMalformed() {
        let good = header + section("C")
        for line in ["  superclass NSObject\n", "  image ModernTests\n"] {
            let missing = good.replacingOccurrences(of: line, with: "")
            XCTAssertNotEqual(good, missing)
            XCTAssertEqual(RuntimeSnapshotComparison.compare(before: missing, after: missing).errors.count, 2, line)
            XCTAssertEqual(status(good, missing), 2, line)
        }
    }

    // MARK: - Every single change fails

    // One edit to a real fixture snapshot: the line `old` (which must occur
    // `occurrences` times; the first is edited) is replaced by `new`, which
    // may be empty to delete it or hold two lines to add one.
    private struct SingleChange {
        var covers: String
        var className = "RuntimeSnapshotFixture"
        var old: String
        var occurrences = 1
        var new: [String]
        // Each must appear in the report.
        var expected: [String]
    }

    private static let strongLine = "  instance-property atomicStrong type=@\"NSObject\" ownership=strong atomic ivar=_atomicStrong raw=T@\"NSObject\",&,V_atomicStrong"

    private static func enabledLine(_ bool: String) -> String {
        return "  instance-property enabled type=\(bool) ownership=assign nonatomic getter=isEnabled ivar=_enabled raw=T\(bool),N,GisEnabled,V_enabled"
    }

    private static let customSetterLine = "  instance-property customSetter type=q ownership=assign nonatomic setter=assignCustomSetter: ivar=_customSetter raw=Tq,N,SassignCustomSetter:,V_customSetter"

    private static func strongLine(replacing old: String, with new: String) -> [String] {
        return [strongLine.replacingOccurrences(of: old, with: new)]
    }

    private var singleChanges: [SingleChange] {
        let strong = Self.strongLine
        let changedStrong = "class RuntimeSnapshotFixture: changed instance-property atomicStrong"
        return [
            SingleChange(covers: "language",
                         className: "RuntimeSnapshotSwiftFixture",
                         old: "  language swift", new: ["  language objc"],
                         expected: ["class RuntimeSnapshotSwiftFixture changed language from swift to objc"]),
            SingleChange(covers: "language unknown",
                         old: "  language objc", new: ["  language unknown"],
                         expected: ["class RuntimeSnapshotFixture: language objc before, unknown after"]),
            SingleChange(covers: "superclass",
                         old: "  superclass RuntimeSnapshotFixtureBase", new: ["  superclass NSObject"],
                         expected: ["class RuntimeSnapshotFixture: changed superclass\n      before: RuntimeSnapshotFixtureBase\n      after:  NSObject"]),
            SingleChange(covers: "superclass to none",
                         old: "  superclass RuntimeSnapshotFixtureBase", new: ["  superclass"],
                         expected: ["class RuntimeSnapshotFixture: changed superclass\n      before: RuntimeSnapshotFixtureBase\n      after:  (no value)"]),
            SingleChange(covers: "image",
                         old: "  image ModernTests", new: ["  image Other"],
                         expected: ["class RuntimeSnapshotFixture: changed image\n      before: ModernTests\n      after:  Other"]),
            SingleChange(covers: "image to none",
                         old: "  image ModernTests", new: ["  image"],
                         expected: ["class RuntimeSnapshotFixture: changed image\n      before: ModernTests\n      after:  (no value)"]),
            SingleChange(covers: "protocol added",
                         old: "  protocol RuntimeSnapshotFixtureProtocol",
                         new: ["  protocol RuntimeSnapshotFixtureProtocol", "  protocol RuntimeSnapshotAddedProtocol"],
                         expected: ["class RuntimeSnapshotFixture: added protocol RuntimeSnapshotAddedProtocol"]),
            SingleChange(covers: "protocol removed",
                         old: "  protocol RuntimeSnapshotFixtureProtocol", new: [],
                         expected: ["class RuntimeSnapshotFixture: removed protocol RuntimeSnapshotFixtureProtocol"]),
            SingleChange(covers: "protocol renamed",
                         old: "  protocol RuntimeSnapshotFixtureProtocol", new: ["  protocol RuntimeSnapshotRenamedProtocol"],
                         expected: ["class RuntimeSnapshotFixture: removed protocol RuntimeSnapshotFixtureProtocol",
                                    "class RuntimeSnapshotFixture: added protocol RuntimeSnapshotRenamedProtocol"]),
            SingleChange(covers: "protocol adopted once fewer",
                         className: "RuntimeSnapshotPropertyRepeatFixture",
                         old: "  protocol RuntimeSnapshotFixtureObjectProtocol", occurrences: 2, new: [],
                         expected: ["class RuntimeSnapshotPropertyRepeatFixture: changed protocol RuntimeSnapshotFixtureObjectProtocol"]),
            SingleChange(covers: "ivar added",
                         old: "  ivar _atomicAssign types=d ownership=scalar layout=", new: ["  ivar _atomicAssign types=d ownership=scalar layout=", "  ivar _atomicAssignToo types=d ownership=scalar layout="],
                         expected: ["class RuntimeSnapshotFixture: added ivar _atomicAssignToo types=d ownership=scalar layout="]),
            SingleChange(covers: "ivar removed",
                         old: "  ivar _atomicAssign types=d ownership=scalar layout=", new: [],
                         expected: ["class RuntimeSnapshotFixture: removed ivar _atomicAssign types=d ownership=scalar layout="]),
            SingleChange(covers: "ivar renamed",
                         old: "  ivar _atomicAssign types=d ownership=scalar layout=", new: ["  ivar _atomicAssignRenamed types=d ownership=scalar layout="],
                         expected: ["class RuntimeSnapshotFixture: removed ivar _atomicAssign types=d ownership=scalar layout=",
                                    "class RuntimeSnapshotFixture: added ivar _atomicAssignRenamed types=d ownership=scalar layout="]),
            SingleChange(covers: "ivar type",
                         old: "  ivar _atomicAssign types=d ownership=scalar layout=", new: ["  ivar _atomicAssign types=f ownership=scalar layout="],
                         expected: ["class RuntimeSnapshotFixture: changed ivar _atomicAssign\n      before: types=d ownership=scalar layout=\n      after:  types=f ownership=scalar layout="]),
            SingleChange(covers: "class-method added",
                         old: "  class-method +classProperty types=@16@0:8",
                         new: ["  class-method +classProperty types=@16@0:8", "  class-method +classPropertyToo types=@16@0:8"],
                         expected: ["class RuntimeSnapshotFixture: added class-method +classPropertyToo types=@16@0:8"]),
            SingleChange(covers: "class-method removed",
                         old: "  class-method +classProperty types=@16@0:8", new: [],
                         expected: ["class RuntimeSnapshotFixture: removed class-method +classProperty types=@16@0:8"]),
            SingleChange(covers: "class-method types",
                         old: "  class-method +classProperty types=@16@0:8", new: ["  class-method +classProperty types=#16@0:8"],
                         expected: ["class RuntimeSnapshotFixture: changed class-method +classProperty"]),
            SingleChange(covers: "class-method also-implemented-by",
                         old: "  class-method +baseClassMethod types=v16@0:8 also-implemented-by=+RuntimeSnapshotFixtureBase",
                         new: ["  class-method +baseClassMethod types=v16@0:8"],
                         expected: ["class RuntimeSnapshotFixture: changed class-method +baseClassMethod"]),
            SingleChange(covers: "class-method image",
                         old: "  class-method +classProperty types=@16@0:8", new: ["  class-method +classProperty types=@16@0:8 image=Other"],
                         expected: ["class RuntimeSnapshotFixture: changed class-method +classProperty"]),
            SingleChange(covers: "instance-method added",
                         old: "  instance-method -protocolMethod types=v16@0:8",
                         new: ["  instance-method -protocolMethod types=v16@0:8", "  instance-method -protocolMethodToo types=v16@0:8"],
                         expected: ["class RuntimeSnapshotFixture: added instance-method -protocolMethodToo types=v16@0:8"]),
            SingleChange(covers: "instance-method removed",
                         old: "  instance-method -protocolMethod types=v16@0:8", new: [],
                         expected: ["class RuntimeSnapshotFixture: removed instance-method -protocolMethod types=v16@0:8"]),
            SingleChange(covers: "instance-method types",
                         old: "  instance-method -protocolMethod types=v16@0:8", new: ["  instance-method -protocolMethod types=v24@0:8@16"],
                         expected: ["class RuntimeSnapshotFixture: changed instance-method -protocolMethod"]),
            SingleChange(covers: "instance-method also-implemented-by",
                         old: "  instance-method -overriddenMethod types=q16@0:8 also-implemented-by=-RuntimeSnapshotFixtureBase",
                         new: ["  instance-method -overriddenMethod types=q16@0:8 also-implemented-by=-NSObject"],
                         expected: ["class RuntimeSnapshotFixture: changed instance-method -overriddenMethod"]),
            SingleChange(covers: "instance-method image",
                         old: "  instance-method -protocolMethod types=v16@0:8", new: ["  instance-method -protocolMethod types=v16@0:8 image=Other"],
                         expected: ["class RuntimeSnapshotFixture: changed instance-method -protocolMethod\n      before: types=v16@0:8\n      after:  types=v16@0:8 image=Other"]),
            SingleChange(covers: "instance-method image none",
                         old: "  instance-method -protocolMethod types=v16@0:8", new: ["  instance-method -protocolMethod types=v16@0:8 image="],
                         expected: ["class RuntimeSnapshotFixture: changed instance-method -protocolMethod\n      before: types=v16@0:8\n      after:  types=v16@0:8 image="]),
            SingleChange(covers: "class-property",
                         old: "  class-property classProperty type=@\"NSString\" ownership=copy nonatomic ivar= raw=T@\"NSString\",C,N",
                         new: ["  class-property classProperty type=@\"NSString\" ownership=strong nonatomic ivar= raw=T@\"NSString\",C,N"],
                         expected: ["class RuntimeSnapshotFixture: changed class-property classProperty"]),
            SingleChange(covers: "class-property repeated once fewer",
                         className: "RuntimeSnapshotPropertyRepeatFixture",
                         old: "  class-property repeatedClassProperty type=q ownership=assign nonatomic readonly optional ivar= raw=Tq,?,R,N",
                         occurrences: 2, new: [],
                         expected: ["class RuntimeSnapshotPropertyRepeatFixture: changed class-property repeatedClassProperty"]),
            SingleChange(covers: "instance-property added",
                         old: strong, new: [strong, strong.replacingOccurrences(of: "property atomicStrong ", with: "property atomicStrongToo ")],
                         expected: ["class RuntimeSnapshotFixture: added instance-property atomicStrongToo"]),
            SingleChange(covers: "instance-property removed",
                         old: strong, new: [],
                         expected: ["class RuntimeSnapshotFixture: removed instance-property atomicStrong"]),
            SingleChange(covers: "instance-property type",
                         old: strong, new: Self.strongLine(replacing: "type=@\"NSObject\"", with: "type=@\"NSString\""),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property ownership",
                         old: strong, new: Self.strongLine(replacing: "ownership=strong", with: "ownership=weak"),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property atomicity",
                         old: strong, new: Self.strongLine(replacing: " atomic ", with: " nonatomic "),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property readonly",
                         old: strong, new: Self.strongLine(replacing: " atomic ", with: " atomic readonly "),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property dynamic",
                         old: strong, new: Self.strongLine(replacing: " atomic ", with: " atomic dynamic "),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property optional",
                         old: strong, new: Self.strongLine(replacing: " atomic ", with: " atomic optional "),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property getter",
                         old: Self.enabledLine(bool), new: [Self.enabledLine(bool).replacingOccurrences(of: " getter=isEnabled ", with: " getter=isOn ")],
                         expected: ["class RuntimeSnapshotFixture: changed instance-property enabled"]),
            SingleChange(covers: "instance-property getter removed",
                         old: Self.enabledLine(bool), new: [Self.enabledLine(bool).replacingOccurrences(of: " getter=isEnabled ", with: " ")],
                         expected: ["class RuntimeSnapshotFixture: changed instance-property enabled"]),
            SingleChange(covers: "instance-property setter",
                         className: "RuntimeSnapshotAccessorFixture",
                         old: Self.customSetterLine, new: [Self.customSetterLine.replacingOccurrences(of: " setter=assignCustomSetter: ", with: " setter=setOther: ")],
                         expected: ["class RuntimeSnapshotAccessorFixture: changed instance-property customSetter"]),
            SingleChange(covers: "instance-property setter removed",
                         className: "RuntimeSnapshotAccessorFixture",
                         old: Self.customSetterLine, new: [Self.customSetterLine.replacingOccurrences(of: " setter=assignCustomSetter: ", with: " ")],
                         expected: ["class RuntimeSnapshotAccessorFixture: changed instance-property customSetter"]),
            SingleChange(covers: "instance-property ivar",
                         old: strong, new: Self.strongLine(replacing: "ivar=_atomicStrong", with: "ivar=_other"),
                         expected: [changedStrong]),
            SingleChange(covers: "instance-property raw",
                         old: strong, new: Self.strongLine(replacing: "raw=T@\"NSObject\",&,V_atomicStrong", with: "raw=T@\"NSObject\",&,N,V_atomicStrong"),
                         expected: [changedStrong]),
            SingleChange(covers: "DUPLICATE",
                         old: "  language objc", new: ["  DUPLICATE instance-method -protocolMethod count=2", "  language objc"],
                         expected: ["DUPLICATES (", "after: class RuntimeSnapshotFixture: DUPLICATE instance-method -protocolMethod count=2"]),
            SingleChange(covers: "ivar ownership",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  ivar _object types=@ ownership=strong layout=s", new: ["  ivar _object types=@ ownership=weak layout=s"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed ivar _object\n      before: types=@ ownership=strong layout=s\n      after:  types=@ ownership=weak layout=s"]),
            SingleChange(covers: "ivar layout",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  ivar _object types=@ ownership=strong layout=s", new: ["  ivar _object types=@ ownership=strong layout=w"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed ivar _object"]),
            SingleChange(covers: "ivar-arc-flag",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  ivar-arc-flag set", new: ["  ivar-arc-flag clear"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed ivar-arc-flag\n      before: set\n      after:  clear"]),
            SingleChange(covers: "strong-ivar-layout",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  strong-ivar-layout 0100", new: ["  strong-ivar-layout 1100"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed strong-ivar-layout\n      before: 0100\n      after:  1100"]),
            SingleChange(covers: "strong-ivar-layout to none",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  strong-ivar-layout 0100", new: ["  strong-ivar-layout"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed strong-ivar-layout\n      before: 0100\n      after:  (no value)"]),
            SingleChange(covers: "weak-ivar-layout",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  weak-ivar-layout", new: ["  weak-ivar-layout 0100"],
                         expected: ["class RuntimeSnapshotStrongIvarFixture: changed weak-ivar-layout\n      before: (no value)\n      after:  0100"]),
            SingleChange(covers: "OWNERSHIP-CONFLICT",
                         className: "RuntimeSnapshotStrongIvarFixture",
                         old: "  ivar-arc-flag set", new: ["  OWNERSHIP-CONFLICT runtime-disagrees _object", "  ivar-arc-flag set"],
                         expected: ["OWNERSHIP CONFLICTS (", "after: class RuntimeSnapshotStrongIvarFixture: OWNERSHIP-CONFLICT runtime-disagrees _object"]),
        ]
    }

    // Each row changes exactly one thing in a real snapshot. Every one must
    // fail the comparison, and the report must name what changed.
    func testEverySingleChangeFails() throws {
        var snapshots = [String: String]()
        for change in singleChanges {
            if snapshots[change.className] == nil {
                snapshots[change.className] = try RuntimeSnapshot.snapshot(classNames: [change.className])
            }
            let before = try XCTUnwrap(snapshots[change.className])
            var lines = before.components(separatedBy: "\n")
            let indices = lines.indices.filter { lines[$0] == change.old }
            guard indices.count == change.occurrences, let index = indices.first else {
                XCTFail("\(change.covers): expected \(change.occurrences) of “\(change.old)”, found \(indices.count) in\n\(before)")
                continue
            }
            lines.replaceSubrange(index...index, with: change.new)
            let after = lines.joined(separator: "\n")
            XCTAssertNotEqual(Array(before.utf8), Array(after.utf8), change.covers)
            let result = RuntimeSnapshotComparison.compare(before: before, after: after)
            XCTAssertFalse(result.passed, "\(change.covers): \(result.report)")
            XCTAssertEqual(result.errors, [], change.covers)
            for expected in change.expected {
                XCTAssertTrue(result.report.contains(expected), "\(change.covers): no “\(expected)” in\n\(result.report)")
            }
            XCTAssertNotEqual(status(before, after), 0, change.covers)
        }
    }

    // Every kind of line the fixtures' snapshots contain, and every field of
    // their property lines, has a row in singleChanges, so that a new kind of
    // line or field cannot be added without a test that a change to it fails.
    func testEveryLineKindAndPropertyFieldHasASingleChangeRow() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: fixtureClassNames)
        let rows = singleChanges.map { $0.covers }
        let memberLines = snapshot.components(separatedBy: "\n").filter { $0.hasPrefix("  ") }
        var kinds = Set(memberLines.compactMap { $0.dropFirst(2).split(separator: " ").first.map(String.init) })
        kinds.formUnion(RuntimeSnapshotFormat.singleValueKeywords + RuntimeSnapshotFormat.memberKinds + [RuntimeSnapshotFormat.duplicateKeyword, RuntimeSnapshotFormat.ownershipConflictKeyword])
        for kind in kinds.sorted() {
            XCTAssertTrue(rows.contains { $0 == kind || $0.hasPrefix(kind + " ") }, "no row covers lines of kind \(kind)")
        }
        // A property line is "<kind> <name> <fields>", each field either
        // name=value or a bare flag.
        var fields = Set<String>()
        for line in memberLines where line.hasPrefix("  instance-property ") || line.hasPrefix("  class-property ") {
            for token in line.split(separator: " ").dropFirst(2) {
                let name = String(token.split(separator: "=", maxSplits: 1).first ?? token)
                fields.insert(name == "nonatomic" || name == "atomic" ? "atomicity" : name)
            }
        }
        XCTAssertTrue(fields.isSuperset(of: ["type", "ownership", "atomicity", "readonly", "dynamic", "optional", "getter", "setter", "ivar", "raw"]),
                      "the fixtures no longer show every property field: \(fields.sorted())")
        for field in fields.sorted() {
            XCTAssertTrue(rows.contains("instance-property " + field), "no row covers the property field \(field)")
        }
    }

    // MARK: - Accessors

    // The whole snapshot of the accessor fixture: Class properties with no
    // ownership code, a custom setter name, which is printed because the
    // attribute string states it, and a property with a custom getter name
    // added by a Swift extension, for which Swift writes no G code.
    func testSnapshotOfAccessorFixture() throws {
        let actual = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotAccessorFixture"])
        let expected = header + """
            class RuntimeSnapshotAccessorFixture
              language objc
              superclass NSObject
              image ModernTests
              ivar-arc-flag set
              strong-ivar-layout
              weak-ivar-layout
              ivar _assignedClass types=# ownership=unretained-or-manual layout=
              ivar _both types=\(bool) ownership=scalar layout=
              ivar _customSetter types=q ownership=scalar layout=
              ivar _unretainedClass types=# ownership=unretained-or-manual layout=
              instance-method -assignBoth: types=v20@0:8\(bool)16
              instance-method -assignCustomSetter: types=v24@0:8q16
              instance-method -assignedClass types=#16@0:8
              instance-method -customSetter types=q16@0:8
              instance-method -isBoth types=\(bool)16@0:8
              instance-method -isExtensionNamed types=\(bool)16@0:8
              instance-method -setAssignedClass: types=v24@0:8#16
              instance-method -setUnretainedClass: types=v24@0:8#16
              instance-method -unretainedClass types=#16@0:8
              instance-property assignedClass type=# ownership=unrecorded nonatomic ivar=_assignedClass raw=T#,N,V_assignedClass
              instance-property both type=\(bool) ownership=assign nonatomic getter=isBoth setter=assignBoth: ivar=_both raw=T\(bool),N,GisBoth,SassignBoth:,V_both
              instance-property customSetter type=q ownership=assign nonatomic setter=assignCustomSetter: ivar=_customSetter raw=Tq,N,SassignCustomSetter:,V_customSetter
              instance-property extensionNamed type=\(bool) ownership=assign nonatomic readonly ivar= raw=T\(bool),N,R
              instance-property unretainedClass type=# ownership=unrecorded nonatomic ivar=_unretainedClass raw=T#,N,V_unretainedClass
            end class RuntimeSnapshotAccessorFixture

            """
        XCTAssertEqual(actual, expected)
    }

    // The getter and setter fields appear only when the attribute string
    // states the name with a G or S code. The snapshot derives no names.
    func testAccessorFieldsComeOnlyFromAttributeCodes() throws {
        let accessor = try lines(of: "RuntimeSnapshotAccessorFixture")
        XCTAssertTrue(accessor.contains(Self.customSetterLine), accessor.joined(separator: "\n"))
        let plain = try XCTUnwrap(accessor.first { $0.hasPrefix("  instance-property unretainedClass ") })
        XCTAssertFalse(plain.contains(" getter="), plain)
        XCTAssertFalse(plain.contains(" setter="), plain)
        let fixture = try lines(of: "RuntimeSnapshotFixture")
        XCTAssertTrue(fixture.contains(Self.enabledLine(bool)), fixture.joined(separator: "\n"))
    }

    // Swift writes no G code for a property whose getter has a custom
    // Objective-C name, in a Swift class and in a Swift extension of an
    // Objective-C class, so no getter field is printed. The getter is listed
    // as a method.
    func testSwiftCustomGetterNameIsNotDerived() throws {
        let swift = try lines(of: "RuntimeSnapshotSwiftAccessorFixture")
        XCTAssertTrue(swift.contains("  instance-method -isNamed types=\(bool)16@0:8"), swift.joined(separator: "\n"))
        XCTAssertTrue(swift.contains("  instance-property named type=\(bool) ownership=assign nonatomic readonly ivar= raw=T\(bool),N,R"),
                      swift.joined(separator: "\n"))
        let objc = try lines(of: "RuntimeSnapshotAccessorFixture")
        XCTAssertTrue(objc.contains("  instance-method -isExtensionNamed types=\(bool)16@0:8"), objc.joined(separator: "\n"))
        XCTAssertTrue(objc.contains("  instance-property extensionNamed type=\(bool) ownership=assign nonatomic readonly ivar= raw=T\(bool),N,R"),
                      objc.joined(separator: "\n"))
    }

    // A readwrite Class property with no ownership code could be
    // unsafe_unretained, assign, or compiled without ARC, so its ownership is
    // unrecorded.
    func testReadwriteClassPropertyWithoutCodeIsUnrecorded() throws {
        let lines = try lines(of: "RuntimeSnapshotAccessorFixture")
        for name in ["unretainedClass", "assignedClass"] {
            let line = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-property \(name) ") }, lines.joined(separator: "\n"))
            XCTAssertTrue(line.contains(" ownership=unrecorded "), line)
            XCTAssertTrue(line.hasSuffix(" raw=T#,N,V_\(name)"), line)
        }
    }

    // Adds a property to a class being built at run time. The attribute
    // strings must outlive class_addProperty, which copies them.
    private func addProperty(_ cls: AnyClass, _ name: String, _ attributes: [(String, String)]) {
        let strings: [UnsafeMutablePointer<CChar>] = attributes.flatMap { [$0.0, $0.1] }.compactMap { (text: String) in strdup(text) }
        defer {
            strings.forEach { free($0) }
        }
        guard strings.count == attributes.count * 2 else {
            XCTFail("strdup failed")
            return
        }
        let list = attributes.indices.map { objc_property_attribute_t(name: strings[2 * $0], value: strings[2 * $0 + 1]) }
        XCTAssertTrue(class_addProperty(cls, name, list, UInt32(list.count)), name)
    }

    // A class whose language is unknown may follow either compiler's rules,
    // so a W code is weak-or-unowned and an object property with no code is
    // unrecorded, as for a Swift class.
    func testPropertyLabelsOfClassWithUnknownLanguage() throws {
        let name = "RuntimeSnapshot.UnknownLanguageLabels"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            addProperty(made, "held", [("T", "@"), ("W", "")])
            addProperty(made, "plain", [("T", "@")])
            objc_registerClassPair(made)
            cls = made
        }
        XCTAssertEqual(RuntimeSnapshot.language(of: cls), "unknown")
        let lines = try RuntimeSnapshot.snapshot(classes: [cls]).components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  instance-property held type=@ ownership=weak-or-unowned atomic ivar= raw=T@,W"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("  instance-property plain type=@ ownership=unrecorded atomic ivar= raw=T@"), lines.joined(separator: "\n"))
    }

    // Names and encodings can contain spaces (a C++ type's encoding does)
    // and other characters that would make a line ambiguous. They are
    // written with those bytes percent-escaped, the result parses, and it
    // still tells the names apart.
    func testNamesAndEncodingsAreEscaped() throws {
        let name = "RuntimeSnapshotEscapeFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let block: @convention(block) (AnyObject) -> Void = { _ in }
            for selector in ["with space", "percent%", "zero\u{200B}width", "tab\tbed"] {
                XCTAssertTrue(class_addMethod(made, NSSelectorFromString(selector), imp_implementationWithBlock(block), "v16@0:8"), selector)
            }
            XCTAssertTrue(class_addIvar(made, "cxx", 8, 3, "{vector<int, std::allocator<int> >=}"))
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        for expected in ["  ivar cxx types={vector<int,%20std::allocator<int>%20>=} ownership=manual layout=",
                         "  instance-method -percent%25 types=v16@0:8",
                         "  instance-method -tab%09bed types=v16@0:8",
                         "  instance-method -with%20space types=v16@0:8",
                         "  instance-method -zero%E2%80%8Bwidth types=v16@0:8"] {
            XCTAssertTrue(lines.contains(expected), "no “\(expected)” in\n\(snapshot)")
        }
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertTrue(result.passed, result.report)
        let changed = snapshot.replacingOccurrences(of: "-with%20space ", with: "-with%2520space ")
        XCTAssertNotEqual(snapshot, changed)
        XCTAssertEqual(status(snapshot, changed), 1)
    }

    // The parser accepts exactly what the writer produces, for every fixture
    // and for a fixed sample of the app classes in the test host: every
    // eighth one in byte order of name. All of them take about 17 seconds,
    // which is too slow for the suite; the sample takes about 2.
    func testParserAcceptsWriterOutput() throws {
        let fixtures = try RuntimeSnapshot.snapshot(classNames: fixtureClassNames + ["RuntimeSnapshotSwiftAccessorFixture",
                                                                                     "RuntimeSnapshotSwiftSubclassFixture",
                                                                                     "RuntimeSnapshotLoadFixture",
                                                                                     "RuntimeSnapshotInitializeFixture"])
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: fixtures, after: fixtures).errors, [])
        let all = appClasses().map { $0.cls }.sorted { String(cString: class_getName($0)).utf8.lexicographicallyPrecedes(String(cString: class_getName($1)).utf8) }
        let classes = stride(from: 0, to: all.count, by: 8).map { all[$0] }
        XCTAssertGreaterThan(classes.count, 100)
        let app = try RuntimeSnapshot.snapshot(classes: classes)
        let result = RuntimeSnapshotComparison.compare(before: app, after: app)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.differences, [])
    }

    // Classes defined in the binaries in the app bundle's MacOS directory,
    // with the binary that defines each, limited to those the snapshot
    // accepts: a root of NSObject or NSProxy, and no other class of the same
    // name loaded first.
    private func appClasses() -> [(cls: AnyClass, image: String)] {
        let macOSDirectory = Bundle.main.bundlePath + "/Contents/MacOS/"
        var result = [(cls: AnyClass, image: String)]()
        for i in 0..<_dyld_image_count() {
            guard let pathPointer = _dyld_get_image_name(i) else {
                continue
            }
            let path = String(cString: pathPointer)
            guard path.hasPrefix(macOSDirectory) else {
                continue
            }
            var count: UInt32 = 0
            guard let names = objc_copyClassNamesForImage(path, &count) else {
                continue
            }
            defer {
                free(names)
            }
            for j in 0..<Int(count) {
                guard let cls = objc_lookUpClass(names[j]), class_getImageName(cls).map({ String(cString: $0) }) == path else {
                    continue
                }
                var root: AnyClass = cls
                while let superclass = class_getSuperclass(root) {
                    root = superclass
                }
                if [ObjectIdentifier(NSObject.self), ObjectIdentifier(NSProxy.self)].contains(ObjectIdentifier(root)) {
                    result.append((cls, path))
                }
            }
        }
        return result
    }

    // MARK: - Comparison details

    func testDifferencesOfClassUnknownOnBothSidesAreUnclassified() {
        let before = header + section("C", language: "unknown", "instance-method -foo types=v16@0:8")
        let after = header + section("C", language: "unknown")
        let result = RuntimeSnapshotComparison.compare(before: before, after: after)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.differences, [])
        XCTAssertEqual(result.unclassified, ["class C: removed instance-method -foo types=v16@0:8"])
    }

    func testHeaderLineAfterClassIsAnError() {
        let good = header + section("C")
        let bad = good + "architecture \(architecture)\n" + section("D")
        let result = RuntimeSnapshotComparison.compare(before: good + section("D"), after: bad)
        XCTAssertEqual(result.errors, ["after line 13: “architecture \(architecture)” is a header line after the first class section"])
        XCTAssertEqual(status(good + section("D"), bad), 2)
    }

    // Each line must match the grammar of its kind exactly. Each variant is
    // made the same way in both inputs, so only the parser can catch it.
    func testMalformedLinesAreRefusedEvenWhenBothSidesAgree() {
        let good = header + section("C",
                                    "protocol P",
                                    "ivar _x types=q ownership=scalar layout=",
                                    "instance-method -foo types=v16@0:8",
                                    "instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p")
        XCTAssertEqual(status(good, good), 0)
        let method = "  instance-method -foo types=v16@0:8\n"
        let property = "  instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p\n"
        let variants: [(String, String, String)] = [
            ("two spaces before a field", method, "  instance-method -foo  types=v16@0:8\n"),
            ("a tab between fields", method, "  instance-method -foo\ttypes=v16@0:8\n"),
            ("a no-break space inside", method, "  instance-method -fo\u{a0}o types=v16@0:8\n"),
            ("a carriage return inside", method, "  instance-method -fo\ro types=v16@0:8\n"),
            ("a vertical tab inside", method, "  instance-method -fo\u{0b}o types=v16@0:8\n"),
            ("a line separator inside", method, "  instance-method -fo\u{2028}o types=v16@0:8\n"),
            ("a NUL inside", method, "  instance-method -fo\u{0}o types=v16@0:8\n"),
            ("a trailing zero-width space", method, "  instance-method -foo types=v16@0:8\u{200B}\n"),
            ("an extra field", method, "  instance-method -foo types=v16@0:8 extra\n"),
            ("no types field", method, "  instance-method -foo\n"),
            ("fields out of order", method, "  instance-method -foo image=X types=v16@0:8\n"),
            ("a repeated field", method, "  instance-method -foo types=v16@0:8 types=v16@0:8\n"),
            ("the wrong sign", method, "  instance-method +foo types=v16@0:8\n"),
            ("a non-canonical escape", method, "  instance-method -fo%6F types=v16@0:8\n"),
            ("a bad escape", method, "  instance-method -fo%zz types=v16@0:8\n"),
            ("a detail on a protocol line", "  protocol P\n", "  protocol P extra\n"),
            ("an ivar without types", "  ivar _x types=q ownership=scalar layout=\n", "  ivar _x ownership=scalar layout=\n"),
            ("a superclass with a space", "  superclass NSObject\n", "  superclass NS Object\n"),
            ("an image with an extra field", "  image ModernTests\n", "  image ModernTests extra\n"),
            ("a header line with an extra field", "architecture \(architecture)\n", "architecture \(architecture) extra\n"),
            ("a property without ownership", property, "  instance-property p type=q nonatomic ivar=_p raw=Tq,N,V_p\n"),
            ("an unknown ownership", property, "  instance-property p type=q ownership=owned nonatomic ivar=_p raw=Tq,N,V_p\n"),
            ("property fields out of order", property, "  instance-property p ownership=assign type=q nonatomic ivar=_p raw=Tq,N,V_p\n"),
            ("a property flag out of order", property, "  instance-property p type=q ownership=assign nonatomic dynamic readonly ivar=_p raw=Tq,N,V_p\n"),
            ("an unknown property flag", property, "  instance-property p type=q ownership=assign nonatomic frozen ivar=_p raw=Tq,N,V_p\n"),
            ("a DUPLICATE line with a bad count", method, method + "  DUPLICATE instance-method -foo count=x\n"),
            ("a DUPLICATE line with a count of 1", method, method + "  DUPLICATE instance-method -foo count=1\n"),
            ("a DUPLICATE line with a leading zero", method, method + "  DUPLICATE instance-method -foo count=02\n"),
            ("a repeated optional method field", method, "  instance-method -foo types=v16@0:8 image=X image=Y\n"),
            ("a value starting with =", method, "  instance-method -foo types==\n"),
            ("a repeated property field", property, "  instance-property p type=q ownership=assign nonatomic ivar=_p ivar=_q raw=Tq,N,V_p\n"),
            ("a field after raw", property, "  instance-property p type=q ownership=assign nonatomic ivar=_p raw=Tq,N,V_p extra\n"),
            ("a DUPLICATE line for an unknown kind", method, method + "  DUPLICATE protocol P count=2\n"),
            ("an empty also-implemented-by", method, "  instance-method -foo types=v16@0:8 also-implemented-by=\n"),
            ("also-implemented-by without a sign", method, "  instance-method -foo types=v16@0:8 also-implemented-by=NSObject\n"),
            ("also-implemented-by with only a sign", method, "  instance-method -foo types=v16@0:8 also-implemented-by=-\n"),
            ("an instance method also implemented by a class method", method, "  instance-method -foo types=v16@0:8 also-implemented-by=+NSObject\n"),
            ("a method image= that names the class's image", method, "  instance-method -foo types=v16@0:8 image=ModernTests\n"),
            ("a language line with no value", "  language objc\n", "  language\n"),
            ("an architecture line with no value", "architecture \(architecture)\n", "architecture\n"),
            ("a superclass line with a trailing space", "  superclass NSObject\n", "  superclass \n"),
            ("an image line with a trailing space", "  image ModernTests\n", "  image \n"),
        ]
        for (what, old, new) in variants {
            let bad = good.replacingOccurrences(of: old, with: new)
            XCTAssertNotEqual(Array(bad.utf8), Array(good.utf8), what)
            let result = RuntimeSnapshotComparison.compare(before: bad, after: bad)
            XCTAssertFalse(result.passed, what)
            XCTAssertFalse(result.errors.isEmpty, what)
            XCTAssertEqual(status(bad, bad), 2, what)
        }
    }

    // A method's image= is written only when it differs from the class's
    // image, so in a class with no image, image= with no value is refused,
    // while image= naming a binary is accepted.
    func testMethodImageMustDifferFromClassImage() {
        let named = header + section("C", image: nil, "instance-method -foo types=v16@0:8 image=Other")
        XCTAssertEqual(status(named, named), 0)
        let empty = header + section("C", image: nil, "instance-method -foo types=v16@0:8 image=")
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: empty, after: empty).errors, [
            "before: class C: instance-method -foo has image= equal to the class's image, which the snapshot never writes",
            "after: class C: instance-method -foo has image= equal to the class's image, which the snapshot never writes"])
        XCTAssertEqual(status(empty, empty), 2)
        let inClassImage = header + section("C", "class-method +foo types=v16@0:8 image=ModernTests")
        XCTAssertEqual(status(inClassImage, inClassImage), 2)
        let unknownInKnownClass = header + section("C", "class-method +foo types=v16@0:8 image=")
        XCTAssertEqual(status(unknownInKnownClass, unknownInKnownClass), 0)
    }

    // A class method can be also implemented by the root class's instance
    // method, written with a minus sign.
    func testClassMethodAlsoImplementedByRootInstanceMethodParses() {
        let snapshot = header + section("C", "class-method +foo types=v16@0:8 also-implemented-by=-NSObject",
                                        "class-method +bar types=v16@0:8 also-implemented-by=+NSObject")
        XCTAssertEqual(status(snapshot, snapshot), 0)
        let other = snapshot.replacingOccurrences(of: "+foo types=v16@0:8 also-implemented-by=-NSObject", with: "+foo types=v16@0:8 also-implemented-by=+NSObject")
        XCTAssertNotEqual(snapshot, other)
        XCTAssertEqual(status(snapshot, other), 1)
    }

    // MARK: - Malformed input

    // Each of these is not exactly what the snapshot writes, so it is refused
    // with exit status 2 rather than compared.
    func testMalformedInputIsRefused() {
        let good = header + section("C", "protocol P")
        let malformed: [(String, String)] = [
            ("a second format line", good.replacingOccurrences(of: "format 3\n", with: "format 3\n# Objective-C runtime snapshot, format 3\n")),
            ("a snapshot in format 2", good.replacingOccurrences(of: "format 3\n", with: "format 2\n")),
            ("a comment inside a class", good.replacingOccurrences(of: "  protocol P\n", with: "  protocol P\n# comment\n")),
            ("a trailing no-break space", good.replacingOccurrences(of: "  protocol P\n", with: "  protocol P\u{a0}\n")),
            ("a trailing space", good.replacingOccurrences(of: "  protocol P\n", with: "  protocol P \n")),
            ("a carriage return", good.replacingOccurrences(of: "\n", with: "\r\n")),
            ("three spaces of indentation", good.replacingOccurrences(of: "  protocol P\n", with: "   protocol P\n")),
            ("a tab for indentation", good.replacingOccurrences(of: "  protocol P\n", with: "\tprotocol P\n")),
            ("a leading no-break space", good.replacingOccurrences(of: "  protocol P\n", with: "  \u{a0}protocol P\n")),
            ("an indented class line", good.replacingOccurrences(of: "class C\n", with: "  class C\n")),
            ("an unindented member line", good.replacingOccurrences(of: "  protocol P\n", with: "protocol P\n")),
            ("two spaces between fields", good.replacingOccurrences(of: "  protocol P\n", with: "  protocol  P\n")),
            ("an empty line", good.replacingOccurrences(of: "  protocol P\n", with: "  protocol P\n\n")),
            ("an unknown kind of line", good.replacingOccurrences(of: "  protocol P\n", with: "  frobnicate P\n")),
            ("no final line feed", String(good.dropLast())),
            ("an empty file", ""),
        ]
        XCTAssertEqual(status(good, good), 0)
        for (what, text) in malformed {
            XCTAssertNotEqual(Array(text.utf8), Array(good.utf8), what)
            let result = RuntimeSnapshotComparison.compare(before: good, after: text)
            XCTAssertFalse(result.passed, what)
            XCTAssertFalse(result.errors.isEmpty, what)
            XCTAssertEqual(status(good, text), 2, what)
            XCTAssertEqual(status(text, good), 2, what)
        }
    }

    // MARK: - Refused classes

    func testTwoNamesForOneClassAreRefused() throws {
        let qualified = NSStringFromClass(RuntimeSnapshotUnnamedSwiftFixture.self)
        XCTAssertEqual(qualified, "ModernTests.RuntimeSnapshotUnnamedSwiftFixture")
        let mangled = "_TtC11ModernTests34RuntimeSnapshotUnnamedSwiftFixture"
        let found: AnyClass = try XCTUnwrap(NSClassFromString(mangled))
        XCTAssertEqual(ObjectIdentifier(found), ObjectIdentifier(RuntimeSnapshotUnnamedSwiftFixture.self))
        XCTAssertTrue(try RuntimeSnapshot.snapshot(classNames: [mangled]).contains("\nclass \(qualified)\n"))
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classNames: [mangled, qualified])) { error in
            XCTAssertEqual("\(error)", "\(qualified) and \(mangled) name the same class; give only one of them")
        }
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classes: [found, RuntimeSnapshotUnnamedSwiftFixture.self]))
    }

    // A root class other than NSObject and NSProxy is refused before anything
    // sends it a message. The fixture implements nothing but +initialize, so
    // any message would crash the test process. As with
    // testSnapshotDoesNotInitializeTheClass, the flag is never reset, so a
    // repeated run in one process passes only while no earlier run
    // initialized the fixture.
    func testClassWithAnotherRootIsRefusedWithoutMessagingIt() {
        for name in ["RuntimeSnapshotRootFixture", "RuntimeSnapshotRootSubclassFixture"] {
            XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classNames: [name])) { error in
                XCTAssertEqual("\(error)", "Cannot snapshot \(name): its root class is RuntimeSnapshotRootFixture, not NSObject or NSProxy, and taking a snapshot would send it messages it may not implement")
            }
        }
        XCTAssertFalse(RuntimeSnapshotRootFixtureInitialized.boolValue)
    }

    // MARK: - Repeats, order, and empty values

    func testRepeatedProtocolAndClassPropertyAreListedEachTime() throws {
        let lines = try lines(of: "RuntimeSnapshotPropertyRepeatFixture")
        let text = lines.joined(separator: "\n")
        XCTAssertEqual(lines.filter { $0 == "  protocol RuntimeSnapshotFixtureObjectProtocol" }.count, 2, text)
        XCTAssertEqual(lines.filter { $0.hasPrefix("  class-property repeatedClassProperty ") }.count, 2, text)
        XCTAssertFalse(lines.contains { $0.contains("DUPLICATE") }, text)
    }

    // The final order is UTF-8 byte order, which differs from Swift's String
    // order: Swift compares "e\u{301}x" as "\u{e9}x", after "\u{e9}a", while
    // its first byte, e, comes before \u{e9}'s first byte.
    func testLinesAreInByteOrderNotStringOrder() throws {
        let decomposed = "e\u{301}x"
        let precomposed = "\u{e9}a"
        XCTAssertTrue(precomposed < decomposed, "the premise of this test")
        let name = "RuntimeSnapshotSortOrderFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let block: @convention(block) (AnyObject) -> Void = { _ in }
            for selector in [precomposed, decomposed] {
                XCTAssertTrue(class_addMethod(made, NSSelectorFromString(selector), imp_implementationWithBlock(block), "v16@0:8"))
            }
            objc_registerClassPair(made)
            cls = made
        }
        let lines = try RuntimeSnapshot.snapshot(classes: [cls]).components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("  instance-method ") }.map { Array($0.utf8) },
                       ["  instance-method -e%CC%81x types=v16@0:8", "  instance-method -%C3%A9a types=v16@0:8"].map { Array($0.utf8) })
    }

    // An empty encoding is written as nothing after types=, which no
    // encoding, not even one spelled (none), can be mistaken for.
    func testEmptyIvarEncodingIsWrittenAsNothing() throws {
        let name = "RuntimeSnapshotEmptyIvarEncodingFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            XCTAssertTrue(class_addIvar(made, "untyped", 8, 3, ""))
            XCTAssertTrue(class_addIvar(made, "spelled", 8, 3, "(none)"))
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  ivar untyped types= ownership=unknown-type layout="), snapshot)
        XCTAssertTrue(lines.contains("  ivar spelled types=(none) ownership=manual layout="), snapshot)
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
    }

    // A class made at run time is in no loaded binary, so its image line has
    // no value. A method made at run time in it is in no binary either, so
    // its line has no image= field, while a method whose code is in a binary
    // names that binary.
    func testClassInNoBinaryHasImageLineWithoutValue() throws {
        let name = "RuntimeSnapshotNoImageFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let block: @convention(block) (AnyObject) -> Void = { _ in }
            XCTAssertTrue(class_addMethod(made, NSSelectorFromString("blockMethod"), imp_implementationWithBlock(block), "v16@0:8"))
            let description = try XCTUnwrap(class_getInstanceMethod(NSObject.self, #selector(NSObject.description)))
            XCTAssertTrue(class_addMethod(made, NSSelectorFromString("borrowedDescription"), method_getImplementation(description), method_getTypeEncoding(description)))
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  image"), snapshot)
        XCTAssertTrue(lines.contains("  instance-method -blockMethod types=v16@0:8"), snapshot)
        let borrowed = try XCTUnwrap(lines.first { $0.hasPrefix("  instance-method -borrowedDescription types=@16@0:8 image=") }, snapshot)
        XCTAssertGreaterThan(borrowed.count, "  instance-method -borrowedDescription types=@16@0:8 image=".count, borrowed)
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
        // Gaining an image is a difference.
        let withImage = snapshot.replacingOccurrences(of: "\n  image\n", with: "\n  image Other\n")
        XCTAssertNotEqual(snapshot, withImage)
        XCTAssertTrue(single(RuntimeSnapshotComparison.compare(before: snapshot, after: withImage).differences)
            .hasPrefix("class RuntimeSnapshotNoImageFixture: changed image\n      before: (no value)\n      after:  Other"))
    }

    // A root class has no superclass, so its superclass line has no value.
    func testRootClassHasSuperclassLineWithoutValue() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classes: [NSProxy.self])
        XCTAssertTrue(snapshot.contains("\nclass NSProxy\n  language objc\n  superclass\n  image "), snapshot)
        XCTAssertEqual(status(snapshot, snapshot), 0)
        let withSuperclass = snapshot.replacingOccurrences(of: "\n  superclass\n", with: "\n  superclass NSObject\n")
        XCTAssertNotEqual(snapshot, withSuperclass)
        XCTAssertEqual(single(RuntimeSnapshotComparison.compare(before: snapshot, after: withSuperclass).differences),
                       "class NSProxy: changed superclass\n      before: (no value)\n      after:  NSObject")
    }

    // Names spelled like placeholders are ordinary names: a superclass named
    // (none) is not the absence of a superclass, and an image named
    // (unknown) is not the absence of an image.
    func testNamesSpelledLikePlaceholdersAreOrdinaryNames() throws {
        let superName = "(none)"
        let superclass: AnyClass
        if let existing = objc_lookUpClass(superName) {
            superclass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, superName, 0))
            objc_registerClassPair(made)
            superclass = made
        }
        let name = "RuntimeSnapshotPlaceholderSubclass"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(superclass, name, 0))
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        XCTAssertTrue(snapshot.contains("\n  superclass (none)\n"), snapshot)
        XCTAssertEqual(status(snapshot, snapshot), 0)
        let root = snapshot.replacingOccurrences(of: "\n  superclass (none)\n", with: "\n  superclass\n")
        XCTAssertEqual(status(snapshot, root), 1)

        let unknownImage = header + section("C", image: "(unknown)", "instance-method -foo types=v16@0:8 image=")
        XCTAssertEqual(status(unknownImage, unknownImage), 0)
        XCTAssertEqual(status(unknownImage, header + section("C", image: nil, "instance-method -foo types=v16@0:8 image=Other")), 1)
    }

    // The writer refuses a class with a name it would have to write as an
    // empty field, rather than write a placeholder that a real name could
    // share.
    func testEmptyNamesAreRefused() throws {
        let ivarClassName = "RuntimeSnapshotEmptyIvarNameFixture"
        let ivarClass: AnyClass
        if let existing = NSClassFromString(ivarClassName) {
            ivarClass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, ivarClassName, 0))
            XCTAssertTrue(class_addIvar(made, "", 8, 3, "q"))
            objc_registerClassPair(made)
            ivarClass = made
        }
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classes: [ivarClass])) { error in
            XCTAssertEqual("\(error)", "Cannot snapshot \(ivarClassName): it has an ivar with no name, which a snapshot cannot write")
        }

        let propertyClassName = "RuntimeSnapshotEmptyPropertyNameFixture"
        let propertyClass: AnyClass
        if let existing = NSClassFromString(propertyClassName) {
            propertyClass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, propertyClassName, 0))
            addProperty(made, "", [("T", "q")])
            objc_registerClassPair(made)
            propertyClass = made
        }
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classes: [propertyClass])) { error in
            XCTAssertEqual("\(error)", "Cannot snapshot \(propertyClassName): it has a property with no name, which a snapshot cannot write")
        }

        let emptySuperclass: AnyClass
        if let existing = objc_lookUpClass("") {
            emptySuperclass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, "", 0))
            objc_registerClassPair(made)
            emptySuperclass = made
        }
        let subclassName = "RuntimeSnapshotEmptySuperclassNameFixture"
        let subclass: AnyClass
        if let existing = NSClassFromString(subclassName) {
            subclass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(emptySuperclass, subclassName, 0))
            objc_registerClassPair(made)
            subclass = made
        }
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classes: [subclass])) { error in
            XCTAssertEqual("\(error)", "Cannot snapshot \(subclassName): it has a superclass with no name, which a snapshot cannot write")
        }
    }

    // A class and one of its categories both implementing +initialize is a
    // duplicate: unlike +load, only one of them runs.
    func testInitializeInClassAndCategoryIsADuplicate() throws {
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotInitializeCategoryFixture"])
        let lines = snapshot.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  DUPLICATE class-method +initialize count=2"), snapshot)
        XCTAssertEqual(lines.filter { $0 == "  class-method +initialize types=v16@0:8 also-implemented-by=+NSObject" }.count, 2, snapshot)
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.duplicates, [
            "before: class RuntimeSnapshotInitializeCategoryFixture: DUPLICATE class-method +initialize count=2",
            "after: class RuntimeSnapshotInitializeCategoryFixture: DUPLICATE class-method +initialize count=2"])

        // The comparison recounts +initialize too.
        let undeclared = header + section("C", "class-method +initialize types=v16@0:8", "class-method +initialize types=v16@0:8")
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: undeclared, after: undeclared).duplicates, [
            "before: class C: class-method +initialize appears 2 times with no DUPLICATE line",
            "after: class C: class-method +initialize appears 2 times with no DUPLICATE line"])
    }

    // MARK: - Escaping of every value

    // The superclass and also-implemented-by= name a class, and both are
    // escaped, for an instance method and for a class method.
    func testSuperclassAndAlsoImplementedByAreEscaped() throws {
        let superName = "RuntimeSnapshot Escaped Super%"
        let block: @convention(block) (AnyObject) -> Void = { _ in }
        let superclass: AnyClass
        if let existing = objc_lookUpClass(superName) {
            superclass = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, superName, 0))
            XCTAssertTrue(class_addMethod(made, NSSelectorFromString("shared"), imp_implementationWithBlock(block), "v16@0:8"))
            objc_registerClassPair(made)
            let metaclass: AnyClass = try XCTUnwrap(objc_getMetaClass(superName) as? AnyClass)
            XCTAssertTrue(class_addMethod(metaclass, NSSelectorFromString("sharedClass"), imp_implementationWithBlock(block), "v16@0:8"))
            superclass = made
        }
        let name = "RuntimeSnapshotEscapedSubclass"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(superclass, name, 0))
            XCTAssertTrue(class_addMethod(made, NSSelectorFromString("shared"), imp_implementationWithBlock(block), "v16@0:8"))
            objc_registerClassPair(made)
            let metaclass: AnyClass = try XCTUnwrap(objc_getMetaClass(name) as? AnyClass)
            XCTAssertTrue(class_addMethod(metaclass, NSSelectorFromString("sharedClass"), imp_implementationWithBlock(block), "v16@0:8"))
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        for expected in ["  superclass RuntimeSnapshot%20Escaped%20Super%25",
                         "  class-method +sharedClass types=v16@0:8 also-implemented-by=+RuntimeSnapshot%20Escaped%20Super%25",
                         "  instance-method -shared types=v16@0:8 also-implemented-by=-RuntimeSnapshot%20Escaped%20Super%25"] {
            XCTAssertTrue(lines.contains(expected), "no “\(expected)” in\n\(snapshot)")
        }
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
    }

    // The getter= and setter= values are escaped.
    func testAccessorNamesAreEscaped() throws {
        let name = "RuntimeSnapshotEscapedAccessorFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            addProperty(made, "on", [("T", "c"), ("G", "is on"), ("S", "set\u{e9}On:")])
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        XCTAssertTrue(snapshot.components(separatedBy: "\n").contains(
            "  instance-property on type=c ownership=assign atomic getter=is%20on setter=set%C3%A9On: ivar= raw=Tc,Gis%20on,Sset%C3%A9On:"), snapshot)
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
    }

    // The class's image line, a method's image=, and every other field of a
    // method line are escaped. A method in no binary, in a class that is in
    // one, has image= with no value; a method in the class's own binary, or
    // in none when the class is in none, has no image= field.
    func testLineFormattingFunctionsEscapeEveryValue() {
        XCTAssertEqual(RuntimeSnapshot.valueLine(RuntimeSnapshotFormat.imageKeyword, "My Binary%"), "image My%20Binary%25")
        XCTAssertEqual(RuntimeSnapshot.valueLine(RuntimeSnapshotFormat.imageKeyword, nil), "image")
        XCTAssertEqual(RuntimeSnapshot.valueLine(RuntimeSnapshotFormat.superclassKeyword, "Super\u{e9}"), "superclass Super%C3%A9")
        XCTAssertEqual(RuntimeSnapshot.valueLine(RuntimeSnapshotFormat.superclassKeyword, nil), "superclass")
        XCTAssertEqual(RuntimeSnapshot.methodLine(kind: "instance-method", sign: "-", selector: "a b", types: "v 16",
                                                  alsoImplementedBy: "-Super Class", image: "My Binary", classImage: "Other"),
                       "instance-method -a%20b types=v%2016 also-implemented-by=-Super%20Class image=My%20Binary")
        XCTAssertEqual(RuntimeSnapshot.methodLine(kind: "class-method", sign: "+", selector: "x", types: "",
                                                  alsoImplementedBy: nil, image: nil, classImage: "Other"),
                       "class-method +x types= image=")
        XCTAssertEqual(RuntimeSnapshot.methodLine(kind: "class-method", sign: "+", selector: "x", types: "v16@0:8",
                                                  alsoImplementedBy: nil, image: "Other", classImage: "Other"),
                       "class-method +x types=v16@0:8")
        XCTAssertEqual(RuntimeSnapshot.methodLine(kind: "class-method", sign: "+", selector: "x", types: "v16@0:8",
                                                  alsoImplementedBy: nil, image: nil, classImage: nil),
                       "class-method +x types=v16@0:8")
        XCTAssertEqual(RuntimeSnapshot.methodLine(kind: "class-method", sign: "+", selector: "x", types: "v16@0:8",
                                                  alsoImplementedBy: nil, image: "Lib One", classImage: nil),
                       "class-method +x types=v16@0:8 image=Lib%20One")
    }

    // MARK: - Writing the output file

    func testToolReplacesAnExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("snapshot.txt").path
        try Data("an earlier file".utf8).write(to: URL(fileURLWithPath: output))
        XCTAssertNotNil(try RuntimeSnapshotTool.writeRequestedSnapshot(environment: [
            RuntimeSnapshotTool.classesVariable: "RuntimeSnapshotFixtureBase",
            RuntimeSnapshotTool.outputVariable: output]))
        XCTAssertEqual(try String(contentsOfFile: output, encoding: .utf8),
                       try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["snapshot.txt"])
    }

    // A write that fails partway leaves neither a partial file at the output
    // path nor a temporary file beside it.
    func testToolLeavesNoPartialFileWhenWritingFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("snapshot.txt").path
        try Data("an earlier file".utf8).write(to: URL(fileURLWithPath: output))
        struct Interrupted: Error {}
        var wroteTo: URL?
        XCTAssertThrowsError(try RuntimeSnapshotTool.writeRequestedSnapshot(
            environment: [RuntimeSnapshotTool.classesVariable: "RuntimeSnapshotFixtureBase",
                          RuntimeSnapshotTool.outputVariable: output],
            writeFile: { data, url in
                wroteTo = url
                try data.prefix(data.count / 2).write(to: url)
                throw Interrupted()
            })) { error in
            XCTAssertTrue(error is Interrupted, "\(error)")
        }
        XCTAssertNotNil(wroteTo)
        XCTAssertNotEqual(wroteTo?.path, output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    // MARK: - What a pass does not cover

    // The pass caveat, exactly. It names what this tool does not compare.
    func testPassCaveatText() throws {
        XCTAssertEqual(RuntimeSnapshotFormat.notCoveredByPass, "A pass means only that the recorded lines match. Known gaps, which this tool does not compare:\n- what methods do, including methods that decide at run time which selectors or keys an object answers (respondsToSelector:, forwarding, method resolution, valueForUndefinedKey:), so selectors a class forwards or resolves dynamically are not covered\n- the contents of adopted protocols; only their names are recorded\n- classes not named in the snapshot, including the members of superclasses and subclasses\n- the ownership of an ivar labeled unretained-or-manual, manual, unretained-or-unknown, struct-or-cxx-object, struct-no-destructor, struct-unknown, c-pointer, unaligned-object or unknown-type, or the words of an arc-members ivar outside the layouts, which the runtime cannot tell; check them against the source or with tools/swift_migration/ivar_ownership_check.py\n- the ownership of the stored properties of a Swift class, which the runtime layouts do not describe\n- the type of an ivar whose encoding the runtime leaves unknown or empty\n- the class of an object parameter or return value, which every method encoding writes as plain @, so NSString * becoming NSArray *, or id becoming a class, is not seen; the reviewer compares the Swift signatures with the Objective-C declarations (for an Objective-C header, the Swift interface snapshot, tools/swift_migration/swift_interface.py, shows the types Swift sees)\n- nullability: a Swift parameter that is not optional where the Objective-C method accepted nil (a nil passed from Objective-C then traps) is not seen; nullability claims are made and proven by the annotate process (docs/swift-migration/nullability.md) and checked at run time by the nullability sanitizer configuration (phase0.md section 4)\n- ivar declaration order, which decides teardown order under ARC\n- the ownership of a property printed as unrecorded\n- weak versus unowned in Swift, including a property that a Swift extension declares on an Objective-C class, which is printed as weak even when Swift declared it unowned\n- for a Swift class, whether a member is dynamic\n- build configurations other than the one snapshotted")
        let snapshot = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"])
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.report.hasSuffix("PASS: the snapshots match.\n" + RuntimeSnapshotFormat.notCoveredByPass + "\n"), result.report)
    }

    // Two classes that differ only in whether their ivar is strong or weak
    // differ in their ivar lines and layouts, so a port that changed an
    // ivar's ownership fails. (Before the snapshot read the layouts this
    // test showed the opposite, and the pass caveat listed it as a gap.)
    func testIvarOwnershipIsCompared() throws {
        let strong = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotStrongIvarFixture"])
        let weak = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotWeakIvarFixture"])
            .replacingOccurrences(of: "RuntimeSnapshotWeakIvarFixture", with: "RuntimeSnapshotStrongIvarFixture")
        XCTAssertTrue(strong.contains("\n  ivar _object types=@ ownership=strong layout=s\n"), strong)
        XCTAssertTrue(weak.contains("\n  ivar _object types=@ ownership=weak layout=w\n"), weak)
        let result = RuntimeSnapshotComparison.compare(before: strong, after: weak)
        XCTAssertFalse(result.passed, result.report)
        XCTAssertTrue(result.differences.contains("class RuntimeSnapshotStrongIvarFixture: changed ivar _object\n      before: types=@ ownership=strong layout=s\n      after:  types=@ ownership=weak layout=w"), "\(result.differences)")
        XCTAssertFalse(RuntimeSnapshotFormat.notCoveredByPass.contains("whether an ivar is strong, weak, or unretained"))
    }

    // Two Swift classes that differ only in whether a property is dynamic
    // have identical snapshots apart from their names.
    func testSwiftDynamicIsNotCompared() throws {
        let plain = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotSwiftStaticFixture"])
        let dynamic = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotSwiftDynamicFixture"])
            .replacingOccurrences(of: "RuntimeSnapshotSwiftDynamicFixture", with: "RuntimeSnapshotSwiftStaticFixture")
        let result = RuntimeSnapshotComparison.compare(before: plain, after: dynamic)
        XCTAssertTrue(result.passed, result.report)
        XCTAssertTrue(result.report.contains("- for a Swift class, whether a member is dynamic\n"), result.report)
    }

    // Names are positional, so a name that looks like a key or flag, and a
    // DUPLICATE line for a property named count, parse.
    func testNamesThatLookLikeKeysParse() {
        let property = "type=q ownership=assign nonatomic ivar= raw=Tq"
        let snapshot = header + section("C",
                                        "DUPLICATE instance-property count count=2",
                                        "DUPLICATE instance-method -image=x count=2",
                                        "protocol count=2",
                                        "ivar types=q types=q ownership=scalar layout=",
                                        "instance-method -image=x types=v16@0:8",
                                        "instance-method -image=x types=v24@0:8@16",
                                        "instance-method -types= types=v16@0:8",
                                        "instance-property count " + property,
                                        "instance-property count type=q ownership=assign atomic ivar= raw=Tq",
                                        "instance-property getter=x " + property,
                                        "instance-property readonly " + property)
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertEqual(result.errors, [], result.report)
        XCTAssertEqual(result.duplicates.count, 4, result.report)
        XCTAssertEqual(RuntimeSnapshot.duplicateLines(kind: "instance-property", entries: [("count", "a"), ("count", "b")], onlyWhenDetailsDiffer: true),
                       ["DUPLICATE instance-property count count=2"])
    }

    // The type scanner in attributeCodes keeps every kind of bracket and
    // quoted string together, and the first value of a repeated code wins.
    func testAttributeCodes() {
        let cases: [(String, [String: String])] = [
            ("T^{?=*i[128c]^{?}},R,N", ["T": "^{?=*i[128c]^{?}}", "R": "", "N": ""]),
            ("T(?=\"a\"i\"b\"f),R,N", ["T": "(?=\"a\"i\"b\"f)", "R": "", "N": ""]),
            ("T[4{pair=i,i}],N", ["T": "[4{pair=i,i}]", "N": ""]),
            ("T(u=i,c),N", ["T": "(u=i,c)", "N": ""]),
            ("T{a<b,c>=i},V_x", ["T": "{a<b,c>=i}", "V": "_x"]),
            ("T@\"NS,Thing\",&,N", ["T": "@\"NS,Thing\"", "&": "", "N": ""]),
            ("T{o={i=[2(u=i,c)]}},C,GisO,SsetO:,V_o", ["T": "{o={i=[2(u=i,c)]}}", "C": "", "G": "isO", "S": "setO:", "V": "_o"]),
            ("Tq,GfirstGetter,GsecondGetter", ["T": "q", "G": "firstGetter"]),
            ("N,R", ["N": "", "R": ""]),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(RuntimeSnapshot.attributeCodes(raw), expected, raw)
        }
        // An unbalanced quote makes the type unreadable; the other codes are
        // still read.
        XCTAssertEqual(RuntimeSnapshot.attributeCodes("T@\"NSObject,&,N"), ["&": "", "N": ""])
    }

    // A property with both a custom getter and a custom setter.
    func testCustomGetterAndSetter() throws {
        let lines = try lines(of: "RuntimeSnapshotAccessorFixture")
        let line = "  instance-property both type=\(bool) ownership=assign nonatomic getter=isBoth setter=assignBoth: ivar=_both raw=T\(bool),N,GisBoth,SassignBoth:,V_both"
        XCTAssertTrue(lines.contains(line), lines.joined(separator: "\n"))
        let snapshot = header + section("C", String(line.dropFirst(2)))
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
    }

    // MARK: - Shadowed class

    // A class whose name the runtime resolves to a different class. The
    // runtime cannot dispose of a duplicated class, so it is made once per
    // process; objc_lookUpClass still finds the original under that name.
    private static let shadowingDuplicate: AnyClass = objc_duplicateClass(RuntimeSnapshotFixtureBase.self, "RuntimeSnapshotFixtureBase", 0)

    func testClassThatItsNameDoesNotResolveToIsRefused() throws {
        let duplicate: AnyClass = Self.shadowingDuplicate
        XCTAssertNotEqual(ObjectIdentifier(duplicate), ObjectIdentifier(RuntimeSnapshotFixtureBase.self))
        XCTAssertThrowsError(try RuntimeSnapshot.snapshot(classes: [duplicate])) { error in
            XCTAssertEqual("\(error)", "Cannot snapshot this RuntimeSnapshotFixtureBase: the runtime resolves the name RuntimeSnapshotFixtureBase to a different class, so its class methods cannot be looked up by name")
        }
        // The original is unaffected.
        XCTAssertTrue(try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotFixtureBase"]).contains("\nclass RuntimeSnapshotFixtureBase\n"))
    }

    // MARK: - Build configuration from the app's location

    func testBuildConfigurationAndVariantFromAppLocation() {
        let asan = URL(fileURLWithPath: "/repo/Build/Variant-ASan/Development/iTerm2.app")
        XCTAssertEqual(RuntimeSnapshot.buildConfiguration(appURL: asan), "Development")
        XCTAssertEqual(RuntimeSnapshot.buildVariant(appURL: asan), "ASan")
        let plain = URL(fileURLWithPath: "/repo/Build/Deployment/iTerm2.app")
        XCTAssertEqual(RuntimeSnapshot.buildConfiguration(appURL: plain), "Deployment")
        XCTAssertNil(RuntimeSnapshot.buildVariant(appURL: plain))
        XCTAssertNil(RuntimeSnapshot.buildVariant(appURL: URL(fileURLWithPath: "/repo/Build/Variant-/Development/iTerm2.app")))
        // A variant that happens to be named none is a variant, not the
        // absence of one.
        XCTAssertEqual(RuntimeSnapshot.buildVariant(appURL: URL(fileURLWithPath: "/repo/Build/Variant-none/Development/iTerm2.app")), "none")
    }

    // MARK: - Values the writer must still write parseably

    func testEmptyValuesAndMissingTypeAreWrittenParseably() throws {
        let name = "RuntimeSnapshotEmptyValuesFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let block: @convention(block) (AnyObject) -> Void = { _ in }
            XCTAssertTrue(class_addMethod(made, NSSelectorFromString("untyped"), imp_implementationWithBlock(block), ""))
            addProperty(made, "emptyCodes", [("T", "@"), ("&", ""), ("G", ""), ("V", "")])
            addProperty(made, "noType", [("N", "")])
            // An unbalanced quote makes the type unreadable, and so the
            // ownership too, although the & code follows.
            addProperty(made, "broken", [("T", "@\"NSObject"), ("&", "")])
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        for expected in ["  instance-method -untyped types=",
                         "  instance-property emptyCodes type=@ ownership=strong atomic getter= ivar= raw=T@,&,G,V",
                         "  instance-property noType type= ownership=unrecorded nonatomic ivar= raw=N",
                         "  instance-property broken type= ownership=unrecorded atomic ivar= raw=T@\"NSObject,&"] {
            XCTAssertTrue(lines.contains(expected), "no “\(expected)” in\n\(snapshot)")
        }
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
    }

    // property_copyAttributeList splits the T code at a comma, so the type is
    // read from the raw attribute string, keeping brackets balanced.
    func testPropertyTypeWithCommaIsWhole() throws {
        let name = "RuntimeSnapshotCommaTypeFixture"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            addProperty(made, "pair", [("T", "{pair<int,int>=ii}"), ("N", ""), ("V", "_pair")])
            objc_registerClassPair(made)
            cls = made
        }
        let lines = try RuntimeSnapshot.snapshot(classes: [cls]).components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  instance-property pair type={pair<int,int>=ii} ownership=assign nonatomic ivar=_pair raw=T{pair<int,int>=ii},N,V_pair"),
                      lines.joined(separator: "\n"))
    }

    // Class, protocol, property, and DUPLICATE names and the raw attribute
    // string are all escaped.
    func testEveryKindOfNameIsEscaped() throws {
        let name = "RuntimeSnapshot Escaped\u{e9}"
        let cls: AnyClass
        if let existing = NSClassFromString(name) {
            cls = existing
        } else {
            let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
            let protocolName = "RuntimeSnapshot Escaped Protocol"
            let proto: Protocol
            if let existing = objc_getProtocol(protocolName) {
                proto = existing
            } else {
                let allocated = try XCTUnwrap(objc_allocateProtocol(protocolName))
                objc_registerProtocol(allocated)
                proto = allocated
            }
            XCTAssertTrue(class_addProtocol(made, proto))
            addProperty(made, "a b", [("T", "@\"Some Class\"")])
            objc_registerClassPair(made)
            cls = made
        }
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let lines = snapshot.components(separatedBy: "\n")
        for expected in ["class RuntimeSnapshot%20Escaped%C3%A9",
                         "  protocol RuntimeSnapshot%20Escaped%20Protocol",
                         "  instance-property a%20b type=@\"Some%20Class\" ownership=unsafe_unretained atomic ivar= raw=T@\"Some%20Class\"",
                         "end class RuntimeSnapshot%20Escaped%C3%A9"] {
            XCTAssertTrue(lines.contains(expected), "no “\(expected)” in\n\(snapshot)")
        }
        XCTAssertEqual(RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot).errors, [])
        XCTAssertEqual(RuntimeSnapshot.duplicateLines(kind: "instance-method", entries: [("-a b", "x"), ("-a b", "y")], onlyWhenDetailsDiffer: false),
                       ["DUPLICATE instance-method -a%20b count=2"])
    }

    // Escaping uses no Unicode tables: every byte that is not printable ASCII
    // is escaped, and so is %.
    func testEscapingIsByteBased() {
        XCTAssertEqual(RuntimeSnapshotFormat.escape("a b%c\u{7f}\u{e9}\u{200B}\u{0}"), "a%20b%25c%7F%C3%A9%E2%80%8B%00")
        XCTAssertEqual(RuntimeSnapshotFormat.escape("{CGSize=dd}<x,y>\"q\""), "{CGSize=dd}<x,y>\"q\"")
        XCTAssertTrue(RuntimeSnapshotFormat.isCanonical("a%20b%C3%A9"))
        XCTAssertFalse(RuntimeSnapshotFormat.isCanonical("a%41"))
        XCTAssertFalse(RuntimeSnapshotFormat.isCanonical("caf\u{e9}"))
        XCTAssertFalse(RuntimeSnapshotFormat.isCanonical("%c3%a9"))
    }

    // MARK: - Helpers

    // The only element, or a test failure and an empty string, so a wrong
    // count fails the test instead of crashing the test process.
    private func single(_ values: [String], file: StaticString = #filePath, line: UInt = #line) -> String {
        guard values.count == 1, let value = values.first else {
            XCTFail("expected exactly one element, got \(values)", file: file, line: line)
            return ""
        }
        return value
    }

    private func removingLines(containing needle: String, from text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter { !$0.contains(needle) }
        XCTAssertNotEqual(lines.count, text.components(separatedBy: "\n").count, "no line contains \(needle)")
        return lines.joined(separator: "\n")
    }
}
