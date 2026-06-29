//
//  iTermBijectionNullabilityTests.swift
//  iTerm2
//
//  Created by George Nachman on 2026-05-05.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermBijectionNullabilityTests: XCTestCase {
    // The lookup methods on iTermBijection return nil for missing keys, so
    // their Swift import must be Optional-returning. If the ObjC header
    // declares them nonnull, Swift imports the inferred return as a
    // non-Optional reference — making any caller that lets the type be
    // inferred (e.g. `let x = bijection.object(forLeft: ...)`) hold a nil
    // pointer in a value the type system claims is non-nil.
    //
    // We assert the imported function type by reflecting on a method
    // reference. This avoids dereferencing the (possibly-nil) result.

    func testObjectForLeftIsImportedAsOptional() {
        let bijection = iTermBijection<NSNumber, NSString>()
        let methodRef = bijection.object(forLeft:)
        let signature = String(describing: type(of: methodRef))
        XCTAssertTrue(signature.contains("Optional"),
                      "object(forLeft:) should be imported with Optional return, got \(signature)")
    }

    func testObjectForRightIsImportedAsOptional() {
        let bijection = iTermBijection<NSNumber, NSString>()
        let methodRef = bijection.object(forRight:)
        let signature = String(describing: type(of: methodRef))
        XCTAssertTrue(signature.contains("Optional"),
                      "object(forRight:) should be imported with Optional return, got \(signature)")
    }

}
