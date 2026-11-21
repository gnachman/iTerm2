//
//  RuntimeSnapshotOwnershipTests.swift
//  ModernTests
//
//  Tests of the ivar ownership that the runtime snapshot reports
//  (RuntimeSnapshotIvarOwnership.swift, docs/swift-migration/phase0.md
//  section 9), against fixture classes whose layouts are known by
//  construction: RuntimeSnapshotFixtures/RuntimeSnapshotOwnershipFixtures.m
//  (ARC), RuntimeSnapshotOwnershipCxxFixtures.mm (Objective-C++), the Swift
//  fixtures in RuntimeSnapshotFixtureExtensions.swift, classes made at run
//  time here, and AATreeNode, an app class compiled without ARC (the test
//  target cannot compile a file without ARC: that needs a per-file flag in
//  the project file).
//

import XCTest
import ObjectiveC

final class RuntimeSnapshotOwnershipTests: XCTestCase {
    private typealias Ownership = RuntimeSnapshotIvarOwnership

    // MARK: - Decoding layouts

    // Each byte is a skip nibble and a scan nibble, skip first; runs longer
    // than 15 continue in further bytes; a zero byte ends the layout.
    func testScannedWords() {
        XCTAssertEqual(Ownership.scannedWords([]), [])
        XCTAssertEqual(Ownership.scannedWords([0x01]), [0])
        XCTAssertEqual(Ownership.scannedWords([0x10]), [])
        XCTAssertEqual(Ownership.scannedWords([0x11, 0xF0, 0x11]), [1, 18])
        XCTAssertEqual(Ownership.scannedWords([0x0F, 0x03]), Array(0..<18))
        XCTAssertEqual(Ownership.scannedWords([0xF0, 0x5F, 0x02, 0xF0, 0x41]), Array(20...36) + [56])
        XCTAssertEqual(Ownership.scannedWords([0xF0, 0xF0, 0xF0, 0xA1]), [55])
        XCTAssertEqual(Ownership.scannedWords([0x01, 0x00, 0x01]), [0], "a zero byte ends the layout")
    }

    func testLayoutLineValue() {
        XCTAssertNil(Ownership.layoutLineValue(nil))
        XCTAssertEqual(Ownership.layoutLineValue([]), "00")
        XCTAssertEqual(Ownership.layoutLineValue([0x01, 0x3A]), "013A00")
    }

    // The layouts clang wrote for the fixtures, as the comments in
    // RuntimeSnapshotOwnershipFixtures.m derive them.
    func testFixtureLayoutsMatchTheirConstruction() throws {
        func layouts(_ name: String) throws -> ([UInt8]?, [UInt8]?) {
            let cls: AnyClass = try XCTUnwrap(NSClassFromString(name))
            return (Ownership.layoutBytes(class_getIvarLayout(cls)), Ownership.layoutBytes(class_getWeakIvarLayout(cls)))
        }
        // Strong: word 0; skip 3, scan 1 (word 4); skip 1, scan 1 (word 6);
        // skip 9, scan 1 (word 16); skip 3, scan 3 (words 20 to 22).
        // Weak: skip 1, scan 1 (word 1); skip 15, then skip 1 and scan 1
        // (word 18).
        let arc = try layouts("RuntimeSnapshotOwnershipARCFixture")
        XCTAssertEqual(arc.0, [0x01, 0x31, 0x11, 0x91, 0x33])
        XCTAssertEqual(arc.1, [0x11, 0xF0, 0x11])
        // Strong: skip 15 then 5 and scan 15, then scan 2 (words 20 to 36);
        // skip 15, then skip 4 and scan 1 (word 56). Weak: skip 15 three
        // times, then skip 10 and scan 1 (word 55).
        let long = try layouts("RuntimeSnapshotOwnershipLongLayoutFixture")
        XCTAssertEqual(long.0, [0xF0, 0x5F, 0x02, 0xF0, 0x41])
        XCTAssertEqual(long.1, [0xF0, 0xF0, 0xF0, 0xA1])
        let noStrong = try layouts("RuntimeSnapshotOwnershipNoStrongFixture")
        XCTAssertNil(noStrong.0)
        XCTAssertEqual(noStrong.1, [0x01])
        // Relative to the subclass's own instance start: skip 1, scan 1.
        let subclass = try layouts("RuntimeSnapshotOwnershipSubclassFixture")
        XCTAssertEqual(subclass.0, [0x11])
        XCTAssertNil(subclass.1)
    }

