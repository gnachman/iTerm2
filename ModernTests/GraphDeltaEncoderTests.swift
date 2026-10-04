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

    // MARK: - Duplicate sibling records

    // What iTermGraphDatabase's reallySave: does with each (before, after) pair, except that
    // the two failures that crash the app are recorded instead of thrown or asserted:
    // a `before` without a rowid (the MissingRowID exception) and a `before`/`after` pair whose
    // rowids disagree (assert(before.rowid == after.rowid)).
    private struct SaveProblems {
        var missingRowIDs = [String]()
        var mismatchedRowIDs = [String]()
    }

    private func simulateSave(_ encoder: iTermGraphDeltaEncoder) -> SaveProblems {
        var problems = SaveProblems()
        _ = encoder.enumerateRecords { before, after, _, path, _ in
            if let before, before.rowid == nil {
                problems.missingRowIDs.append(path)
                return
            }
            switch (before, after) {
            case (nil, let after?):
                self.nextRowID += 1
                after.rowid = NSNumber(value: self.nextRowID)
            case (let before?, let after?):
                if after.rowid == nil {
                    after.rowid = before.rowid
                } else if before.generation == after.generation && after.generation != iTermGenerationAlwaysEncode {
                    return
                }
                if before.rowid != after.rowid {
                    problems.mismatchedRowIDs.append("\(path): before rowid \(self.describe(before.rowid)), after rowid \(self.describe(after.rowid))")
                }
            default:
                break
            }
        }
        return problems
    }

    // Paths of records that a save left without a rowid. The next save's delta is computed
    // against this tree, and any such record makes it throw MissingRowID.
    private func recordsWithoutRowIDs(_ record: iTermEncoderGraphRecord, path: String = "root") -> [String] {
        var result = record.rowid == nil ? [path] : []
        for child in record.graphRecords {
            result += recordsWithoutRowIDs(child, path: "\(path).\(child.key)[\(child.identifier)]")
        }
        return result
    }

    private func record(key: String,
                        identifier: String,
                        generation: Int,
                        rowid: Int,
                        pod: [String: Any] = [:],
                        children: [iTermEncoderGraphRecord] = []) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs(pod,
                                                graphs: children,
                                                generation: generation,
                                                key: key,
                                                identifier: identifier,
                                                rowid: NSNumber(value: rowid))
    }

    // A previous revision shaped like what loads from a database containing a duplicate
    // sibling: root > __array[items] > { e0...e(n-1), X (first), X (last) }, where each X has a
    // "wrapper" child. This is the shape of the crashing records (a LineBuffer block's
    // "Block Wrapper", or a mark's "content", inside a large array).
    private func previousRevisionWithDuplicate(uniqueCount: Int,
                                               firstGeneration: Int,
                                               firstWrapperGeneration: Int,
                                               lastGeneration: Int,
                                               lastWrapperGeneration: Int,
                                               includeLast: Bool = true) -> iTermEncoderGraphRecord {
        var elements = (0..<uniqueCount).map {
            record(key: "", identifier: "e\($0)", generation: 1, rowid: 10 + $0, pod: ["v": "old"])
        }
        elements.append(record(key: "", identifier: "X", generation: firstGeneration, rowid: 100,
                               children: [record(key: "wrapper", identifier: "", generation: firstWrapperGeneration, rowid: 101)]))
        if includeLast {
            elements.append(record(key: "", identifier: "X", generation: lastGeneration, rowid: 200,
                                   children: [record(key: "wrapper", identifier: "", generation: lastWrapperGeneration, rowid: 201)]))
        }
        let order = ((0..<uniqueCount).map { "e\($0)" } + ["X"]).joined(separator: "\t")
        let array = record(key: "__array", identifier: "items", generation: 1, rowid: 2,
                           pod: ["__order": order], children: elements)
        nextRowID = 1000
        return record(key: "", identifier: "", generation: 1, rowid: 1, children: [array])
    }

    // Encodes a new revision of the array in which X's wrapper is at `wrapperGeneration`.
    private func encodeItems(previous: iTermEncoderGraphRecord,
                             uniqueCount: Int,
                             wrapperGeneration: Int) -> iTermGraphDeltaEncoder {
        let encoder = iTermGraphDeltaEncoder(previousRevision: previous)
        let identifiers = (0..<uniqueCount).map { "e\($0)" } + ["X"]
        encoder.encodeArray(withKey: "items",
                            generation: 2,
                            identifiers: identifiers,
                            options: []) { identifier, _, subencoder, _ in
            subencoder.encode("new", forKey: "v")
            if identifier == "X" {
                _ = subencoder.encodeChild(withKey: "wrapper", identifier: "", generation: wrapperGeneration) { wrapper in
                    wrapper.encode("payload", forKey: "p")
                    return true
                }
            }
            return true
        }
        return encoder
    }

    // MissingRowID: with more than 16 elements the delta encoder looks up X's previous revision
    // in an index. If the index picked the LAST duplicate (gen 5, so the new X is gen 6) while
    // the save pairs X with the FIRST (also gen 6), equal rowid and generation would make the
    // save skip X's subtree, so X's new wrapper would never get a rowid and the next save
    // would throw MissingRowID.
    func testDuplicateSiblingInLargeArrayLeavesRecordWithoutRowID() throws {
        let previous = previousRevisionWithDuplicate(uniqueCount: 17,
                                                     firstGeneration: 6,
                                                     firstWrapperGeneration: 10,
                                                     lastGeneration: 5,
                                                     lastWrapperGeneration: 10)
        let encoder = encodeItems(previous: previous, uniqueCount: 17, wrapperGeneration: 11)
        let problems = simulateSave(encoder)
        XCTAssertEqual(problems.missingRowIDs, [])
        XCTAssertEqual(problems.mismatchedRowIDs, [])
        XCTAssertEqual(recordsWithoutRowIDs(try XCTUnwrap(encoder.record)), [])
    }

    // assert(before.rowid == after.rowid): if the index picked the LAST duplicate, the delta
    // encoder would reuse its unchanged wrapper (rowid 201) in the new tree, while the save
    // pairs it with the FIRST duplicate's wrapper (rowid 101).
    func testDuplicateSiblingInLargeArrayPairsMismatchedRowIDs() throws {
        let previous = previousRevisionWithDuplicate(uniqueCount: 17,
                                                     firstGeneration: 9,
                                                     firstWrapperGeneration: 10,
                                                     lastGeneration: 5,
                                                     lastWrapperGeneration: 20)
        let encoder = encodeItems(previous: previous, uniqueCount: 17, wrapperGeneration: 20)
        let problems = simulateSave(encoder)
        XCTAssertEqual(problems.missingRowIDs, [])
        XCTAssertEqual(problems.mismatchedRowIDs, [])
        XCTAssertEqual(recordsWithoutRowIDs(try XCTUnwrap(encoder.record)), [])
    }

    // The same duplicate in a small array (16 elements or fewer), where the delta encoder
    // doesn't use an index.
    func testDuplicateSiblingInSmallArrayIsConsistent() throws {
        for (firstGeneration, lastWrapperGeneration, wrapperGeneration) in [(6, 10, 11), (9, 20, 20)] {
            let previous = previousRevisionWithDuplicate(uniqueCount: 3,
                                                         firstGeneration: firstGeneration,
                                                         firstWrapperGeneration: 10,
                                                         lastGeneration: 5,
                                                         lastWrapperGeneration: lastWrapperGeneration)
            let encoder = encodeItems(previous: previous, uniqueCount: 3, wrapperGeneration: wrapperGeneration)
            let problems = simulateSave(encoder)
            XCTAssertEqual(problems.missingRowIDs, [])
            XCTAssertEqual(problems.mismatchedRowIDs, [])
            XCTAssertEqual(recordsWithoutRowIDs(try XCTUnwrap(encoder.record)), [])
        }
    }

    // The large-array scenarios without the duplicate.
    func testLargeArrayWithoutDuplicateIsConsistent() throws {
        for (firstGeneration, wrapperGeneration) in [(6, 11), (9, 20)] {
            let previous = previousRevisionWithDuplicate(uniqueCount: 17,
                                                         firstGeneration: firstGeneration,
                                                         firstWrapperGeneration: 10,
                                                         lastGeneration: 5,
                                                         lastWrapperGeneration: 10,
                                                         includeLast: false)
            let encoder = encodeItems(previous: previous, uniqueCount: 17, wrapperGeneration: wrapperGeneration)
            let problems = simulateSave(encoder)
            XCTAssertEqual(problems.missingRowIDs, [])
            XCTAssertEqual(problems.mismatchedRowIDs, [])
            XCTAssertEqual(recordsWithoutRowIDs(try XCTUnwrap(encoder.record)), [])
        }
    }
}
