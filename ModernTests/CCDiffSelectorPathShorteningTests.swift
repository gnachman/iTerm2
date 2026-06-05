//
//  CCDiffSelectorPathShorteningTests.swift
//  iTerm2 ModernTests
//
//  Pins the diff selector's path-shortening behavior. The displayed
//  label for each changed file strips the directory prefix shared by
//  every reported path, so files in a common subtree read as just
//  their tail. The prefix is computed from ALL reported paths, which
//  means the set of files fed to set(fileStatuses:) determines how
//  aggressively labels shorten: with fewer paths the common prefix can
//  only grow, so labels get shorter.
//
//  This matters because the git client now excludes untracked files
//  from fileStatuses (so rename detection doesn't hash them). That
//  removes them as a source of paths here, which lengthens the common
//  prefix and shortens the displayed labels for tracked changes. These
//  tests lock down both the pure prefix math and the end-to-end
//  behavior through set(fileStatuses:), including the fact that the
//  shortening responds to the input path set rather than being filtered
//  inside the selector.
//

import XCTest
@testable import iTerm2SharedARC

final class CCDiffSelectorPathShorteningTests: XCTestCase {

    // MARK: - Pure prefix math

    func testEmptyPathsHaveZeroPrefix() {
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: []), 0)
    }

    func testSingleNestedFileSharesItsWholeDirectory() {
        // One path: the "common" directory prefix is its entire parent
        // directory, so only the filename remains after shortening.
        let paths = ["deeply/nested/src/foo.swift"]
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: paths), 3)
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath(paths[0], prefixLength: 3),
            "foo.swift")
    }

    func testRootLevelFileCollapsesPrefixToZero() {
        // The example from the review: a deep tracked change alongside a
        // root-level file. The root file has no parent directory, so the
        // shared directory prefix is empty and the deep path stays full.
        let paths = ["deeply/nested/src/foo.swift", "README.md"]
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: paths), 0)
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath(paths[0], prefixLength: 0),
            "deeply/nested/src/foo.swift")
    }

    func testFilenamesNeverCountTowardPrefix() {
        // Two files in the same directory: the directory is shared but
        // the differing filenames must not extend the prefix.
        let paths = ["a/b/x.txt", "a/b/y.txt"]
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: paths), 2)
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath("a/b/x.txt", prefixLength: 2),
            "x.txt")
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath("a/b/y.txt", prefixLength: 2),
            "y.txt")
    }

    func testPrefixStopsAtFirstDivergentSegment() {
        let paths = ["a/b/x.txt", "a/c/y.txt"]
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: paths), 1)
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath("a/b/x.txt", prefixLength: 1),
            "b/x.txt")
        XCTAssertEqual(
            CCDiffSelectorItem.shortenedPath("a/c/y.txt", prefixLength: 1),
            "c/y.txt")
    }

    func testDivergentTopLevelDirsLeaveFullPaths() {
        let paths = ["src/a.txt", "test/b.txt"]
        XCTAssertEqual(
            CCDiffSelectorItem.commonDirectoryPrefixLength(forPaths: paths), 0)
    }

    func testFewerPathsCanOnlyLengthenPrefix() {
        // Core property behind the untracked-exclusion change: dropping a
        // path never shortens the prefix and can only lengthen it.
        let withRootFile = CCDiffSelectorItem.commonDirectoryPrefixLength(
            forPaths: ["deeply/nested/foo.swift", "README.md"])
        let withoutRootFile = CCDiffSelectorItem.commonDirectoryPrefixLength(
            forPaths: ["deeply/nested/foo.swift"])
        XCTAssertEqual(withRootFile, 0)
        XCTAssertEqual(withoutRootFile, 2)
        XCTAssertGreaterThanOrEqual(withoutRootFile, withRootFile)
    }

    // MARK: - End to end through set(fileStatuses:)

    func testLoneNestedChangeShortensToBasename() {
        let item = makeItem()
        item.set(fileStatuses: [
            status("deeply/nested/src/foo.swift", workdir: .modified),
        ])
        XCTAssertEqual(item.fileRowDisplayTitles, ["M  foo.swift"])
    }

    func testTwoTrackedChangesShareDeepPrefix() {
        let item = makeItem()
        item.set(fileStatuses: [
            status("src/app/a.swift", workdir: .modified),
            status("src/app/b.swift", workdir: .modified),
        ])
        XCTAssertEqual(Set(item.fileRowDisplayTitles),
                       Set(["M  a.swift", "M  b.swift"]))
    }

    func testMMFileReadsIdenticallyInBothGroups() {
        // A file that is both staged and further modified in the workdir
        // appears under Staged and Unstaged. The shortened path must be
        // identical in both, which is why the prefix is computed from all
        // reported paths rather than per group.
        let item = makeItem()
        item.set(fileStatuses: [
            status("src/app/a.swift", index: .modified, workdir: .modified),
            status("src/app/b.swift", workdir: .modified),
        ])
        let titles = item.fileRowDisplayTitles
        // a.swift shows up once in Staged and once in Unstaged, same text.
        XCTAssertEqual(titles.filter { $0 == "M  a.swift" }.count, 2)
        XCTAssertEqual(titles.filter { $0 == "M  b.swift" }.count, 1)
    }

    func testUntrackedInputIsNotDisplayedButStillNarrowsPrefix() {
        // Two things in one test, both load-bearing for the review point:
        //
        // 1. An untracked entry in the input is never shown as a row (the
        //    selector filters .untracked out of both groups), so even if
        //    upstream regressed and started emitting untracked entries,
        //    they wouldn't appear in the menu.
        //
        // 2. The shortening is driven by the input path SET, not by any
        //    filtering inside the selector: with the root-level untracked
        //    file present the lone tracked change keeps its full path,
        //    and once that file is gone (the real-world effect of the git
        //    client excluding untracked from fileStatuses) the same
        //    change shortens to its basename.
        let item = makeItem()
        item.set(fileStatuses: [
            status("deeply/nested/foo.swift", workdir: .modified),
            status("README.md", workdir: .untracked),
        ])
        XCTAssertEqual(item.fileRowDisplayTitles,
                       ["M  deeply/nested/foo.swift"])

        item.set(fileStatuses: [
            status("deeply/nested/foo.swift", workdir: .modified),
        ])
        XCTAssertEqual(item.fileRowDisplayTitles, ["M  foo.swift"])
    }

    // MARK: - Helpers

    private func makeItem() -> CCDiffSelectorItem {
        let poller = iTermGitPoller(cadence: 2) { }
        return CCDiffSelectorItem(identifier: "test", priority: 0, poller: poller)
    }

    private func status(_ path: String,
                        index: iTermGitFileChangeKind = .none,
                        workdir: iTermGitFileChangeKind = .none) -> iTermGitFileStatus {
        let fs = iTermGitFileStatus()
        fs.path = path
        fs.indexStatus = index
        fs.workdirStatus = workdir
        return fs
    }
}
