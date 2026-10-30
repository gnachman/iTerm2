//
//  AdvancedSettingsThreadSafetyTests.swift
//  iTerm2
//
//  Mutation queues and parser threads read advanced settings while the main thread changes them.
//

import XCTest
@testable import iTerm2SharedARC

final class AdvancedSettingsThreadSafetyTests: XCTestCase {
    // Readers on other threads get a live value, never one that was released by a change.
    func testReadingOffMainWhileMainChangesASetting() {
        let original = iTermAdvancedSettingsModel.searchCommand()!
        defer {
            iTermAdvancedSettingsModel.setSearchCommand(original)
        }
        // Long enough that none of these are tagged pointers, so each one is a separate object.
        let values = (0..<4).map { "https://example.com/\(String(repeating: "x", count: 40 + $0))?q=%@" }
        let done = MutableAtomicObject(false)
        let readersFinished = DispatchGroup()
        for _ in 0..<4 {
            readersFinished.enter()
            DispatchQueue.global().async {
                while !done.value {
                    let value = iTermAdvancedSettingsModel.searchCommand()!
                    XCTAssertTrue(value.hasSuffix("?q=%@"))
                }
                readersFinished.leave()
            }
        }
        for i in 0..<400 {
            iTermAdvancedSettingsModel.setSearchCommand(values[i % values.count])
        }
        done.set(true)
        readersFinished.wait()
    }
}
