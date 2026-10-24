//
//  RenderingComparerReportTests.swift
//  iTerm2
//
//  -compare-rendering saves three PNGs and reports the comparison. A failed
//  save must be reported as an error with a nonzero exit status rather than
//  as a passing result naming files that do not exist.
//

import XCTest
@testable import iTerm2SharedARC

final class RenderingComparerReportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func solidImage(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func makePaths(in folder: URL) -> iTermRenderingComparer.Paths {
        return iTermRenderingComparer.Paths(legacy: folder.appendingPathComponent("legacy.png").path,
                                            gpu: folder.appendingPathComponent("gpu.png").path,
                                            diff: folder.appendingPathComponent("diff.png").path)
    }

    func testWritableDirectoryPasses() {
        let paths = makePaths(in: directory)
        let report = iTermRenderingComparer.saveAndCompare(legacyImage: solidImage(.red),
                                                           gpuImage: solidImage(.red),
                                                           paths: paths)
        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(report.exitStatus, 0)
        XCTAssertEqual(report.output.last, "RESULT: PASS")
        XCTAssertTrue(report.output.contains("PIXELS_DIFFERENT: 0"))
        for path in [paths.legacy, paths.gpu, paths.diff] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
    }

    func testUnwritableDirectoryIsAnError() {
        // A directory that does not exist can't be written to, like the
        // unwritable working directory in the QA report.
        let paths = makePaths(in: directory.appendingPathComponent("missing"))
        let report = iTermRenderingComparer.saveAndCompare(legacyImage: solidImage(.red),
                                                           gpuImage: solidImage(.red),
                                                           paths: paths)
        XCTAssertEqual(report.errors, [
            "ERROR: Could not save the legacy image to \(paths.legacy)",
            "ERROR: Could not save the GPU image to \(paths.gpu)",
            "ERROR: Could not save the diff image to \(paths.diff)",
        ])
        XCTAssertNotEqual(report.exitStatus, 0)
        XCTAssertFalse(report.output.contains("RESULT: PASS"))
        XCTAssertFalse(report.output.contains { $0.hasPrefix("COMPARE_RENDERING:") })
        XCTAssertEqual(report.output.last, "RESULT: ERROR: could not save the images")
    }

    func testOneUnwritableFileIsAnError() throws {
        let paths = makePaths(in: directory)
        // A directory in the way of the GPU image makes only that save fail.
        try FileManager.default.createDirectory(atPath: paths.gpu, withIntermediateDirectories: true)
        let report = iTermRenderingComparer.saveAndCompare(legacyImage: solidImage(.red),
                                                           gpuImage: solidImage(.red),
                                                           paths: paths)
        XCTAssertEqual(report.errors, ["ERROR: Could not save the GPU image to \(paths.gpu)"])
        XCTAssertNotEqual(report.exitStatus, 0)
        XCTAssertEqual(report.output.last, "RESULT: ERROR: could not save the images")
    }
}
