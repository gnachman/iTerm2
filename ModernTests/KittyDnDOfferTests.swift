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
        func report(_ serialized: String) { reports.append(serialized) }
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
        var canMaterializeFiles = false
        func materializeFile(named name: String, contents: Data) async throws -> String { "" }
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
