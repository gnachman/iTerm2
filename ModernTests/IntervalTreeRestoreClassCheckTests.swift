//
//  IntervalTreeRestoreClassCheckTests.swift
//  ModernTests
//
//  -[IntervalTree restoreFromDictionary:] reads each entry's class name from
//  saved state (window arrangements, session restoration) and instantiates
//  it with -initWithDictionary:. Many unrelated classes respond to that
//  selector, so restoring must accept only classes that conform to
//  IntervalTreeObject (the protocol that declares -initWithDictionary: for
//  objects stored in the tree), and must keep accepting every class that is
//  legitimately stored.
//

import XCTest
import ObjectiveC
import SQLite3
@testable import iTerm2SharedARC

final class IntervalTreeRestoreClassCheckTests: XCTestCase {
    // The restored objects, read as an untyped NSArray: before the fix a
    // restored object need not conform to IntervalTreeImmutableObject, and
    // bridging -allObjects to its Swift element type would trap.
    private func restore(_ dictionary: [AnyHashable: Any]) -> [AnyObject] {
        let tree = IntervalTree(dictionary: dictionary)
        guard let result = tree.perform(NSSelectorFromString("allObjects"))?.takeUnretainedValue() as? NSArray else {
            XCTFail("-allObjects returned nothing")
            return []
        }
        return result.map { $0 as AnyObject }
    }

    private func roundTrip(_ object: IntervalTreeObject) -> [AnyObject] {
        let tree = IntervalTree()
        tree.add(object, with: Interval(location: 10, length: 5))
        return restore(tree.dictionaryValue(withOffset: 0))
    }

    // MARK: - Rejected

    // A class that responds to -initWithDictionary: and has the entry
    // property the tree sets, but does not conform to IntervalTreeObject.
    // Before the fix it was instantiated and added to the tree.
    func testEntryNamingANonIntervalTreeObjectClassIsSkipped() throws {
        let className = NSStringFromClass(NotAnIntervalTreeObject.self)
        XCTAssertTrue(NotAnIntervalTreeObject.instancesRespond(to: NSSelectorFromString("initWithDictionary:")))
        let protocolObject = try XCTUnwrap(objc_getProtocol("IntervalTreeObject"))
        XCTAssertFalse(class_conformsToProtocol(NotAnIntervalTreeObject.self, protocolObject))

        let mark = iTermMark()
        let tree = IntervalTree()
        tree.add(mark, with: Interval(location: 0, length: 1))
        var dictionary = tree.dictionaryValue(withOffset: 0)
        var entries = try XCTUnwrap(dictionary["Entries"] as? [[AnyHashable: Any]])
        XCTAssertEqual(entries.count, 1)
        var foreign = entries[0]
        foreign["Class"] = className
        foreign["Object"] = ["anything": 1]
        entries.append(foreign)
        dictionary["Entries"] = entries

        let restored = restore(dictionary)
        XCTAssertEqual(restored.count, 1, "only the mark should be restored: \(restored)")
        XCTAssertTrue(restored.first is iTermMark)
        XCTAssertFalse(restored.contains { $0 is NotAnIntervalTreeObject })
    }

    func testEntryNamingANonexistentClassIsSkipped() throws {
        let tree = IntervalTree()
        tree.add(iTermMark(), with: Interval(location: 0, length: 1))
        var dictionary = tree.dictionaryValue(withOffset: 0)
        var entries = try XCTUnwrap(dictionary["Entries"] as? [[AnyHashable: Any]])
        entries[0]["Class"] = "iTermNoSuchIntervalTreeObjectClass"
        dictionary["Entries"] = entries
        XCTAssertEqual(restore(dictionary).count, 0)
    }

    // MARK: - Accepted

    // One instance of each class that is stored in interval trees, keyed by
    // its runtime name (the name the tree writes and looks up). The headers
    // of iTermCapturedOutputMark and VT100WorkingDirectory are not visible to
    // Swift, so those two are made through the runtime: the first with
    // iTermMark's -init, which it inherits, and the second with
    // -initWithDictionary: on a hand-written dictionary in the form its
    // -dictionaryValue produces.
    private static func runtimeClass<T>(_ name: String, as type: T.Type) -> T {
        return NSClassFromString(name) as! T
    }

    private static let makers: [String: () -> IntervalTreeObject] = [
        "iTermMark": { iTermMark() },
        "VT100ScreenMark": { VT100ScreenMark() },
        "iTermCapturedOutputMark": { runtimeClass("iTermCapturedOutputMark", as: iTermMark.Type.self).init() },
        "iTermImageMark": { iTermImageMark(imageCode: NSNumber(value: 7)) },
        "iTermBlockMark": { BlockMark() },
        "iTermButtonMark": { ButtonMark() },
        "iTermFoldMark": { FoldMark(savedLines: nil, savedITOs: [], promptLength: 0, imageCodes: [], width: 80) },
        "iTermPathMark": { PathMark(remoteHost: nil, path: "/fake/path") },
        "iTerm2SharedARC.PortholeMark": { PortholeMark("IntervalTreeRestoreClassCheckTests-porthole", width: 80) },
        "PTYAnnotation": { PTYAnnotation() },
        "VT100RemoteHost": { VT100RemoteHost(username: "fakeuser", hostname: "fakehost.example") },
        "VT100WorkingDirectory": {
            runtimeClass("VT100WorkingDirectory", as: IntervalTreeObject.Type.self)
                .init(dictionary: ["Working Directory": "/fake/directory", "Guid": "IntervalTreeRestoreClassCheckTests-guid"])!
        },
    ]

