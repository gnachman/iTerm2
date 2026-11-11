import XCTest
@testable import iTerm2SharedARC

final class ProjectSidebarTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCatalogCanonicalIdentityAndRemovalKeepsDirectory() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let catalog = iTermProjectCatalog(defaults: defaults)
        let alias = root.appendingPathComponent("alias")
        let folder = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let done = expectation(description: "added twice")
        catalog.addDirectory(atPath: folder.path) { first, error in
            XCTAssertNil(error)
            catalog.addDirectory(atPath: alias.path) { second, error in
                XCTAssertNil(error)
                XCTAssertEqual(first?.identifier, second?.identifier)
                XCTAssertEqual(catalog.projects.count, 1)
                if let first { catalog.removeProject(withIdentifier: first.identifier) }
                XCTAssertTrue(catalog.projects.isEmpty)
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testCatalogRejectsFileAndRelativeRoot() throws {
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        let catalog = iTermProjectCatalog(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let done = expectation(description: "rejections")
        done.expectedFulfillmentCount = 2
        for path in [file.path, "relative"] {
            catalog.addDirectory(atPath: path) { project, error in
                XCTAssertNil(project)
                XCTAssertNotNil(error)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(catalog.projects.isEmpty)
    }

    func testListingIsLazyNaturalSortedAndTreatsPackagesAndSymlinksAsLeaves() throws {
        for name in ["folder2", "folder10", "Bundle.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for name in ["file10", "file2", ".hidden"] { try Data().write(to: root.appendingPathComponent(name)) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("folder2"))
        let source = iTermFileTreeDataSource()
        source.reset(rootPath: root.path)
        XCTAssertTrue(source.loadedDirectoryPaths.isEmpty)
        let done = expectation(description: "listed")
        source.loadDirectory(atPath: root.path) { result in
            guard case .success(let entries) = result else { XCTFail("listing failed"); done.fulfill(); return }
            XCTAssertEqual(entries.filter(\.isExpandable).map(\.name), ["folder2", "folder10"])
            XCTAssertEqual(entries.filter { $0.name.hasPrefix("file") }.map(\.name), ["file2", "file10"])
            XCTAssertFalse(entries.contains { $0.name == ".hidden" })
            XCTAssertFalse(entries.first { $0.name == "link" }!.isExpandable)
            XCTAssertFalse(entries.first { $0.name == "Bundle.app" }!.isExpandable)
            XCTAssertEqual(source.loadedDirectoryPaths, [self.root.path])
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testHiddenToggleAndErrorAreDifferentFromEmptyDirectory() throws {
        try Data().write(to: root.appendingPathComponent(".hidden"))
        let source = iTermFileTreeDataSource()
        source.reset(rootPath: root.path)
        source.showsHiddenFiles = true
        let done = expectation(description: "hidden and missing")
        done.expectedFulfillmentCount = 3
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        source.loadDirectory(atPath: empty.path) { result in
            XCTAssertEqual(try? result.get().count, 0)
            done.fulfill()
        }
        source.loadDirectory(atPath: root.path) { result in
            XCTAssertEqual(try? result.get().map(\.name), ["empty", ".hidden"])
            done.fulfill()
        }
        source.loadDirectory(atPath: root.appendingPathComponent("missing").path) { result in
            if case .success = result { XCTFail("missing directory reported empty") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testConcurrentRequestsShareOneListing() throws {
        try Data().write(to: root.appendingPathComponent("file"))
        let queue = DispatchQueue(label: "ProjectSidebarTests.coalescing")
        queue.suspend()
        let source = iTermFileTreeDataSource(ioQueue: queue)
        source.reset(rootPath: root.path)
        var first: iTermFileTreeEntry?
        let done = expectation(description: "coalesced results")
        done.expectedFulfillmentCount = 2
        source.loadDirectory(atPath: root.path) { result in
            first = try? result.get().first
            done.fulfill()
        }
        source.loadDirectory(atPath: root.path) { result in
            XCTAssertTrue(first === (try? result.get().first))
            done.fulfill()
        }
        queue.resume()
        wait(for: [done], timeout: 5)
    }

    func testResetDiscardsOldReadAndCoalescesPendingLoads() throws {
        let queue = DispatchQueue(label: "ProjectSidebarTests.io")
        queue.suspend()
        let source = iTermFileTreeDataSource(ioQueue: queue)
        source.reset(rootPath: root.path)
        let cancelled = expectation(description: "old request cancelled")
        cancelled.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            source.loadDirectory(atPath: root.path) { result in
                guard case .failure(let error) = result else { XCTFail("stale result accepted"); cancelled.fulfill(); return }
                XCTAssertEqual((error as NSError).code, NSUserCancelledError)
                cancelled.fulfill()
            }
        }
        source.reset(rootPath: nil)
        let drained = expectation(description: "old IO result delivered and discarded")
        queue.async { DispatchQueue.main.async { drained.fulfill() } }
        queue.resume()
        wait(for: [cancelled, drained], timeout: 5)
        XCTAssertTrue(source.loadedDirectoryPaths.isEmpty)
    }
}