    // MARK: - Snapshots of the fixtures

    func testARCFixture() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipARCFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar") || $0.hasPrefix("strong-") || $0.hasPrefix("weak-") || $0.hasPrefix("OWNERSHIP") }, [
            "ivar-arc-flag set",
            "strong-ivar-layout 013111913300",
            "weak-ivar-layout 11F01100",
            "ivar _afterByte types=@ ownership=strong layout=s",
            "ivar _block types=@? ownership=strong layout=s",
            "ivar _byte types=c ownership=scalar layout=",
            "ivar _cfString types=^{__CFString=} ownership=c-pointer layout=",
            "ivar _classObject types=# ownership=unretained-or-manual layout=",
            "ivar _flagA types=b1 ownership=bitfield layout=",
            "ivar _flagB types=b3 ownership=bitfield layout=",
            "ivar _mixed types={?=\"strongField\"@\"number\"q\"weakField\"@\"unretainedField\"@} ownership=arc-members layout=s-w",
            "ivar _objectPointer types=^@ ownership=c-pointer layout=",
            "ivar _objects types=[3@] ownership=arc-members layout=sss",
            "ivar _rawPointer types=^v ownership=c-pointer layout=",
            "ivar _rect types={CGRect=\"origin\"{CGPoint=\"x\"d\"y\"d}\"size\"{CGSize=\"width\"d\"height\"d}} ownership=struct-or-cxx-object layout=",
            "ivar _scalar types=i ownership=scalar layout=",
            "ivar _selector types=: ownership=selector layout=",
            "ivar _strongObject types=@ ownership=strong layout=s",
            "ivar _union types=(?=\"i\"i\"f\"f) ownership=struct-or-cxx-object layout=",
            "ivar _unretainedObject types=@ ownership=unretained-or-manual layout=",
            "ivar _weakObject types=@ ownership=weak layout=w",
        ])
    }

    func testLongLayoutFixture() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipLongLayoutFixture")
        XCTAssertTrue(lines.contains("strong-ivar-layout F05F02F04100"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("weak-ivar-layout F0F0F0A100"), lines.joined(separator: "\n"))
        let ivars = lines.filter { $0.hasPrefix("ivar ") }
        let expected = (0...19).map { String(format: "ivar _s%02d types=q ownership=scalar layout=", $0) } +
            (0...16).map { String(format: "ivar _o%02d types=@ ownership=strong layout=s", $0) } +
            (0...17).map { String(format: "ivar _t%02d types=q ownership=scalar layout=", $0) } +
            ["ivar _weak types=@ ownership=weak layout=w", "ivar _last types=@ ownership=strong layout=s"]
        XCTAssertEqual(ivars.sorted(), expected.sorted())
        XCTAssertFalse(lines.contains { $0.hasPrefix("OWNERSHIP-CONFLICT") }, lines.joined(separator: "\n"))
    }

    // A class compiled with ARC whose ivars are all weak or unretained has no
    // strong layout; the ARC flag still says that the unretained one is
    // unretained under ARC rather than managed by hand.
    func testClassWithNoStrongIvar() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipNoStrongFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar") || $0.hasPrefix("strong-") || $0.hasPrefix("weak-") }, [
            "ivar-arc-flag set",
            "strong-ivar-layout",
            "weak-ivar-layout 0100",
            "ivar _number types=q ownership=scalar layout=",
            "ivar _unretainedObject types=@ ownership=unretained-or-manual layout=",
            "ivar _weakObject types=@ ownership=weak layout=w",
        ])
    }

    // The layout counts from the subclass's own first ivar, not from the
    // start of the object.
    func testSubclassLayoutIsRelativeToItsOwnIvars() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipSubclassFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar ") }, [
            "ivar _subclassNumber types=q ownership=scalar layout=",
            "ivar _subclassStrong types=@ ownership=strong layout=s",
        ])
    }

    // Ivars synthesized for properties get the property's ownership: strong
    // and copy are strong, assign is unretained.
    func testPropertyBackedIvars() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipPropertyFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar ") }, [
            "ivar _assignProperty types=@\"NSObject\" ownership=unretained-or-manual layout=",
            "ivar _copiedProperty types=@\"NSString\" ownership=strong layout=s",
            "ivar _strongProperty types=@\"NSObject\" ownership=strong layout=s",
            "ivar _weakProperty types=@\"NSObject\" ownership=weak layout=w",
        ])
    }

    // C++ members are never in a layout: their destructors, run from
    // .cxx_destruct, own what they hold, including the strong references a
    // std::vector<id> keeps in memory it allocates. A C++ class with an ARC
    // member is in the layout like a struct.
    func testCxxFixture() throws {
        let lines = try sectionLines("RuntimeSnapshotOwnershipCxxFixture")
        XCTAssertTrue(lines.contains("instance-method -.cxx_destruct types=v16@0:8"), lines.joined(separator: "\n"))
        let ivars = lines.filter { $0.hasPrefix("ivar ") }.map { line in
            // The C++ encodings are long; keep the name and the ownership.
            let fields = line.split(separator: " ")
            return "\(fields[1]) \(fields[fields.count - 2]) \(fields[fields.count - 1])"
        }
        XCTAssertEqual(ivars, [
            "_holder ownership=arc-members layout=s",
            "_name ownership=cxx-object layout=",
            "_objects ownership=cxx-object layout=",
            "_plain ownership=struct-or-cxx-object layout=",
            "_plainObject ownership=strong layout=s",
            "_shared ownership=cxx-object layout=",
        ])
        XCTAssertFalse(lines.contains { $0.hasPrefix("OWNERSHIP-CONFLICT") }, lines.joined(separator: "\n"))
    }

    // Swift writes no layouts for its stored properties, so the snapshot does
    // not read ownership from the runtime for a Swift class.
    func testSwiftClassOwnershipComesFromTheDeclaration() throws {
        let lines = try sectionLines("RuntimeSnapshotSwiftOwnershipFixture")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar") || $0.hasPrefix("strong-") || $0.hasPrefix("weak-") }, [
            "ivar-arc-flag set",
            "strong-ivar-layout",
            "weak-ivar-layout",
            "ivar copied types=@\"NSString\" ownership=swift layout=",
            "ivar string types=? ownership=swift layout=",
            "ivar unownedObject types=? ownership=swift layout=",
            "ivar unownedUnsafeObject types=? ownership=swift layout=",
            "ivar weakObject types=? ownership=swift layout=",
        ])
        XCTAssertFalse(lines.contains { $0.hasPrefix("OWNERSHIP-CONFLICT") }, lines.joined(separator: "\n"))
    }

    // AATreeNode is compiled without ARC (sources/DataStructuresAlgorithms/
    // AATree/AATreeNode.m). Its object ivars are retained by hand, which no
    // layout records, and its ARC flag is clear.
    func testClassCompiledWithoutARC() throws {
        let lines = try sectionLines("AATreeNode")
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar") || $0.hasPrefix("strong-") || $0.hasPrefix("weak-") }, [
            "ivar-arc-flag clear",
            "strong-ivar-layout",
            "weak-ivar-layout",
            "ivar _deleted types=\(bool) ownership=scalar layout=",
            "ivar data types=@ ownership=manual layout=",
            "ivar key types=@ ownership=manual layout=",
            "ivar left types=@\"AATreeNode\" ownership=manual layout=",
            "ivar level types=i ownership=scalar layout=",
            "ivar right types=@\"AATreeNode\" ownership=manual layout=",
        ])
    }

    // A class made at run time has an empty layout and a clear ARC flag, so
    // its object ivar is labeled manual, never "not owned".
    func testClassMadeAtRunTime() throws {
        let cls: AnyClass = try makeClass("RuntimeSnapshotOwnershipMadeFixture")
        let lines = try sectionLines(of: cls)
        XCTAssertEqual(lines.filter { $0.hasPrefix("ivar") || $0.hasPrefix("strong-") || $0.hasPrefix("weak-") }, [
            "ivar-arc-flag clear",
            "strong-ivar-layout 00",
            "weak-ivar-layout 00",
            "ivar _number types=q ownership=scalar layout=",
            "ivar _object types=@ ownership=manual layout=",
        ])
    }

    // A class made at run time with a strong layout set by hand: the layout
    // says strong, but the class's ARC flag is clear, so the runtime itself
    // treats the ivar as unknown. That contradiction is reported loudly.
    func testLayoutThatTheRuntimeDisownsIsAConflict() throws {
        let cls: AnyClass = try makeClass("RuntimeSnapshotOwnershipMadeWithLayoutFixture", strongLayout: [0x01])
        let lines = try sectionLines(of: cls)
        XCTAssertTrue(lines.contains("OWNERSHIP-CONFLICT runtime-disagrees _object"), lines.joined(separator: "\n"))
        let snapshot = try RuntimeSnapshot.snapshot(classes: [cls])
        let result = RuntimeSnapshotComparison.compare(before: snapshot, after: snapshot)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.report.contains("OWNERSHIP CONFLICTS"), result.report)
    }

    // Every class the app's binaries define is decoded without a conflict:
    // in particular _class_getIvarMemoryManagement, which reads the same
    // layouts with objc4's own code, agrees with this decoding for the first
    // word of every word-aligned ivar of every Objective-C class in the app.
    func testNoConflictsInAppClasses() throws {
        let macOSDirectory = Bundle.main.bundlePath + "/Contents/MacOS/"
        var classes = [AnyClass]()
        for i in 0..<_dyld_image_count() {
            guard let pathPointer = _dyld_get_image_name(i), String(cString: pathPointer).hasPrefix(macOSDirectory) else {
                continue
            }
            var count: UInt32 = 0
            guard let names = objc_copyClassNamesForImage(pathPointer, &count) else {
                continue
            }
            defer {
                free(names)
            }
            for j in 0..<Int(count) {
                guard let cls = objc_lookUpClass(names[j]), class_getImageName(cls).map({ strcmp($0, pathPointer) == 0 }) == true else {
                    continue
                }
                var root: AnyClass = cls
                while let superclass = class_getSuperclass(root) {
                    root = superclass
                }
                if [ObjectIdentifier(NSObject.self), ObjectIdentifier(NSProxy.self)].contains(ObjectIdentifier(root)) {
                    classes.append(cls)
                }
            }
        }
        XCTAssertGreaterThan(classes.count, 1000)
        var conflicts = [String]()
        var flags = Set<Ownership.ARCFlag>()
        var ivarCount = 0
        for cls in classes {
            let result = RuntimeSnapshot.ivarOwnership(of: cls)
            conflicts.append(contentsOf: result.conflicts.map { "\(String(cString: class_getName(cls))): \($0.reason) \($0.subject)" })
            flags.insert(result.arcFlag)
            ivarCount += result.ivars.count
        }
        XCTAssertEqual(conflicts, [])
        XCTAssertGreaterThan(ivarCount, 5000)
        XCTAssertTrue(flags.isSuperset(of: [.set, .clear]), "\(flags)")
    }

    // MARK: - Classification without the runtime

    private func facts(strong: [UInt8]? = nil,
                       weak: [UInt8]? = nil,
                       size: Int,
                       cxxDestruct: Bool = false,
                       answers: [String: Ownership.MemoryManagement] = [:]) -> Ownership.ClassFacts {
        return Ownership.ClassFacts(isSwift: false,
                                    hasCxxDestruct: cxxDestruct,
                                    strongLayout: strong,
                                    weakLayout: weak,
                                    instanceSize: size,
                                    memoryManagement: answers)
    }

    func testEncodingKinds() {
        XCTAssertEqual(Ownership.kind(ofEncoding: "@"), .object)
        XCTAssertEqual(Ownership.kind(ofEncoding: "@?"), .object)
        XCTAssertEqual(Ownership.kind(ofEncoding: "@\"NSString\""), .object)
        XCTAssertEqual(Ownership.kind(ofEncoding: "#"), .object)
        XCTAssertEqual(Ownership.kind(ofEncoding: "^@"), .cPointer)
        XCTAssertEqual(Ownership.kind(ofEncoding: "r*"), .cPointer)
        XCTAssertEqual(Ownership.kind(ofEncoding: "^{__CFString=}"), .cPointer)
        XCTAssertEqual(Ownership.kind(ofEncoding: "Ai"), .scalar)
        XCTAssertEqual(Ownership.kind(ofEncoding: "{CGPoint=dd}"), .aggregate)
        XCTAssertEqual(Ownership.kind(ofEncoding: "(?=if)"), .aggregate)
        XCTAssertEqual(Ownership.kind(ofEncoding: "[4@]"), .aggregate)
        XCTAssertEqual(Ownership.kind(ofEncoding: "b3"), .bitfield)
        XCTAssertEqual(Ownership.kind(ofEncoding: ":"), .selector)
        XCTAssertEqual(Ownership.kind(ofEncoding: ""), .unknown)
        XCTAssertEqual(Ownership.kind(ofEncoding: "?"), .unknown)
        XCTAssertTrue(Ownership.encodingNamesCxxClass("{vector<id, std::allocator<id>>=}"))
        XCTAssertTrue(Ownership.encodingNamesCxxClass("{ns::Thing=i}"))
        XCTAssertFalse(Ownership.encodingNamesCxxClass("{CGPoint=dd}"))
        XCTAssertFalse(Ownership.encodingNamesCxxClass("{?=\"a\"<x>}"), "only the name counts")
    }

    // Without an answer from _class_getIvarMemoryManagement and without a
    // strong layout, an object in neither layout may be unretained or managed
    // by hand, and the label says it is not known which.
    func testUnknownARCFlag() {
        let ivars = [Ownership.Ivar(name: "_o", encoding: "@", offset: 8),
                     Ownership.Ivar(name: "_s", encoding: "{S=ii}", offset: 16)]
        let result = Ownership.ownership(ivars: ivars, facts: facts(size: 24))
        XCTAssertEqual(result.arcFlag, .unknown)
        XCTAssertEqual(result.ivars["_o"], .init(label: "unretained-or-unknown", layout: ""))
        XCTAssertEqual(result.ivars["_s"], .init(label: "struct-unknown", layout: ""))
        XCTAssertEqual(result.conflicts, [])
    }

    func testStructsByARCFlagAndDestructor() {
        let ivars = [Ownership.Ivar(name: "_o", encoding: "@", offset: 8),
                     Ownership.Ivar(name: "_s", encoding: "{S=ii}", offset: 16)]
        let arc = Ownership.ownership(ivars: ivars, facts: facts(strong: [0x01], size: 24))
        XCTAssertEqual(arc.arcFlag, .set)
        XCTAssertEqual(arc.ivars["_s"], .init(label: "struct-no-destructor", layout: ""))
        let manual = Ownership.ownership(ivars: ivars, facts: facts(size: 24, answers: ["_o": .unknown, "_s": .unknown]))
        XCTAssertEqual(manual.arcFlag, .clear)
        XCTAssertEqual(manual.ivars["_o"], .init(label: "manual", layout: ""))
        XCTAssertEqual(manual.ivars["_s"], .init(label: "manual", layout: ""))
        let manualCxx = Ownership.ownership(ivars: [Ownership.Ivar(name: "_v", encoding: "{vector<int>=}", offset: 8)],
                                            facts: facts(size: 32, cxxDestruct: true, answers: ["_v": .unknown]))
        XCTAssertEqual(manualCxx.ivars["_v"], .init(label: "cxx-object", layout: ""))
    }

    // A word in both layouts, a layout word on a scalar, a layout word past
    // every ivar, and two answers that disagree about the ARC flag are each a
    // conflict.
    func testConflicts() {
        let both = Ownership.ownership(ivars: [Ownership.Ivar(name: "_o", encoding: "@", offset: 8)],
                                       facts: facts(strong: [0x01], weak: [0x01], size: 16))
        XCTAssertEqual(both.conflicts, [.init(reason: "word-in-both-layouts", subject: "word=0")])

        let scalar = Ownership.ownership(ivars: [Ownership.Ivar(name: "_n", encoding: "q", offset: 8)],
                                         facts: facts(strong: [0x01], size: 16))
        XCTAssertEqual(scalar.conflicts, [.init(reason: "layout-word-on-non-object", subject: "_n")])
        XCTAssertEqual(scalar.ivars["_n"], .init(label: "scalar", layout: "s"))

        let past = Ownership.ownership(ivars: [Ownership.Ivar(name: "_o", encoding: "@", offset: 8)],
                                       facts: facts(strong: [0x02], size: 16))
        XCTAssertEqual(past.conflicts, [.init(reason: "layout-word-without-ivar", subject: "word=1")])

        let inconsistent = Ownership.ownership(ivars: [Ownership.Ivar(name: "_a", encoding: "@", offset: 8),
                                                       Ownership.Ivar(name: "_b", encoding: "@", offset: 16)],
                                               facts: facts(size: 24, answers: ["_a": .unretained, "_b": .unknown]))
        XCTAssertEqual(inconsistent.arcFlag, .unknown)
        XCTAssertTrue(inconsistent.conflicts.contains(.init(reason: "arc-flag-inconsistent", subject: "class")), "\(inconsistent.conflicts)")

        let disagreeing = Ownership.ownership(ivars: [Ownership.Ivar(name: "_o", encoding: "@", offset: 8)],
                                              facts: facts(strong: [0x01], size: 16, answers: ["_o": .weak]))
        XCTAssertEqual(disagreeing.conflicts, [.init(reason: "runtime-disagrees", subject: "_o")])
    }

    // An object pointer at an offset that is not a multiple of the word size
    // cannot be in a layout, so its ownership is unknown.
    func testUnalignedObject() {
        let result = Ownership.ownership(ivars: [Ownership.Ivar(name: "_c", encoding: "c", offset: 8),
                                                 Ownership.Ivar(name: "_o", encoding: "@", offset: 9)],
                                         facts: facts(strong: [0x01], size: 24))
        XCTAssertEqual(result.ivars["_o"], .init(label: "unaligned-object", layout: ""))
    }

    // MARK: - The format

    func testLabelListsAgree() {
        XCTAssertEqual(RuntimeSnapshotFormat.ivarOwnerships, Ownership.labels)
        XCTAssertEqual(RuntimeSnapshotFormat.ownershipConflictReasons, Ownership.conflictReasons)
    }

    func testMalformedOwnershipIsRefused() throws {
        let good = try RuntimeSnapshot.snapshot(classNames: ["RuntimeSnapshotStrongIvarFixture"])
        let cases = [
            ("an unknown label", good.replacingOccurrences(of: "ownership=strong", with: "ownership=owned")),
            ("a trailing - in layout=", good.replacingOccurrences(of: "layout=s\n", with: "layout=s-\n")),
            ("a letter other than s, w and -", good.replacingOccurrences(of: "layout=s\n", with: "layout=x\n")),
            ("no layout=", good.replacingOccurrences(of: " layout=s\n", with: "\n")),
            ("no ownership=", good.replacingOccurrences(of: " ownership=strong", with: "")),
            ("no ivar-arc-flag line", good.replacingOccurrences(of: "  ivar-arc-flag set\n", with: "")),
            ("an unknown ARC flag", good.replacingOccurrences(of: "ivar-arc-flag set", with: "ivar-arc-flag maybe")),
            ("a layout with no terminator", good.replacingOccurrences(of: "strong-ivar-layout 0100", with: "strong-ivar-layout 01")),
            ("a layout in lowercase", good.replacingOccurrences(of: "strong-ivar-layout 0100", with: "strong-ivar-layout 0a00")),
            ("a layout with an inner zero", good.replacingOccurrences(of: "strong-ivar-layout 0100", with: "strong-ivar-layout 000100")),
            ("an unknown conflict", good.replacingOccurrences(of: "  ivar-arc-flag set\n", with: "  ivar-arc-flag set\n  OWNERSHIP-CONFLICT whatever _object\n")),
        ]
        XCTAssertTrue(good.contains("  ivar-arc-flag set\n  strong-ivar-layout 0100\n"), good)
        for (what, text) in cases {
            XCTAssertNotEqual(text, good, what)
            let result = RuntimeSnapshotComparison.compare(before: good, after: text)
            XCTAssertFalse(result.errors.isEmpty, "\(what) was accepted:\n\(result.report)")
        }
    }

    // MARK: - Helpers

    #if arch(x86_64)
    private let bool = "c"
    #else
    private let bool = "B"
    #endif

    // The lines of one class's section, without their indentation and
    // without the class and end lines.
    private func sectionLines(_ name: String) throws -> [String] {
        return try sectionLines(of: try XCTUnwrap(NSClassFromString(name), name))
    }

    private func sectionLines(of cls: AnyClass) throws -> [String] {
        return try RuntimeSnapshot.snapshot(classes: [cls])
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("  ") }
            .map { String($0.dropFirst(2)) }
    }

    // A class made at run time with an object ivar and an integer ivar, and
    // optionally a strong layout. It is made once per process.
    private func makeClass(_ name: String, strongLayout: [UInt8]? = nil) throws -> AnyClass {
        if let existing = NSClassFromString(name) {
            return existing
        }
        let made: AnyClass = try XCTUnwrap(objc_allocateClassPair(NSObject.self, name, 0))
        XCTAssertTrue(class_addIvar(made, "_object", 8, 3, "@"))
        XCTAssertTrue(class_addIvar(made, "_number", 8, 3, "q"))
        if let strongLayout {
            (strongLayout + [0]).withUnsafeBufferPointer { class_setIvarLayout(made, $0.baseAddress) }
        }
        objc_registerClassPair(made)
        return made
    }
}
