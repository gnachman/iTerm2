//
//  iTermGrammarProcessorTests.swift
//  ModernTests
//
//  Characterization tests for iTermGrammarProcessor, which numbers the
//  production rules it is given, joins them into the Backus-Naur form that a
//  CoreParse parser is built from, and runs the transform block registered
//  with a rule on a syntax tree whose rule's tag is that rule's number. The
//  expression parser and the function call suggester each own one.
//
//  CoreParse's classes are compiled into the app but cannot be linked from
//  the test bundle, so the tests make CoreParse rules and syntax trees by
//  class name and set their properties by key. Most tests also send the
//  processor's methods by selector through AnyObject, as Objective-C callers
//  do.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The processor's methods, sent by selector through AnyObject. The Swift
// names differ from the class's own so that the dynamic lookup is not
// ambiguous.
@objc private protocol GrammarProcessorSelectors {
    @objc(addProductionRule:treeTransform:)
    func gpt_addProductionRule(_ bnf: String?, treeTransform: @escaping (AnyObject?) -> AnyObject?)

    @objc(transformSyntaxTree:)
    func gpt_transformSyntaxTree(_ syntaxTree: AnyObject?) -> AnyObject?

    @objc(backusNaurForm)
    var gpt_backusNaurForm: String { get }
}

final class iTermGrammarProcessorTests: XCTestCase {
    private let unitClassName = "iTermGrammarProcessor"

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func newProcessor() -> AnyObject {
        return iTermGrammarProcessor()
    }

    private func add(_ processor: AnyObject,
                     _ bnf: String?,
                     _ transform: @escaping (AnyObject?) -> AnyObject?) {
        processor.gpt_addProductionRule?(bnf, treeTransform: transform)
    }

    private func transform(_ processor: AnyObject, _ syntaxTree: AnyObject?) -> AnyObject? {
        return processor.gpt_transformSyntaxTree?(syntaxTree) ?? nil
    }

    private func form(_ processor: AnyObject) -> String? {
        return processor.gpt_backusNaurForm
    }

    private func newObject(ofClassNamed name: String) throws -> NSObject {
        let cls = try XCTUnwrap(NSClassFromString(name) as? NSObject.Type, name)
        return cls.init()
    }

    // A CoreParse syntax tree whose rule carries the given tag and nothing
    // else.
    private func tree(tag: UInt) throws -> NSObject {
        let rule = try newObject(ofClassNamed: "CPRule")
        rule.setValue(NSNumber(value: tag), forKey: "tag")
        XCTAssertEqual((rule.value(forKey: "tag") as? NSNumber)?.uintValue, tag)
        let tree = try newObject(ofClassNamed: "CPSyntaxTree")
        tree.setValue(rule, forKey: "rule")
        return tree
    }

    // A processor with one rule per name, whose transform returns the name.
    private func processor(returning names: [String]) -> AnyObject {
        let processor = newProcessor()
        for name in names {
            add(processor, "\(name) ::= 'x'") { _ in name as NSString }
        }
        return processor
    }

    // MARK: - The runtime interface

