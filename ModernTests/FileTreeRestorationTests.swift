import XCTest
@testable import iTerm2SharedARC

final class FileTreeRestorationTests: XCTestCase {
    func testPublishedChildrenRemainAvailableDuringRefreshAndVisibilityReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["file1", "file2"] { try Data().write(to: root.appendingPathComponent(name)) }
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "FileTreeRestorationTests.presentation")
        let state = iTermFileTreeState(source: iTermFileTreeDataSource(ioQueue: queue))
        state.setRoot(root.path)
        state.clearPublishedTree()
        publishDirectory(state, path: root.path)
        let displayed = state.publishedChildren(of: nil)
        XCTAssertEqual(displayed.map(\.name), ["file1", "file2"])

        // AppKit may request the old rows again while a refresh or window zoom resets IO.
        state.source.invalidate(directoryPaths: [root.path])
        XCTAssertNil(state.source.cachedListing(atPath: root.path))
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["file1", "file2"])
        XCTAssertTrue(state.publishedChildren(of: nil).first === displayed.first)
        state.source.reset(rootPath: root.path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["file1", "file2"])

        queue.suspend()
        try FileManager.default.removeItem(at: root.appendingPathComponent("file2"))
        let refreshed = expectation(description: "refreshed directory published")
        state.loadDirectory(atPath: root.path) { result in
            guard case .success(let children) = result else { XCTFail("Refresh failed"); refreshed.fulfill(); return }
            state.publishDirectory(children, atPath: root.path)
            refreshed.fulfill()
        }
        XCTAssertEqual(state.publishedChildren(of: nil).count, displayed.count)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["file1", "file2"])
        queue.resume()
        wait(for: [refreshed], timeout: 5)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["file1"])
    }

    func testPublishedNestedChildrenSurviveParentRefreshUntilNewListingIsPublished() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("child"))
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let state = iTermFileTreeState()
        state.setRoot(root.path)
        state.clearPublishedTree()
        publishDirectory(state, path: root.path)
        let item = try XCTUnwrap(state.publishedChildren(of: nil).first)
        publishDirectory(state, path: folder.path)
        state.source.invalidate(directoryPaths: [root.path, folder.path])
        XCTAssertEqual(state.publishedChildren(of: item).map(\.name), ["child"])
        state.publishDirectory([], atPath: root.path)
        XCTAssertTrue(state.publishedChildren(of: nil).isEmpty)
        XCTAssertTrue(state.publishedChildren(of: item).isEmpty)
    }

    func testRootChangeKeepsPublishedRowsUntilOutlineReloadClearsThem() throws {
        let state = iTermFileTreeState()
        state.setRoot("/tmp/old")
        state.clearPublishedTree()
        let entry = iTermFileTreeEntry(path: "/tmp/old/file", name: "file", isDirectory: false, isExpandable: false)
        state.publishDirectory([entry], atPath: "/tmp/old")
        state.setRoot("/tmp/new")
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.path), ["/tmp/old/file"])
        state.clearPublishedTree()
        XCTAssertTrue(state.publishedChildren(of: nil).isEmpty)
        state.publishDirectory([entry], atPath: "/tmp/old")
        XCTAssertTrue(state.publishedChildren(of: nil).isEmpty)
    }

    private func publishDirectory(_ state: iTermFileTreeState, path: String) {
        let published = expectation(description: "directory published")
        state.loadDirectory(atPath: path) { result in
            guard case .success(let children) = result else { XCTFail("Read failed"); published.fulfill(); return }
            state.publishDirectory(children, atPath: path)
            published.fulfill()
        }
        wait(for: [published], timeout: 5)
    }

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
