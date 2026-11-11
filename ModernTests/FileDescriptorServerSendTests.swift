//
//  FileDescriptorServerSendTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

// macOS fails a blocking sendmsg that carries a file descriptor with EMSGSIZE, instead of
// blocking, when the receiver's buffer is completely full. The multi-server hit this while
// reporting its children during the handshake, so a new app could not attach to a server left
// running by the previous version and every session was lost.
final class FileDescriptorServerSendTests: XCTestCase {
    private var sockets: [Int32] = [-1, -1]
    private var pipeFDs: [Int32] = [-1, -1]

    override func setUp() {
        super.setUp()
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        XCTAssertEqual(pipe(&pipeFDs), 0)
    }

    override func tearDown() {
        for fd in sockets + pipeFDs where fd >= 0 {
            close(fd)
        }
        super.tearDown()
    }

    // Write until the socket refuses even one more byte, then restore blocking mode as the
    // server uses it.
    private func fillSocket(_ fd: Int32) -> Int {
        let flags = fcntl(fd, F_GETFL)
        XCTAssertEqual(fcntl(fd, F_SETFL, flags | O_NONBLOCK), 0)
        var total = 0
        var byte: UInt8 = 0
        while write(fd, &byte, 1) == 1 {
            total += 1
        }
        XCTAssertEqual(errno, EAGAIN)
        XCTAssertEqual(fcntl(fd, F_SETFL, flags), 0)
        return total
    }

    private func readExactly(_ fd: Int32, count: Int) -> [UInt8] {
        var result = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count < count {
            let n = read(fd, &buffer, min(buffer.count, count - result.count))
            if n <= 0 {
                XCTFail("read returned \(n): \(String(cString: strerror(errno)))")
                break
            }
            result.append(contentsOf: buffer[0..<n])
        }
        return result
    }

    func testSendingFileDescriptorOnFullSocketWaitsForRoom() {
        let sender = sockets[0]
        let receiver = sockets[1]
        let filler = fillSocket(sender)
        XCTAssertGreaterThan(filler, 0)

        let sent = expectation(description: "sent")
        let started = DispatchSemaphore(value: 0)
        var result = 0
        var savedErrno: Int32 = 0
        let fdToSend = pipeFDs[0]
        DispatchQueue.global().async {
            var payload: UInt8 = 0x2a
            started.signal()
            result = iTermFileDescriptorServerSendMessageAndFileDescriptor(sender, &payload, 1, fdToSend)
            savedErrno = errno
            sent.fulfill()
        }
        started.wait()

        // Drain the filler, which makes room for the pending send.
        XCTAssertEqual(readExactly(receiver, count: filler).count, filler)
        wait(for: [sent], timeout: 60)

        XCTAssertEqual(result, 1, "send failed: \(String(cString: strerror(savedErrno)))")
        XCTAssertEqual(readExactly(receiver, count: 1), [0x2a])
    }
}
