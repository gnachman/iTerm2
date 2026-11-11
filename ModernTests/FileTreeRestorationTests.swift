import XCTest
@testable import iTerm2SharedARC

final class FileTreeRestorationTests: XCTestCase {
    func testMatchingRootRestoreReloadsNestedExpansionAndRoundTripsAfterCancellation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("folder")
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent(".hidden"))
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "FileTreeRestorationTests.IO")
        let state = iTermFileTreeState(source: iTermFileTreeDataSource(ioQueue: queue))
        state.setRoot(root.path)
        queue.suspend()
        var obsoleteCompletionRan = false
        state.loadDirectory(atPath: root.path) { _ in obsoleteCompletionRan = true }
        XCTAssertTrue(state.loadingPaths.contains(root.path))
        let saved: [AnyHashable: Any] = [
            "ProjectFileTreeRoot": root.path,
            "ProjectFileTreeExpandedPaths": [root.path: [folder.path, nested.path]],
            "ProjectFileTreeShowHidden": true
        ]
        state.restore(from: saved)
        XCTAssertEqual(state.rootDirectory, root.path)
        XCTAssertEqual(state.expandedPaths, [folder.path, nested.path])
        XCTAssertTrue(state.loadingPaths.isEmpty)
        queue.resume()
        reloadRememberedDirectories(state)
        let drained = expectation(description: "obsolete IO drained")
        queue.async { DispatchQueue.main.async { drained.fulfill() } }
        wait(for: [drained], timeout: 5)
        XCTAssertFalse(obsoleteCompletionRan)
        XCTAssertEqual(Set(state.source.loadedDirectoryPaths), [root.path, folder.path, nested.path])
        if case .success(let entries)? = state.source.cachedListing(atPath: nested.path) {
            XCTAssertEqual(entries.map(\.name), [".hidden"])
        } else { XCTFail("Nested directory was not reloaded") }
        let roundTrip = state.restorableState()
        let paths = roundTrip["ProjectFileTreeExpandedPaths"] as? [String: [String]]
        XCTAssertEqual(Set(paths?[root.path] ?? []), [folder.path, nested.path])
        let restoredAgain = iTermFileTreeState()
        restoredAgain.setRoot(root.path)
        restoredAgain.restore(from: roundTrip)
        reloadRememberedDirectories(restoredAgain)
        XCTAssertEqual(restoredAgain.expandedPaths, state.expandedPaths)
        XCTAssertEqual(Set(restoredAgain.source.loadedDirectoryPaths), [root.path, folder.path, nested.path])
    }

    func testSavedRootCompatibilityAndSelectedRootOverrideKeepRememberedExpansions() {
        let state = iTermFileTreeState()
        state.setRoot("/tmp/current")
        state.restore(from: [
            "ProjectFileTreeRoot": "/tmp/saved",
            "ProjectFileTreeExpandedPaths": ["/tmp/current": ["/tmp/current/folder"],
                                              "/tmp/saved": ["/tmp/saved/nested"]]
        ])
        XCTAssertEqual(state.rootDirectory, "/tmp/saved")
        XCTAssertEqual(state.expandedPaths, ["/tmp/saved/nested"])
        // The window's selected project remains authoritative after Toolbelt restoration.
        state.setRoot("/tmp/current")
        XCTAssertEqual(state.expandedPaths, ["/tmp/current/folder"])
        state.restore(from: ["ProjectFileTreeExpandedPaths": ["/tmp/current": ["/tmp/current/restored"]]])
        XCTAssertEqual(state.rootDirectory, "/tmp/current")
        XCTAssertEqual(state.expandedPaths, ["/tmp/current/restored"])
    }

    private func reloadRememberedDirectories(_ state: iTermFileTreeState) {
        let loaded = expectation(description: "remembered directories reloaded")
        func step() {
            guard let path = state.directoriesNeedingLoad().first else { loaded.fulfill(); return }
            state.loadDirectory(atPath: path) { result in
                if case .failure(let error) = result { XCTFail("Unexpected read error: \(error)") }
                step()
            }
        }
        step()
        wait(for: [loaded], timeout: 5)
    }
}
