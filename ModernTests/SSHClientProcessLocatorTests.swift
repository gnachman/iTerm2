//
//  SSHClientProcessLocatorTests.swift
//  iTerm2
//
//  F-786: after a restart, a session that reattached to its job resets its SSH Integration
//  framers only if an it2ssh or ssh client still runs in the job.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeProcessInspector: SSHClientProcessInspecting {
    struct Info {
        var parent: pid_t
        var arguments: [String]?
    }
    var processes = [pid_t: Info]()

    func arguments(of pid: pid_t) -> [String]? {
        return processes[pid]?.arguments
    }

    func childPIDs(of pid: pid_t) -> [pid_t] {
        return processes.filter { $0.value.parent == pid }.map { $0.key }.sorted()
    }
}

final class SSHClientProcessLocatorTests: XCTestCase {
    private let it2sshArgs = ["bash", "/Users/me/.iterm2/it2ssh", "example.com"]

    // A restored session's job still runs ssh only if an ssh client or it2ssh is among its
    // descendants.
    func testFindsSSHClientAmongDescendants() {
        let inspector = FakeProcessInspector()
        // login (100) -> zsh (110) -> it2ssh (120) -> ssh (130)
        inspector.processes[110] = .init(parent: 100, arguments: ["-zsh"])
        inspector.processes[120] = .init(parent: 110, arguments: it2sshArgs)
        inspector.processes[130] = .init(parent: 120, arguments: ["/usr/bin/ssh", "-t", "example.com"])
        let locator = SSHClientProcessLocator(inspector: inspector)
        XCTAssertTrue(locator.hasSSHClient(amongDescendantsOf: 100))

        // ssh died while iTerm2 was down: only the shell is left.
        inspector.processes[120] = nil
        inspector.processes[130] = nil
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 100))

        // Not fooled by something merely named like ssh.
        inspector.processes[140] = .init(parent: 110, arguments: ["/usr/bin/sshd-keygen-wrapper"])
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 100))
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 0))
    }
}
