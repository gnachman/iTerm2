//
//  UserVariableAssignmentTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/4/26.
//

import XCTest
@testable import iTerm2SharedARC

final class UserVariableAssignmentTests: XCTestCase {
    func testSet() {
        let assignment = UserVariableAssignment(payload: "host_name=Ym94")
        XCTAssertEqual(assignment?.name, "user.host_name")
        XCTAssertEqual(assignment?.value, "box")
    }

    func testUnset() {
        let assignment = UserVariableAssignment(payload: "host_name")
        XCTAssertEqual(assignment?.name, "user.host_name")
        XCTAssertNil(assignment?.value)
    }

    func testValueMayContainEquals() {
        // base64 padding
        let assignment = UserVariableAssignment(payload: "x=MQ==")
        XCTAssertEqual(assignment?.name, "user.x")
        XCTAssertEqual(assignment?.value, "1")
    }

    func testRejectsDottedName() {
        XCTAssertNil(UserVariableAssignment(payload: "a.b=MQ=="))
        XCTAssertNil(UserVariableAssignment(payload: "a.b"))
    }
}
