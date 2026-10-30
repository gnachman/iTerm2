//
//  WorkgroupModelThreadSafetyTests.swift
//  iTerm2
//
//  Triggers read the workgroup model on sessions' mutation queues while the main thread edits it.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupModelThreadSafetyTests: XCTestCase {
    private var saved = [iTermWorkgroup]()

    override func setUp() {
        super.setUp()
        saved = iTermWorkgroupModel.instance.workgroups
    }

    override func tearDown() {
        iTermWorkgroupModel.instance.setAll(saved)
        super.tearDown()
    }

    private func workgroups(count: Int) -> [iTermWorkgroup] {
        return (0..<count).map { i in
            iTermWorkgroup(uniqueIdentifier: "wg\(i)", name: "WG \(i)", sessions: [])
        }
    }

    // Readers on other threads see a whole list, never a list being replaced.
    func testReadingOffMainWhileMainReplacesTheList() {
        let model = iTermWorkgroupModel.instance
        let lists = [workgroups(count: 1), workgroups(count: 7), workgroups(count: 3), []]
        let done = MutableAtomicObject(false)
        let readersFinished = DispatchGroup()
        for _ in 0..<4 {
            readersFinished.enter()
            DispatchQueue.global().async {
                while !done.value {
                    let snapshot = model.workgroups
                    for wg in snapshot {
                        XCTAssertFalse(wg.uniqueIdentifier.isEmpty)
                    }
                    _ = model.workgroup(uniqueIdentifier: "wg2")
                }
                readersFinished.leave()
            }
        }
        for i in 0..<400 {
            model.setAll(lists[i % lists.count])
        }
        done.set(true)
        readersFinished.wait()
    }
}
