//
//  iTermVariableScopeGlobalTests.swift
//  ModernTests
//
//  Characterization tests for the category iTermVariableScope (Global):
//  +globalsScope makes a new scope whose unnamed frame is the app's global
//  variables, and four accessors (applicationPID, localhostName,
//  effectiveTheme, appBundlePath) read and write the variables that hold the
//  app's pid, the host name, the theme and the bundle path in whatever scope
//  receives them. The category adopts the protocol iTermGlobalScope. The
//  accessors are exercised on a
//  scope of fresh variables, so the app's global variables are only read.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermVariableScopeGlobalTests: XCTestCase {
    private let accessors = [
        ("applicationPID", "setApplicationPID:", iTermVariableKeyApplicationPID),
        ("localhostName", "setLocalhostName:", iTermVariableKeyApplicationLocalhostName),
        ("effectiveTheme", "setEffectiveTheme:", iTermVariableKeyApplicationEffectiveTheme),
        ("appBundlePath", "setAppBundlePath:", iTermVariableKeyApplicationBundlePath),
    ]

    private func methods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(list) }
        return Dictionary((0..<Int(count)).map {
            (NSStringFromSelector(method_getName(list[$0])),
             method_getTypeEncoding(list[$0]).map { String(cString: $0) } ?? "")
        }, uniquingKeysWith: { first, _ in first })
    }

    private func globalsScope() -> iTermVariableScope? {
        return (iTermVariableScope.self as AnyObject).perform(NSSelectorFromString("globalsScope"))?
            .takeUnretainedValue() as? iTermVariableScope
    }

    private func freshScope() -> iTermVariableScope {
        let scope = iTermVariableScope()
        scope.add(iTermVariables(context: [], owner: iTermVariableScopeGlobalTestsOwner.shared), toScopeNamed: nil)
        return scope
    }

    private func get(_ scope: iTermVariableScope, _ getter: String) -> Any? {
        return scope.perform(NSSelectorFromString(getter))?.takeUnretainedValue()
    }

    private func set(_ scope: iTermVariableScope, _ setter: String, _ value: Any?) {
        _ = scope.perform(NSSelectorFromString(setter), with: value)
    }

    func testSelectorsAndEncodings() {
        let instanceMethods = methods(iTermVariableScope.self)
        for (getter, setter, _) in accessors {
            XCTAssertEqual(instanceMethods[getter], "@16@0:8", getter)
            XCTAssertEqual(instanceMethods[setter], "v24@0:8@16", setter)
        }
        guard let metaclass = object_getClass(iTermVariableScope.self) else {
            XCTFail("no metaclass")
            return
        }
        XCTAssertEqual(methods(metaclass)["globalsScope"], "@16@0:8")
    }

    func testAdoptsTheGlobalScopeProtocol() {
        guard let proto = NSProtocolFromString("iTermGlobalScope") else {
            XCTFail("no protocol")
            return
        }
        XCTAssertTrue(class_conformsToProtocol(iTermVariableScope.self, proto))
        XCTAssertTrue(iTermVariableScope.conforms(to: proto))
        XCTAssertTrue(iTermVariableScope().conforms(to: proto))
        XCTAssertTrue(protocol_conformsToProtocol(proto, NSObjectProtocol.self))
        for (getter, setter, _) in accessors {
            for name in [getter, setter] {
                let description = protocol_getMethodDescription(proto, NSSelectorFromString(name), true, true)
                XCTAssertNotNil(description.name, name)
            }
        }
    }

    func testGlobalsScopeIsANewScopeOverTheGlobalVariables() {
        guard let first = globalsScope(), let second = globalsScope() else {
            XCTFail("no scope")
            return
        }
        XCTAssertTrue(type(of: first) == iTermVariableScope.self)
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.frames.count, 1)
        XCTAssertNil(first.frames.first?.firstObject)
        XCTAssertTrue(first.frames.first?.secondObject === iTermVariables.globalInstance())
        let unnamed = first.variables(inScopeNamed: nil)
        XCTAssertEqual(unnamed.count, 1)
        XCTAssertTrue(unnamed.first === iTermVariables.globalInstance())
    }

    func testGlobalsScopeReadsTheAppsPID() {
        guard let scope = globalsScope() else {
            XCTFail("no scope")
            return
        }
        XCTAssertEqual((get(scope, "applicationPID") as? NSNumber)?.int32Value, getpid())
        XCTAssertEqual(get(scope, "applicationPID") as? NSNumber,
                       scope.value(forVariableName: iTermVariableKeyApplicationPID) as? NSNumber)
    }

    func testGettersReadTheirVariables() {
        let scope = freshScope()
        for (getter, _, key) in accessors {
            XCTAssertNil(get(scope, getter), getter)
            let value: NSObject = getter == "applicationPID" ? NSNumber(value: 1234) : "value of \(getter)" as NSString
            scope.setValue(value, forVariableNamed: key)
            XCTAssertEqual(get(scope, getter) as? NSObject, value, getter)
        }
    }

    func testSettersWriteTheirVariables() {
        let scope = freshScope()
        for (getter, setter, key) in accessors {
            let value: NSObject = getter == "applicationPID" ? NSNumber(value: 99) : "set \(getter)" as NSString
            set(scope, setter, value)
            XCTAssertEqual(scope.value(forVariableName: key) as? NSObject, value, setter)
            XCTAssertEqual(get(scope, getter) as? NSObject, value, setter)
        }
        // Setting nil unsets the variable.
        for (getter, setter, key) in accessors {
            set(scope, setter, nil)
            XCTAssertNil(scope.value(forVariableName: key), setter)
            XCTAssertNil(get(scope, getter), getter)
        }
    }
}

// The owner of the variables the tests make.
private final class iTermVariableScopeGlobalTestsOwner: NSObject, iTermObject {
    static let shared = iTermVariableScopeGlobalTestsOwner()

    func objectMethodRegistry() -> iTermBuiltInFunctions? {
        return nil
    }

    func objectScope() -> iTermVariableScope? {
        return nil
    }
}
