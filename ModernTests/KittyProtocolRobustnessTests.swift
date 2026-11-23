//
//  KittyProtocolRobustnessTests.swift
//  iTerm2
//
//  Kitty graphics protocol commands whose keys or payloads a program controls: delete commands
//  with huge coordinates, truncated and oversized zlib payloads, chunked transmissions that never
//  stop growing, and files, temporary files and shared memory that are too large or are not
//  regular files.
//

import XCTest
import AppKit
import zlib
@testable import iTerm2SharedARC

final class KittyProtocolRobustnessTests: XCTestCase {
    // A 64x64 red square encoded as PNG.
    private let redPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeUlEQVR4nO3PQQkAMAzAwAqrfxUTMxF7HINABFzm7H7dcEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFj108cEE8uoIF1wAAAABJRU5ErkJggg=="

    private final class RecordingDelegate: NSObject, KittyImageControllerDelegate {
        var reports = [String]()
        func kittyImageControllerReport(message: String) {
            reports.append(message)
        }
        func kittyImageControllerPlacementsDidChange() {}
        func kittyImageControllerCursorCoord() -> VT100GridAbsCoord {
            return VT100GridAbsCoord(x: 0, y: 0)
        }
        func kittyImageControllerMoveCursor(dx: Int, dy: Int) {}
        func kittyImageControllerCellSize() -> NSSize {
            return NSSize(width: 10, height: 20)
        }
        func kittyImageControllerScreenAbsLine() -> Int64 {
            return 0
        }
    }

    private var delegates = [RecordingDelegate]()

    /// The cache budget used by the size-cap tests. Production uses 320 MB.
    private let smallBudget = 64 * 1024

    private func makeController(budget: Int? = nil) -> (KittyImageController, RecordingDelegate) {
        let delegate = RecordingDelegate()
        delegates.append(delegate)
        let controller = budget.map { KittyImageController(imageCacheBudget: $0) } ?? KittyImageController()
        controller.delegate = delegate
        return (controller, delegate)
    }

    private func run(_ controller: KittyImageController, _ apc: String) {
        controller.execute(command: KittyImageCommand(apc)!)
    }

