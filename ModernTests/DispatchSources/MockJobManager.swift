//
//  MockJobManager.swift
//  ModernTests
//
//  Minimal mock implementing iTermJobManager for testing PTYTask code paths
//  that require a job manager (e.g., closeFileDescriptorAndDeregisterIfPossible).
//

import Foundation
@testable import iTerm2SharedARC

/// A minimal mock job manager for dispatch source tests.
///
/// Only `closeFileDescriptor` and the required properties are implemented.
/// All other protocol methods are no-ops or stubs.
final class MockJobManager: NSObject, iTermJobManager {

    // MARK: - Test hooks

    /// Value returned by `closeFileDescriptor`. Defaults to true.
    var closeFileDescriptorReturnValue: Bool = true

    /// Number of times `closeFileDescriptor` was called.
    private(set) var closeFileDescriptorCallCount = 0

    // MARK: - iTermJobManager required properties

    var fd: Int32 = -1
    var tty: String? = nil

    var externallyVisiblePid: pid_t { return 0 }
    var hasJob: Bool { return false }
    var sessionRestorationIdentifier: Any! { return nil }
    var pidToWaitOn: pid_t { return 0 }
    var isSessionRestorationPossible: Bool { return false }
    var ioAllowed: Bool { return true }
    var queue: dispatch_queue_t! { return DispatchQueue.main }
    var isReadOnly: Bool { return false }

    // MARK: - iTermJobManager required class method

    static func available() -> Bool { return true }

    // MARK: - iTermJobManager required initializer

    required init!(queue: dispatch_queue_t!) {
        super.init()
    }

    override init() {
        super.init()
    }

    // MARK: - iTermJobManager required methods

    func forkAndExec(with ttyState: iTermTTYState,
                     argpath: String!,
                     argv: [String]!,
                     initialPwd: String!,
                     newEnviron: [String]!,
                     task: any iTermTask,
                     completion: ((iTermJobManagerForkAndExecStatus, NSNumber?) -> Void)!) {
        // No-op for tests
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: any iTermTask,
                completion: ((iTermJobManagerAttachResults) -> Void)!) {
        // No-op for tests
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: any iTermTask) -> iTermJobManagerAttachResults {
        return []
    }

    func kill(with mode: iTermJobManagerKillingMode) {
        // No-op for tests
    }

    func closeFileDescriptor() -> Bool {
        closeFileDescriptorCallCount += 1
        return closeFileDescriptorReturnValue
    }
}
