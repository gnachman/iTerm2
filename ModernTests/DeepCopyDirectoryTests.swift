//
//  DeepCopyDirectoryTests.swift
//  ModernTests
//
//  “Export All Settings and Data” copies ~/.iterm2 and Application Support with
//  FileManager.deepCopyContentsOfDirectory. Those can contain live Unix domain sockets (it2 over
//  SSH puts them in ~/.iterm2/it2), which can't be copied, so copyItem threw and the whole export
//  failed with “Failed to copy file: “….sock” couldn’t be copied”. Sockets, FIFOs, and devices
//  are runtime state, not settings, so the copy skips them.
//

import Darwin
import XCTest
@testable import iTerm2SharedARC

final class DeepCopyDirectoryTests: XCTestCase {
    private var root: URL!
    private var socketFDs = [Int32]()

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Short, because a Unix socket path is limited to about 104 bytes.
        root = URL(fileURLWithPath: "/tmp/dcd-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for fd in socketFDs {
            close(fd)
        }
        socketFDs.removeAll()
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // Creates a listening Unix domain socket at `url`, like it2 over SSH does.
    private func makeSocket(at url: URL) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        socketFDs.append(fd)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = url.path
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        XCTAssertLessThan(path.utf8.count, capacity, "Socket path too long")
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(result, 0, "bind failed: \(String(cString: strerror(errno)))")
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), "Precondition")
    }

    func testCopySkipsSocketsAndCopiesEverythingElse() throws {
        let source = root.appendingPathComponent("src")
        let it2 = source.appendingPathComponent("it2")
        try FileManager.default.createDirectory(at: it2, withIntermediateDirectories: true)
        try Data("settings".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("".utf8).write(to: it2.appendingPathComponent("abc.sock.lock"))
        try makeSocket(at: it2.appendingPathComponent("abc.sock"))
        try makeSocket(at: source.appendingPathComponent("top.sock"))

        let destination = root.appendingPathComponent("dst")
        XCTAssertNoThrow(try FileManager.default.deepCopyContentsOfDirectory(source: source,
                                                                             to: destination,
                                                                             excluding: Set()))

        let fm = FileManager.default
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("a.txt")), "settings")
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("it2/abc.sock.lock").path))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("it2/abc.sock").path))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("top.sock").path))
    }
}
