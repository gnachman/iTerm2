//
//  RuntimeSnapshotTool.swift
//  ModernTests
//
//  The test-host entry point for the runtime snapshot tool. It is not a test:
//  it does nothing (and is skipped) unless tools/swift_migration/runtime_snapshot.sh
//  asks for a snapshot through these environment variables, which xcodebuild
//  forwards to the test host when they are set with a TEST_RUNNER_ prefix:
//
//    ITERM2_RUNTIME_SNAPSHOT_CLASSES  Class names separated by commas or spaces.
//    ITERM2_RUNTIME_SNAPSHOT_OUTPUT   Absolute path of the file to write.
//

import XCTest

final class RuntimeSnapshotTool: XCTestCase {
    func testWriteRequestedSnapshot() throws {
        guard let summary = try RuntimeSnapshotTool.writeRequestedSnapshot(environment: ProcessInfo.processInfo.environment) else {
            throw XCTSkip("Runs only from tools/swift_migration/runtime_snapshot.sh")
        }
        print(summary)
    }

    static let classesVariable = "ITERM2_RUNTIME_SNAPSHOT_CLASSES"
    static let outputVariable = "ITERM2_RUNTIME_SNAPSHOT_OUTPUT"

    // Writes the snapshot the environment asks for and returns a one-line
    // summary, or returns nil if the environment asks for nothing. On failure
    // it throws. A relative output path is refused before anything is
    // touched. For an absolute one, any file already at that path is removed
    // first (and if it cannot be, the run fails), so a run that fails later
    // leaves no file from an earlier run. The snapshot is then written by
    // writeFile to a temporary file in the same directory, which is renamed
    // to the output path only once it is complete, so the output path never
    // holds a partial snapshot. writeFile is a parameter so that tests can
    // make the write fail partway.
    static func writeRequestedSnapshot(environment: [String: String],
                                       writeFile: (Data, URL) throws -> Void = { try $0.write(to: $1) }) throws -> String? {
        guard let classList = environment[classesVariable],
              let outputPath = environment[outputVariable] else {
            return nil
        }
        guard outputPath.hasPrefix("/") else {
            throw SnapshotToolError("\(outputVariable) must be an absolute path, not \(outputPath)")
        }
        do {
            try FileManager.default.removeItem(atPath: outputPath)
        } catch CocoaError.fileNoSuchFile {
            // Nothing to remove.
        }
        let classNames = try RuntimeSnapshot.classNames(fromList: classList)

        let start = Date()
        let text = try RuntimeSnapshot.snapshot(classNames: classNames)
        let elapsed = Date().timeIntervalSince(start)
        try writeAtomically(Data(text.utf8), toPath: outputPath, writeFile: writeFile)
        return String(format: "Runtime snapshot of %d classes took %.3f seconds and wrote %d bytes to %@",
                      classNames.count, elapsed, text.utf8.count, outputPath)
    }

    // Writes data to a temporary file beside path and renames it to path,
    // which replaces any file there in one step. If anything fails, the
    // temporary file is removed and path is left as it was.
    private static func writeAtomically(_ data: Data, toPath path: String, writeFile: (Data, URL) throws -> Void) throws {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).partial")
        do {
            try writeFile(data, temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw SnapshotToolError("Cannot rename \(temporary.path) to \(destination.path): \(String(cString: strerror(errno)))")
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

private struct SnapshotToolError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
