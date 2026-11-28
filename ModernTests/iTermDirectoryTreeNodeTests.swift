//
//  iTermDirectoryTreeNodeTests.swift
//  ModernTests
//
//  Characterization tests for iTermDirectoryTreeNode, a node of the tree of
//  recently used directories that iTermDirectoryTree keeps to decide which
//  path components can be abbreviated to their first character. A node has
//  a path component (nil for the root), a mutable dictionary of children
//  keyed by component, and a count of the paths that pass through it.
//  iTermDirectoryTree adds paths by walking and creating children itself and
//  removes them with -removePathWithParts:.
//
//  Everything goes through the Objective-C runtime: the class is found by
//  name, nodes are made with +nodeWithComponent:, and every member is sent
//  by its selector, as iTermDirectoryTree reaches them.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The node's selectors, sent by name through AnyObject.
@objc private protocol DirectoryTreeNodeSelectors {
    @objc(nodeWithComponent:)
    func nodeBySelector(component: NSString?) -> NSObject

    @objc(component)
    func componentBySelector() -> NSString?

    @objc(setComponent:)
    func setComponentBySelector(_ component: NSString?)

    @objc(children)
    func childrenBySelector() -> NSMutableDictionary

    @objc(count)
    func countBySelector() -> Int32

    @objc(setCount:)
    func setCountBySelector(_ count: Int32)

    @objc(numberOfChildrenStartingWithString:)
    func numberOfChildrenBySelector(prefix: NSString?) -> Int32

    @objc(removePathWithParts:)
    func removePathBySelector(parts: NSArray?)
}

final class iTermDirectoryTreeNodeTests: XCTestCase {
    private let unitClassName = "iTermDirectoryTreeNode"

    private func nodeClass() throws -> AnyClass {
        return try XCTUnwrap(NSClassFromString(unitClassName))
    }

    private func makeNode(_ component: NSString?) throws -> NSObject {
        let made = (try nodeClass() as AnyObject).nodeBySelector?(component: component)
        return try XCTUnwrap(made)
    }

    private func component(_ node: NSObject) -> NSString? {
        return (node as AnyObject).componentBySelector?() ?? nil
    }

    private func children(_ node: NSObject) throws -> NSMutableDictionary {
        return try XCTUnwrap((node as AnyObject).childrenBySelector?())
    }

    private func count(_ node: NSObject) throws -> Int32 {
        return try XCTUnwrap((node as AnyObject).countBySelector?())
    }

    private func setCount(_ node: NSObject, _ value: Int32) {
        (node as AnyObject).setCountBySelector?(value)
    }

    private func numberOfChildren(_ node: NSObject, _ prefix: NSString?) throws -> Int32 {
        return try XCTUnwrap((node as AnyObject).numberOfChildrenBySelector?(prefix: prefix))
    }

    private func remove(_ parts: [String]?, from node: NSObject) {
        (node as AnyObject).removePathBySelector?(parts: parts.map { $0 as NSArray })
    }

    private func child(_ node: NSObject, _ key: String) throws -> NSObject? {
        return try children(node)[key] as? NSObject
    }

    // Adds a path the way iTermDirectoryTree's -addPath: does: the root's
    // count goes up, and each component's node is found or made under its
    // parent and its count goes up.
    private func add(_ parts: [String], to root: NSObject) throws {
        setCount(root, try count(root) + 1)
        var parent = root
        for part in parts {
            let node: NSObject
            if let existing = try child(parent, part) {
                node = existing
            } else {
                node = try makeNode(part as NSString)
                try children(parent)[part] = node
            }
            setCount(node, try count(node) + 1)
            parent = node
        }
    }

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func attributes(_ cls: AnyClass, _ name: String) throws -> [String] {
        let property = try XCTUnwrap(class_getProperty(cls, name))
        let attributes = try XCTUnwrap(property_getAttributes(property))
        return String(cString: attributes).split(separator: ",").map(String.init)
    }

