import XCTest
@testable import iTerm2SharedARC

final class FileTreeRestorationTests: XCTestCase {
    func testReturningToRecentRootReusesCompletedListingsAndEntryIdentity() throws {
        let roots = try makeRoots(names: ["a", "b"])
        let folder = roots[0].appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("nested"))
        let state = iTermFileTreeState()
        state.setRoot(roots[0].path)
        state.clearPublishedTree()
        publishDirectory(state, path: roots[0].path)
        let originalFolder = try XCTUnwrap(state.publishedChildren(of: nil).first { $0.name == "folder" })
        publishDirectory(state, path: folder.path)
        let originalNested = try XCTUnwrap(state.publishedChildren(of: originalFolder).first)
        state.expandedPaths = [folder.path]
        state.setRoot(roots[1].path)
        state.clearPublishedTree()
        publishDirectory(state, path: roots[1].path)
        state.setRoot(roots[0].path)

        let restoredRoot = try XCTUnwrap(try state.source.cachedListing(atPath: roots[0].path)?.get())
        let restoredFolder = try XCTUnwrap(restoredRoot.first { $0.name == "folder" })
        XCTAssertTrue(restoredFolder === originalFolder)
        XCTAssertTrue(try state.source.cachedListing(atPath: folder.path)?.get().first === originalNested)
        XCTAssertEqual(state.expandedPaths, [folder.path])
        let canonicalEntries = state.preparePublishedTreeFromCache()
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["folder", "a-file"])
        XCTAssertEqual(state.publishedChildren(of: originalFolder).map(\.name), ["nested"])
        XCTAssertTrue(canonicalEntries[folder.path] === originalFolder)
        XCTAssertTrue(canonicalEntries[originalNested.path] === originalNested)
        XCTAssertTrue(state.directoriesNeedingLoad().isEmpty)
    }

    func testRecentRootCacheEvictsOldestAndKeepsRecentlyRevisitedRoot() throws {
        let roots = try makeRoots(names: ["a", "b", "c", "d", "e", "f"])
        let state = iTermFileTreeState()
        for root in roots.prefix(4) {
            state.setRoot(root.path)
            state.clearPublishedTree()
            publishDirectory(state, path: root.path)
        }
        state.setRoot(roots[0].path)
        let reusedA = try XCTUnwrap(try state.source.cachedListing(atPath: roots[0].path)?.get().first)
        for root in roots.suffix(2) {
            state.setRoot(root.path)
            state.clearPublishedTree()
            publishDirectory(state, path: root.path)
        }
        // Revisiting A before leaving E/F makes B the oldest of the four retained snapshots.
        state.setRoot(roots[0].path)
        XCTAssertTrue(try state.source.cachedListing(atPath: roots[0].path)?.get().first === reusedA)
        state.setRoot(roots[1].path)
        XCTAssertNil(state.source.cachedListing(atPath: roots[1].path))
        XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
        publishDirectory(state, path: roots[1].path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["b-file"])
    }

    func testOversizedRootIsNotArchivedButBoundarySizedRootIsReusable() throws {
        let state = iTermFileTreeState()
        for size in [20_000, 20_001] {
            let root = "/tmp/file-tree-sized-\(size)"
            state.setRoot(root)
            let entries = (0..<size).map {
                iTermFileTreeEntry(path: root + "/file\($0)", name: "file\($0)",
                                   isDirectory: false, isExpandable: false)
            }
            state.source.restoreCachedListings([root: .success(entries)])
            state.setRoot("/tmp/file-tree-other")
            state.setRoot(root)
            if size == 20_000 {
                let retained = try XCTUnwrap(try state.source.cachedListing(atPath: root)?.get())
                XCTAssertTrue(retained.first === entries.first)
                XCTAssertTrue(retained.last === entries.last)
                XCTAssertTrue(state.preparePublishedTreeFromCache()[root + "/file19999"] === entries.last)
            } else {
                XCTAssertTrue(state.source.cachedListing(atPath: root) == nil)
                XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
            }
        }
    }

    func testCancellationKeepsCompletedRowsAndRejectsAlreadyFinishedObsoleteRead() throws {
        let roots = try makeRoots(names: ["a"])
        let root = roots[0]
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("old"))
        let queue = DispatchQueue(label: "FileTreeRestorationTests.cancel-finished")
        let state = iTermFileTreeState(source: iTermFileTreeDataSource(ioQueue: queue))
        state.setRoot(root.path)
        state.clearPublishedTree()
        publishDirectory(state, path: root.path)
        let item = try XCTUnwrap(state.publishedChildren(of: nil).first { $0.name == "folder" })
        var obsoleteCompletionRan = false
        state.loadDirectory(atPath: folder.path) { _ in obsoleteCompletionRan = true }
        // The old IO is done, but its main-thread delivery is still queued.
        queue.sync {}
        let generation = state.source.generation
        state.source.cancelPendingRequests()
        state.loadingPaths.removeAll() // The view clears this when hiding.
        XCTAssertGreaterThan(state.source.generation, generation)
        XCTAssertTrue(try state.source.cachedListing(atPath: root.path)?.get().first === item)
        XCTAssertTrue(state.preparePublishedTreeFromCache()[folder.path] === item)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("old"))
        try Data().write(to: folder.appendingPathComponent("new"))
        publishDirectory(state, path: folder.path)
        XCTAssertFalse(obsoleteCompletionRan)
        XCTAssertEqual(state.publishedChildren(of: item).map(\.name), ["new"])
        XCTAssertEqual(try state.source.cachedListing(atPath: folder.path)?.get().map(\.name), ["new"])
    }

    func testRootSwitchRejectsObsoleteReadEvenWhenReturningToOriginalRoot() throws {
        let roots = try makeRoots(names: ["a", "b"])
        let folder = roots[0].appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("old"))
        let queue = DispatchQueue(label: "FileTreeRestorationTests.cancel-root-switch")
        let state = iTermFileTreeState(source: iTermFileTreeDataSource(ioQueue: queue))
        state.setRoot(roots[0].path)
        state.clearPublishedTree()
        publishDirectory(state, path: roots[0].path)
        var obsoleteCompletionRan = false
        state.loadDirectory(atPath: folder.path) { _ in obsoleteCompletionRan = true }
        queue.sync {}
        state.setRoot(roots[1].path)
        state.setRoot(roots[0].path)
        let canonical = state.preparePublishedTreeFromCache()
        let item = try XCTUnwrap(canonical[folder.path])
        try FileManager.default.removeItem(at: folder.appendingPathComponent("old"))
        try Data().write(to: folder.appendingPathComponent("current"))
        publishDirectory(state, path: folder.path)
        XCTAssertFalse(obsoleteCompletionRan)
        XCTAssertEqual(state.publishedChildren(of: item).map(\.name), ["current"])
        XCTAssertEqual(try state.source.cachedListing(atPath: folder.path)?.get().map(\.name), ["current"])
    }

    func testHiddenModeAndRestorationCannotResurrectUnfilteredRootCache() throws {
        let roots = try makeRoots(names: ["a", "b"])
        try Data().write(to: roots[0].appendingPathComponent(".hidden"))
        let state = iTermFileTreeState()
        state.setRoot(roots[0].path)
        state.source.showsHiddenFiles = true
        state.clearPublishedTree()
        publishDirectory(state, path: roots[0].path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), [".hidden", "a-file"])
        state.setRoot(roots[1].path)
        state.source.showsHiddenFiles = false
        state.setRoot(roots[0].path)
        XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
        publishDirectory(state, path: roots[0].path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), ["a-file"])
        state.setRoot(roots[1].path)
        state.source.showsHiddenFiles = true
        state.setRoot(roots[0].path)
        XCTAssertNil(state.source.cachedListing(atPath: roots[0].path))
        XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
        publishDirectory(state, path: roots[0].path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), [".hidden", "a-file"])
        state.setRoot(roots[1].path)
        state.restore(from: ["ProjectFileTreeRoot": roots[1].path, "ProjectFileTreeShowHidden": true])
        state.setRoot(roots[0].path)
        XCTAssertNil(state.source.cachedListing(atPath: roots[0].path))
        XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
        publishDirectory(state, path: roots[0].path)
        XCTAssertEqual(state.publishedChildren(of: nil).map(\.name), [".hidden", "a-file"])
    }

    func testInvalidatedParentAndSymlinkSubtreesAreNotRestored() throws {
        let roots = try makeRoots(names: ["a", "b"])
        let folder = roots[0].appendingPathComponent("folder")
        let link = roots[0].appendingPathComponent("link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("child"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let state = iTermFileTreeState()
        state.setRoot(roots[0].path)
        state.clearPublishedTree()
        publishDirectory(state, path: roots[0].path)
        publishDirectory(state, path: folder.path)
        let snapshot = state.source.cachedListings
        let linkedEntry = try XCTUnwrap(state.publishedChildren(of: nil).first { $0.name == "link" })
        XCTAssertFalse(linkedEntry.isExpandable)
        var withOrphan = snapshot
        withOrphan[link.path] = .success([iTermFileTreeEntry(path: link.path + "/child", name: "child",
                                                           isDirectory: false, isExpandable: false)])
        state.source.reset(rootPath: roots[0].path)
        state.source.restoreCachedListings(withOrphan)
        XCTAssertNil(state.source.cachedListing(atPath: link.path))
        XCTAssertEqual(state.preparePublishedTreeFromCache()[folder.path + "/child"]?.name, "child")
        state.source.invalidate(directoryPaths: [roots[0].path])
        state.setRoot(roots[1].path)
        state.setRoot(roots[0].path)
        XCTAssertTrue(state.preparePublishedTreeFromCache().isEmpty)
        XCTAssertNil(state.source.cachedListing(atPath: folder.path))
    }

    private func makeRoots(names: [String]) throws -> [URL] {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = names.map { parent.appendingPathComponent($0) }
        for (name, root) in zip(names, roots) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent(name + "-file"))
        }
        addTeardownBlock { try FileManager.default.removeItem(at: parent) }
        return roots
    }

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
