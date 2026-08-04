//
//  KittyDnDAcceptTests.swift
//  iTerm2 ModernTests
//
//  Phase 2 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Drives the controller's accept-drop state machine
//  with fake collaborators (report sink, endpoint, drop data) and asserts the
//  OSC 72 traffic it emits, including the three-tier routing for text/uri-list.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDAcceptTests: XCTestCase {
    // MARK: - Fakes

    private final class Recorder {
        var reports: [String] = []
        var onReport: ((KittyDnDMessage) -> Void)?
        func report(_ serialized: String) {
            let msg = KittyDnDAcceptTests.parse(serialized)
            reports.append(serialized)
            onReport?(msg)
        }
        var messages: [KittyDnDMessage] {
            return reports.map { KittyDnDAcceptTests.parse($0) }
        }
        var last: KittyDnDMessage? { messages.last }
    }

    private final class FakeEndpoint: KittyDnDEndpoint {
        var canMaterializeFiles: Bool
        var materialized: [(name: String, contents: Data)] = []
        var shouldThrow = false
        init(canMaterializeFiles: Bool) { self.canMaterializeFiles = canMaterializeFiles }
        func materializeFile(named name: String, contents: Data) async throws -> String {
            if shouldThrow {
                throw NSError(domain: "test", code: 1)
            }
            materialized.append((name, contents))
            return "/remote/tmp/\(name)"
        }
    }

    private final class FakeDropData: KittyDnDDropData {
        let mimeTypes: [String]
        let fileURLs: [URL]
        private let dataByIndex: [Int: Data]
        init(mimeTypes: [String], fileURLs: [URL] = [], dataByIndex: [Int: Data] = [:]) {
            self.mimeTypes = mimeTypes
            self.fileURLs = fileURLs
            self.dataByIndex = dataByIndex
        }
        func data(forMimeIndex index: Int) -> Data? { dataByIndex[index] }
    }

    // MARK: - Helpers

    nonisolated static func parse(_ serialized: String) -> KittyDnDMessage {
        var s = serialized
        precondition(s.hasPrefix("\u{1b}]72;"), "not an OSC 72 sequence: \(serialized.debugDescription)")
        s.removeFirst("\u{1b}]72;".count)
        precondition(s.hasSuffix("\u{1b}\\"))
        s.removeLast(2)
        return KittyDnDMessage(oscContent: s)
    }

    private let ourID = KittyDnDMachineID.hashed("us")
    private let peerID = KittyDnDMachineID.hashed("peer")

    private func makeController(endpoint: FakeEndpoint,
                               recorder: Recorder) -> KittyDnDController {
        return KittyDnDController(ourMachineID: ourID, endpoint: endpoint) { serialized in
            recorder.report(serialized)
        }
    }

    /// Feed all emitted t=r messages through a reassembler and return the
    /// completed data response (metadata comes from the first chunk, so the X=1
    /// flag and index are visible here).
    private func reassembledDataResponse(_ recorder: Recorder) -> KittyDnDMessage? {
        let reassembler = KittyDnDChunkReassembler()
        var result: KittyDnDMessage?
        for message in recorder.messages where message.type == "r" {
            if let done = reassembler.accept(message.serializedContent()) {
                result = done
            }
        }
        return result
    }

    /// All emitted t=r messages (data chunks plus the empty terminator).
    private func dataResponseChunks(_ recorder: Recorder) -> [KittyDnDMessage] {
        return recorder.messages.filter { $0.type == "r" }
    }

    // MARK: - Announce / query

    func testAnnounceEnablesAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain text/uri-list")
        XCTAssertTrue(c.isAcceptingDrops)
    }

    func testUnregisterDisablesAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.handleInboundSequence("t=A")
        XCTAssertFalse(c.isAcceptingDrops)
    }

    func testUnregisterViaXEquals2DisablesAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.handleInboundSequence("t=a:x=2")
        XCTAssertFalse(c.isAcceptingDrops)
    }

    func testQueryIsAnswered() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=q:i=7")
        XCTAssertEqual(recorder.last?.type, "q")
        XCTAssertEqual(recorder.last?.metadata["i"], "7")
    }

    // MARK: - Move / drop reporting

    func testDragEnteredSendsMoveWithMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.dragEntered(cellX: 3, cellY: 4, pixelX: 5, pixelY: 6,
                      operations: 3, mimeTypes: ["text/uri-list"])
        let m = recorder.last
        XCTAssertEqual(m?.type, "m")
        XCTAssertEqual(m?.intValue("x"), 3)
        XCTAssertEqual(m?.intValue("y"), 4)
        XCTAssertEqual(m?.intValue("X"), 5)
        XCTAssertEqual(m?.intValue("Y"), 6)
        XCTAssertEqual(m?.intValue("o"), 3)
        XCTAssertEqual(m?.textPayload, "text/uri-list")
    }

    func testDragMovedOmitsMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.dragEntered(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/uri-list"])
        c.dragMoved(cellX: 2, cellY: 2, pixelX: 1, pixelY: 1, operations: 3)
        let m = recorder.last
        XCTAssertEqual(m?.type, "m")
        XCTAssertEqual(m?.intValue("x"), 2)
        XCTAssertNil(m?.rawPayload)
    }

    func testInertWhenNotAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.dragEntered(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/uri-list"])
        XCTAssertTrue(recorder.reports.isEmpty)
    }

    func testDragExitedSendsLeave() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.dragExited()
        let m = recorder.last
        XCTAssertEqual(m?.type, "m")
        XCTAssertEqual(m?.intValue("x"), -1)
        XCTAssertEqual(m?.intValue("y"), -1)
    }

    func testDropSendsDropMessageWithMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 2, cellY: 3, pixelX: 4, pixelY: 5, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        let m = recorder.last
        XCTAssertEqual(m?.type, "M")
        XCTAssertEqual(m?.intValue("x"), 2)
        XCTAssertEqual(m?.textPayload, "text/plain")
    }

    // MARK: - Data requests

    func testContentDataRequestReturnsBytes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"],
                                         dataByIndex: [1: Data("hello".utf8)]))
        c.handleInboundSequence("t=r:x=1")
        let r = reassembledDataResponse(recorder)
        XCTAssertEqual(r?.intValue("x"), 1)
        XCTAssertEqual(r?.dataPayload, Data("hello".utf8))
    }

    func testLargeContentIsChunked() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        let big = Data((0..<10_000).map { UInt8($0 & 0xff) })
        c.handleInboundSequence("t=a;application/octet-stream")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["application/octet-stream"],
                                         dataByIndex: [1: big]))
        c.handleInboundSequence("t=r:x=1")
        let responses = recorder.messages.filter { $0.type == "r" }
        XCTAssertGreaterThan(responses.count, 1)
        // Feed them through the reassembler to reconstruct the payload.
        let reassembler = KittyDnDChunkReassembler()
        var reconstructed: Data?
        for r in responses {
            if let done = reassembler.accept(r.serializedContent()) {
                reconstructed = done.dataPayload
            }
        }
        XCTAssertEqual(reconstructed, big)
    }

    func testUnknownMimeIndexSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:x=5")
        XCTAssertEqual(recorder.last?.type, "R")
    }

    func testMissingContentDataSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;image/png")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["image/png"]))
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
    }

    // MARK: - text/uri-list three-tier routing

    func testURIListTier1LocalReturnsLocalURIsNoCrossMachineFlag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        // No peer machine id -> local.
        c.handleInboundSequence("t=a;text/uri-list")
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [url]))
        c.handleInboundSequence("t=r:x=1")
        let r = reassembledDataResponse(recorder)
        XCTAssertNil(r?.metadata["X"], "local drop must not set the cross-machine flag")
        let uriList = String(data: r?.dataPayload ?? Data(), encoding: .utf8)
        XCTAssertEqual(uriList, url.absoluteString)
    }

    func testURIListJoinsMultipleFilesWithCRLF() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [a, b]))
        c.handleInboundSequence("t=r:x=1")
        let uriList = String(data: reassembledDataResponse(recorder)?.dataPayload ?? Data(),
                             encoding: .utf8)
        XCTAssertEqual(uriList, "\(a.absoluteString)\r\n\(b.absoluteString)")
    }

    func testURIListTier3RemoteNoConductorSetsCrossMachineFlag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        // Peer machine id differs and endpoint cannot materialize -> Tier 3.
        c.handleInboundSequence("t=a;text/uri-list \(peerID)")
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [url]))
        c.handleInboundSequence("t=r:x=1")
        let r = reassembledDataResponse(recorder)
        XCTAssertEqual(r?.metadata["X"], "1", "remote foreign uri-list must set X=1")
        let uriList = String(data: r?.dataPayload ?? Data(), encoding: .utf8)
        XCTAssertEqual(uriList, url.absoluteString)
        // The cross-machine flag must be on every emitted chunk, including the
        // terminator, so the client sees it regardless of which it reads.
        for chunk in dataResponseChunks(recorder) {
            XCTAssertEqual(chunk.metadata["X"], "1")
        }
    }

    func testURIListTier2RemoteWithConductorMaterializesAndOmitsFlag() async throws {
        let recorder = Recorder()
        let endpoint = FakeEndpoint(canMaterializeFiles: true)
        let c = makeController(endpoint: endpoint, recorder: recorder)

        // A real local file whose bytes get materialized on the endpoint.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kittydnd-\(UUID().uuidString).txt")
        try Data("payload".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // No machine id sent: a conductor being present is enough to materialize
        // (regression test for the bug where Tier 2 required the machine id too).
        c.handleInboundSequence("t=a;text/uri-list")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [tmp]))

        let exp = expectation(description: "uri-list response after materialization")
        // Two t=r messages arrive (the data chunk and the empty terminator);
        // either one satisfies the wait.
        exp.assertForOverFulfill = false
        recorder.onReport = { if $0.type == "r" { exp.fulfill() } }
        c.handleInboundSequence("t=r:x=1")
        await fulfillment(of: [exp], timeout: 5)

        XCTAssertEqual(endpoint.materialized.count, 1)
        XCTAssertEqual(endpoint.materialized.first?.contents, Data("payload".utf8))
        let r = reassembledDataResponse(recorder)
        XCTAssertNil(r?.metadata["X"], "materialized files are local to the program; no X=1")
        let uriList = String(data: r?.dataPayload ?? Data(), encoding: .utf8)
        XCTAssertEqual(uriList, "file:///remote/tmp/\(tmp.lastPathComponent)")
    }

    func testTier2MaterializeFailureSendsError() async {
        let recorder = Recorder()
        let endpoint = FakeEndpoint(canMaterializeFiles: true)
        endpoint.shouldThrow = true
        let c = makeController(endpoint: endpoint, recorder: recorder)

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kittydnd-\(UUID().uuidString).txt")
        try? Data("payload".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        c.handleInboundSequence("t=a;text/uri-list \(peerID)")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [tmp]))

        let exp = expectation(description: "error response")
        recorder.onReport = { if $0.type == "R" { exp.fulfill() } }
        c.handleInboundSequence("t=r:x=1")
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertEqual(recorder.last?.type, "R")
    }

    // MARK: - Data-request error paths

    func testDataRequestBeforeDropSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        // No drop yet.
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
    }

    func testDataRequestWithMissingIndexSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r")  // no x=
        XCTAssertEqual(recorder.last?.type, "R")
    }

    // MARK: - Cross-machine in-band file/dir transfer (plain ssh, no conductor)

    private func makeTempDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kittydnd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Send `request`, wait for the terminal's terminal response (final chunk or
    /// error), and return the reassembled t=r message (or the t=R error).
    private func awaitResponse(_ recorder: Recorder,
                              _ c: KittyDnDController,
                              _ request: String) async -> KittyDnDMessage? {
        recorder.reports.removeAll()
        let exp = expectation(description: request)
        exp.assertForOverFulfill = false
        recorder.onReport = { msg in
            if msg.type == "R" || (msg.type == "r" && msg.metadata["m"] != "1") {
                exp.fulfill()
            }
        }
        c.handleInboundSequence(request)
        await fulfillment(of: [exp], timeout: 5)
        recorder.onReport = nil
        if let error = recorder.messages.first(where: { $0.type == "R" }) {
            return error
        }
        let reassembler = KittyDnDChunkReassembler()
        var result: KittyDnDMessage?
        for msg in recorder.messages where msg.type == "r" {
            if let done = reassembler.accept(msg.serializedContent()) {
                result = done
            }
        }
        return result
    }

    private func remoteDropController(fileURLs: [URL],
                                     recorder: Recorder) -> KittyDnDController {
        let c = makeController(endpoint: FakeEndpoint(canMaterializeFiles: false), recorder: recorder)
        // Peer machine id present and no conductor -> Tier 3 (in-band transfer).
        c.handleInboundSequence("t=a;text/uri-list \(peerID)")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: fileURLs))
        return c
    }

    func testCrossMachineURIListIsFlaggedThenFileBytesStreamed() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("hello remote".utf8).write(to: file)

        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [file], recorder: recorder)

        // The uri-list is flagged cross-machine.
        let list = await awaitResponse(recorder, c, "t=r:x=1")
        XCTAssertEqual(list?.metadata["X"], "1")

        // The program then pulls the actual bytes by sub-index.
        let entry = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        XCTAssertNil(entry?.metadata["X"], "a regular file carries no type flag")
        XCTAssertEqual(entry?.dataPayload, Data("hello remote".utf8))
    }

    func testCrossMachineSymlinkReturnsTarget() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "a.txt")

        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [link], recorder: recorder)
        let entry = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        XCTAssertEqual(entry?.metadata["X"], "1", "symlink is flagged X=1")
        XCTAssertEqual(entry?.dataPayload, Data("a.txt".utf8))
    }

    func testCrossMachineDirectoryTraversal() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("A".utf8).write(to: sub.appendingPathComponent("a.txt"))
        try Data("B".utf8).write(to: sub.appendingPathComponent("b.txt"))

        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [sub], recorder: recorder)

        // The directory entry yields a handle and null-separated names.
        let dirResp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        let handle = dirResp?.metadata["X"]
        XCTAssertNotNil(handle)
        XCTAssertNotEqual(handle, "0")
        XCTAssertNotEqual(handle, "1")
        let names = String(data: dirResp?.dataPayload ?? Data(), encoding: .utf8)?
            .split(separator: "\u{0}").map(String.init)
        XCTAssertEqual(names, ["a.txt", "b.txt"])

        // Traverse into the directory by handle + index.
        let child = await awaitResponse(recorder, c, "t=r:Y=\(handle!):x=1")
        XCTAssertEqual(child?.dataPayload, Data("A".utf8))

        // Freeing the handle produces no response; a later use is an error.
        c.handleInboundSequence("t=r:Y=\(handle!)")
        let afterFree = await awaitResponse(recorder, c, "t=r:Y=\(handle!):x=1")
        XCTAssertEqual(afterFree?.type, "R")
    }

    func testCrossMachineBadSubIndexIsError() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try? Data("x".utf8).write(to: file)
        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [file], recorder: recorder)
        let resp = await awaitResponse(recorder, c, "t=r:x=1:y=99")
        XCTAssertEqual(resp?.type, "R")
    }
}
