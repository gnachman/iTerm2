//
//  PathSnifferTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class PathSnifferTests: XCTestCase {
    private let screen = VT100Screen()

    private func makeSniffer(queue: DispatchQueue) -> PathSniffer {
        var dataSource: VT100ScreenMutableState!
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            dataSource = mutableState
        })
        return PathSniffer(extractor: iTermTextExtractor(dataSource: dataSource),
                           range: VT100GridCoordRange(),
                           remoteHost: nil,
                           offset: 0,
                           pwd: "/",
                           width: 80,
                           queue: queue)
    }

    // A sniffer keeps itself alive in a process-wide list while stats are pending. Sessions with
    // mutation queues of their own sniff on different queues at once, so the list must be safe to
    // change from all of them.
    func testSniffersOnDifferentQueuesTrackThemselvesSafely() {
        let queues = (0..<8).map { DispatchQueue(label: "test.sniffer.\($0)") }
        let sniffers = queues.map { makeSniffer(queue: $0) }
        DispatchQueue.concurrentPerform(iterations: sniffers.count) { i in
            queues[i].sync {
                for _ in 0..<2000 {
                    sniffers[i].count += 1
                    sniffers[i].count -= 1
                }
            }
        }
        XCTAssertEqual(PathSniffer.pendingCountForTesting, 0)
    }
}