    private func zlibCompressed(_ data: Data) -> Data {
        var destinationLength = compressBound(uLong(data.count))
        var destination = Data(count: Int(destinationLength))
        let status = destination.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int32 in
            data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int32 in
                compress2(out.bindMemory(to: Bytef.self).baseAddress,
                          &destinationLength,
                          input.bindMemory(to: Bytef.self).baseAddress,
                          uLong(data.count),
                          Z_BEST_COMPRESSION)
            }
        }
        XCTAssertEqual(status, Z_OK)
        destination.count = Int(destinationLength)
        return destination
    }

    private func base64(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
    }

    // MARK: - Delete commands

    /// Displays the PNG as a single cell at the top-left of the screen.
    private func controllerWithOneCellPlacement() -> KittyImageController {
        let (controller, _) = makeController()
        run(controller, "a=T,f=100,t=d,i=1,c=1,r=1,q=2;" + redPNGBase64)
        XCTAssertTrue(controller.hasPlacement(imageID: 1, placementID: 0))
        return controller
    }

    func testDeleteByCellAndZIndexWithHugeColumnDoesNotCrash() {
        // CGFloat(column + 1) trapped for column == Int32.max.
        let controller = controllerWithOneCellPlacement()
        run(controller, "a=d,d=q,x=4294967295,y=1,z=0;")
        run(controller, "a=d,d=Q,x=4294967295,y=4294967295,z=0;")
        XCTAssertTrue(controller.hasPlacement(imageID: 1, placementID: 0))
    }

    func testDeleteByCellAndZIndexUsesOneBasedCoordinates() {
        // The spec: the x and y keys are the same as cursor positions, so x=1,y=1 is the top-left
        // cell. d=q treated them as 0-based, unlike d=p.
        let controller = controllerWithOneCellPlacement()
        run(controller, "a=d,d=q,x=2,y=1,z=0;")
        XCTAssertTrue(controller.hasPlacement(imageID: 1, placementID: 0))
        run(controller, "a=d,d=q,x=1,y=1,z=5;")
        XCTAssertTrue(controller.hasPlacement(imageID: 1, placementID: 0))
        run(controller, "a=d,d=q,x=1,y=1,z=0;")
        XCTAssertFalse(controller.hasPlacement(imageID: 1, placementID: 0))
    }

    func testDeleteWithHugeCoordinatesDoesNotCrash() {
        let controller = controllerWithOneCellPlacement()
        for keys in ["d=p,x=4294967295,y=4294967295",
                     "d=P,x=0,y=0",
                     "d=x,x=4294967295",
                     "d=X,x=0",
                     "d=y,y=4294967295",
                     "d=Y,y=0",
                     "d=r,x=4294967295,y=4294967295",
                     "d=z,z=-2147483648",
                     "d=n,I=4294967295,p=4294967295",
                     "d=i,i=4294967295,p=4294967295"] {
            run(controller, "a=d," + keys + ";")
        }
        XCTAssertTrue(controller.hasPlacement(imageID: 1, placementID: 0))
        run(controller, "a=d,d=p,x=1,y=1;")
        XCTAssertFalse(controller.hasPlacement(imageID: 1, placementID: 0))
    }

    // MARK: - zlib payloads

    func testInflateRejectsTruncatedAndEmptyInput() {
        let (controller, _) = makeController()
        let text = Data("hello world hello world".utf8)
        let compressed = zlibCompressed(text)
        XCTAssertEqual(controller.inflate(data: compressed), text)
        // Without its last four bytes (the Adler-32 check) the stream never ends. inflate used to
        // loop forever, because zlib returns Z_BUF_ERROR on every call once the input runs out.
        XCTAssertNil(controller.inflate(data: compressed.prefix(compressed.count - 4)))
        XCTAssertNil(controller.inflate(data: compressed.prefix(2)))
        XCTAssertNil(controller.inflate(data: Data()))
    }

    func testTruncatedZlibTransmissionReportsAnError() {
        let (controller, delegate) = makeController()
        // zlib of "hello world hello world" without its last four bytes.
        run(controller, "a=T,f=100,o=z,t=d,i=9;eJzLSM3JyVcozy/KSVHIQLAB")
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertFalse(delegate.reports.first?.contains(";OK") ?? true, delegate.reports.description)
    }

    func testInflatedDataIsCappedAtTheCacheBudget() {
        let (controller, delegate) = makeController(budget: smallBudget)
        let bomb = zlibCompressed(Data(count: smallBudget * 3))
        XCTAssertLessThan(bomb.count, 2048)
        run(controller, "a=T,f=100,o=z,t=d,i=9;" + bomb.base64EncodedString())
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertTrue(delegate.reports[0].contains("ENOSPC"), delegate.reports.description)
        // Data within the budget still inflates.
        let small = Data(count: smallBudget / 2)
        XCTAssertEqual(controller.inflate(data: zlibCompressed(small)), small)
    }

    // MARK: - Chunked transmissions

    func testAccumulatedChunksAreCappedAtTheCacheBudget() {
        let (controller, delegate) = makeController(budget: smallBudget)
        let chunk = Data(count: smallBudget / 2).base64EncodedString()
        run(controller, "a=T,f=100,t=d,i=7,m=1;" + chunk)
        run(controller, "a=T,f=100,t=d,i=7,m=1;" + chunk)
        run(controller, "a=T,f=100,t=d,i=7,m=1;" + chunk)
        run(controller, "a=T,f=100,t=d,i=7,m=1;" + chunk)
        XCTAssertEqual(delegate.reports, [], "no response until the final chunk")
        run(controller, "a=T,f=100,t=d,i=7,m=0;" + chunk)
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertTrue(delegate.reports[0].contains("i=7"), delegate.reports.description)
        XCTAssertTrue(delegate.reports[0].contains("ENOSPC"), delegate.reports.description)
        // The abandoned transmission is forgotten: a new one works.
        run(controller, "a=T,f=100,t=d,i=8,q=2;" + redPNGBase64)
        XCTAssertTrue(controller.hasPlacement(imageID: 8, placementID: 0))
    }

    // MARK: - Files and shared memory

    private func temporaryPath(_ name: String) -> String {
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(name + "-" + UUID().uuidString)
    }

    func testFileLargerThanTheCacheBudgetIsRejected() throws {
        let (controller, delegate) = makeController(budget: smallBudget)
        let path = temporaryPath("kitty-large-file")
        try Data(count: smallBudget * 2).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        run(controller, "a=T,f=100,t=f,i=5;" + base64(path))
        // The reply is the one every t=f read failure gets, so that it does not reveal that a
        // large file exists at the path (it said ENOSPC until 2026-11-22).
        XCTAssertEqual(delegate.reports, [fileReadFailure(id: 5)])
    }

    func testSharedMemoryLargerThanTheCacheBudgetIsRejected() {
        let (controller, delegate) = makeController(budget: smallBudget)
        let name = "/kittytest" + String(UInt32.random(in: 0...UInt32.max))
        let fd = FileManager.default.it_shmOpen(name, oflag: O_CREAT | O_RDWR, mode: 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(ftruncate(fd, off_t(smallBudget * 2)), 0)
        close(fd)
        run(controller, "a=T,f=100,t=s,i=5;" + base64(name))
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertTrue(delegate.reports[0].contains("ENOSPC"), delegate.reports.description)
        // The object is unlinked whether or not it was used.
        let reopened = FileManager.default.it_shmOpen(name, oflag: O_RDONLY, mode: 0)
        XCTAssertEqual(reopened, -1)
        if reopened >= 0 {
            close(reopened)
            shm_unlink(name)
        }
    }

    func testTemporaryFileTransmissionDoesNotDeleteADirectory() throws {
        let (controller, delegate) = makeController()
        let directory = temporaryPath("tty-graphics-protocol-dir")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let inside = (directory as NSString).appendingPathComponent("keep")
        try Data("keep".utf8).write(to: URL(fileURLWithPath: inside))
        run(controller, "a=T,f=100,t=t,i=5;" + base64(directory))
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertFalse(delegate.reports[0].contains(";OK"), delegate.reports.description)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inside), "the directory must not be deleted")
    }

    func testTemporaryFileTransmissionReadsAndDeletesARegularFile() throws {
        let (controller, _) = makeController()
        let path = temporaryPath("tty-graphics-protocol-png")
        try Data(base64Encoded: redPNGBase64)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        run(controller, "a=T,f=100,t=t,i=6,q=2;" + base64(path))
        XCTAssertTrue(controller.hasPlacement(imageID: 6, placementID: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - File transmission (t=f): the denylist and its replies

    /// The one reply the kitty specification asks for when a file cannot be read, whatever the
    /// reason, so that the reply reveals nothing about the file system. The p=0 is there because
    /// these tests transmit and display (a=T).
    private func fileReadFailure(id: Int) -> String {
        return "\u{1B}_Gi=\(id),p=0;EBADF:Failed to read image file\u{1B}\\"
    }

    /// A new directory under the test's temporary directory, spelled as resolution spells it.
    private func makeScratchDirectory() throws -> String {
        let path = temporaryPath("kitty-denylist")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        addTeardownBlock {
            _ = chmod(path + "/unreadable.png", 0o600)
            try? FileManager.default.removeItem(atPath: path)
        }
        return KittyImageController.resolvedFileTransmissionURL(path).path
    }

    func testDenylistBlocksEveryEntryUnderEverySpelling() {
        // Paths as data, in the forms resolution can produce and the forms the entries were
        // first written in. The /private forms of /etc, /var/db and /var/root never matched,
        // because resolution removes /private.
        let denied = [
            "/etc", "/etc/", "/etc/hosts", "/etc/ssh/ssh_host_rsa_key",
            "/private/etc", "/private/etc/hosts",
            "/var/db", "/var/db/sudo/ts/me", "/private/var/db/sudo/ts/me",
            "/var/root", "/var/root/.bash_history", "/private/var/root/.bash_history",
            "/dev", "/dev/null", "/System", "/System/Library/x.png",
            "/Library/Keychains", "/Library/Keychains/System.keychain",
            "/Users/me/.ssh", "/Users/me/.ssh/id_ed25519", "/Users/me/.ssh/",
            // Case, as a case-insensitive volume would accept it.
            "/ETC/hosts", "/Private/Etc/hosts", "/VAR/DB/x", "/var/Root/x", "/DEV/null",
            "/system/Library/x.png", "/library/keychains/x", "/Users/me/.SSH/id_ed25519",
            // Repeated and "." components.
            "//etc//hosts", "/./etc/./hosts", "/private//var/db/x",
        ]
        for path in denied {
            XCTAssertTrue(KittyImageController.fileTransmissionPathIsDenied(path), path)
        }
    }

    func testDenylistDoesNotBlockPathsThatOnlyShareAPrefix() {
        let allowed = [
            "/etcetera/x.png", "/private/etcetera/x.png", "/developer/x.png",
            "/Systemic/x.png", "/var/dbx/x.png", "/private/var/rootkit/x.png",
            "/var/folders/ab/T/x.png", "/private/var/folders/ab/T/x.png",
            "/tmp/x.png", "/private/tmp/x.png", "/Library/KeychainsBackup/x.png",
            "/Users/me/.sshx/x.png", "/Users/me/a.ssh/x.png", "/Users/me/Pictures/x.png",
            "/private/Users/etc/x.png", "/Users/me/etc/x.png", "/Users/me/var/db/x.png",
        ]
        for path in allowed {
            XCTAssertFalse(KittyImageController.fileTransmissionPathIsDenied(path), path)
        }
    }

    func testFileTransmissionPathResolution() throws {
        // How t=f paths are resolved before the denylist sees them. Only names are resolved
        // here; no sensitive file is opened.
        XCTAssertEqual(KittyImageController.resolvedFileTransmissionURL("/private/etc").path, "/etc")
        XCTAssertEqual(KittyImageController.resolvedFileTransmissionURL("/tmp/../etc").path, "/etc")
        XCTAssertEqual(KittyImageController.resolvedFileTransmissionURL("/private/tmp").path, "/tmp")
        XCTAssertEqual(KittyImageController.resolvedFileTransmissionURL("/private/var/db").path, "/var/db")

        let dir = try makeScratchDirectory()
        try FileManager.default.createDirectory(atPath: dir + "/.ssh", withIntermediateDirectories: false)
        try FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: false)
        try Data(base64Encoded: redPNGBase64)!.write(to: URL(fileURLWithPath: dir + "/.ssh/img.png"))
        try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: ".ssh")
        let canonical = dir + "/.ssh/img.png"
        for spelling in [dir + "/.SSH/img.png",
                         dir + "/sub/../.ssh/img.png",
                         dir + "/link/img.png",
                         dir + "/.ssh/img.png/",
                         dir + "//.ssh/./img.png",
                         "/private" + dir + "/.ssh/img.png"] {
            XCTAssertEqual(KittyImageController.resolvedFileTransmissionURL(spelling).path, canonical, spelling)
        }
    }

    func testFileTransmissionRefusesADeniedFileUnderEverySpelling() throws {
        let dir = try makeScratchDirectory()
        let png = Data(base64Encoded: redPNGBase64)!
        try FileManager.default.createDirectory(atPath: dir + "/.ssh", withIntermediateDirectories: false)
        try FileManager.default.createDirectory(atPath: dir + "/.sshx", withIntermediateDirectories: false)
        try FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: false)
        try png.write(to: URL(fileURLWithPath: dir + "/.ssh/img.png"))
        try png.write(to: URL(fileURLWithPath: dir + "/.sshx/img.png"))
        try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: ".ssh")
        try FileManager.default.createSymbolicLink(atPath: dir + "/alias.png", withDestinationPath: ".ssh/img.png")

        let spellings = [dir + "/.ssh/img.png",
                         dir + "/.SSH/img.png",
                         dir + "/sub/../.ssh/img.png",
                         dir + "/link/img.png",
                         dir + "/alias.png",
                         dir + "/.ssh/img.png/",
                         "/private" + dir + "/.ssh/img.png"]
        for (index, spelling) in spellings.enumerated() {
            let (controller, delegate) = makeController()
            let id = index + 1
            run(controller, "a=T,f=100,t=f,i=\(id);" + base64(spelling))
            XCTAssertEqual(delegate.reports, [fileReadFailure(id: id)], spelling)
            XCTAssertFalse(controller.hasPlacement(imageID: UInt32(id), placementID: 0), spelling)
        }

        // The same image outside the denied directory loads.
        let (controller, delegate) = makeController()
        run(controller, "a=T,f=100,t=f,i=40;" + base64(dir + "/.sshx/img.png"))
        XCTAssertEqual(delegate.reports, ["\u{1B}_Gi=40;OK\u{1B}\\"])
        XCTAssertTrue(controller.hasPlacement(imageID: 40, placementID: 0))
    }

    func testFileTransmissionFailuresShareOneReply() throws {
        // Missing, not a regular file, denied, unreadable, too large and not an image: a
        // program, perhaps on a remote host, must not be able to tell these apart.
        let dir = try makeScratchDirectory()
        try FileManager.default.createDirectory(atPath: dir + "/.ssh", withIntermediateDirectories: false)
        try Data(base64Encoded: redPNGBase64)!.write(to: URL(fileURLWithPath: dir + "/.ssh/img.png"))
        try Data("not an image".utf8).write(to: URL(fileURLWithPath: dir + "/text.png"))
        try Data(count: smallBudget * 2).write(to: URL(fileURLWithPath: dir + "/large.png"))
        try Data(base64Encoded: redPNGBase64)!.write(to: URL(fileURLWithPath: dir + "/unreadable.png"))
        XCTAssertEqual(chmod(dir + "/unreadable.png", 0), 0)
        XCTAssertEqual(mkfifo(dir + "/fifo.png", 0o600), 0)
        try FileManager.default.createDirectory(atPath: dir + "/directory.png", withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: dir + "/loop.png", withDestinationPath: "loop.png")

        for name in ["missing.png", "directory.png", "fifo.png", ".ssh/img.png", "unreadable.png",
                     "large.png", "text.png", "loop.png"] {
            for verbosity in ["", ",q=1"] {
                let (controller, delegate) = makeController(budget: smallBudget)
                run(controller, "a=T,f=100,t=f,i=5\(verbosity);" + base64(dir + "/" + name))
                XCTAssertEqual(delegate.reports, [fileReadFailure(id: 5)], name + verbosity)
            }
        }
    }
}