    // Every class of the app that conforms to IntervalTreeObject, found at
    // run time, round-trips through the dictionary form as that class. A new
    // conforming class fails here until it is given a maker above.
    func testEveryIntervalTreeObjectClassRoundTrips() throws {
        let names = BindingObjCRuntime.shared.appClassesConforming(to: "IntervalTreeObject")
        XCTAssertTrue(names.contains("iTerm2SharedARC.PortholeMark"), "\(names)")
        XCTAssertEqual(Set(names), Set(Self.makers.keys),
                       "every class conforming to IntervalTreeObject needs a maker in this test")
        for name in names {
            guard let make = Self.makers[name] else {
                continue
            }
            let theClass: AnyClass = try XCTUnwrap(NSClassFromString(name), name)
            let object = make()
            XCTAssertTrue(type(of: object as AnyObject) === theClass, "the maker for \(name) made \(type(of: object))")
            XCTAssertEqual(NSStringFromClass(type(of: object as AnyObject)), name)
            let restored = roundTrip(object)
            XCTAssertEqual(restored.count, 1, "\(name) did not round-trip")
            if let first = restored.first {
                XCTAssertTrue(type(of: first) === theClass, "\(name) came back as \(type(of: first))")
            }
        }
    }

    // PortholeMark has no @objc(Name), so its stored name is module-qualified
    // and must still resolve.
    func testPortholeMarkModuleQualifiedNameResolves() {
        XCTAssertTrue(NSClassFromString("iTerm2SharedARC.PortholeMark") === PortholeMark.self)
    }

    // MARK: - Stored-state corpus

    // 3.4.0 saved each session's interval trees in dictionary form inside the
    // "Screen State" node of restorable-state.sqlite (later versions use the
    // graph form, restored by -restoreFromGraphRecord:..., which already
    // checked conformance). Every tree restores the number and classes of
    // objects that its entries list; all of them are legitimate classes.
    func testCorpusIntervalTreesRestore() throws {
        let files = [
            "tests/stored-state-corpus/3.4.0/home/Library/Application Support/iTerm2/SavedState/restorable-state.sqlite",
            "tests/stored-state-corpus/3.4.0-restore1/home/Library/Application Support/iTerm2/SavedState/restorable-state.sqlite",
        ]
        var trees = 0
        var objects = 0
        for file in files {
            for blob in try Self.screenStateBlobs(BindingRepository.url(file)) {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: blob)
                unarchiver.requiresSecureCoding = false
                let screenState = try XCTUnwrap(unarchiver.decodeObject(forKey: "root") as? [AnyHashable: Any], file)
                for key in ["Interval Tree", "Saved Interval Tree"] {
                    let dictionary = try XCTUnwrap(screenState[key] as? [AnyHashable: Any], "\(file) \(key)")
                    let entries = try XCTUnwrap(dictionary["Entries"] as? [[AnyHashable: Any]], "\(file) \(key)")
                    let expected = entries.map { $0["Class"] as? String ?? "" }.sorted()
                    let actual = restore(dictionary).map { NSStringFromClass(type(of: $0)) }.sorted()
                    XCTAssertEqual(actual, expected, "\(file) \(key)")
                    trees += 1
                    objects += actual.count
                }
            }
        }
        // Counted from the corpus with a separate script: 9 sessions (2 in
        // 3.4.0, 7 in 3.4.0-restore1), 18 trees (the saved trees are empty),
        // 84 objects (VT100ScreenMark, VT100RemoteHost, VT100WorkingDirectory).
        XCTAssertEqual(trees, 18)
        XCTAssertEqual(objects, 84)
    }

    // The data column of every Node row whose key is "Screen State". The
    // database is copied first because the corpus files are in WAL mode and
    // opening one in place would create -shm and -wal files next to it.
    private static func screenStateBlobs(_ url: URL) throws -> [Data] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("interval-tree-corpus-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let copy = directory.appendingPathComponent("db.sqlite")
        try FileManager.default.copyItem(at: url, to: copy)
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw NSError(domain: "IntervalTreeRestoreClassCheckTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(url.path)"])
        }
        defer {
            sqlite3_close(db)
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM Node WHERE key = 'Screen State' ORDER BY rowid", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "IntervalTreeRestoreClassCheckTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer {
            sqlite3_finalize(statement)
        }
        var result = [Data]()
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            if count > 0, let bytes = sqlite3_column_blob(statement, 0) {
                result.append(Data(bytes: bytes, count: count))
            }
        }
        return result
    }
}

// Responds to -initWithDictionary: and has the entry property that
// -[IntervalTree addObject:withInterval:] sets, but does not conform to
// IntervalTreeObject.
@objc(IntervalTreeRestoreClassCheckTestsNotAnIntervalTreeObject)
final class NotAnIntervalTreeObject: NSObject {
    @objc weak var entry: IntervalTreeEntry?

    @objc(initWithDictionary:)
    init?(dictionary: [AnyHashable: Any]) {
        super.init()
    }
}
