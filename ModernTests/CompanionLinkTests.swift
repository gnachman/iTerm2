//
//  CompanionLinkTests.swift
//  iTerm2 ModernTests
//
//  CompanionLink is the off-main endpoint of a phone connection. These tests
//  drive it the way a phone would, over an in-memory transport, and pin:
//
//    - It keeps answering hello and ping while the main queue is frozen by a
//      modal run loop started from a main-queue callout (the bug: iTerm2 Buddy
//      went dead whenever such an alert was up).
//    - What it answers itself versus what it forwards to the bridge, and that
//      forwarding preserves wire order with `.closed` last.
//    - The ordering guarantees the bridge used to get from running on the main
//      actor: no aiAvailabilityChanged before the hello reply, nothing but
//      hello/error/unpaired to a version-blocked peer, farewell before close.
//    - How link events classify a connection for the presence warning.
//

import XCTest
import os
import CompanionProtocol
@testable import iTerm2SharedARC

final class CompanionLinkTests: XCTestCase {
    // MARK: Fixture

    /// The phone's end of the connection.
    private final class Phone {
        let transport: CompanionLoopbackTransport

        init(transport: CompanionLoopbackTransport) {
            self.transport = transport
        }

        private static func encoder() -> JSONEncoder {
            let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
        }
        private static func decoder() -> JSONDecoder {
            let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
        }

        func send(_ payload: CompanionClientMessage, requestID: UInt64? = nil) async throws {
            let envelope = ClientEnvelope(requestID: requestID, payload: payload)
            try await transport.send(try Self.encoder().encode(envelope))
        }

        func sendRaw(_ data: Data) async throws {
            try await transport.send(data)
        }

        /// The next frame the Mac sent, described. Fails rather than hangs if
        /// nothing arrives.
        func next() async throws -> String {
            let transport = self.transport
            let data = try await FrozenMainQueue.withFailsafe("the next frame from the Mac") {
                try await transport.receive()
            }
            let envelope = try Self.decoder().decode(HostEnvelope.self, from: data)
            return CompanionLinkTests.describe(envelope)
        }

        /// The next frame the Mac sent, decoded.
        func nextEnvelope() async throws -> HostEnvelope {
            let transport = self.transport
            let data = try await FrozenMainQueue.withFailsafe("the next frame from the Mac") {
                try await transport.receive()
            }
            return try Self.decoder().decode(HostEnvelope.self, from: data)
        }

        /// Asserts the connection is closed with nothing further queued.
        func expectClosed(file: StaticString = #filePath, line: UInt = #line) async {
            let transport = self.transport
            do {
                let data = try await FrozenMainQueue.withFailsafe("the connection to close") {
                    try await transport.receive()
                }
                let text = String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
                XCTFail("expected the connection to be closed, but received: \(text)", file: file, line: line)
            } catch {
                XCTAssertFalse(error is FrozenMainQueue.Timeout,
                               "the connection never closed", file: file, line: line)
            }
        }

        func close() async {
            await transport.close()
        }
    }

    /// Stands in for the keychain-backed room secret store.
    private final class RoomSecretStore: Sendable {
        struct Unwritable: Error {}
        private let state = OSAllocatedUnfairLock(initialState: (stored: [Data](), fails: false))

        var stored: [Data] { state.withLock { $0.stored } }
        func failWrites() { state.withLock { $0.fails = true } }

        func store(_ secret: Data) throws {
            let fails = state.withLock { state -> Bool in
                if !state.fails {
                    state.stored.append(secret)
                }
                return state.fails
            }
            if fails {
                throw Unwritable()
            }
        }
    }

    /// Stands in for ModalAlertRegistry: the alerts "on screen", and what
    /// happens when one is answered.
    private final class FakeAlertSource: ModalAlertSource {
        struct Answer: Equatable, Sendable {
            let id: UUID
            let buttonIndex: Int
            let suppress: Bool
            var inputs: [String: String] = [:]
        }
        private struct State: Sendable {
            var alerts: [ModalAlertSnapshot] = []
            var observers: [@Sendable () -> Void] = []
            var answers: [Answer] = []
            var accepts = true
            /// When set, answer() suspends until release() is called.
            var holdsAnswers = false
            var held: [CheckedContinuation<Void, Never>] = []
        }
        private let state = OSAllocatedUnfairLock(initialState: State())

        var answers: [Answer] { state.withLock { $0.answers } }

        static func alert(_ heading: String, id: UUID = UUID(), isAppModal: Bool = true) -> ModalAlertSnapshot {
            return ModalAlertSnapshot(
                id: id,
                heading: heading,
                body: "Body of \(heading)",
                buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true),
                          .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
                suppressionLabel: "Remember my choice",
                hasAccessory: false,
                isAppModal: isAppModal)
        }

        /// Change what is on screen and tell the observers, as the registry does.
        func show(_ alerts: [ModalAlertSnapshot]) {
            let observers = state.withLock { state -> [@Sendable () -> Void] in
                state.alerts = alerts
                return state.observers
            }
            observers.forEach { $0() }
        }

        /// Tell the observers although nothing changed.
        func notifyWithoutChange() {
            state.withLock { $0.observers }.forEach { $0() }
        }

