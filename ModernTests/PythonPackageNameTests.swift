//
//  PythonPackageNameTests.swift
//  ModernTests
//
//  Regression: the Dependency Editor passed a full requirement (e.g. "aiohttp>=3.14.3")
//  to `pip show`, which wants a bare package name and (under uv, strictly) errors. It now
//  uses -[NSString pythonPackage] to extract the name.
//

import XCTest
@testable import iTerm2SharedARC

final class PythonPackageNameTests: XCTestCase {
    private func name(_ requirement: String) -> String? {
        return (requirement as NSString).pythonPackage()
    }

    func testStripsVersionSpecifiers() {
        XCTAssertEqual(name("aiohttp>=3.14.3"), "aiohttp")
        XCTAssertEqual(name("aiohttp==3.0"), "aiohttp")
        XCTAssertEqual(name("aiohttp<=2"), "aiohttp")
        XCTAssertEqual(name("aiohttp != 1.0"), "aiohttp")
    }

    func testBareNameUnchanged() {
        XCTAssertEqual(name("iterm2"), "iterm2")
        XCTAssertEqual(name("pyobjc-core"), "pyobjc-core")
    }

    func testToleratesWhitespaceAroundOperator() {
        XCTAssertEqual(name("aiohttp >= 3.14.3"), "aiohttp")
    }

    func testDoubleVersionWouldNotRoundtripAsName() {
        // The corrupt form a previous re-pin bug could produce is not a valid
        // requirement, so it does not parse to a name; the fix prevents creating it.
        XCTAssertNil(name("aiohttp>=3.14.3>=3.14.3"))
    }
}
