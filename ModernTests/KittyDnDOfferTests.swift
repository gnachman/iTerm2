//
//  KittyDnDOfferTests.swift
//  iTerm2 ModernTests
//
//  Phase 3 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Drives the controller's offer / start-drag state
//  machine (a program dragging its own data OUT of the terminal) with a fake
//  drag host, and asserts the OSC 72 traffic and the native-drag handoff.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDOfferTests: XCTestCase {
    // MARK: - Fakes

    private final class Recorder {
        var reports: [String] = []
        var onReport: ((KittyDnDMessage) -> Void)?
        func report(_ serialized: String) {
            reports.append(serialized)
            onReport?(KittyDnDAcceptTests.parse(serialized))
        }
        var messages: [KittyDnDMessage] { reports.map { KittyDnDAcceptTests.parse($0) } }
        var last: KittyDnDMessage? { messages.last }
    }

    private final class FakeDragHost: KittyDnDDragHost {
        var begun: [KittyDnDDragOffer] = []
        var cancelCount = 0
        var beginResult = true
        func beginDrag(_ offer: KittyDnDDragOffer) -> Bool {
            begun.append(offer)
            return beginResult
        }
        func cancelDrag() { cancelCount += 1 }
    }

    private final class FakeEndpoint: KittyDnDEndpoint {
        var isRemoteHost = false
    }

    private let ourID = KittyDnDMachineID.hashed("us")

    private func makeController(host: FakeDragHost,
                               recorder: Recorder) -> KittyDnDController {
        return KittyDnDController(ourMachineID: ourID,
                                 endpoint: FakeEndpoint(),
                                 dragHost: host) { recorder.report($0) }
    }

    private func presend(_ c: KittyDnDController, index: Int, data: Data) {
        c.handleInboundSequence(
            KittyDnDMessage(metadata: ["t": "p", "x": String(index)],
                            dataPayload: data).serializedContent())
    }

    // MARK: - Enable / disable

    func testEnableOffering() {
        let recorder = Recorder()
        let c = makeController(host: FakeDragHost(), recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        XCTAssertTrue(c.isOfferingDrags)
    }

    func testDisableOffering() {
        let recorder = Recorder()
        let c = makeController(host: FakeDragHost(), recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.handleInboundSequence("t=o:x=2")
        XCTAssertFalse(c.isOfferingDrags)
    }

    // MARK: - Gesture notification

    func testGestureSendsOfferNotification() {
        let recorder = Recorder()
        let c = makeController(host: FakeDragHost(), recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 4, cellY: 5, pixelX: 6, pixelY: 7)
        let m = recorder.last
        XCTAssertEqual(m?.type, "o")
        XCTAssertEqual(m?.intValue("x"), 4)
        XCTAssertEqual(m?.intValue("y"), 5)
        XCTAssertEqual(m?.intValue("X"), 6)
        XCTAssertEqual(m?.intValue("Y"), 7)
    }

    func testGestureInertWhenNotOffering() {
        let recorder = Recorder()
        let c = makeController(host: FakeDragHost(), recorder: recorder)
        c.dragGestureDetected(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0)
        XCTAssertTrue(recorder.reports.isEmpty)
    }

    // MARK: - Start drag

    func testStartDragBeginsNativeDragAndAcks() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = makeController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/plain")
        presend(c, index: 0, data: Data("hello".utf8))
        c.handleInboundSequence("t=P:x=-1")

        XCTAssertEqual(host.begun.count, 1)
        let offer = host.begun.first
        XCTAssertEqual(offer?.mimeTypes, ["text/plain"])
        XCTAssertEqual(offer?.data[0], Data("hello".utf8))
        XCTAssertEqual(offer?.operations, 1)

        // Acked with t=E ; OK.
        XCTAssertEqual(recorder.last?.type, "E")
        XCTAssertEqual(recorder.last?.textPayload, "OK")
    }

    func testImageThumbnailIsRecorded() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = makeController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/plain")
        presend(c, index: 0, data: Data("hi".utf8))
        // Image at negative index with format/size metadata.
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        c.handleInboundSequence(
            KittyDnDMessage(metadata: ["t": "p", "x": "-1", "y": "100", "X": "10", "Y": "20"],
                            dataPayload: png).serializedContent())
        c.handleInboundSequence("t=P:x=-1")

        let image = host.begun.first?.image
        XCTAssertEqual(image?.format, 100)
        XCTAssertEqual(image?.width, 10)
        XCTAssertEqual(image?.height, 20)
        XCTAssertEqual(image?.data, png)
    }

    func testChunkedPreSendIsReassembled() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = makeController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;application/octet-stream")
        let big = Data((0..<8000).map { UInt8($0 & 0xff) })
        for msg in KittyDnDChunker.messages(baseMetadata: ["t": "p", "x": "0"], data: big) {
            c.handleInboundSequence(msg.serializedContent())
        }
        c.handleInboundSequence("t=P:x=-1")
        XCTAssertEqual(host.begun.first?.data[0], big)
    }

    func testStartDragWithoutHostReportsError() {
        let recorder = Recorder()
        // No host.
        let c = KittyDnDController(ourMachineID: ourID, endpoint: FakeEndpoint(),
                                  dragHost: nil) { recorder.report($0) }
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/plain")
        presend(c, index: 0, data: Data("hello".utf8))
        c.handleInboundSequence("t=P:x=-1")
        XCTAssertEqual(recorder.last?.type, "E")
        XCTAssertNotEqual(recorder.last?.textPayload, "OK")
    }

    // MARK: - Drag lifecycle events (host -> controller -> t=e)

    private func startedController(host: FakeDragHost, recorder: Recorder) -> KittyDnDController {
        let c = makeController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=3;text/plain")
        presend(c, index: 0, data: Data("hello".utf8))
        c.handleInboundSequence("t=P:x=-1")
        return c
    }

    func testLifecycleAccepted() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        c.dragAccepted(preferredMimeIndex: 2)
        XCTAssertEqual(recorder.last?.type, "e")
        XCTAssertEqual(recorder.last?.intValue("x"), 1)
        XCTAssertEqual(recorder.last?.intValue("y"), 2)
    }

    func testLifecycleActionChanged() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        c.dragActionChanged(operation: 2)
        XCTAssertEqual(recorder.last?.type, "e")
        XCTAssertEqual(recorder.last?.intValue("x"), 2)
        XCTAssertEqual(recorder.last?.intValue("o"), 2)
    }

    func testLifecycleDropped() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        c.dragDropped()
        XCTAssertEqual(recorder.last?.type, "e")
        XCTAssertEqual(recorder.last?.intValue("x"), 3)
    }

    func testLifecycleFinishedCanceled() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        c.dragFinished(canceled: true)
        XCTAssertEqual(recorder.last?.type, "e")
        XCTAssertEqual(recorder.last?.intValue("x"), 4)
        XCTAssertEqual(recorder.last?.intValue("y"), 1)
        // Offering stays enabled for the next drag.
        XCTAssertTrue(c.isOfferingDrags)
    }

    // MARK: - Lazy data request round trip

    func testLazyDataRequestRoundTrip() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)

        var delivered: Data?
        c.requestDragData(mimeIndex: 0) { delivered = $0 }
        // Controller asked the program for the data.
        XCTAssertEqual(recorder.last?.type, "e")
        XCTAssertEqual(recorder.last?.intValue("x"), 5)
        XCTAssertEqual(recorder.last?.intValue("y"), 0)

        // Program replies with the bytes.
        c.handleInboundSequence(
            KittyDnDMessage(metadata: ["t": "e", "y": "0"],
                            dataPayload: Data("lazy".utf8)).serializedContent())
        XCTAssertEqual(delivered, Data("lazy".utf8))
    }

    func testLazyDataRequestErrorDeliversNil() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        var called = false
        var delivered: Data? = Data("sentinel".utf8)
        c.requestDragData(mimeIndex: 0) { called = true; delivered = $0 }
        // Program reports an error for the request.
        c.handleInboundSequence("t=E:y=0;ENOENT:missing")
        XCTAssertTrue(called)
        XCTAssertNil(delivered)
    }

    // MARK: - Cancel

    func testInboundCancelCancelsNativeDrag() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = startedController(host: host, recorder: recorder)
        c.handleInboundSequence("t=E:y=-1")
        XCTAssertEqual(host.cancelCount, 1)
    }

    // Re-requesting the same index must not leak the first completion.
    func testDoubleDataRequestFailsFirstCompletion() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        var firstResult: Data? = Data("sentinel".utf8)
        var firstCalled = false
        c.requestDragData(mimeIndex: 0) { firstCalled = true; firstResult = $0 }
        c.requestDragData(mimeIndex: 0) { _ in }
        XCTAssertTrue(firstCalled)
        XCTAssertNil(firstResult)
    }

    // A pending request must be drained (with nil) when the drag finishes.
    func testFinishDrainsPendingRequestWithNil() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        var called = false
        var result: Data? = Data("sentinel".utf8)
        c.requestDragData(mimeIndex: 0) { called = true; result = $0 }
        c.dragFinished(canceled: false)
        XCTAssertTrue(called)
        XCTAssertNil(result)
    }

    // Disabling offering drains a pending data request with nil.
    func testDisableOfferingDrainsPendingRequestWithNil() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        var called = false
        var result: Data? = Data("sentinel".utf8)
        c.requestDragData(mimeIndex: 0) { called = true; result = $0 }
        c.handleInboundSequence("t=o:x=2")
        XCTAssertTrue(called)
        XCTAssertNil(result)
        XCTAssertFalse(c.isOfferingDrags)
    }

    // MARK: - Remote drag-out (t=k)

    private func remoteOfferController(host: FakeDragHost,
                                      recorder: Recorder) -> KittyDnDController {
        let endpoint = FakeEndpoint()
        endpoint.isRemoteHost = true
        return KittyDnDController(ourMachineID: ourID, endpoint: endpoint,
                                 dragHost: host) { recorder.report($0) }
    }

    func testRemoteFileDragFetchesBytesViaTK() async throws {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = remoteOfferController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/uri-list")
        presend(c, index: 0, data: Data("file:///remote/a.txt".utf8))

        let started = expectation(description: "drag started")
        started.assertForOverFulfill = false
        recorder.onReport = { msg in
            if msg.type == "k", let x = msg.metadata["x"] {
                // Serve the remote file's bytes (no X => regular file).
                c.handleInboundSequence(
                    KittyDnDMessage(metadata: ["t": "k", "x": x],
                                    dataPayload: Data("hello".utf8)).serializedContent())
            } else if msg.type == "E" {
                started.fulfill()
            }
        }
        c.handleInboundSequence("t=P:x=-1")
        await fulfillment(of: [started], timeout: 5)

        XCTAssertEqual(recorder.messages.last { $0.type == "E" }?.textPayload, "OK")
        XCTAssertEqual(host.begun.count, 1)
        // The offer now points at a local temp copy holding the fetched bytes.
        let uriData = try XCTUnwrap(host.begun.first?.data[0])
        let url = try XCTUnwrap(URL(string: String(decoding: uriData, as: UTF8.self)))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "a.txt")
        XCTAssertEqual(try Data(contentsOf: url), Data("hello".utf8))
    }

    func testRemoteDirectoryDragIsFetchedRecursively() async throws {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = remoteOfferController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/uri-list")
        presend(c, index: 0, data: Data("file:///remote/dir".utf8))

        let started = expectation(description: "drag started")
        started.assertForOverFulfill = false
        recorder.onReport = { msg in
            if msg.type == "k" {
                if let x = msg.metadata["x"], msg.metadata["Y"] == nil {
                    // Top-level entry is a directory (X=handle) with two children.
                    c.handleInboundSequence(
                        KittyDnDMessage(metadata: ["t": "k", "x": x, "X": "7"],
                                        dataPayload: Data("a.txt\u{0}b.txt".utf8)).serializedContent())
                } else if let parent = msg.metadata["Y"], let child = msg.metadata["y"] {
                    let content = child == "1" ? "A" : "B"
                    c.handleInboundSequence(
                        KittyDnDMessage(metadata: ["t": "k", "Y": parent, "y": child],
                                        dataPayload: Data(content.utf8)).serializedContent())
                }
            } else if msg.type == "E" {
                started.fulfill()
            }
        }
        c.handleInboundSequence("t=P:x=-1")
        await fulfillment(of: [started], timeout: 5)

        let uriData = try XCTUnwrap(host.begun.first?.data[0])
        let dirURL = try XCTUnwrap(URL(string: String(decoding: uriData, as: UTF8.self)))
        defer { try? FileManager.default.removeItem(at: dirURL.deletingLastPathComponent()) }
        XCTAssertEqual(dirURL.lastPathComponent, "dir")
        XCTAssertEqual(try Data(contentsOf: dirURL.appendingPathComponent("a.txt")), Data("A".utf8))
        XCTAssertEqual(try Data(contentsOf: dirURL.appendingPathComponent("b.txt")), Data("B".utf8))
    }

    // A single remote drag with several uri-list entries; `respond` serves each
    // t=k request. Returns the local temp URLs from the started drag's offer.
    private func runRemoteDrag(uriList: String,
                              respond: @escaping (KittyDnDMessage, KittyDnDController) -> Void)
        async throws -> [URL] {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = remoteOfferController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/uri-list")
        presend(c, index: 0, data: Data(uriList.utf8))
        let done = expectation(description: "drag or error")
        done.assertForOverFulfill = false
        recorder.onReport = { msg in
            if msg.type == "k" { respond(msg, c) } else if msg.type == "E" { done.fulfill() }
        }
        c.handleInboundSequence("t=P:x=-1")
        await fulfillment(of: [done], timeout: 5)
        guard let uriData = host.begun.first?.data[0] else { return [] }
        return String(decoding: uriData, as: UTF8.self)
            .split(separator: "\r\n").map(String.init).compactMap { URL(string: $0) }
    }

    // A regular file may be flagged explicitly with X=0 (not just absent X); it
    // must be treated as a file, not directory handle 0.
    func testRemoteFileWithExplicitX0IsRegularFile() async throws {
        let urls = try await runRemoteDrag(uriList: "file:///remote/a.txt") { msg, c in
            c.handleInboundSequence(
                KittyDnDMessage(metadata: ["t": "k", "x": msg.metadata["x"]!, "X": "0"],
                                dataPayload: Data("hello".utf8)).serializedContent())
        }
        XCTAssertEqual(urls.count, 1)
        defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent().deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data("hello".utf8))
    }

    // Two offered files with the same basename must not overwrite each other.
    func testRemoteDuplicateBasenamesDoNotCollide() async throws {
        let urls = try await runRemoteDrag(uriList: "file:///a/x.txt\r\nfile:///b/x.txt") { msg, c in
            let content = msg.metadata["x"] == "1" ? "AAA" : "BBB"
            c.handleInboundSequence(
                KittyDnDMessage(metadata: ["t": "k", "x": msg.metadata["x"]!],
                                dataPayload: Data(content.utf8)).serializedContent())
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertNotEqual(urls[0], urls[1])
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data("AAA".utf8))
        XCTAssertEqual(try Data(contentsOf: urls[1]), Data("BBB".utf8))
        try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent().deletingLastPathComponent())
    }

    // A symlink entry (X=1) is skipped, not materialized, and does not appear in
    // the drag (its target is untrusted and meaningless on this machine).
    func testRemoteSymlinkEntryIsSkipped() async throws {
        let urls = try await runRemoteDrag(uriList: "file:///a.txt\r\nfile:///evil-link") { msg, c in
            if msg.metadata["x"] == "1" {
                c.handleInboundSequence(
                    KittyDnDMessage(metadata: ["t": "k", "x": "1"],
                                    dataPayload: Data("hello".utf8)).serializedContent())
            } else {
                // Symlink pointing at a local secret.
                c.handleInboundSequence(
                    KittyDnDMessage(metadata: ["t": "k", "x": "2", "X": "1"],
                                    dataPayload: Data("/Users/victim/.ssh/id_rsa".utf8)).serializedContent())
            }
        }
        XCTAssertEqual(urls.count, 1, "the symlink must be dropped from the drag")
        XCTAssertEqual(urls[0].lastPathComponent, "a.txt")
        try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent().deletingLastPathComponent())
    }

    // reset() (a new prompt) drains a pending data request with nil.
    func testResetDrainsPendingRequestWithNil() {
        let recorder = Recorder()
        let c = startedController(host: FakeDragHost(), recorder: recorder)
        var called = false
        var result: Data? = Data("sentinel".utf8)
        c.requestDragData(mimeIndex: 0) { called = true; result = $0 }
        c.reset()
        XCTAssertTrue(called)
        XCTAssertNil(result)
        XCTAssertFalse(c.isOfferingDrags)
    }

    // A bare t=o (neither x nor o) must not destroy an in-progress offer.
    func testBareOfferIsIgnored() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = makeController(host: host, recorder: recorder)
        c.handleInboundSequence("t=o:x=1")
        c.dragGestureDetected(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=1;text/plain")
        presend(c, index: 0, data: Data("hello".utf8))
        c.handleInboundSequence("t=o")  // bare, must be ignored
        c.handleInboundSequence("t=P:x=-1")
        XCTAssertEqual(host.begun.first?.mimeTypes, ["text/plain"])
        XCTAssertEqual(host.begun.first?.data[0], Data("hello".utf8))
    }

    // A second full offer cycle on the same controller must work (state resets).
    func testSecondOfferCycleReusesController() {
        let recorder = Recorder()
        let host = FakeDragHost()
        let c = startedController(host: host, recorder: recorder)  // first cycle
        c.dragFinished(canceled: false)

        // Second cycle with different content.
        c.dragGestureDetected(cellX: 1, cellY: 1, pixelX: 0, pixelY: 0)
        c.handleInboundSequence("t=o:o=2;text/uri-list")
        presend(c, index: 0, data: Data("world".utf8))
        c.handleInboundSequence("t=P:x=-1")
        XCTAssertEqual(host.begun.count, 2)
        XCTAssertEqual(host.begun.last?.mimeTypes, ["text/uri-list"])
        XCTAssertEqual(host.begun.last?.data[0], Data("world".utf8))
        XCTAssertEqual(host.begun.last?.operations, 2)
    }
}
