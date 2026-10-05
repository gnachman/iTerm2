//
//  GraphTableTransformerTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermCodingTests.m. Covers turning Node table rows
//  back into an iTermEncoderGraphRecord tree with iTermGraphTableTransformer.
//

import XCTest
@testable import iTerm2SharedARC

final class GraphTableTransformerTests: XCTestCase {

    // MARK: - Helpers

    // Row format: [key, identifier, parent, rowid, data, generation, has_large_data]
    private func row(_ key: String,
                     _ identifier: String,
                     parent: Int,
                     rowid: Int,
                     data: Data = Data(),
                     generation: Int = 0,
                     hasLargeData: Bool = false) -> [Any] {
        return [key,
                identifier,
                NSNumber(value: parent),
                NSNumber(value: rowid),
                data,
                NSNumber(value: generation),
                NSNumber(value: hasLargeData)]
    }

    private func serialize(_ pod: [String: Any]) throws -> Data {
        return NSData.it_data(withSecurelyArchivedObject: pod as NSDictionary, error: nil)
    }

    private func record(pod: [String: Any] = [:],
                        graphs: [iTermEncoderGraphRecord] = [],
                        generation: Int = 0,
                        key: String,
                        identifier: String,
                        rowid: Int) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs(pod,
                                                graphs: graphs,
                                                generation: generation,
                                                key: key,
                                                identifier: identifier,
                                                rowid: NSNumber(value: rowid))
    }

    // MARK: - Tests

    /*
     <root vk1=vv1 vk2=@123 vk3=date vk4=data>
       <k2>
         <k4[i1]>
         <k4[i2]>
           <k5 vv2=vk5>
     */
    func testHappyPathBuildsTreeFromUnorderedRows() throws {
        let data = Data("xyz".utf8)
        let date = Date(timeIntervalSince1970: 1000000000)
        let rootPOD: [String: Any] = ["vk1": "vv1", "vk2": 123, "vk3": date, "vk4": data]
        let k5POD: [String: Any] = ["vv2": "vk5"]
        let nodes: [[Any]] = [
            row("k5", "", parent: 3, rowid: 5, data: try serialize(k5POD)),
            row("k4", "i1", parent: 2, rowid: 4),
            row("k4", "i2", parent: 2, rowid: 3),
            row("k2", "", parent: 1, rowid: 2),
            row("", "", parent: 0, rowid: 1, data: try serialize(rootPOD)),
        ]

        let transformer = iTermGraphTableTransformer(nodeRows: nodes)
        let actual = try XCTUnwrap(transformer.root)
        XCTAssertNil(transformer.lastError)

        let expectedK4Children = [
            record(pod: k5POD, key: "k5", identifier: "", rowid: 5),
        ]
        let expectedK2Children = [
            record(graphs: expectedK4Children, key: "k4", identifier: "i2", rowid: 3),
            record(key: "k4", identifier: "i1", rowid: 4),
        ]
        let expectedRootGraphs = [
            record(graphs: expectedK2Children, key: "k2", identifier: "", rowid: 2),
        ]
        let expected = record(pod: rootPOD, graphs: expectedRootGraphs, key: "", identifier: "", rowid: 1)
        XCTAssertEqual(actual, expected)
    }

    func testRootIsCachedAcrossAccesses() throws {
        let transformer = iTermGraphTableTransformer(nodeRows: [row("", "", parent: 0, rowid: 1)])
        let first = try XCTUnwrap(transformer.root)
        let second = try XCTUnwrap(transformer.root)
        XCTAssertTrue(first === second)
    }

    func testGenerationColumnIsRestored() throws {
        let nodes: [[Any]] = [
            row("", "", parent: 0, rowid: 1, generation: 7),
            row("child", "", parent: 1, rowid: 2, generation: 3),
        ]
        let root = try XCTUnwrap(iTermGraphTableTransformer(nodeRows: nodes).root)
        XCTAssertEqual(root.generation, 7)
        XCTAssertEqual(root.childRecord(withKey: "child", identifier: "")?.generation, 3)
    }

    func testEmptyDataYieldsEmptyPOD() throws {
        let root = try XCTUnwrap(iTermGraphTableTransformer(nodeRows: [row("", "", parent: 0, rowid: 1)]).root)
        XCTAssertEqual(root.pod as NSDictionary, [:])
    }

    func testMissingFieldInNodeRowFails() {
        let transformer = iTermGraphTableTransformer(nodeRows: [["", ""]])
        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testMistypedFieldInNodeRowFails() {
        let nodes: [[Any]] = [
            [NSNumber(value: 666), "", NSNumber(value: 0), NSNumber(value: 1), Data(), NSNumber(value: 0), NSNumber(value: false)],
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: nodes)
        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testTwoRootsFails() {
        let nodes: [[Any]] = [
            row("", "", parent: 0, rowid: 1),
            row("", "", parent: 0, rowid: 2),
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: nodes)
        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testNoRootFails() {
        let nodes: [[Any]] = [
            row("child", "", parent: 1, rowid: 2),
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: nodes)
        XCTAssertNil(transformer.root)
    }

    func testChildWithBadParentFails() {
        let nodes: [[Any]] = [
            row("", "", parent: 0, rowid: 1),
            row("child", "", parent: 666, rowid: 2),
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: nodes)
        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testEmptyTableHasNoRoot() {
        let transformer = iTermGraphTableTransformer(nodeRows: [])
        XCTAssertNil(transformer.root)
    }
}
