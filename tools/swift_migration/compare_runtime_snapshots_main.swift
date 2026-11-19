//
//  compare_runtime_snapshots_main.swift
//
//  Command-line driver for RuntimeSnapshotComparison.swift, built and run by
//  compare_runtime_snapshots.sh. Not part of any Xcode target.
//

import Foundation

@main
struct CompareRuntimeSnapshots {
    static func main() {
        let (output, error, status) = RuntimeSnapshotComparison.runCommandLine(
            arguments: CommandLine.arguments,
            readFile: { try Data(contentsOf: URL(fileURLWithPath: $0)) })
        print(output, terminator: "")
        FileHandle.standardError.write(Data(error.utf8))
        exit(status)
    }
}
