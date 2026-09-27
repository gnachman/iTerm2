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
        var isRemoteHost: Bool
        init(isRemoteHost: Bool) { self.isRemoteHost = isRemoteHost }
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain text/uri-list")
        XCTAssertTrue(c.isAcceptingDrops)
    }

    func testUnregisterDisablesAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.handleInboundSequence("t=A")
        XCTAssertFalse(c.isAcceptingDrops)
    }

    func testUnregisterViaXEquals2DisablesAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.handleInboundSequence("t=a:x=2")
        XCTAssertFalse(c.isAcceptingDrops)
    }

    func testResetClearsAcceptAndOfferState() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.handleInboundSequence("t=o:x=1")
        XCTAssertTrue(c.isAcceptingDrops)
        XCTAssertTrue(c.isOfferingDrags)
        c.reset()
        XCTAssertFalse(c.isAcceptingDrops)
        XCTAssertFalse(c.isOfferingDrags)
        // A stray data request after reset finds no drop and errors.
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
    }

    func testResetInvalidatesDirectoryHandle() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("A".utf8).write(to: sub.appendingPathComponent("a.txt"))
        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [sub], recorder: recorder)
        let dirResp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        let handle = dirResp?.metadata["X"]
        c.reset()
        let stale = await awaitResponse(recorder, c, "t=r:Y=\(handle!):x=1")
        XCTAssertEqual(stale?.type, "R")
    }

    func testQueryIsAnswered() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=q:i=7")
        XCTAssertEqual(recorder.last?.type, "q")
        XCTAssertEqual(recorder.last?.metadata["i"], "7")
    }

    // MARK: - Move / drop reporting

    func testDragEnteredSendsMoveWithMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.dragEntered(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/uri-list"])
        XCTAssertTrue(recorder.reports.isEmpty)
    }

    func testDragExitedSendsLeave() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.dragExited()
        let m = recorder.last
        XCTAssertEqual(m?.type, "m")
        XCTAssertEqual(m?.intValue("x"), -1)
        XCTAssertEqual(m?.intValue("y"), -1)
    }

    func testDropSendsDropMessageWithMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:x=5")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "ENOENT", "out-of-bounds index is ENOENT")
    }

    func testMissingContentDataSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;image/png")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["image/png"]))
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "ENOENT",
                       "an in-bounds index with no data is ENOENT")
    }

    // MARK: - text/uri-list three-tier routing

    func testURIListTier1LocalReturnsLocalURIsNoCrossMachineFlag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
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

    func testURIListRemoteByMachineIdSetsCrossMachineFlag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        // Peer machine id differs (plain ssh, no conductor) -> remote, in-band.
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

    // A conductor (remote host) makes the drop cross-machine even when the
    // program sent no machine id: the uri-list is flagged X=1 for in-band
    // transfer, and the URIs are the local file paths (no materialization).
    func testURIListRemoteByConductorSetsCrossMachineFlag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: true), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")  // no machine id
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [url]))
        c.handleInboundSequence("t=r:x=1")
        let r = reassembledDataResponse(recorder)
        XCTAssertEqual(r?.metadata["X"], "1")
        let uriList = String(data: r?.dataPayload ?? Data(), encoding: .utf8)
        XCTAssertEqual(uriList, url.absoluteString)
    }

    // MARK: - Data-request error paths

    func testDataRequestBeforeDropSendsError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        // No drop yet.
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EINVAL", "a request with no drop is EINVAL")
    }

    // A bare t=r (no x, no Y, no o) is the canceled drop-completion signal, not a
    // malformed request; it must not draw an error and must clear the drop.
    func testBareDataRequestIsCanceledCompletion() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"], dataByIndex: [1: Data("x".utf8)]))
        c.handleInboundSequence("t=r")  // no x, no Y, no o
        XCTAssertNil(recorder.messages.first { $0.type == "R" })
        XCTAssertEqual(c.lastCompletedDropOperation, 0)  // 0 = canceled
        // The drop is now cleared: a later read errors.
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
    }

    // A sub-index request before the client has requested the uri-list is EINVAL.
    func testSubIndexBeforeURIListRequestIsEINVAL() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try? Data("hi".utf8).write(to: file)
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list \(peerID)")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [file]))
        // Straight to a sub-index without first requesting the uri-list.
        let resp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        XCTAssertEqual(resp?.type, "R")
        XCTAssertEqual(resp?.textPayload, "EINVAL")
    }

    // Spec: "if too many requests are received, terminals must deny the request
    // with EMFILE and end the drop." The in-flight key is inserted synchronously
    // before the async read, so 65 distinct sub-index requests fired in one batch
    // trip the 64-request cap on the 65th and end the drop.
    func testTooManyConcurrentEntryRequestsIsEMFILEAndEndsDrop() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let recorder = Recorder()
        // 65 entries so 65 distinct sub-index reads can be in flight at once.
        let c = remoteDropController(fileURLs: Array(repeating: file, count: 65), recorder: recorder)
        recorder.reports.removeAll()
        // Fire all 65 synchronously: no async read completes during the loop, so
        // all 64 keys stay in flight and the 65th is over the cap.
        for y in 1...65 {
            c.handleInboundSequence("t=r:x=1:y=\(y)")
        }
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EMFILE")
        // The drop was ended: a following request finds no drop and errors.
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EINVAL")
    }

    // A streamed file response interrupted mid-flight by a new drag must be closed
    // with its m=0 terminator (so the client does not hang) and must emit no
    // further chunks (the generation guard). Interrupts from onReport after the
    // first data chunk, exercising terminateInFlightStream and the mid-stream guard.
    func testInFlightStreamIsTerminatedAndStoppedByNewDrag() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("big.bin")
        // Several chunks (maxRawChunkSize is 3072 bytes).
        try Data(count: 10_000).write(to: file)
        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [file], recorder: recorder)
        recorder.reports.removeAll()

        var interrupted = false
        var chunksAfterInterrupt = 0
        let done = expectation(description: "terminator after interrupt")
        done.assertForOverFulfill = false
        recorder.onReport = { msg in
            guard msg.type == "r" else { return }
            if !interrupted {
                if msg.metadata["m"] == "1" {
                    // First data chunk: interrupt with a new drag (bumps the
                    // generation and terminates the stream).
                    interrupted = true
                    c.dragEntered(cellX: 9, cellY: 9, pixelX: 0, pixelY: 0,
                                  operations: 1, mimeTypes: ["text/uri-list"])
                }
            } else if msg.metadata["m"] == "1" {
                chunksAfterInterrupt += 1
            } else {
                done.fulfill()  // the m=0 terminator emitted by the interrupt
            }
        }
        c.handleInboundSequence("t=r:x=1:y=1")
        await fulfillment(of: [done], timeout: 5)
        recorder.onReport = nil
        XCTAssertEqual(chunksAfterInterrupt, 0, "no chunks may follow the terminator")
        let terminators = recorder.messages.filter { $0.type == "r" && $0.metadata["m"] == "0" }
        XCTAssertEqual(terminators.count, 1, "exactly one m=0 terminator (not zero, not two)")
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
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        // Peer machine id present and no conductor -> Tier 3 (in-band transfer).
        c.handleInboundSequence("t=a;text/uri-list \(peerID)")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: fileURLs))
        // The client must request the uri-list before sub-indexing its entries;
        // do so here so the per-entry tests can drive t=r:x=1:y=N directly.
        c.handleInboundSequence("t=r:x=1")
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

    func testDirectoryHandleIsInvalidatedByNewDrag() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("A".utf8).write(to: sub.appendingPathComponent("a.txt"))

        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [sub], recorder: recorder)
        let dirResp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        let handle = dirResp?.metadata["X"]
        XCTAssertNotNil(handle)

        // A new drag cycle must invalidate the handle so a stray request errors.
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 1, mimeTypes: ["text/uri-list"])
        let stale = await awaitResponse(recorder, c, "t=r:Y=\(handle!):x=1")
        XCTAssertEqual(stale?.type, "R")
    }

    func testCrossMachineNestedDirectoryTraversal() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let top = dir.appendingPathComponent("top")
        let inner = top.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("deep".utf8).write(to: inner.appendingPathComponent("deep.txt"))

        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [top], recorder: recorder)

        // top -> handle with child "inner"
        let topResp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        let topHandle = topResp?.metadata["X"]
        XCTAssertNotNil(topHandle)
        // descend into "inner" -> a fresh handle with child "deep.txt"
        let innerResp = await awaitResponse(recorder, c, "t=r:Y=\(topHandle!):x=1")
        let innerHandle = innerResp?.metadata["X"]
        XCTAssertNotNil(innerHandle)
        XCTAssertNotEqual(innerHandle, topHandle)
        // read the nested file
        let deep = await awaitResponse(recorder, c, "t=r:Y=\(innerHandle!):x=1")
        XCTAssertEqual(deep?.dataPayload, Data("deep".utf8))
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
        // An out-of-bounds sub-index is "does not exist", not "invalid request".
        XCTAssertEqual(resp?.textPayload, "ENOENT")
    }

    // A t=r carrying y but no x/Y is a malformed sub-index request, not the
    // completion signal; it must draw EINVAL and NOT clear the drop.
    func testSubIndexRequestWithMissingIndexIsEINVAL() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"], dataByIndex: [1: Data("x".utf8)]))
        c.handleInboundSequence("t=r:y=1")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EINVAL")
        XCTAssertNil(c.lastCompletedDropOperation)  // not treated as completion
    }

    // AppKit delivers periodic stationary hover updates; identical moves must not
    // be re-sent over the pty.
    func testStationaryHoverMovesAreDeduped() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 1, cellY: 1, pixelX: 2, pixelY: 3,
                      operations: 1, mimeTypes: ["text/plain"])
        func moveCount() -> Int { recorder.messages.filter { $0.type == "m" }.count }
        XCTAssertEqual(moveCount(), 1)
        c.dragMoved(cellX: 1, cellY: 1, pixelX: 2, pixelY: 3, operations: 1)  // identical
        c.dragMoved(cellX: 1, cellY: 1, pixelX: 2, pixelY: 3, operations: 1)  // identical
        XCTAssertEqual(moveCount(), 1, "duplicate stationary moves must be dropped")
        c.dragMoved(cellX: 2, cellY: 1, pixelX: 2, pixelY: 3, operations: 1)  // moved
        XCTAssertEqual(moveCount(), 2)
    }

    // Before the program replies, the OS operation is optimistically the offered
    // one (so a fast drop is accepted, not sprung back); an explicit o=0 refuses.
    func testOptimisticDropOperationBeforeReply() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 2, mimeTypes: ["text/plain"])
        XCTAssertEqual(c.osDragOperation, 2, "no reply yet -> optimistic offered op (move)")
        c.handleInboundSequence("t=m:o=1")
        XCTAssertEqual(c.osDragOperation, 1, "program's reply wins")
        c.handleInboundSequence("t=m:o=0")
        XCTAssertEqual(c.osDragOperation, 0, "explicit refuse")
    }

    // Security-critical default: before the program replies, a copy+move offer
    // (and any empty/unknown mask) must optimistically report COPY, never move, so
    // an unconfirmed drop cannot authorize a destructive move that deletes the
    // source's only copy. Only a move-ONLY offer optimistically reports move.
    func testOptimisticDropOperationPrefersCopy() {
        func optimisticOp(forOffered offered: Int) -> Int {
            let recorder = Recorder()
            let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
            c.handleInboundSequence("t=a;text/plain")
            c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                          operations: offered, mimeTypes: ["text/plain"])
            return c.osDragOperation
        }
        XCTAssertEqual(optimisticOp(forOffered: 3), 1, "copy+move must optimistically be copy")
        XCTAssertEqual(optimisticOp(forOffered: 0), 1, "empty/unknown mask must be copy")
        XCTAssertEqual(optimisticOp(forOffered: 1), 1, "copy-only is copy")
        XCTAssertEqual(optimisticOp(forOffered: 2), 2, "move-only may optimistically be move")
    }

    // If the program stops accepting mid-drag (t=A), the OS operation must go to 0
    // so the drop is not reported accepted while performDrop silently discards it.
    func testOsDragOperationIsZeroWhenNotAccepting() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 1, mimeTypes: ["text/plain"])
        XCTAssertEqual(c.osDragOperation, 1, "accepting + copy offered -> optimistic copy")
        c.handleInboundSequence("t=A")  // program stops accepting mid-drag
        XCTAssertEqual(c.osDragOperation, 0,
                       "not accepting must read as refused, not optimistically accepted")
    }

    // A t=a whose MIME list is absurdly long is refused with EFBIG rather than
    // amplified into millions of token Strings; acceptance is not enabled.
    func testOverlongMimeListIsRejectedWithEFBIG() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        let huge = String(repeating: "a ", count: 40_000)  // > 64 KB
        c.handleInboundSequence("t=a;\(huge)")
        XCTAssertEqual(recorder.last?.type, "E")
        XCTAssertEqual(recorder.last?.textPayload, "EFBIG")
        XCTAssertFalse(c.isAcceptingDrops, "an over-long registration must not enable accepting")
    }

    // A present-but-unparseable directory handle (Y) is EINVAL, not a fall-through
    // to a plain MIME read; the raw key is echoed so the client can match it.
    func testUnparseableDirectoryHandleIsEINVAL() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"], dataByIndex: [1: Data("x".utf8)]))
        c.handleInboundSequence("t=r:Y=zzz:x=1")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EINVAL")
        XCTAssertEqual(recorder.last?.metadata["Y"], "zzz", "the raw Y key is echoed")
    }

    // A present-but-unparseable sub-index (y) is EINVAL, not treated as absent.
    func testUnparseableSubIndexIsEINVAL() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"], dataByIndex: [1: Data("x".utf8)]))
        c.handleInboundSequence("t=r:x=1:y=zz")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "EINVAL")
    }

    // An out-of-bounds x that also carries a sub-index y must echo y in the ENOENT
    // response so a pipelining client can match the error to its request.
    func testOutOfBoundsIndexWithSubIndexEchoesSubIndex() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:x=9:y=2")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "ENOENT")
        XCTAssertEqual(recorder.last?.metadata["y"], "2", "the sub-index must be echoed")
    }

    // MARK: - Machine-id version (#6)

    // A machine id with a version we do not understand ("2:...") must be treated
    // as a DIFFERENT machine (remote), and kept out of the accepted MIME list.
    func testUnknownMachineIdVersionIsTreatedAsRemote() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.handleInboundSequence("t=a:x=1;2:deadbeef")  // future version id
        XCTAssertEqual(c.acceptedMimeTypes, ["text/uri-list"],
                       "a machine-id token must not leak into the MIME list")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"],
                                         fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")]))
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(reassembledDataResponse(recorder)?.metadata["X"], "1",
                       "an unknown-version peer id must route as remote (X=1)")
    }

    // MARK: - Multiplexer i key (#4)

    // Spec: "When the terminal receives a t=a or t=o escape code that has the i
    // key set, all escape codes it sends to the terminal program must include the
    // i key with the same value." That includes t=m, t=M, and every t=r chunk.
    func testMultiplexerIDStampedOnAllSends() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a:i=42;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 1, mimeTypes: ["text/plain"])
        XCTAssertEqual(recorder.last?.metadata["i"], "42", "t=m must carry i")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"],
                                         dataByIndex: [1: Data("hi".utf8)]))
        XCTAssertEqual(recorder.last?.metadata["i"], "42", "t=M must carry i")
        c.handleInboundSequence("t=r:x=1")
        for chunk in recorder.messages.filter({ $0.type == "r" }) {
            XCTAssertEqual(chunk.metadata["i"], "42", "every t=r chunk must carry i")
        }
    }

    // A per-message echo (the query's own i) is not overridden by the stamp.
    func testQueryEchoesItsOwnIOverStamp() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a:i=42;text/plain")
        c.handleInboundSequence("t=q:i=7")
        XCTAssertEqual(recorder.last?.type, "q")
        XCTAssertEqual(recorder.last?.metadata["i"], "7")
    }

    // reset() forgets the multiplexer id.
    func testResetClearsMultiplexerID() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a:i=42;text/plain")
        c.reset()
        c.handleInboundSequence("t=q")  // no i on the query
        XCTAssertEqual(recorder.last?.type, "q")
        XCTAssertNil(recorder.last?.metadata["i"])
    }

    // MARK: - Program acceptance reply (t=m:o) (#3)

    // The program replies to our t=m with the operation it will perform (0 not
    // accepted, 1 copy, 2 move). Until then the drop is not accepted.
    func testAcceptOperationIsNilUntilProgramReplies() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        XCTAssertNil(c.acceptedDropOperation)
    }

    func testProgramAcceptReplyIsRecorded() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=2;text/plain")
        XCTAssertEqual(c.acceptedDropOperation, 2)
    }

    func testProgramRejectReplyIsRecorded() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=0")
        XCTAssertEqual(c.acceptedDropOperation, 0)
    }

    func testAcceptOperationResetsOnNewDrag() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=1")
        XCTAssertEqual(c.acceptedDropOperation, 1)
        // A new drag cycle starts with no reply yet.
        c.dragEntered(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        XCTAssertNil(c.acceptedDropOperation)
    }

    func testAcceptOperationClearedOnDropCompletion() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=1")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:o=1")  // completion
        XCTAssertNil(c.acceptedDropOperation)
    }

    // A stale accept must not survive into a later drag that enters while the
    // program is momentarily not accepting, then re-registers.
    func testAcceptOperationClearedOnReRegistration() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=1")
        XCTAssertEqual(c.acceptedDropOperation, 1)
        c.handleInboundSequence("t=a;text/plain")  // re-register
        XCTAssertNil(c.acceptedDropOperation)
    }

    func testAcceptOperationResetsOnExit() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.dragEntered(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0,
                      operations: 3, mimeTypes: ["text/plain"])
        c.handleInboundSequence("t=m:o=1")
        c.dragExited()
        XCTAssertNil(c.acceptedDropOperation)
    }

    // MARK: - Drop completion (t=r:o=operation) (#2)

    // Spec: "Once the client program finishes reading all the dropped data it
    // needs, it must send t=r:o=operation." This is the completion signal, not a
    // data request, so it must not draw an error reply.
    func testDropCompletionIsNotAnError() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"],
                                         dataByIndex: [1: Data("hi".utf8)]))
        c.handleInboundSequence("t=r:o=1")
        XCTAssertNil(recorder.messages.first(where: { $0.type == "R" }),
                     "the drop-completion signal must not produce an error")
        XCTAssertEqual(c.lastCompletedDropOperation, 1)
    }

    // Spec: "If unset (aka 0) the terminal must assume the drop was canceled."
    func testDropCompletionWithZeroOperationIsCancel() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:o=0")
        XCTAssertEqual(c.lastCompletedDropOperation, 0)
    }

    // After completion the per-drop state is gone: a later data request errors
    // and an open directory handle is invalid ("Any queued data requests must be
    // discarded by the terminal").
    func testDropCompletionDiscardsDropStateAndHandles() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("A".utf8).write(to: sub.appendingPathComponent("a.txt"))
        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [sub], recorder: recorder)
        let dirResp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        let handle = dirResp?.metadata["X"]
        XCTAssertNotNil(handle)

        c.handleInboundSequence("t=r:o=1")

        let staleHandle = await awaitResponse(recorder, c, "t=r:Y=\(handle!):x=1")
        XCTAssertEqual(staleHandle?.type, "R")
        let staleData = await awaitResponse(recorder, c, "t=r:x=1")
        XCTAssertEqual(staleData?.type, "R")
    }

    // MARK: - Error-code conformance (#8)

    // The spec: "Terminals must reply with ENOENT if the index is out of bounds."
    func testOutOfBoundsMimeIndexReturnsENOENT() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/plain"]))
        c.handleInboundSequence("t=r:x=5")
        XCTAssertEqual(recorder.last?.type, "R")
        XCTAssertEqual(recorder.last?.textPayload, "ENOENT")
    }

    // The spec: "Terminals must respond with EINVAL if the file is not a regular
    // file or symlink or directory." A FIFO is such a file; it must also never be
    // opened for reading (that would block), so EINVAL comes from a type check.
    func testNonRegularFileReturnsEINVAL() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fifo = dir.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        let recorder = Recorder()
        let c = remoteDropController(fileURLs: [fifo], recorder: recorder)
        let resp = await awaitResponse(recorder, c, "t=r:x=1:y=1")
        XCTAssertEqual(resp?.type, "R")
        XCTAssertEqual(resp?.textPayload, "EINVAL")
    }

    // MARK: - Machine-id registration (#10)

    // "t=a:x=1 ; machine id" registers the peer's machine id. It is a separate
    // escape code from the MIME-list registration and must not clear the MIME
    // types the program previously announced.
    func testMachineIdRegistrationPreservesMimes() {
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/plain text/uri-list")
        XCTAssertEqual(c.acceptedMimeTypes, ["text/plain", "text/uri-list"])
        c.handleInboundSequence("t=a:x=1;\(peerID)")
        XCTAssertEqual(c.acceptedMimeTypes, ["text/plain", "text/uri-list"],
                       "a machine-id registration must not wipe the accepted MIME list")
        // And the machine id took effect: a uri-list drop is now cross-machine.
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"],
                                         fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")]))
        c.handleInboundSequence("t=r:x=1")
        XCTAssertEqual(reassembledDataResponse(recorder)?.metadata["X"], "1")
    }

    // MARK: - Directory file:// URIs end with "/" (#6)

    // The spec: "All file:// URLs that point to directories must end with a /."
    func testDirectoryURIListEntryHasTrailingSlash() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Build a directory URL WITHOUT a trailing slash to prove the controller
        // adds it based on the on-disk type, not the incoming URL's shape.
        let noSlash = URL(fileURLWithPath: dir.path, isDirectory: false)
        XCTAssertFalse(noSlash.absoluteString.hasSuffix("/"))
        let recorder = Recorder()
        let c = makeController(endpoint: FakeEndpoint(isRemoteHost: false), recorder: recorder)
        c.handleInboundSequence("t=a;text/uri-list")
        c.performDrop(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0, operations: 1,
                      drop: FakeDropData(mimeTypes: ["text/uri-list"], fileURLs: [noSlash]))
        c.handleInboundSequence("t=r:x=1")
        let uriList = String(data: reassembledDataResponse(recorder)?.dataPayload ?? Data(),
                             encoding: .utf8)
        XCTAssertEqual(uriList?.hasSuffix("/"), true,
                       "a directory entry in the uri-list must end with a slash")
    }
}
