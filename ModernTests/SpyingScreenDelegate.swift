//
//  SpyingScreenDelegate.swift
//  iTerm2
//
//  Created for testing working directory flow.
//

import Foundation
@testable import iTerm2SharedARC

/// Records calls to VT100ScreenDelegate methods for test verification
class SpyingScreenDelegate: FakeSession {
    // Call records
    struct GetWorkingDirectoryCall {}
    struct PollLocalDirectoryOnlyCall {}
    struct LogWorkingDirectoryCall {
        let path: String?
        let line: Int64
    }
    struct CurrentDirectoryDidChangeCall {
        let path: String
    }

    // MARK: - Configurable Return Values

    /// Value to return from screenGetWorkingDirectory polling.
    /// Set this to test scenarios where the poller returns an actual directory.
    var polledWorkingDirectory: String?

    // MARK: - Call Records

    private(set) var getWorkingDirectoryCalls: [GetWorkingDirectoryCall] = []
    private(set) var pollLocalDirectoryOnlyCalls: [PollLocalDirectoryOnlyCall] = []
    private(set) var logWorkingDirectoryCalls: [LogWorkingDirectoryCall] = []
    private(set) var currentDirectoryDidChangeCalls: [CurrentDirectoryDidChangeCall] = []

    func reset() {
        getWorkingDirectoryCalls.removeAll()
        pollLocalDirectoryOnlyCalls.removeAll()
        logWorkingDirectoryCalls.removeAll()
        currentDirectoryDidChangeCalls.removeAll()
    }

    // MARK: - Overrides

    override func screenGetWorkingDirectory(completion: @escaping (String?) -> Void) {
        getWorkingDirectoryCalls.append(GetWorkingDirectoryCall())
        completion(polledWorkingDirectory)
    }

    override func screenPollLocalDirectoryOnly() {
        pollLocalDirectoryOnlyCalls.append(PollLocalDirectoryOnlyCall())
    }

    override func screenLogWorkingDirectory(onAbsoluteLine line: Int64,
                                            remoteHost: (any VT100RemoteHostReading)?,
                                            withDirectory directory: String?,
                                            pushType: VT100ScreenWorkingDirectoryPushType,
                                            accepted: Bool) {
        logWorkingDirectoryCalls.append(LogWorkingDirectoryCall(path: directory, line: line))
    }

    override func screenCurrentDirectoryDidChange(to newPath: String?, remoteHost: (any VT100RemoteHostReading)?) {
        if let path = newPath {
            currentDirectoryDidChangeCalls.append(CurrentDirectoryDidChangeCall(path: path))
        }
    }
}
