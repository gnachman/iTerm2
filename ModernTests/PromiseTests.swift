//
//  PromiseTests.swift
//  iTerm2
//
//  Ported from the legacy iTermPromiseTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class PromiseTests: XCTestCase {
    private let standardError = NSError(domain: "com.iterm2.promise-tests", code: 123, userInfo: nil)

    private func isStandardError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == standardError.domain && nsError.code == standardError.code
    }

    // MARK: - Single handlers

    func testFulfillFollowedByThen() {
        let promise = iTermPromise<NSNumber>({ seal in
            seal.fulfill(123)
        })
        var ranThen = false
        promise.then { value in
            XCTAssertEqual(value, 123)
            ranThen = true
        }
        XCTAssertTrue(ranThen)
    }

    func testRejectFollowedByCatchError() {
        let promise = iTermPromise<NSNumber>({ seal in
            seal.reject(standardError)
        })
        var ranCatch = false
        promise.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            ranCatch = true
        }
        XCTAssertTrue(ranCatch)
    }

    func testThenFollowedByFulfill() {
        var savedSeal: iTermPromiseSeal?
        let promise = iTermPromise<NSNumber>({ seal in
            savedSeal = seal
        })

        var ranThen = false
        promise.then { value in
            XCTAssertEqual(value, 123)
            ranThen = true
        }
        XCTAssertFalse(ranThen)

        savedSeal?.fulfill(123)
        XCTAssertTrue(ranThen)
    }

    func testCatchErrorFollowedByReject() {
        var savedSeal: iTermPromiseSeal?
        let promise = iTermPromise<NSNumber>({ seal in
            savedSeal = seal
        })

        var ranCatch = false
        promise.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            ranCatch = true
        }
        XCTAssertFalse(ranCatch)

        savedSeal?.reject(standardError)
        XCTAssertTrue(ranCatch)
    }

    // MARK: - Chains

    func testFulfillFollowedByChain() {
        let promise1 = iTermPromise<NSNumber>({ seal in
            seal.fulfill(123)
        })
        var count = 0
        let promise2 = promise1.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        let promise3 = promise2.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        let promise4 = promise3.catchError { error in
            XCTFail("Unexpected error \(error)")
        }
        promise4.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        XCTAssertEqual(count, 3)
    }

    func testChainFollowedByFulfill() {
        var savedSeal: iTermPromiseSeal?
        let promise1 = iTermPromise<NSNumber>({ seal in
            savedSeal = seal
        })
        var count = 0
        let promise2 = promise1.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        let promise3 = promise2.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        let promise4 = promise3.catchError { error in
            XCTFail("Unexpected error \(error)")
        }
        promise4.then { value in
            XCTAssertEqual(value, 123)
            count += 1
        }
        XCTAssertEqual(count, 0)

        savedSeal?.fulfill(123)
        XCTAssertEqual(count, 3)
    }

    func testRejectFollowedByChain() {
        let promise1 = iTermPromise<NSNumber>({ seal in
            seal.reject(standardError)
        })
        var count = 0
        let promise2 = promise1.then { value in
            XCTFail("Unexpected value \(value)")
        }
        let promise3 = promise2.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            count += 1
        }
        let promise4 = promise3.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            count += 1
        }
        promise4.then { _ in
            XCTFail("Should not be called")
        }
        XCTAssertEqual(count, 2)
    }

    func testChainFollowedByReject() {
        var savedSeal: iTermPromiseSeal?
        let promise1 = iTermPromise<NSNumber>({ seal in
            savedSeal = seal
        })
        var count = 0
        let promise2 = promise1.then { value in
            XCTFail("Unexpected value \(value)")
        }
        let promise3 = promise2.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            count += 1
        }
        let promise4 = promise3.catchError { error in
            XCTAssertTrue(self.isStandardError(error))
            count += 1
        }
        promise4.then { _ in
            XCTFail("Should not be called")
        }
        XCTAssertEqual(count, 0)

        savedSeal?.reject(standardError)
        XCTAssertEqual(count, 2)
    }
}