        func rejectAnswers() { state.withLock { $0.accepts = false } }
        func holdAnswers() { state.withLock { $0.holdsAnswers = true } }
        func releaseAnswers() {
            let held = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.holdsAnswers = false
                let held = state.held
                state.held = []
                return held
            }
            held.forEach { $0.resume() }
        }

        func currentAlerts() -> [ModalAlertSnapshot] {
            return state.withLock { $0.alerts }
        }

        func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
            state.withLock { $0.observers.append(changed) }
            return NSObject()
        }

        func answer(id: UUID, buttonIndex: Int, suppress: Bool, inputs: [String: String]) async -> Bool {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    state.answers.append(Answer(id: id, buttonIndex: buttonIndex, suppress: suppress, inputs: inputs))
                    if state.holdsAnswers {
                        state.held.append(continuation)
                        return false
                    }
                    return true
                }
                if resumeNow {
                    continuation.resume()
                }
            }
            return state.withLock { $0.accepts }
        }
    }

    /// Stands in for CompanionMainThreadMonitor.
    private final class FakeStallSource: CompanionMainStallSource {
        private let state = OSAllocatedUnfairLock(initialState: (blocked: false, observers: [@Sendable () -> Void]()))
        private let expedites = OSAllocatedUnfairLock(initialState: 0)

        /// How many times the link asked for a quick check.
        var expediteCount: Int { expedites.withLock { $0 } }

        func expedite() {
            expedites.withLock { $0 += 1 }
        }

        func setBlocked(_ blocked: Bool) {
            let observers = state.withLock { state -> [@Sendable () -> Void] in
                state.blocked = blocked
                return state.observers
            }
            observers.forEach { $0() }
        }

        func isMainBlocked() -> Bool {
            return state.withLock { $0.blocked }
        }

        func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
            state.withLock { $0.observers.append(changed) }
            return NSObject()
        }
    }

    private struct Fixture {
        let link: CompanionLink
        let phone: Phone
        let ai: CompanionAIAvailabilityCache
        let roomSecrets: RoomSecretStore
        let alerts: FakeAlertSource
        let stall: FakeStallSource
    }

    private func makeFixture(aiAvailable: Bool = true,
                             wantsNotificationPermission: Bool = false,
                             alertSource: ModalAlertSource? = nil,
                             start: Bool = true) -> Fixture {
        let (macEnd, phoneEnd) = CompanionLoopbackTransport.makePair()
        let ai = CompanionAIAvailabilityCache(aiAvailable)
        let roomSecrets = RoomSecretStore()
        let alerts = FakeAlertSource()
        let stall = FakeStallSource()
        let link = CompanionLink(transport: macEnd,
                                 aiAvailability: ai,
                                 wantsNotificationPermission: { wantsNotificationPermission },
                                 storeRoomSecret: { try roomSecrets.store($0) },
                                 alerts: alertSource ?? alerts,
                                 mainStall: stall)
        if start {
            link.start()
        }
        return Fixture(link: link, phone: Phone(transport: phoneEnd), ai: ai, roomSecrets: roomSecrets,
                       alerts: alerts, stall: stall)
    }

    private static let compatibleHello = CompanionClientMessage.hello(
        revision: CompanionProtocolVersion.current,
        minimumPeer: CompanionProtocolVersion.minimumPeer)
    private static let incompatibleHello = CompanionClientMessage.hello(revision: 9999, minimumPeer: 9999)
    /// A phone from before the mac-status revision. Still compatible.
    private static let revision13Hello = CompanionClientMessage.hello(revision: 13, minimumPeer: 11)

    // MARK: Describing frames and events

    private static func tag(_ requestID: UInt64?) -> String {
        return requestID.map { "#\($0)" } ?? ""
    }

    private static func describe(_ envelope: HostEnvelope) -> String {
        let name: String
        switch envelope.payload {
        case .hello(_, _, let wantsNotificationPermission, let aiAvailable, _):
            let wants = wantsNotificationPermission.map { "\($0)" } ?? "nil"
            let ai = aiAvailable.map { "\($0)" } ?? "nil"
            name = "hello(wantsNotificationPermission=\(wants), ai=\(ai))"
        case .pong:
            name = "pong"
        case .relayRoomSecretStored:
            name = "relayRoomSecretStored"
        case .error:
            name = "error"
        case .unpaired:
            name = "unpaired"
        case .aiAvailabilityChanged(let available):
            name = "aiAvailabilityChanged(\(available))"
        case .macStatusChanged(let status):
            name = "macStatus(" + describe(status) + ")"
        case .modalAlertAnswerRejected(let alertID):
            name = "answerRejected(\(alertID))"
        case .chatListChanged:
            name = "chatListChanged"
        default:
            name = "other"
        }
        return name + tag(envelope.requestID)
    }

    private static func describe(_ status: CompanionMacStatus?) -> String {
        guard let status else {
            return "none"
        }
        return "alerts=\(status.modalAlerts.map { $0.heading }), blocked=\(status.mainBlocked)"
    }

    /// The status a hello reply carried.
    private static func helloStatus(_ envelope: HostEnvelope) -> String {
        guard case .hello(_, _, _, _, let macStatus) = envelope.payload else {
            return "not a hello: " + describe(envelope)
        }
        return describe(macStatus)
    }

    private static func describe(_ payload: CompanionClientMessage) -> String {
        switch payload {
        case .hello(let revision, _):
            return "hello(\(revision))"
        case .ping:
            return "ping"
        case .relayRoomSecret:
            return "relayRoomSecret"
        case .answerModalAlert:
            return "answerModalAlert"
        case .sendKey:
            return "sendKey"
        case .pasteText:
            return "pasteText"
        case .listChatsAndSessions:
            return "listChatsAndSessions"
        case .unsubscribe(let chatID):
            return "unsubscribe(\(chatID))"
        case .messagesSince:
            return "messagesSince"
        case .syncSince:
            return "syncSince"
        default:
            return "other"
        }
    }

    private static func describe(_ event: CompanionLink.Event) -> String {
        switch event {
        case .envelope(let envelope, let handledByLink):
            return (handledByLink ? "handled " : "forwarded ") + describe(envelope.payload) + tag(envelope.requestID)
        case .helloCompleted(let peerRevision, let blocked):
            return "helloCompleted(\(peerRevision), blocked=\(blocked))"
        case .versionIncompatible:
            return "versionIncompatible"
        case .closed(let error):
            return error == nil ? "closed(locally)" : "closed(dropped)"
        }
    }

    /// Every event the link emitted, up to the end of its stream.
    private func allEvents(_ link: CompanionLink) async throws -> [CompanionLink.Event] {
        return try await FrozenMainQueue.withFailsafe("the link's event stream to end") {
            var events: [CompanionLink.Event] = []
            for await event in link.events {
                events.append(event)
            }
            return events
        }
    }

    private func allEventDescriptions(_ link: CompanionLink) async throws -> [String] {
        return try await allEvents(link).map { Self.describe($0) }
    }

    // MARK: The bug: answering while the main queue is frozen

    func testHelloIsAnsweredWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture(aiAvailable: true)
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(Self.compatibleHello, requestID: 7)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "hello(wantsNotificationPermission=false, ai=true)#7")
        }
    }

    func testPingIsAnsweredWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(.ping, requestID: 2)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "pong#2")
        }
    }

    /// A link created and started on the main thread, in the same callout that
    /// then freezes, must still come up: nothing in start() may wait for a
    /// main-actor hop.
    func testLinkStartedInsideTheFreezingCalloutStillAnswers() async throws {
        let fixture = makeFixture(start: false)
        try await FrozenMainQueue.run(setup: {
            fixture.link.start()
        }) { _ in
            try await fixture.phone.send(Self.compatibleHello, requestID: 1)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "hello(wantsNotificationPermission=false, ai=true)#1")
        }
    }

    /// A poke and a send made on the main thread just before it freezes must
    /// still reach the phone during the freeze.
    func testPokeAndSendMadeInsideTheFreezingCalloutReachThePhone() async throws {
        let fixture = makeFixture(aiAvailable: true)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await FrozenMainQueue.run(setup: {
            fixture.link.send(.chatListChanged(chats: []), requestID: nil)
            fixture.ai.value = false
            fixture.link.poke(.aiAvailability)
        }) { _ in
            let first = try await fixture.phone.next()
            let second = try await fixture.phone.next()
            XCTAssertEqual(first, "chatListChanged")
            XCTAssertEqual(second, "aiAvailabilityChanged(false)")
        }
    }

    /// A reconnecting phone couriers the relay room secret BEFORE it says
    /// hello, and waits for the ack. If that waited for the main actor, the
    /// phone could not get as far as hello while the main queue was frozen.
    func testRoomSecretIsStoredAndAckedWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        let secret = Data(repeating: 7, count: 32)
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(.relayRoomSecret(secret), requestID: 4)
            let ack = try await fixture.phone.next()
            XCTAssertEqual(ack, "relayRoomSecretStored#4")
            try await fixture.phone.send(Self.compatibleHello, requestID: 5)
            let hello = try await fixture.phone.next()
            XCTAssertEqual(hello, "hello(wantsNotificationPermission=false, ai=true)#5")
        }
        XCTAssertEqual(fixture.roomSecrets.stored, [secret])
    }

    // MARK: Room secret

    func testRoomSecretStoreFailureWithholdsTheAck() async throws {
        let fixture = makeFixture()
        fixture.roomSecrets.failWrites()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 4)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#4", "the phone retries on its next connection")
        XCTAssertEqual(fixture.roomSecrets.stored, [])
    }

    /// The link answers the courier, but the bridge still sees it, because it
    /// classifies the connection as interactive just as it did before.
    func testRoomSecretIsForwardedAsHandledAndClassifiesAsUnsolicited() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 4)
        _ = try await fixture.phone.next()
        await fixture.phone.close()
        let events = try await allEvents(fixture.link)
        XCTAssertEqual(events.map { Self.describe($0) }, ["handled relayRoomSecret#4", "closed(dropped)"])
        XCTAssertEqual(classification(of: events), .unsolicited)
    }

    func testVersionBlockedPeerCannotStoreARoomSecret() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 2)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#2")
        XCTAssertEqual(fixture.roomSecrets.stored, [])
    }

    // MARK: Hello

    func testHelloReplyCarriesCachedAIAvailabilityAndNotificationWish() async throws {
        let fixture = makeFixture(aiAvailable: false, wantsNotificationPermission: true)
        try await fixture.phone.send(Self.compatibleHello, requestID: 3)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "hello(wantsNotificationPermission=true, ai=false)#3")
    }

    func testCompatibleHelloEmitsEnvelopeThenHelloCompleted() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "closed(dropped)"])
    }

    // MARK: AI availability ordering

    func testAIAvailabilityChangeBeforeHelloSendsNothing() async throws {
        let fixture = makeFixture(aiAvailable: true)
        fixture.ai.value = false
        fixture.link.poke(.aiAvailability)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        // Whichever of the poke and the hello the link sees first, the phone's
        // first frame is the hello reply carrying the current value, and no
        // change event follows it.
        let first = try await fixture.phone.next()
        XCTAssertEqual(first, "hello(wantsNotificationPermission=false, ai=false)#1")
        try await fixture.phone.send(.ping, requestID: 2)
        let second = try await fixture.phone.next()
        XCTAssertEqual(second, "pong#2")
    }

    func testAIAvailabilityChangeAfterHelloIsSentOnceAndDeduped() async throws {
        let fixture = makeFixture(aiAvailable: true)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        // An unchanged value sends nothing; a changed one sends exactly one
        // event no matter how many pokes announce it.
        fixture.link.poke(.aiAvailability)
        fixture.ai.value = false
        fixture.link.poke(.aiAvailability)
        fixture.link.poke(.aiAvailability)
        let first = try await fixture.phone.next()
        XCTAssertEqual(first, "aiAvailabilityChanged(false)")

        // Pokes are processed in order, so a duplicate "false" would have to
        // come out before this "true".
        fixture.ai.value = true
        fixture.link.poke(.aiAvailability)
        let second = try await fixture.phone.next()
        XCTAssertEqual(second, "aiAvailabilityChanged(true)")
    }

    // MARK: Version-blocked peers

    func testVersionBlockedPeerGetsErrorsAndNothingIsForwarded() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        let helloReply = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello(wantsNotificationPermission=false, ai=true)#1")

        try await fixture.phone.send(.listChatsAndSessions, requestID: 2)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#2")
        // Even ping is refused: a blocked peer is served nothing but a re-hello.
        try await fixture.phone.send(.ping, requestID: 3)
        let pingRefusal = try await fixture.phone.next()
        XCTAssertEqual(pingRefusal, "error#3")

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(9999)#1",
                                "helloCompleted(9999, blocked=true)",
                                "versionIncompatible",
                                "closed(dropped)"])
    }

    func testBlockedPeerIsUnblockedByALaterCompatibleHello() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(Self.compatibleHello, requestID: 2)
        let helloReply = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello(wantsNotificationPermission=false, ai=true)#2")
        try await fixture.phone.send(.ping, requestID: 3)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#3")

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(9999)#1",
                                "helloCompleted(9999, blocked=true)",
                                "versionIncompatible",
                                "handled hello(\(CompanionProtocolVersion.current))#2",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "handled ping#3",
                                "closed(dropped)"])
    }

    /// The bridge learns that the peer is blocked through an event, which lags
    /// while the main actor is busy. In that gap it may still push; the link
    /// must drop the push. The unpair farewell is the exception: a blocked phone
    /// still has to learn it was unpaired.
    func testPushesToBlockedPeerAreDroppedButTheFarewellIsDelivered() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.send(.chatListChanged(chats: []), requestID: nil)
        fixture.link.send(.aiAvailabilityChanged(available: false), requestID: nil)
        await fixture.link.sendFarewellAndClose()

        let frame = try await fixture.phone.next()
        XCTAssertEqual(frame, "unpaired")
        await fixture.phone.expectClosed()
    }

    // MARK: Forwarding

    func testEnvelopesAreForwardedInWireOrderAndClosedIsLast() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        try await fixture.phone.send(.listChatsAndSessions, requestID: 2)
        try await fixture.phone.send(.ping, requestID: 3)
        try await fixture.phone.send(.unsubscribe(chatID: "a"))
        try await fixture.phone.send(.unsubscribe(chatID: "b"))
        // The two replies the link owes prove it has read that far.
        let helloReply = try await fixture.phone.next()
        let pong = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello(wantsNotificationPermission=false, ai=true)#1")
        XCTAssertEqual(pong, "pong#3")
        await fixture.phone.close()

        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "forwarded listChatsAndSessions#2",
                                "handled ping#3",
                                "forwarded unsubscribe(a)",
                                "forwarded unsubscribe(b)",
                                "closed(dropped)"])
    }

    func testUndecodableFrameIsDroppedAndTheLinkKeepsGoing() async throws {
        let fixture = makeFixture()
        try await fixture.phone.sendRaw(Data("not json".utf8))
        try await fixture.phone.send(.ping, requestID: 1)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#1")
        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled ping#1", "closed(dropped)"])
    }

    // MARK: Sending and shutdown

    func testSendsReachThePhoneInCallOrder() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.link.send(.pong, requestID: 10)
        fixture.link.send(.chatListChanged(chats: []), requestID: nil)
        fixture.link.send(.pong, requestID: 11)
        let first = try await fixture.phone.next()
        let second = try await fixture.phone.next()
        let third = try await fixture.phone.next()
        XCTAssertEqual([first, second, third], ["pong#10", "chatListChanged", "pong#11"])
    }

    func testFarewellIsTheLastFrameAndThenTheConnectionCloses() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.send(.chatListChanged(chats: []), requestID: nil)
        await fixture.link.sendFarewellAndClose()

        let first = try await fixture.phone.next()
        let second = try await fixture.phone.next()
        XCTAssertEqual([first, second], ["chatListChanged", "unpaired"])
        await fixture.phone.expectClosed()

        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events.last, "closed(locally)")
    }

    func testCloseEndsTheConnectionAndReportsALocalClose() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(.ping, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.close()
        fixture.link.close()  // idempotent

        await fixture.phone.expectClosed()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNil(error, "a deliberate close is not a drop")
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled ping#1", "closed(locally)"])
    }

    /// Closing a link that was never started must still close the transport,
    /// or the underlying connection would stay open with nothing reading it.
    func testCloseBeforeStartClosesTheTransport() async throws {
        let fixture = makeFixture(start: false)
        fixture.link.close()

        await fixture.phone.expectClosed()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNil(error)
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["closed(locally)"])
        // A late start() must not revive it.
        fixture.link.start()
        await fixture.phone.expectClosed()
    }

    func testRemoteCloseIsReportedAsADrop() async throws {
        let fixture = makeFixture()
        await fixture.phone.close()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNotNil(error, "the phone going away is a drop")
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["closed(dropped)"])
    }

    func testWaitUntilClosedReturnsImmediatelyOnceClosed() async throws {
        let fixture = makeFixture()
        XCTAssertFalse(fixture.link.isClosed)
        await fixture.phone.close()
        let link = fixture.link
        for _ in 0..<2 {
            let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
                await link.waitUntilClosed()
            }
            XCTAssertNotNil(error)
        }
        XCTAssertTrue(fixture.link.isClosed)
    }

    // MARK: Mac status

    func testHelloReplyCarriesTheMacStatus() async throws {
        let fixture = makeFixture()
        fixture.alerts.show([FakeAlertSource.alert("Bottom"), FakeAlertSource.alert("Top")])
        fixture.stall.setBlocked(true)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        let reply = try await fixture.phone.nextEnvelope()
        XCTAssertEqual(Self.helloStatus(reply), "alerts=[\"Bottom\", \"Top\"], blocked=true")
        // The status was already in the hello, so no change event follows it.
        try await fixture.phone.send(.ping, requestID: 2)
        let next = try await fixture.phone.next()
        XCTAssertEqual(next, "pong#2")
    }

    func testAlertIsDescribedInFull() async throws {
        let fixture = makeFixture()
        let id = UUID()
        fixture.alerts.show([FakeAlertSource.alert("Heading", id: id, isAppModal: false)])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        guard case .hello(_, _, _, _, let macStatus) = try await fixture.phone.nextEnvelope().payload else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(macStatus, CompanionMacStatus(
            modalAlerts: [CompanionModalAlert(
                id: id.uuidString,
                heading: "Heading",
                body: "Body of Heading",
                buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true),
                          .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
                suppressionLabel: "Remember my choice",
                hasAccessory: false,
                isAppModal: false)],
            mainBlocked: false))
    }

    /// An alert that asks for values: the phone is told what to ask for, and
    /// what it sends back reaches the alert with the answer.
    func testInputsAreSentWithTheAlertAndReturnedWithTheAnswer() async throws {
        let fixture = makeFixture()
        let id = UUID()
        let snapshot = ModalAlertSnapshot(
            id: id,
            heading: "Paste",
            body: "",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true)],
            suppressionLabel: nil,
            inputs: [.init(id: "name", label: nil, kind: .text, value: "draft"),
                     .init(id: "spaces", label: "Tab size in spaces:", kind: .integer(minimum: 0, maximum: 100),
                           value: "4")],
            hasAccessory: false,
            isAppModal: true)
        fixture.alerts.show([snapshot])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        guard case .hello(_, _, _, _, let macStatus) = try await fixture.phone.nextEnvelope().payload else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(macStatus?.modalAlerts.first?.inputs, [
            .init(id: "name", label: nil, kind: "text", value: "draft"),
            .init(id: "spaces", label: "Tab size in spaces:", kind: "integer", value: "4", minimum: 0, maximum: 100),
        ])

        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false,
                                                       inputs: ["name": "requests", "spaces": "8"]))
        try await FrozenMainQueue.withFailsafe("the answer to reach the alert source") {
            while fixture.alerts.answers.isEmpty {
                await Task.yield()
            }
        }
        XCTAssertEqual(fixture.alerts.answers, [.init(id: id, buttonIndex: 0, suppress: false,
                                                     inputs: ["name": "requests", "spaces": "8"])])
    }

    /// A secret input goes to the phone marked as one and without a value, and
    /// what the phone enters for it reaches the alert.
    func testSecretInputIsSentWithoutAValueAndItsAnswerIsDelivered() async throws {
        let fixture = makeFixture()
        let id = UUID()
        let snapshot = ModalAlertSnapshot(
            id: id,
            heading: "Log in",
            body: "",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: false)],
            suppressionLabel: nil,
            // A value should never get this far. If one does it still must not
            // leave the Mac.
            inputs: [.init(id: "password", label: "Password:", kind: .secret, value: "hunter2")],
            hasAccessory: false,
            isAppModal: true)
        fixture.alerts.show([snapshot])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        guard case .hello(_, _, _, _, let macStatus) = try await fixture.phone.nextEnvelope().payload else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(macStatus?.modalAlerts.first?.inputs, [
            .init(id: "password", label: "Password:", kind: "secret", value: ""),
        ])

        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false,
                                                       inputs: ["password": " correct horse "]))
        try await FrozenMainQueue.withFailsafe("the answer to reach the alert source") {
            while fixture.alerts.answers.isEmpty {
                await Task.yield()
            }
        }
        XCTAssertEqual(fixture.alerts.answers, [.init(id: id, buttonIndex: 0, suppress: false,
                                                     inputs: ["password": " correct horse "])])
    }

    func testOlderPhoneGetsNoMacStatus() async throws {
        let fixture = makeFixture()
        fixture.alerts.show([FakeAlertSource.alert("A")])
        try await fixture.phone.send(Self.revision13Hello, requestID: 1)
        let reply = try await fixture.phone.nextEnvelope()
        XCTAssertEqual(Self.helloStatus(reply), "none")
        // Nor any change event it could not decode.
        fixture.alerts.show([])
        fixture.stall.setBlocked(true)
        try await fixture.phone.send(.ping, requestID: 2)
        let next = try await fixture.phone.next()
        XCTAssertEqual(next, "pong#2")
    }

    func testVersionBlockedPhoneGetsNoMacStatus() async throws {
        let fixture = makeFixture()
        fixture.alerts.show([FakeAlertSource.alert("A")])
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        let reply = try await fixture.phone.nextEnvelope()
        XCTAssertEqual(Self.helloStatus(reply), "none")
        fixture.alerts.show([])
        try await fixture.phone.send(.ping, requestID: 2)
        let next = try await fixture.phone.next()
        XCTAssertEqual(next, "error#2")
    }

    func testStatusChangesArePushedOnceEach() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.alerts.notifyWithoutChange()
        fixture.alerts.show([FakeAlertSource.alert("A")])
        fixture.alerts.notifyWithoutChange()
        let first = try await fixture.phone.next()
        XCTAssertEqual(first, "macStatus(alerts=[\"A\"], blocked=false)")

        // Pokes are handled in order, so a duplicate of the first status would
        // have to come out before this one.
        fixture.stall.setBlocked(true)
        let second = try await fixture.phone.next()
        XCTAssertEqual(second, "macStatus(alerts=[\"A\"], blocked=true)")

        fixture.alerts.show([])
        let third = try await fixture.phone.next()
        XCTAssertEqual(third, "macStatus(alerts=[], blocked=true)")
    }

    func testStatusChangeBeforeHelloIsNotPushedSeparately() async throws {
        let fixture = makeFixture()
        fixture.alerts.show([FakeAlertSource.alert("A")])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        // Whichever of the change and the hello the link sees first, the first
        // frame is the hello reply carrying the status, and no event follows.
        let reply = try await fixture.phone.nextEnvelope()
        XCTAssertEqual(reply.requestID, 1)
        XCTAssertEqual(Self.helloStatus(reply), "alerts=[\"A\"], blocked=false")
        try await fixture.phone.send(.ping, requestID: 2)
        let next = try await fixture.phone.next()
        XCTAssertEqual(next, "pong#2")
    }

    /// The real registry: an alert registered on the main thread, in the same
    /// callout that then freezes, must reach the phone during the freeze. This
    /// is what an iTermWarning shown from a main-queue callout does.
    func testAlertRegisteredInsideTheFreezingCalloutReachesThePhone() async throws {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let fixture = makeFixture(alertSource: registry)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await FrozenMainQueue.run(setup: {
            let descriptor = ModalAlertDescriptor(heading: "Frozen", body: "", buttons: [],
                                                  suppressionLabel: nil, hasAccessory: false, isAppModal: true)
            _ = registry.register(descriptor, window: nil) { _, _ in true }
        }) { _ in
            let pushed = try await fixture.phone.next()
            XCTAssertEqual(pushed, "macStatus(alerts=[\"Frozen\"], blocked=false)")
        }
    }

    // MARK: Answering an alert

    func testAnswerIsPassedToTheAlertSource() async throws {
        let fixture = makeFixture()
        let id = UUID()
        fixture.alerts.show([FakeAlertSource.alert("A", id: id)])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 1, suppress: true))
        // Accepted answers get no reply of their own. The ping is a sync point:
        // a rejection would have been sent before the pong.
        try await fixture.phone.send(.ping, requestID: 2)
        var next = try await fixture.phone.next()
        if next != "pong#2" {
            XCTFail("unexpected frame after an accepted answer: \(next)")
            next = try await fixture.phone.next()
        }
        // The answer runs apart from the receive loop, so wait for it.
        try await FrozenMainQueue.withFailsafe("the answer to reach the alert source") {
            while fixture.alerts.answers.isEmpty {
                await Task.yield()
            }
        }
        XCTAssertEqual(fixture.alerts.answers, [.init(id: id, buttonIndex: 1, suppress: true)])
    }

    /// End to end with the real registry, while the main queue is frozen: the
    /// phone learns of the alert, answers it, and the press lands on the main
    /// thread.
    func testPhoneAnswersAnAlertWhileMainQueueIsFrozen() async throws {
        let registry = ModalAlertRegistry(modalWindow: { nil })
        let fixture = makeFixture(alertSource: registry)
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        let (presses, pressesContinuation) = AsyncStream<String>.makeStream()
        try await FrozenMainQueue.run(setup: {
            let descriptor = ModalAlertDescriptor(
                heading: "Frozen", body: "",
                buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true),
                          .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
                suppressionLabel: "Remember", hasAccessory: false, isAppModal: true)
            _ = registry.register(descriptor, window: nil) { index, suppress in
                pressesContinuation.yield("pressed \(index) suppress=\(suppress) main=\(Thread.isMainThread)")
                return true
            }
        }) { _ in
            guard case .macStatusChanged(let status) = try await fixture.phone.nextEnvelope().payload,
                  let alert = status.modalAlerts.last else {
                return XCTFail("expected the alert to be pushed")
            }
            try await fixture.phone.send(.answerModalAlert(alertID: alert.id, buttonIndex: 1, suppress: true))
            let press = try await FrozenMainQueue.withFailsafe("the button press") { () -> String? in
                for await press in presses {
                    return press
                }
                return nil
            }
            XCTAssertEqual(press, "pressed 1 suppress=true main=true")
        }
    }

    func testRejectedAnswerSendsARejectionAndThenTheCurrentStatus() async throws {
        let fixture = makeFixture()
        let id = UUID()
        fixture.alerts.show([FakeAlertSource.alert("A", id: id)])
        fixture.alerts.rejectAnswers()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false))
        let rejection = try await fixture.phone.next()
        let status = try await fixture.phone.next()
        XCTAssertEqual(rejection, "answerRejected(\(id.uuidString))")
        XCTAssertEqual(status, "macStatus(alerts=[\"A\"], blocked=false)",
                       "the status is sent again, though unchanged, so the phone is certain of what is showing")
    }

    func testAnswerWithAMalformedIDIsRejectedWithoutAskingTheAlertSource() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(.answerModalAlert(alertID: "not a uuid", buttonIndex: 0, suppress: false))
        let rejection = try await fixture.phone.next()
        let status = try await fixture.phone.next()
        XCTAssertEqual(rejection, "answerRejected(not a uuid)")
        XCTAssertEqual(status, "macStatus(alerts=[], blocked=false)")
        XCTAssertEqual(fixture.alerts.answers, [])
    }

    /// Pressing the button needs the main thread. If the main thread is busy in
    /// a way that keeps even that from running, the link must go on answering
    /// everything else.
    func testAPendingAnswerDoesNotHoldUpOtherRequests() async throws {
        let fixture = makeFixture()
        let id = UUID()
        fixture.alerts.show([FakeAlertSource.alert("A", id: id)])
        fixture.alerts.holdAnswers()
        fixture.alerts.rejectAnswers()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false))
        try await fixture.phone.send(.ping, requestID: 2)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#2", "the ping was answered while the answer was still pending")

        fixture.alerts.releaseAnswers()
        let rejection = try await fixture.phone.next()
        XCTAssertEqual(rejection, "answerRejected(\(id.uuidString))")
    }

    /// An answer is only meaningful from a phone that was told about the alert,
    /// which takes a completed hello at a revision that carries the status.
    func testAnswerIsIgnoredBeforeHelloAndFromAPhoneThatGetsNoStatus() async throws {
        let id = UUID()
        // No hello at all.
        let early = makeFixture()
        early.alerts.show([FakeAlertSource.alert("A", id: id)])
        try await early.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false))
        try await early.phone.send(.ping, requestID: 1)
        let pong = try await early.phone.next()
        XCTAssertEqual(pong, "pong#1")
        // A second round trip, so an answer handled apart from the receive loop
        // would have had its turn by now.
        try await early.phone.send(.ping, requestID: 2)
        _ = try await early.phone.next()
        XCTAssertEqual(early.alerts.answers, [])

        // A phone from before the status existed.
        let old = makeFixture()
        old.alerts.show([FakeAlertSource.alert("A", id: id)])
        try await old.phone.send(Self.revision13Hello, requestID: 1)
        _ = try await old.phone.next()
        try await old.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false))
        try await old.phone.send(.ping, requestID: 2)
        let next = try await old.phone.next()
        XCTAssertEqual(next, "pong#2", "and no rejection event it could not decode")
        try await old.phone.send(.ping, requestID: 3)
        _ = try await old.phone.next()
        XCTAssertEqual(old.alerts.answers, [])
    }

    // MARK: Input while the Mac is blocked

    private static func key(_ text: String) -> CompanionClientMessage {
        return .sendKey(sessionGuid: "g", event: CompanionKeyEvent(key: .text(text)))
    }

    /// Keystrokes and pastes sent while the Mac cannot act on them must not be
    /// saved up and typed into the terminal minutes later, when the alert is
    /// finally dismissed.
    func testKeysAndPastesAreRefusedWhileTheMainThreadIsBlocked() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.stall.setBlocked(true)
        let status = try await fixture.phone.next()
        XCTAssertEqual(status, "macStatus(alerts=[], blocked=true)")

        try await fixture.phone.send(Self.key("x"), requestID: 5)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#5")
        // Sent without a request ID, as the phone normally sends them: dropped.
        try await fixture.phone.send(Self.key("y"))
        try await fixture.phone.send(.pasteText(sessionGuid: "g", text: "rm -rf /"))
        try await fixture.phone.send(.ping, requestID: 6)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#6")

        // Unblocked: input goes through again.
        fixture.stall.setBlocked(false)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(Self.key("z"), requestID: 7)
        try await fixture.phone.send(.ping, requestID: 8)
        _ = try await fixture.phone.next()

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "handled ping#6",
                                "forwarded sendKey#7",
                                "handled ping#8",
                                "closed(dropped)"],
                       "nothing typed during the block reaches the bridge")
    }

    /// An alert being up does not by itself mean the Mac cannot act on input.
    /// One started by something the user did at the Mac leaves the main queue
    /// running, and the phone can go on typing into other sessions. Only an
    /// actual stall refuses input.
    func testKeysAreForwardedWhileAnAlertIsUpUnlessTheMainThreadIsBlocked() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.alerts.show([FakeAlertSource.alert("Blocking")])
        _ = try await fixture.phone.next()
        try await fixture.phone.send(Self.key("a"), requestID: 2)
        // A sync point: the link has read the key before the stall is declared.
        try await fixture.phone.send(.ping, requestID: 20)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#20")

        fixture.stall.setBlocked(true)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(Self.key("b"), requestID: 3)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#3")

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events.filter { $0.contains("sendKey") }, ["forwarded sendKey#2"])
    }

    /// Whether an alert has the main queue frozen is not known when it appears.
    /// The link asks the monitor to find out quickly, so the phone learns within
    /// a moment instead of after the ordinary stall threshold.
    func testAnAlertThatCanBlockTheAppAsksForAQuickStallCheck() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        XCTAssertEqual(fixture.stall.expediteCount, 0)

        // A sheet cannot block the app: no need to check.
        fixture.alerts.show([FakeAlertSource.alert("Sheet", isAppModal: false)])
        _ = try await fixture.phone.next()
        XCTAssertEqual(fixture.stall.expediteCount, 0)

        fixture.alerts.show([FakeAlertSource.alert("Sheet", isAppModal: false), FakeAlertSource.alert("Blocking")])
        _ = try await fixture.phone.next()
        XCTAssertEqual(fixture.stall.expediteCount, 1)
    }

    func testWhetherTheCheckboxStartsCheckedIsSentWithTheAlert() async throws {
        let fixture = makeFixture()
        let snapshot = ModalAlertSnapshot(
            id: UUID(), heading: "Log in", body: "",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true)],
            suppressionLabel: "Remember this password", hasAccessory: false, isAppModal: true,
            suppressionDefault: true)
        fixture.alerts.show([snapshot])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        guard case .hello(_, _, _, _, let macStatus) = try await fixture.phone.nextEnvelope().payload else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(macStatus?.modalAlerts.first?.suppressionDefault, true)
    }

    func testTheSessionsAnAlertIsAboutAreSentWithIt() async throws {
        let fixture = makeFixture()
        let snapshot = ModalAlertSnapshot(
            id: UUID(), heading: "Paste", body: "",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true)],
            suppressionLabel: nil, hasAccessory: false, isAppModal: true,
            sessionGuids: ["session-1", "session-2"])
        fixture.alerts.show([snapshot])
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        guard case .hello(_, _, _, _, let macStatus) = try await fixture.phone.nextEnvelope().payload else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(macStatus?.modalAlerts.first?.sessionGuids, ["session-1", "session-2"])
    }

    /// An older Buddy does not know the Mac is blocked and keeps sending. The
    /// refusal does not depend on what the phone was told.
    func testKeysFromAnOlderPhoneAreRefusedWhileBlockedToo() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.revision13Hello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.stall.setBlocked(true)
        try await fixture.phone.send(Self.key("x"), requestID: 2)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#2")
    }

    func testAnswerIsForwardedAsHandledAndClassifiesAsUnsolicited() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(.answerModalAlert(alertID: UUID().uuidString, buttonIndex: 0, suppress: false),
                                     requestID: 9)
        try await fixture.phone.send(.ping, requestID: 10)
        _ = try await fixture.phone.next()
        await fixture.phone.close()
        let events = try await allEvents(fixture.link)
        XCTAssertEqual(Array(events.map { Self.describe($0) }.prefix(2)),
                       ["handled answerModalAlert#9", "handled ping#10"])
        XCTAssertEqual(classification(of: events), .unsolicited)
    }

    func testVersionBlockedPhoneCannotAnswerAnAlert() async throws {
        let fixture = makeFixture()
        let id = UUID()
        fixture.alerts.show([FakeAlertSource.alert("A", id: id)])
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(.answerModalAlert(alertID: id.uuidString, buttonIndex: 0, suppress: false),
                                     requestID: 2)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#2")
        XCTAssertEqual(fixture.alerts.answers, [])
    }

    // MARK: Classification for the presence warning

    /// What the bridge would report for this connection: the first event that
    /// classifies it.
    private func classification(of events: [CompanionLink.Event],
                                outstandingNonces: Set<String> = []) -> CompanionConnectionClassification? {
        for event in events {
            if let result = CompanionHostBridge.connectionClassification(
                for: event, nonceIsOutstanding: { outstandingNonces.contains($0) }) {
                return result
            }
        }
        return nil
    }

    private func eventsAfterSending(_ messages: [CompanionClientMessage]) async throws -> [CompanionLink.Event] {
        let fixture = makeFixture()
        for (index, message) in messages.enumerated() {
            try await fixture.phone.send(message, requestID: UInt64(index + 1))
        }
        await fixture.phone.close()
        return try await allEvents(fixture.link)
    }

    func testPingAnsweredByTheLinkStillClassifiesAsUnsolicited() async throws {
        let events = try await eventsAfterSending([.ping])
        XCTAssertEqual(classification(of: events), .unsolicited)
    }

    func testHelloAloneDoesNotClassify() async throws {
        let events = try await eventsAfterSending([Self.compatibleHello])
        XCTAssertEqual(events.count, 3, "hello envelope, helloCompleted, closed")
        XCTAssertNil(classification(of: events))
    }

    /// The phone's notification extension says hello and then fetches with the
    /// one-time nonce from the push. That must stay solicited, so the Mac does
    /// not warn the user about its own fetch.
    func testHelloThenFetchWithOutstandingNonceClassifiesAsSolicited() async throws {
        let messagesSince = try await eventsAfterSending(
            [Self.compatibleHello, .messagesSince(collapseToken: "t", seq: 0, limit: 10, nonce: "good")])
        XCTAssertEqual(classification(of: messagesSince, outstandingNonces: ["good"]), .solicited)

        let syncSince = try await eventsAfterSending(
            [Self.compatibleHello, .syncSince(messageSeq: 0, alertSeq: 0, limit: 10, nonce: "good")])
        XCTAssertEqual(classification(of: syncSince, outstandingNonces: ["good"]), .solicited)
    }

    func testFetchWithMissingOrUnknownNonceClassifiesAsUnsolicited() async throws {
        let unknown = try await eventsAfterSending(
            [Self.compatibleHello, .messagesSince(collapseToken: "t", seq: 0, limit: 10, nonce: "forged")])
        XCTAssertEqual(classification(of: unknown, outstandingNonces: ["good"]), .unsolicited)

        let missing = try await eventsAfterSending(
            [Self.compatibleHello, .syncSince(messageSeq: 0, alertSeq: 0, limit: 10, nonce: nil)])
        XCTAssertEqual(classification(of: missing, outstandingNonces: ["good"]), .unsolicited)
    }

    func testOtherRequestsClassifyAsUnsolicited() async throws {
        let events = try await eventsAfterSending([Self.compatibleHello, .listChatsAndSessions])
        XCTAssertEqual(classification(of: events), .unsolicited)
    }

    /// Existing behavior: an incompatible peer is reported as solicited so the
    /// presence toast does not pile onto the upgrade alert.
    func testIncompatibleHelloClassifiesAsSolicited() async throws {
        let events = try await eventsAfterSending([Self.incompatibleHello])
        XCTAssertEqual(classification(of: events), .solicited)
    }
}