    // MARK: - The runtime interface

    func testClassIsFoundByItsRuntimeNameWithItsSuperclass() throws {
        let cls = try nodeClass()
        XCTAssertTrue(class_getSuperclass(cls) === NSObject.self)
    }

    func testSelectorsAndEncodings() throws {
        let cls = try nodeClass()
        XCTAssertEqual(instanceMethodEncoding(cls, "initWithComponent:"), "@24@0:8@16")
        XCTAssertEqual(instanceMethodEncoding(cls, "component"), "@16@0:8")
        XCTAssertEqual(instanceMethodEncoding(cls, "setComponent:"), "v24@0:8@16")
        XCTAssertEqual(instanceMethodEncoding(cls, "children"), "@16@0:8")
        XCTAssertNil(instanceMethodEncoding(cls, "setChildren:"))
        XCTAssertEqual(instanceMethodEncoding(cls, "count"), "i16@0:8")
        XCTAssertEqual(instanceMethodEncoding(cls, "setCount:"), "v20@0:8i16")
        XCTAssertEqual(instanceMethodEncoding(cls, "numberOfChildrenStartingWithString:"), "i24@0:8@16")
        XCTAssertEqual(instanceMethodEncoding(cls, "removePathWithParts:"), "v24@0:8@16")
        let metaclass: AnyClass = try XCTUnwrap(object_getClass(cls))
        XCTAssertEqual(instanceMethodEncoding(metaclass, "nodeWithComponent:"), "@24@0:8@16")
    }

    func testPropertyAttributes() throws {
        let cls = try nodeClass()
        let component = try attributes(cls, "component")
        XCTAssertEqual(component.first, "T@\"NSString\"")
        XCTAssertTrue(component.contains("C"), component.joined(separator: ","))
        XCTAssertTrue(component.contains("N"), component.joined(separator: ","))
        XCTAssertFalse(component.contains("R"), component.joined(separator: ","))
        let children = try attributes(cls, "children")
        XCTAssertEqual(children.first, "T@\"NSMutableDictionary\"")
        XCTAssertTrue(children.contains("R"), children.joined(separator: ","))
        XCTAssertTrue(children.contains("N"), children.joined(separator: ","))
        let count = try attributes(cls, "count")
        XCTAssertEqual(count.first, "Ti")
        XCTAssertTrue(count.contains("N"), count.joined(separator: ","))
        XCTAssertFalse(count.contains("R"), count.joined(separator: ","))
    }

    // MARK: - Making nodes

    func testNodeWithComponentMakesAnEmptyNode() throws {
        let node = try makeNode("usr")
        XCTAssertTrue(type(of: node) == (try nodeClass()))
        XCTAssertEqual(component(node), "usr")
        XCTAssertEqual(try children(node).count, 0)
        XCTAssertEqual(try count(node), 0)
    }

    // iTermDirectoryTree's root has no component.
    func testNodeWithNilComponent() throws {
        let node = try makeNode(nil)
        XCTAssertNil(component(node))
        XCTAssertEqual(try children(node).count, 0)
    }

    // A mutable string changed after it was given to the node does not
    // change the node's component.
    func testComponentIsCopied() throws {
        let initial = NSMutableString(string: "usr")
        let node = try makeNode(initial)
        initial.append("-changed")
        XCTAssertEqual(component(node), "usr")
        let later = NSMutableString(string: "bin")
        (node as AnyObject).setComponentBySelector?(later)
        later.append("-changed")
        XCTAssertEqual(component(node), "bin")
        (node as AnyObject).setComponentBySelector?(nil)
        XCTAssertNil(component(node))
    }

    func testCountRoundTrips() throws {
        let node = try makeNode("x")
        for value: Int32 in [1, -1, Int32.max, Int32.min, 0] {
            setCount(node, value)
            XCTAssertEqual(try count(node), value)
        }
    }

