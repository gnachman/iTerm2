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
        XCTAssertEqual(delegate.reports.count, 1)
        XCTAssertTrue(delegate.reports[0].contains("ENOSPC"), delegate.reports.description)
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
}
