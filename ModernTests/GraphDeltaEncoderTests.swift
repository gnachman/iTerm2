//
//  GraphDeltaEncoderTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermCodingTests.m. Exercises iTermGraphDeltaEncoder
//  by chaining revisions and turning enumerateRecords into pseudo-SQL, the way
//  iTermGraphDatabase does when it saves.
//

import XCTest
@testable import iTerm2SharedARC

final class GraphDeltaEncoderTests: XCTestCase {
    private var nextRowID = 0

    override func setUp() {
        super.setUp()
        nextRowID = 0
    }

    // MARK: - Helpers

    // Swift stand-in for the compactDescription categories the legacy test defined
    // on Foundation types. Dictionary keys are sorted so output is deterministic.
    private static func compactDescription(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let data as Data:
            return String(data: data, encoding: .utf8) ?? (data as NSData).it_hexEncoded()
        case let date as Date:
            return "\(date.timeIntervalSince1970)"
        case is NSNull:
            return "{null}"
        case let array as [Any]:
            return "[" + array.map { compactDescription($0) }.joined(separator: ", ") + "]"
        case let dict as [String: Any]:
            let kvps = dict.keys.sorted().map { key in
                "\(key)=\(compactDescription(dict[key] ?? NSNull()))"
            }
            return "{" + kvps.joined(separator: ", ") + "}"
        default:
            return "\(value)"
        }
    }

    private func describe(_ rowid: NSNumber?) -> String {
        return rowid.map { "\($0)" } ?? "nil"
    }

    // Mirrors what iTermGraphDatabase does with the delta: inserts get a fresh rowid
    // (which is a side effect the next revision depends on), unchanged PODs are skipped.
    private func pseudoSQL(from encoder: iTermGraphDeltaEncoder) -> [String] {
        var statements = [String]()
        _ = encoder.enumerateRecords { before, after, parent, _, _ in
            switch (before, after) {
            case (let before?, nil):
                statements.append("delete node where rowid=\(self.describe(before.rowid))")
            case (nil, let after?):
                self.nextRowID += 1
                after.rowid = NSNumber(value: self.nextRowID)
                statements.append("insert node key=\(after.key), identifier=\(after.identifier), parent=\(parent), data=\(Self.compactDescription(after.pod)) -> \(self.nextRowID)")
            case (let before?, let after?):
                if (before.pod as NSDictionary) == (after.pod as NSDictionary) {
                    return
                }
                statements.append("update node where rowid=\(self.describe(before.rowid)) set data=\(Self.compactDescription(after.pod))")
            case (nil, nil):
                XCTFail("At least one of before/after should be nonnil")
            }
        }
        return statements
    }

    // A previous revision must carry rowids (the delta encoder asserts this in beta
    // builds), so give every record in a freshly encoded tree one before chaining.
    private func assignRowIDs(_ record: iTermEncoderGraphRecord) {
        if record.rowid == nil {
            nextRowID += 1
            record.rowid = NSNumber(value: nextRowID)
        }
        for child in record.graphRecords {
            assignRowIDs(child)
        }
    }

    private func committedRecord(_ encoder: iTermGraphEncoder) throws -> iTermEncoderGraphRecord {
        let record = try XCTUnwrap(encoder.record)
        assignRowIDs(record)
        return record
    }

    // Encodes root > leaf with the given leaf POD writer and returns the committed record.
    private func encodeRootAndLeaf(previous: iTermEncoderGraphRecord?,
                                   generation: Int,
                                   leaf: (iTermGraphEncoder) -> Void) throws -> iTermGraphDeltaEncoder {
        let encoder = iTermGraphDeltaEncoder(previousRevision: previous)
        _ = encoder.encodeChild(withKey: "root", identifier: "", generation: generation) { subencoder in
            return subencoder.encodeChild(withKey: "leaf", identifier: "", generation: generation) { leafEncoder in
                leaf(leafEncoder)
                return true
            }
        }
        return encoder
    }

    private func encodeArray(_ encoder: iTermGraphEncoder,
                             generation: Int,
                             identifiers: [String],
                             valuePrefix: String) {
        encoder.encodeArray(withKey: "a",
                            generation: generation,
                            identifiers: identifiers,
                            options: []) { identifier, index, subencoder, _ in
            subencoder.encode("\(valuePrefix)_\(identifier)_\(index)", forKey: "k_\(identifier)")
            return true
        }
    }

    // MARK: - Leaf value changes

    func testUpdateValueReportsBeforeAndAfterPODs() throws {
        var encoder = try encodeRootAndLeaf(previous: nil, generation: 1) { $0.encode("value1", forKey: "key") }
        encoder = try encodeRootAndLeaf(previous: try committedRecord(encoder), generation: 2) { $0.encode("value2", forKey: "key") }

        var done = false
        _ = encoder.enumerateRecords { before, after, _, _, _ in
            XCTAssertFalse(done)
            XCTAssertNotNil(before)
            XCTAssertNotNil(after)
            if before?.key == "leaf" {
                XCTAssertEqual(before?.pod as NSDictionary?, ["key": "value1"])
                XCTAssertEqual(after?.pod as NSDictionary?, ["key": "value2"])
                done = true
            }
        }
        XCTAssertTrue(done)
    }

    func testDeleteValueReportsEmptyAfterPOD() throws {
        var encoder = try encodeRootAndLeaf(previous: nil, generation: 1) { $0.encode("value1", forKey: "key") }
        encoder = try encodeRootAndLeaf(previous: try committedRecord(encoder), generation: 2) { _ in }

        var done = false
        _ = encoder.enumerateRecords { before, after, _, _, _ in
            XCTAssertFalse(done)
            XCTAssertNotNil(before)
            XCTAssertNotNil(after)
            if before?.key == "leaf" {
                XCTAssertEqual(before?.pod as NSDictionary?, ["key": "value1"])
                XCTAssertEqual(after?.pod as NSDictionary?, [:])
                done = true
            }
        }
        XCTAssertTrue(done)
    }

    func testInsertValueReportsEmptyBeforePOD() throws {
        var encoder = try encodeRootAndLeaf(previous: nil, generation: 1) { _ in }
        encoder = try encodeRootAndLeaf(previous: try committedRecord(encoder), generation: 2) { $0.encode("value1", forKey: "key") }

        var done = false
        _ = encoder.enumerateRecords { before, after, _, _, _ in
            XCTAssertFalse(done)
            XCTAssertNotNil(before)
            XCTAssertNotNil(after)
            if before?.key == "leaf" {
                XCTAssertEqual(before?.pod as NSDictionary?, [:])
                XCTAssertEqual(after?.pod as NSDictionary?, ["key": "value1"])
                done = true
            }
        }
        XCTAssertTrue(done)
    }

    // MARK: - Node insertion and deletion

    func testDeleteNodeReportsNilAfter() throws {
        let first = try encodeRootAndLeaf(previous: nil, generation: 1) { $0.encode("value1", forKey: "key") }
        let encoder = iTermGraphDeltaEncoder(previousRevision: try committedRecord(first))
        _ = encoder.encodeChild(withKey: "root", identifier: "", generation: 2) { _ in true }

        var done = false
        _ = encoder.enumerateRecords { before, after, _, _, _ in
            if before?.key == "leaf" {
                XCTAssertNil(after)
                XCTAssertEqual(before?.pod as NSDictionary?, ["key": "value1"])
                done = true
            }
        }
        XCTAssertTrue(done)
    }

    func testInsertNodeReportsNilBefore() throws {
        let first = iTermGraphDeltaEncoder(previousRevision: nil)
        _ = first.encodeChild(withKey: "root", identifier: "", generation: 1) { _ in true }
        let encoder = try encodeRootAndLeaf(previous: try committedRecord(first), generation: 2) { $0.encode("value1", forKey: "key") }

        var done = false
        _ = encoder.enumerateRecords { before, after, _, _, _ in
            if after?.key == "leaf" {
                XCTAssertNil(before)
                XCTAssertEqual(after?.pod as NSDictionary?, ["key": "value1"])
                done = true
            }
        }
        XCTAssertTrue(done)
    }

    func testEnumerationReportsPaths() throws {
        let encoder = try encodeRootAndLeaf(previous: nil, generation: 1) { $0.encode("value1", forKey: "key") }
        var paths = [String]()
        _ = encoder.enumerateRecords { _, _, _, path, _ in
            paths.append(path)
        }
        XCTAssertEqual(paths, ["root", "root.root[]", "root.root[].leaf[]"])
    }

    // MARK: - Arrays

    func testArrayWithUnchangedGenerationDoesNotInvokeBlock() throws {
        let first = iTermGraphDeltaEncoder(previousRevision: nil)
        encodeArray(first, generation: 1, identifiers: ["i1", "i2", "i3"], valuePrefix: "value1")

        let encoder = iTermGraphDeltaEncoder(previousRevision: try committedRecord(first))
        encoder.encodeArray(withKey: "a",
                            generation: 1,
                            identifiers: ["i1", "i2", "i3"],
                            options: []) { _, _, _, _ in
            XCTFail("Should not have been called because generation didn't change")
            return true
        }
    }

    // root (1)
    //   __array[a] (2)
    //     [i1 k_i1=value1_i1_0] (3)
    //     [i2 k_i2=value1_i2_1] (4)
    //     [i3 k_i3=value1_i3_2] (5)
    private let initialArrayStatements = [
        "insert node key=, identifier=, parent=0, data={} -> 1",
        "insert node key=__array, identifier=a, parent=1, data={__order=i1\ti2\ti3} -> 2",
        "insert node key=, identifier=i1, parent=2, data={k_i1=value1_i1_0} -> 3",
        "insert node key=, identifier=i2, parent=2, data={k_i2=value1_i2_1} -> 4",
        "insert node key=, identifier=i3, parent=2, data={k_i3=value1_i3_2} -> 5",
    ]

    private func encodeInitialArray() throws -> iTermGraphDeltaEncoder {
        let encoder = iTermGraphDeltaEncoder(previousRevision: nil)
        encodeArray(encoder, generation: 1, identifiers: ["i1", "i2", "i3"], valuePrefix: "value1")
        XCTAssertEqual(pseudoSQL(from: encoder), initialArrayStatements)
        return encoder
    }

    func testArrayModifyValuesUpdatesEachElement() throws {
        let first = try encodeInitialArray()

        let encoder = iTermGraphDeltaEncoder(previousRevision: try XCTUnwrap(first.record))
        encodeArray(encoder, generation: 2, identifiers: ["i1", "i2", "i3"], valuePrefix: "value2")

        XCTAssertEqual(pseudoSQL(from: encoder), [
            "update node where rowid=3 set data={k_i1=value2_i1_0}",
            "update node where rowid=4 set data={k_i2=value2_i2_1}",
            "update node where rowid=5 set data={k_i3=value2_i3_2}",
        ])
    }

    func testArrayDeleteFirstValueRewritesOrderAndDeletesNode() throws {
        let first = try encodeInitialArray()

        let encoder = iTermGraphDeltaEncoder(previousRevision: try XCTUnwrap(first.record))
        encodeArray(encoder, generation: 2, identifiers: ["i2", "i3"], valuePrefix: "value2")

        XCTAssertEqual(pseudoSQL(from: encoder), [
            "update node where rowid=2 set data={__order=i2\ti3}",
            "delete node where rowid=3",
            "update node where rowid=4 set data={k_i2=value2_i2_0}",
            "update node where rowid=5 set data={k_i3=value2_i3_1}",
        ])
    }

    func testArrayAppendInsertsOnlyNewElement() throws {
        let first = try encodeInitialArray()

        let encoder = iTermGraphDeltaEncoder(previousRevision: try XCTUnwrap(first.record))
        encodeArray(encoder, generation: 2, identifiers: ["i1", "i2", "i3", "i4"], valuePrefix: "value1")

        XCTAssertEqual(pseudoSQL(from: encoder), [
            "update node where rowid=2 set data={__order=i1\ti2\ti3\ti4}",
            "insert node key=, identifier=i4, parent=2, data={k_i4=value1_i4_3} -> 6",
        ])
    }

    // MARK: - Mixed tree delta

    /*
       [root k1=k1_v1]
         [k2 k3=k3_v1]
           [k4 k5=k5v1]
           [k6[i1] k7=k7_v1]
           [k6[i2] k9=k9_v1 k9a=k9a_v1]
           [k6[i3] k10=k10_v1]
     */
    private func encodeInitialTree() -> iTermGraphDeltaEncoder {
        let encoder = iTermGraphDeltaEncoder(previousRevision: nil)
        encoder.encode("k1_v1", forKey: "k1")
        _ = encoder.encodeChild(withKey: "k2", identifier: "", generation: 1) { k2 in
            k2.encode("k3_v1", forKey: "k3")
            _ = k2.encodeChild(withKey: "k4", identifier: "", generation: 1) { k4 in
                k4.encode("k5_v1", forKey: "k5")
                return true
            }
            _ = k2.encodeChild(withKey: "k6", identifier: "i1", generation: 1) { k6 in
                k6.encode("k7_v1", forKey: "k7")
                return true
            }
            _ = k2.encodeChild(withKey: "k6", identifier: "i2", generation: 1) { k6 in
                k6.encode("k9_v1", forKey: "k9")
                k6.encode("k9a_v1", forKey: "k9a")
                return true
            }
            _ = k2.encodeChild(withKey: "k6", identifier: "i3", generation: 1) { k6 in
                k6.encode("k10_v1", forKey: "k10")
                return true
            }
            return true
        }
        return encoder
    }

    func testInitialTreeIsAllInserts() {
        let encoder = encodeInitialTree()
        XCTAssertEqual(pseudoSQL(from: encoder), [
            "insert node key=, identifier=, parent=0, data={k1=k1_v1} -> 1",
            "insert node key=k2, identifier=, parent=1, data={k3=k3_v1} -> 2",
            "insert node key=k4, identifier=, parent=2, data={k5=k5_v1} -> 3",
            "insert node key=k6, identifier=i1, parent=2, data={k7=k7_v1} -> 4",
            "insert node key=k6, identifier=i2, parent=2, data={k9=k9_v1, k9a=k9a_v1} -> 5",
            "insert node key=k6, identifier=i3, parent=2, data={k10=k10_v1} -> 6",
        ])
    }

    /*
       [root k1=k1_v1->k1_v2]
         [k2 k3=k3_v1->(unset)]
           [k4 k5=k5v1]
           del k6[i1]
           [k6[i2] k9=k9_v1->k9_v2 k9a=k9a_v1 k9b=(unset)->k9b_v1]
           [k6[i3] k10=k10_v1]
           add [k6[i4] k11=k11_v1]
     */
    func testSecondRevisionEmitsOnlyChanges() throws {
        let first = encodeInitialTree()
        // This has the side effect of assigning row IDs so the next batch of SQL is correct.
        _ = pseudoSQL(from: first)

        let encoder = iTermGraphDeltaEncoder(previousRevision: try XCTUnwrap(first.record))
        encoder.encode("k1_v2", forKey: "k1")
        _ = encoder.encodeChild(withKey: "k2", identifier: "", generation: 2) { k2 in
            // Omit k3
            _ = k2.encodeChild(withKey: "k4", identifier: "", generation: 1) { _ in
                XCTFail("Shouldn't reach this because generation is unchanged.")
                return true
            }
            // Omit k6[i1]
            _ = k2.encodeChild(withKey: "k6", identifier: "i2", generation: 2) { k6 in
                k6.encode("k9_v2", forKey: "k9")
                k6.encode("k9a_v1", forKey: "k9a")
                k6.encode("k9b_v1", forKey: "k9b")
                return true
            }
            _ = k2.encodeChild(withKey: "k6", identifier: "i3", generation: 1) { _ in
                XCTFail("Shouldn't reach this because generation is unchanged.")
                return true
            }
            _ = k2.encodeChild(withKey: "k6", identifier: "i4", generation: 1) { k6 in
                k6.encode("k11_v1", forKey: "k11")
                return true
            }
            return true
        }

        XCTAssertEqual(pseudoSQL(from: encoder), [
            "update node where rowid=1 set data={k1=k1_v2}",
            "update node where rowid=2 set data={}",
            "delete node where rowid=4",
            "update node where rowid=5 set data={k9=k9_v2, k9a=k9a_v1, k9b=k9b_v1}",
            "insert node key=k6, identifier=i4, parent=2, data={k11=k11_v1} -> 7",
        ])
    }
}