    // The children dictionary is one mutable object that callers change in
    // place.
    func testChildrenIsOneSharedMutableDictionary() throws {
        let node = try makeNode("x")
        let first = try children(node)
        let child = try makeNode("y")
        first["y"] = child
        let second = try children(node)
        XCTAssertTrue(first === second)
        XCTAssertTrue(second["y"] as AnyObject === child)
    }

    // MARK: - Counting children by prefix

    func testNumberOfChildrenStartingWithString() throws {
        let node = try makeNode(nil)
        for key in ["usr", "Users", "bin", "ubuntu", "u"] {
            try children(node)[key] = try makeNode(key as NSString)
        }
        XCTAssertEqual(try numberOfChildren(node, "u"), 3)
        XCTAssertEqual(try numberOfChildren(node, "U"), 1)
        XCTAssertEqual(try numberOfChildren(node, "us"), 1)
        XCTAssertEqual(try numberOfChildren(node, "b"), 1)
        XCTAssertEqual(try numberOfChildren(node, "z"), 0)
        XCTAssertEqual(try numberOfChildren(node, "usrx"), 0)
    }

    // An empty prefix matches no child, as -[NSString hasPrefix:] answers NO
    // for an empty string.
    func testEmptyPrefixMatchesNothing() throws {
        let node = try makeNode(nil)
        try children(node)["usr"] = try makeNode("usr")
        XCTAssertEqual(try numberOfChildren(node, ""), 0)
    }

    func testNoChildrenGivesZeroForAnyPrefix() throws {
        let node = try makeNode(nil)
        XCTAssertEqual(try numberOfChildren(node, "a"), 0)
        XCTAssertEqual(try numberOfChildren(node, nil), 0)
    }

    // iTermDirectoryTree passes the first UTF-16 unit of a component as the
    // prefix, which for a character outside the Basic Multilingual Plane is
    // half of a surrogate pair. Prefixes are compared unit by unit, so two
    // emoji that share a leading surrogate both match it.
    func testHalfASurrogatePairPrefixMatchesByUTF16Units() throws {
        let node = try makeNode(nil)
        for key in ["\u{1F600}a", "\u{1F603}b", "\u{2603}c", "x"] {
            try children(node)[key] = try makeNode(key as NSString)
        }
        let prefix = ("\u{1F600}" as NSString).substring(to: 1) as NSString
        XCTAssertEqual(prefix.length, 1)
        XCTAssertEqual(try numberOfChildren(node, prefix), 2)
    }

    // Prefixes are compared unit by unit, not by canonical equivalence: a
    // decomposed “é” starts with “e”, and a precomposed one does not.
    func testPrefixesAreComparedLiterally() throws {
        let node = try makeNode(nil)
        let decomposed = NSString(characters: [0x65, 0x301, 0x78], length: 3)
        let precomposed = NSString(characters: [0xE9, 0x79], length: 2)
        for key in [decomposed, precomposed, "ez" as NSString] {
            try children(node)[key] = try makeNode(key)
        }
        XCTAssertEqual(try numberOfChildren(node, "e"), 2)
        XCTAssertEqual(try numberOfChildren(node, NSString(characters: [0xE9], length: 1)), 1)
    }

    // MARK: - Removing paths

    func testRemovingTheOnlyPathRemovesItsBranch() throws {
        let root = try makeNode(nil)
        try add(["a", "b"], to: root)
        remove(["a", "b"], from: root)
        XCTAssertEqual(try count(root), 0)
        XCTAssertNil(try child(root, "a"))
    }

    // Removing one of two paths through a node decrements its count and
    // keeps it. The last component's node is left in its parent's children
    // with its count unchanged.
    func testRemovingOneOfTwoPathsKeepsTheSharedNodeAndTheLeaf() throws {
        let root = try makeNode(nil)
        try add(["a", "b"], to: root)
        try add(["a", "c"], to: root)
        remove(["a", "b"], from: root)
        XCTAssertEqual(try count(root), 1)
        let a = try XCTUnwrap(try child(root, "a"))
        XCTAssertEqual(try count(a), 1)
        let b = try XCTUnwrap(try child(a, "b"))
        XCTAssertEqual(try count(b), 1)
        let c = try XCTUnwrap(try child(a, "c"))
        XCTAssertEqual(try count(c), 1)
    }

