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

    // A plain sendmsg of one byte plus a descriptor, bypassing the code under test. Returns
    // errno on failure or 0 on success.
    private func rawSendFileDescriptor(socket: Int32, fd: Int32) -> Int32 {
        var payload: UInt8 = 0
        let controlLength = Int(MemoryLayout<cmsghdr>.size + MemoryLayout<Int32>.size)
        var control = [UInt8](repeating: 0, count: controlLength + 8)
        return withUnsafeMutablePointer(to: &payload) { payloadPointer in
            var iov = iovec(iov_base: payloadPointer, iov_len: 1)
            return control.withUnsafeMutableBytes { controlBytes in
                withUnsafeMutablePointer(to: &iov) { iovPointer in
                    var message = msghdr()
                    message.msg_iov = iovPointer
                    message.msg_iovlen = 1
                    message.msg_control = controlBytes.baseAddress
                    message.msg_controllen = socklen_t(controlLength)
                    let header = controlBytes.baseAddress!.assumingMemoryBound(to: cmsghdr.self)
                    header.pointee.cmsg_len = socklen_t(controlLength)
                    header.pointee.cmsg_level = SOL_SOCKET
                    header.pointee.cmsg_type = SCM_RIGHTS
                    let data = controlBytes.baseAddress!.advanced(by: MemoryLayout<cmsghdr>.size)
                    data.storeBytes(of: fd, as: Int32.self)
                    return sendmsg(socket, &message, 0) == -1 ? errno : 0
                }
            }
        }
    }

    private final class Waiter {
        let receiver: Int32
        let filler: Int
        var calls = 0
        var drained = [UInt8]()
        init(receiver: Int32, filler: Int) {
            self.receiver = receiver
            self.filler = filler
        }
    }

    // The premise: on a full socket, a descriptor send fails with EMSGSIZE rather than
    // blocking. If macOS ever starts blocking instead, the fix is unnecessary.
    func testRawDescriptorSendOnFullSocketFailsWithMessageTooLong() {
        _ = fillSocket(sockets[0])
        XCTAssertEqual(rawSendFileDescriptor(socket: sockets[0], fd: pipeFDs[0]), EMSGSIZE)
    }

    // Deterministic: the socket is full when the send starts, so it must ask the waiter for
    // room. The waiter drains the socket on this thread, and the retry must then succeed.
    func testSendingFileDescriptorOnFullSocketWaitsForRoomAndRetries() {
        let sender = sockets[0]
        let receiver = sockets[1]
        let filler = fillSocket(sender)
        XCTAssertGreaterThan(filler, 0)
        XCTAssertEqual(rawSendFileDescriptor(socket: sender, fd: pipeFDs[0]), EMSGSIZE)

        let waiter = Waiter(receiver: receiver, filler: filler)
        var payload: UInt8 = 0x2a
        let result = withExtendedLifetime(waiter) {
            iTermFileDescriptorServerSendMessageAndFileDescriptorWithWaiter(
                sender, &payload, 1, pipeFDs[0],
                { _, context in
                    let waiter = Unmanaged<Waiter>.fromOpaque(context!).takeUnretainedValue()
                    waiter.calls += 1
                    var buffer = [UInt8](repeating: 0, count: waiter.filler)
                    var total = 0
                    while total < waiter.filler {
                        let n = buffer.withUnsafeMutableBytes {
                            read(waiter.receiver, $0.baseAddress! + total, waiter.filler - total)
                        }
                        if n <= 0 {
                            return 0
                        }
                        total += n
                    }
                    waiter.drained.append(contentsOf: buffer[0..<total])
                    return 1
                },
                Unmanaged.passUnretained(waiter).toOpaque())
        }
        let savedErrno = errno

        XCTAssertEqual(waiter.calls, 1, "The send should have waited for room exactly once")
        XCTAssertEqual(waiter.drained.count, filler)
        XCTAssertEqual(result, 1, "send failed: \(String(cString: strerror(savedErrno)))")
        XCTAssertEqual(readExactly(receiver, count: 1), [0x2a])
    }

    // When the waiter reports an error (for example, the client went away), the send fails
    // instead of retrying.
    func testSendFailsWhenWaiterReportsError() {
        let sender = sockets[0]
        _ = fillSocket(sender)
        var payload: UInt8 = 0x2a
        let result = iTermFileDescriptorServerSendMessageAndFileDescriptorWithWaiter(
            sender, &payload, 1, pipeFDs[0], { _, _ in 0 }, nil)
        XCTAssertEqual(result, -1)
        XCTAssertEqual(errno, EMSGSIZE)
    }
}
