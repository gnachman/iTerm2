//
//  MockCoprocess.swift
//  ModernTests
//
//  Mock implementation of Coprocess for testing TaskNotifier coprocess handling.
//  Subclass of Coprocess that uses pipes instead of spawning a subprocess.
//

import Foundation
@testable import iTerm2SharedARC

class MockCoprocess: Coprocess {

    /// The external write FD - test code writes here to simulate coprocess output.
    /// This is the write end of the read pipe (TaskNotifier reads from inputFd/readFileDescriptor).
    private(set) var testWriteFd: Int32 = -1

    /// The external read FD - test code reads here to see data written to coprocess.
    /// This is the read end of the write pipe (TaskNotifier writes to outputFd/writeFileDescriptor).
    private(set) var testReadFd: Int32 = -1

    /// Create a MockCoprocess with pipe FDs.
    /// Returns nil on failure (pipe creation failed).
    @objc static func createPipe() -> MockCoprocess? {
        var readPipe: [Int32] = [0, 0]
        var writePipe: [Int32] = [0, 0]

        guard pipe(&readPipe) == 0 else { return nil }
        guard pipe(&writePipe) == 0 else {
            close(readPipe[0])
            close(readPipe[1])
            return nil
        }

        // Set non-blocking on inputFd
        var flags = fcntl(readPipe[0], F_GETFL)
        fcntl(readPipe[0], F_SETFL, flags | O_NONBLOCK)

        // Set non-blocking on outputFd
        flags = fcntl(writePipe[1], F_GETFL)
        fcntl(writePipe[1], F_SETFL, flags | O_NONBLOCK)

        let coprocess = MockCoprocess()
        coprocess.inputFd = readPipe[0]
        coprocess.outputFd = writePipe[1]
        coprocess.pid = getpid()
        coprocess.testWriteFd = readPipe[1]
        coprocess.testReadFd = writePipe[0]

        return coprocess
    }

    deinit {
        closeTestFds()
    }

    // Override to NOT send kill signal - MockCoprocess uses getpid() as pid
    // and we don't want to kill the test process!
    override func terminate() {
        if outputFd >= 0 {
            close(outputFd)
            outputFd = -1
        }
        if inputFd >= 0 {
            close(inputFd)
            inputFd = -1
        }
        pid = -1
    }

    /// Close the test FDs (call in addition to terminate to clean up test resources).
    @objc func closeTestFds() {
        if testWriteFd >= 0 {
            close(testWriteFd)
            testWriteFd = -1
        }
        if testReadFd >= 0 {
            close(testReadFd)
            testReadFd = -1
        }
    }
}