    func testRemovingADeepPathTwice() throws {
        let root = try makeNode(nil)
        try add(["a", "b", "c"], to: root)
        try add(["a", "b", "c"], to: root)
        remove(["a", "b", "c"], from: root)
        let a = try XCTUnwrap(try child(root, "a"))
        let b = try XCTUnwrap(try child(a, "b"))
        let c = try XCTUnwrap(try child(b, "c"))
        XCTAssertEqual(try count(root), 1)
        XCTAssertEqual(try count(a), 1)
        XCTAssertEqual(try count(b), 1)
        XCTAssertEqual(try count(c), 2)
        remove(["a", "b", "c"], from: root)
        XCTAssertEqual(try count(root), 0)
        XCTAssertNil(try child(root, "a"))
        XCTAssertEqual(try count(a), 0)
        XCTAssertNil(try child(a, "b"))
        XCTAssertEqual(try count(b), 0)
        XCTAssertEqual(try count(c), 2)
    }

    // With one part or none, only the node's own count changes.
    func testRemovingOnePartOrNoneOnlyDecrementsTheCount() throws {
        let root = try makeNode(nil)
        try add(["a"], to: root)
        remove(["a"], from: root)
        XCTAssertEqual(try count(root), 0)
        let a = try XCTUnwrap(try child(root, "a"))
        XCTAssertEqual(try count(a), 1)
        remove([], from: root)
        XCTAssertEqual(try count(root), -1)
        remove(nil, from: root)
        XCTAssertEqual(try count(root), -2)
        XCTAssertNotNil(try child(root, "a"))
    }

    // A path whose first component is not a child decrements the count and
    // changes nothing else.
    func testRemovingAMissingPath() throws {
        let root = try makeNode(nil)
        try add(["a", "b"], to: root)
        remove(["z", "y"], from: root)
        XCTAssertEqual(try count(root), 0)
        let a = try XCTUnwrap(try child(root, "a"))
        XCTAssertEqual(try count(a), 1)
        XCTAssertEqual(try children(root).count, 1)
    }

    // A child whose count was already zero or below and is decremented is
    // removed only when its count is exactly zero afterwards.
    func testAChildIsRemovedOnlyWhenItsCountReachesZero() throws {
        let root = try makeNode(nil)
        try add(["a", "b"], to: root)
        let a = try XCTUnwrap(try child(root, "a"))
        setCount(a, 0)
        remove(["a", "b"], from: root)
        XCTAssertEqual(try count(a), -1)
        XCTAssertTrue(try child(root, "a") === a)
    }

    // MARK: - Description

    func testDescription() throws {
        let node = try makeNode("usr")
        try children(node)["a"] = try makeNode("a")
        try children(node)["b"] = try makeNode("b")
        XCTAssertEqual(node.description, "<iTermDirectoryTreeNode: \(node.it_addressString) component=usr 2 children>")
        let root = try makeNode(nil)
        XCTAssertEqual(root.description, "<iTermDirectoryTreeNode: \(root.it_addressString) component=(null) 0 children>")
    }

    // MARK: - Lifetime

    // A node holds its children until it goes away, and then releases them.
    func testChildrenAreReleasedWithTheNode() throws {
        weak var weakNode: NSObject?
        weak var weakChild: NSObject?
        try autoreleasepool {
            let node = try makeNode("a")
            let child = try makeNode("b")
            try children(node)["b"] = child
            weakNode = node
            weakChild = child
        }
        XCTAssertNil(weakNode)
        XCTAssertNil(weakChild)
    }
}