    func testClassIsFoundByItsRuntimeName() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        XCTAssertTrue(cls.superclass() === NSObject.self)
    }

    func testSelectorsAndEncodings() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        XCTAssertEqual(instanceMethodEncoding(cls, "init"), "@16@0:8")
        XCTAssertEqual(instanceMethodEncoding(cls, "addProductionRule:treeTransform:"), "v32@0:8@16@?24")
        XCTAssertEqual(instanceMethodEncoding(cls, "backusNaurForm"), "@16@0:8")
        XCTAssertEqual(instanceMethodEncoding(cls, "transformSyntaxTree:"), "@24@0:8@16")
    }

    func testBackusNaurFormIsReadOnly() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        XCTAssertNil(class_getInstanceMethod(cls, NSSelectorFromString("setBackusNaurForm:")))
        let property = try XCTUnwrap(class_getProperty(cls, "backusNaurForm"))
        let attributes = try XCTUnwrap(property_getAttributes(property))
        XCTAssertTrue(String(cString: attributes).split(separator: ",").contains("R"))
    }

    // MARK: - The Backus-Naur form

    func testNewProcessorHasEmptyForm() {
        XCTAssertEqual(form(newProcessor()), "")
        XCTAssertEqual(iTermGrammarProcessor().backusNaurForm, "")
    }

    func testRulesAreNumberedFromZeroAndJoinedByNewlines() {
        let processor = processor(returning: ["a", "b", "c"])
        XCTAssertEqual(form(processor), "0 a ::= 'x';\n1 b ::= 'x';\n2 c ::= 'x';")
    }

    func testRuleTextIsKeptVerbatim() {
        let processor = newProcessor()
        add(processor, "  héllo ::= <wörld> ';' ") { _ in nil }
        XCTAssertEqual(form(processor), "0   héllo ::= <wörld> ';' ;")
    }

    func testNilRuleIsWrittenAsNull() {
        let processor = newProcessor()
        add(processor, nil) { _ in nil }
        XCTAssertEqual(form(processor), "0 (null);")
    }

    func testNumbersPassTen() throws {
        let names = (0..<12).map { "r\($0)" }
        let lines = try XCTUnwrap(form(processor(returning: names))).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 12)
        XCTAssertEqual(lines[10], "10 r10 ::= 'x';")
        XCTAssertEqual(lines[11], "11 r11 ::= 'x';")
    }

    // MARK: - Transforming syntax trees

    func testTransformRunsTheBlockOfTheRuleWithTheTreesTag() throws {
        let processor = processor(returning: ["a", "b", "c"])
        XCTAssertEqual(transform(processor, try tree(tag: 0)) as? String, "a")
        XCTAssertEqual(transform(processor, try tree(tag: 1)) as? String, "b")
        XCTAssertEqual(transform(processor, try tree(tag: 2)) as? String, "c")
    }

    func testTransformPassesTheTreeToTheBlock() throws {
        let processor = newProcessor()
        var received = [AnyObject?]()
        add(processor, "a ::= 'x'") { tree in
            received.append(tree)
            return "result" as NSString
        }
        let syntaxTree = try tree(tag: 0)
        XCTAssertEqual(transform(processor, syntaxTree) as? String, "result")
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(try XCTUnwrap(received.first) === syntaxTree)
    }

    func testTransformReturnsTheBlocksNil() throws {
        let processor = newProcessor()
        var calls = 0
        add(processor, "a ::= 'x'") { _ in
            calls += 1
            return nil
        }
        XCTAssertNil(transform(processor, try tree(tag: 0)))
        XCTAssertEqual(calls, 1)
    }

    func testTagEqualToTheRuleCountGivesNil() throws {
        let processor = processor(returning: ["a", "b"])
        XCTAssertNil(transform(processor, try tree(tag: 2)))
    }

    func testLargeTagsGiveNil() throws {
        let processor = processor(returning: ["a", "b"])
        XCTAssertNil(transform(processor, try tree(tag: 1000)))
        XCTAssertNil(transform(processor, try tree(tag: UInt(Int.max))))
        XCTAssertNil(transform(processor, try tree(tag: UInt(Int.max) + 1)))
        XCTAssertNil(transform(processor, try tree(tag: UInt.max)))
    }

    func testTransformWithNoRulesGivesNil() throws {
        XCTAssertNil(transform(newProcessor(), try tree(tag: 0)))
    }

    // A nil tree has tag zero, so the first rule's block runs and receives nil.
    func testNilTreeRunsTheFirstBlockWithNil() throws {
        let processor = newProcessor()
        var received = [AnyObject?]()
        add(processor, "a ::= 'x'") { tree in
            received.append(tree)
            return "first" as NSString
        }
        add(processor, "b ::= 'x'") { _ in "second" as NSString }
        XCTAssertEqual(transform(processor, nil) as? String, "first")
        XCTAssertEqual(received.count, 1)
        XCTAssertNil(try XCTUnwrap(received.first))
    }

    func testNilTreeWithNoRulesGivesNil() {
        XCTAssertNil(transform(newProcessor(), nil))
    }

    // A block is kept after the call that registered it returns, and a block
    // registered later does not replace an earlier one.
    func testBlocksAreKeptPerRule() throws {
        let processor = newProcessor()
        for i in 0..<3 {
            let value = NSNumber(value: i * 10)
            add(processor, "r\(i) ::= 'x'") { _ in value }
        }
        XCTAssertEqual(transform(processor, try tree(tag: 2)) as? NSNumber, 20)
        XCTAssertEqual(transform(processor, try tree(tag: 0)) as? NSNumber, 0)
        XCTAssertEqual(transform(processor, try tree(tag: 1)) as? NSNumber, 10)
    }

    // The same answers through NSObject's perform(_:with:).
    func testTransformByPerform() throws {
        let processor = try XCTUnwrap(processor(returning: ["a", "b"]) as? NSObject)
        let result = processor.perform(NSSelectorFromString("transformSyntaxTree:"),
                                       with: try tree(tag: 1))
        XCTAssertEqual(result?.takeUnretainedValue() as? String, "b")
        let form = processor.perform(NSSelectorFromString("backusNaurForm"))
        XCTAssertEqual(form?.takeUnretainedValue() as? String, "0 a ::= 'x';\n1 b ::= 'x';")
    }
}
