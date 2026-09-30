//
//  PythonArgumentParserTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermPythonArgumentParserTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class PythonArgumentParserTests: XCTestCase {

    private func parser(_ args: [String]) -> iTermPythonArgumentParser {
        return iTermPythonArgumentParser(args: args)
    }

    // The script/module/statement properties are declared nonnull in the header but are nil until
    // the parser finds them. A nil NSString bridges to an empty Swift String, which would hide the
    // difference between “absent” and “empty”, so read them through key-value coding, which
    // returns nil faithfully.
    private func script(of parser: iTermPythonArgumentParser) -> String? {
        return parser.value(forKey: "script") as? String
    }

    private func module(of parser: iTermPythonArgumentParser) -> String? {
        return parser.value(forKey: "module") as? String
    }

    private func statement(of parser: iTermPythonArgumentParser) -> String? {
        return parser.value(forKey: "statement") as? String
    }

    func testStatement() {
        let p = parser(["python", "-c", "statement", "script"])
        XCTAssertEqual(statement(of: p), "statement")
        XCTAssertNil(script(of: p))
    }

    func testCompoundStatement() {
        let p = parser(["python", "-cstatement", "script"])
        XCTAssertEqual(statement(of: p), "statement")
        XCTAssertNil(script(of: p))
    }

    func testModule() {
        let p = parser(["python", "-m", "module", "arg"])
        XCTAssertEqual(module(of: p), "module arg")
        XCTAssertNil(script(of: p))
    }

    func testCompoundModule() {
        let p = parser(["python", "-mmodule", "arg"])
        XCTAssertEqual(module(of: p), "module arg")
        XCTAssertNil(script(of: p))
    }

    func testScript() {
        let p = parser(["python", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testIgnoresDivisionControl() {
        let p = parser(["python", "-Q", "old", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testIgnoresCompoundDivisionControl() {
        let p = parser(["python", "-Qold", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testIgnoresWarningControl() {
        let p = parser(["python", "-W", "old", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testIgnoresCompoundWarningControl() {
        let p = parser(["python", "-Wold", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testIgnoresArgv() {
        let p = parser(["python", "-", "argv"])
        XCTAssertNil(script(of: p))
    }

    func testIgnoresUnrecognized() {
        let p = parser(["python", "-B", "script"])
        XCTAssertEqual(script(of: p), "script")
    }

    func testFullPythonPath() {
        let p = parser(["/usr/bin/python3", "script"])
        XCTAssertEqual(p.fullPythonPath, "/usr/bin/python3")
        XCTAssertEqual(p.args, ["script"])
    }

    // MARK: - Header nullability

    // sources/API/iTermPythonArgumentParser.h declares script, module and statement as nonnull
    // (they sit inside NS_ASSUME_NONNULL, since 8ebd2c753) but the implementation leaves them nil
    // unless the matching argument was parsed. Swift trusts the annotation and bridges the nil
    // NSString to “”, so a Swift caller cannot tell “absent” from “empty”. Once the header marks
    // them nullable the `as String?` casts below become real optionals and these assertions pass.
    func testScriptIsNilWhenNoScriptArgumentWasGiven() {
        let p = parser(["python", "-c", "statement"])
        XCTAssertNil(p.value(forKey: "script"))
        XCTExpectFailure("iTermPythonArgumentParser.h declares script nonnull but it is nil when absent, so Swift sees an empty string") {
            XCTAssertNil(p.script as String?)
        }
    }

    func testModuleIsNilWhenNoModuleArgumentWasGiven() {
        let p = parser(["python", "script"])
        XCTAssertNil(p.value(forKey: "module"))
        XCTExpectFailure("iTermPythonArgumentParser.h declares module nonnull but it is nil when absent, so Swift sees an empty string") {
            XCTAssertNil(p.module as String?)
        }
    }

    func testStatementIsNilWhenNoStatementArgumentWasGiven() {
        let p = parser(["python", "script"])
        XCTAssertNil(p.value(forKey: "statement"))
        XCTExpectFailure("iTermPythonArgumentParser.h declares statement nonnull but it is nil when absent, so Swift sees an empty string") {
            XCTAssertNil(p.statement as String?)
        }
    }
}
