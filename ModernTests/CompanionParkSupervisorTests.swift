//
//  CompanionParkSupervisorTests.swift
//  iTerm2 ModernTests
//
//  CompanionParkSupervisor keeps an established pairing reachable off the main
//  actor. These tests drive it against a scripted relay and a real Noise
//  handshake, and pin:
//
//    - A phone can reconnect while the main queue is frozen by a modal run loop
//      started from a main-queue callout (the bug: the Mac never parked again
//      until the alert was dismissed).
//    - Who gets in: only the pinned phone key; a failed handshake or a wrong
//      key is dropped and the same park keeps accepting.
//    - What happens when a park or a live connection ends: which failures wait,
//      for how long, and which are surfaced.
//    - Commands are handled in the order they were sent, stop leaves a live
//      link open, and nothing parks while parking is not allowed.
//
//  Delays never really elapse: the injected sleep records the request and
//  returns at once, so the tests step from one park to the next.
//

import XCTest
import os
import CompanionProtocol
import CompanionNoise
@testable import iTerm2SharedARC

// MARK: - Test doubles

/// A FIFO the test awaits on. Fails rather than hangs when nothing arrives.
private final class TestQueue<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []
    private var waiters: [CheckedContinuation<Element, Never>] = []
    private var total = 0

    /// How many elements were ever pushed.
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return total
    }

    func push(_ element: Element) {
        lock.lock()
        total += 1
        if waiters.isEmpty {
            items.append(element)
            lock.unlock()
        } else {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: element)
        }
    }

    func next(_ what: String) async throws -> Element {
        return try await FrozenMainQueue.withFailsafe(what) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Element, Never>) in
                self.lock.lock()
                if self.items.isEmpty {
                    self.waiters.append(continuation)
                    self.lock.unlock()
                } else {
                    let item = self.items.removeFirst()
                    self.lock.unlock()
                    continuation.resume(returning: item)
                }
            }
        }
    }
}

/// One park in the scripted relay: the listener the supervisor is accepting on.
private final class FakePark: TransportListener, @unchecked Sendable {
    let transportName = "fake"
    let recipe: CompanionParkRecipe
    let forceFreshResolve: Bool
    private let onParked: @Sendable () -> Void
    private let lock = NSLock()
    private var results: [Result<MessageTransport, Error>] = []
    private var acceptWaiter: CheckedContinuation<MessageTransport, Error>?
    private var stopped = false

    init(recipe: CompanionParkRecipe, forceFreshResolve: Bool, onParked: @escaping @Sendable () -> Void) {
        self.recipe = recipe
        self.forceFreshResolve = forceFreshResolve
        self.onParked = onParked
    }

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // MARK: TransportListener

    func accept() async throws -> MessageTransport {
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if stopped {
                lock.unlock()
                continuation.resume(throwing: TransportError.closed)
            } else if results.isEmpty {
                acceptWaiter = continuation
                lock.unlock()
            } else {
                let result = results.removeFirst()
                lock.unlock()
                continuation.resume(with: result)
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let waiter = acceptWaiter
        acceptWaiter = nil
        lock.unlock()
        waiter?.resume(throwing: TransportError.closed)
    }

    // MARK: Scripting

    private func deliver(_ result: Result<MessageTransport, Error>) {
        lock.lock()
        if let waiter = acceptWaiter {
            acceptWaiter = nil
            lock.unlock()
            waiter.resume(with: result)
        } else {
            results.append(result)
            lock.unlock()
        }
    }

    /// The relay admits the park.
    func admit() {
        onParked()
    }

    /// A peer joins the room. Returns the peer's end of the raw connection.
    func connect() -> CompanionLoopbackTransport {
        let (macEnd, phoneEnd) = CompanionLoopbackTransport.makePair()
        deliver(.success(macEnd))
        return phoneEnd
    }

    /// The park dies: accept() throws.
    func fail(_ error: Error) {
        deliver(.failure(error))
    }
}

private struct ListenerBuildFailed: Error {}

/// Stands in for the relay, the shard resolver, and the clock.
private final class FakeRelay: @unchecked Sendable {
    let parks = TestQueue<FakePark>()
    private let lock = NSLock()
    private var _eligible = true
    private var _sleeps: [UInt64] = []
    private var _buildFailuresRemaining = 0
    private var _linksMade = 0

    static let jitteredReparkNanos: UInt64 = 1_234_000_000

    var eligible: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _eligible }
        set { lock.lock(); _eligible = newValue; lock.unlock() }
    }

    /// Every delay the supervisor asked for, in order.
    var sleeps: [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return _sleeps
    }

    var linksMade: Int {
        lock.lock(); defer { lock.unlock() }
        return _linksMade
    }

    func failNextListenerBuilds(_ count: Int) {
        lock.lock(); _buildFailuresRemaining = count; lock.unlock()
    }

    var environment: CompanionParkEnvironment {
        return CompanionParkEnvironment(
            isEligible: { self.eligible },
            makeListener: { recipe, forceFreshResolve, onParked in
                self.lock.lock()
                let fail = self._buildFailuresRemaining > 0
                if fail {
                    self._buildFailuresRemaining -= 1
                }
                self.lock.unlock()
                if fail {
                    throw ListenerBuildFailed()
                }
                let park = FakePark(recipe: recipe, forceFreshResolve: forceFreshResolve, onParked: onParked)
                self.parks.push(park)
                return park
            },
            makeLink: { transport in
                self.lock.lock(); self._linksMade += 1; self.lock.unlock()
                return CompanionLink(transport: transport,
                                     aiAvailability: CompanionAIAvailabilityCache(true),
                                     wantsNotificationPermission: { false },
                                     storeRoomSecret: { _ in },
                                     alerts: ModalAlertRegistry(modalWindow: { nil }),
                                     mainStall: CompanionMainThreadMonitor(ticksAutomatically: false))
            },
            sleep: { nanoseconds in
                self.lock.lock(); self._sleeps.append(nanoseconds); self.lock.unlock()
            },
            jitteredReparkNanos: { Self.jitteredReparkNanos })
    }
}

// MARK: - Supervisor tests

final class CompanionParkSupervisorTests: XCTestCase {
    private struct Fixture {
        let relay: FakeRelay
        let supervisor: CompanionParkSupervisor
        /// Each event, described.
        let events: TestQueue<String>
        /// The same events, each prefixed with the generation it carries.
        let taggedEvents: TestQueue<String>
        let recipe: CompanionParkRecipe
        let phoneKeys: NoiseKeyPair
    }

    private static let seconds: UInt64 = 1_000_000_000

    private func makeRecipe(pairingID: String = "0123456789abcdef",
                            phoneKeys: NoiseKeyPair) throws -> CompanionParkRecipe {
        return CompanionParkRecipe(pairingID: pairingID,
                                   keyPair: try NoiseKeyPair.generate(),
                                   pinnedPhoneStatic: phoneKeys.publicKey)
    }

    private func makeFixture() throws -> Fixture {
        let relay = FakeRelay()
        let supervisor = CompanionParkSupervisor(environment: relay.environment)
        let events = TestQueue<String>()
        let taggedEvents = TestQueue<String>()
        Task.detached {
            for await tagged in supervisor.events {
                events.push(Self.describe(tagged.event))
                taggedEvents.push("\(tagged.generation): " + Self.describe(tagged.event))
            }
        }
        let phoneKeys = try NoiseKeyPair.generate()
        return Fixture(relay: relay,
                       supervisor: supervisor,
                       events: events,
                       taggedEvents: taggedEvents,
                       recipe: try makeRecipe(phoneKeys: phoneKeys),
                       phoneKeys: phoneKeys)
    }

    private static func describe(_ event: CompanionParkSupervisor.Event) -> String {
        switch event {
        case .parked:
            return "parked"
        case .linkUp:
            return "linkUp"
        case .linkDown(_, let error):
            return error == nil ? "linkDown(closed locally)" : "linkDown(dropped)"
        case .retryScheduled(let nanoseconds, let failure):
            return "retry(\(Double(nanoseconds) / Double(seconds))s after \(failure))"
        case .fault:
            return "fault"
        case .stopped:
            return "stopped"
        }
    }

    /// The phone's side of one connection.
    private struct Phone {
        /// The encrypted channel, after the handshake.
        let channel: NoiseChannel
        /// The raw connection under it, which is what the relay would close.
        let raw: CompanionLoopbackTransport
    }

    /// Join the park and run the real Noise handshake as the initiator.
    private func connectPhone(to park: FakePark,
                              keys: NoiseKeyPair) async throws -> Phone {
        let phoneEnd = park.connect()
        let recipe = park.recipe
        let channel = try await FrozenMainQueue.withFailsafe("the phone's Noise handshake") {
            let code = PairingCode(responderStaticPublicKey: recipe.keyPair.publicKey,
                                   pairingID: recipe.pairingID)
            return try await NoiseHandshake.perform(role: .initiator,
                                                    transport: phoneEnd,
                                                    localKeyPair: keys,
                                                    remoteStaticPublicKey: recipe.keyPair.publicKey,
                                                    prologue: code.handshakePrologue())
        }
        return Phone(channel: channel, raw: phoneEnd)
    }

    /// Say hello on an established channel and return whether the Mac replied
    /// with its hello.
    private func helloIsAnswered(on phone: Phone, requestID: UInt64 = 1) async throws -> Bool {
        let channel = phone.channel
        let hello = ClientEnvelope(requestID: requestID,
                                   payload: .hello(revision: CompanionProtocolVersion.current,
                                                   minimumPeer: CompanionProtocolVersion.minimumPeer))
        try await channel.send(try WireCoding.encode(hello))
        let data = try await FrozenMainQueue.withFailsafe("the Mac's hello reply") {
            try await channel.receive()
        }
        let reply = try WireCoding.decode(HostEnvelope.self, from: data)
        guard reply.requestID == requestID, case .hello = reply.payload else {
            return false
        }
        return true
    }

    /// Asserts the channel is dead: the Mac closed it without serving anything.
    private func assertRejected(_ phone: Phone,
                                file: StaticString = #filePath, line: UInt = #line) async {
        let channel = phone.channel
        do {
            _ = try await FrozenMainQueue.withFailsafe("the rejected channel to close") {
                try await channel.receive()
            }
            XCTFail("the Mac served a phone it should have rejected", file: file, line: line)
        } catch {
            XCTAssertFalse(error is FrozenMainQueue.Timeout, "the channel was left open", file: file, line: line)
        }
    }

    /// Start, park, and connect the pinned phone. Consumes "parked" and "linkUp".
    private func connectedFixture() async throws -> (Fixture, FakePark, Phone) {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the first park")
        park.admit()
        let parked = try await fixture.events.next("parked")
        XCTAssertEqual(parked, "parked")
        let phone = try await connectPhone(to: park, keys: fixture.phoneKeys)
        let linkUp = try await fixture.events.next("linkUp")
        XCTAssertEqual(linkUp, "linkUp")
        return (fixture, park, phone)
    }

    // MARK: Parking and connecting

    func testStartParksAndThePinnedPhoneConnects() async throws {
        let (fixture, park, channel) = try await connectedFixture()
        XCTAssertFalse(park.forceFreshResolve)
        XCTAssertEqual(park.recipe, fixture.recipe)
        // The link is live: it answers hello without any help from a bridge.
        let answered = try await helloIsAnswered(on: channel)
        XCTAssertTrue(answered)
        // Connected: stop accepting. The room has a single mac slot, so parking
        // again while connected would displace this very connection.
        XCTAssertTrue(park.isStopped)
        XCTAssertEqual(fixture.relay.parks.count, 1)
        XCTAssertEqual(fixture.relay.sleeps, [])
    }

    // MARK: The bug: reconnecting while the main queue is frozen

    func testPhoneReconnectsWhileMainQueueIsFrozen() async throws {
        let (fixture, _, firstChannel) = try await connectedFixture()
        try await FrozenMainQueue.run { _ in
            // The phone drops. Nothing on the main actor can notice.
            await firstChannel.channel.close()
            let linkDown = try await fixture.events.next("linkDown")
            XCTAssertEqual(linkDown, "linkDown(dropped)")

            // The supervisor parks again on its own, and the phone gets back in.
            let secondPark = try await fixture.relay.parks.next("the re-park")
            secondPark.admit()
            let secondChannel = try await self.connectPhone(to: secondPark, keys: fixture.phoneKeys)
            let answered = try await self.helloIsAnswered(on: secondChannel)
            XCTAssertTrue(answered)

            let parked = try await fixture.events.next("parked")
            let linkUp = try await fixture.events.next("linkUp")
            XCTAssertEqual([parked, linkUp], ["parked", "linkUp"])
        }
        XCTAssertEqual(fixture.relay.sleeps, [], "an ordinary drop parks again at once")
    }

    /// A start command sent on the main thread, in the same callout that then
    /// freezes, must still take effect during the freeze.
    func testStartSentInsideTheFreezingCalloutStillParks() async throws {
        let fixture = try makeFixture()
        try await FrozenMainQueue.run(setup: {
            fixture.supervisor.send(.start(fixture.recipe))
        }) { _ in
            let park = try await fixture.relay.parks.next("the park")
            park.admit()
            let channel = try await self.connectPhone(to: park, keys: fixture.phoneKeys)
            let answered = try await self.helloIsAnswered(on: channel)
            XCTAssertTrue(answered)
        }
    }

    // MARK: Who gets in

    func testPhoneWithTheWrongKeyIsRejectedAndTheParkKeepsAccepting() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.admit()
        let parked = try await fixture.events.next("parked")
        XCTAssertEqual(parked, "parked")

        // Anyone who photographed the QR can complete the handshake, but only
        // the pinned key is served.
        let stranger = try await connectPhone(to: park, keys: try NoiseKeyPair.generate())
        await assertRejected(stranger)

        // The same park is still accepting, and the real phone gets in.
        let channel = try await connectPhone(to: park, keys: fixture.phoneKeys)
        let linkUp = try await fixture.events.next("linkUp")
        XCTAssertEqual(linkUp, "linkUp")
        let answered = try await helloIsAnswered(on: channel)
        XCTAssertTrue(answered)
        XCTAssertEqual(fixture.relay.parks.count, 1, "a rejected phone must not cost a re-park")
        XCTAssertEqual(fixture.relay.linksMade, 1, "no link is made for a rejected phone")
        XCTAssertEqual(fixture.relay.sleeps, [])
    }

    func testFailedHandshakeIsDroppedAndTheParkKeepsAccepting() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.admit()
        _ = try await fixture.events.next("parked")

        // A peer that talks nonsense instead of Noise.
        let garbage = park.connect()
        try await garbage.send(Data("not a handshake".utf8))
        do {
            _ = try await FrozenMainQueue.withFailsafe("the failed handshake's socket to close") {
                try await garbage.receive()
            }
            XCTFail("the Mac answered a garbage handshake")
        } catch {
            XCTAssertFalse(error is FrozenMainQueue.Timeout, "the failed handshake's socket was left open")
        }

        let channel = try await connectPhone(to: park, keys: fixture.phoneKeys)
        let linkUp = try await fixture.events.next("linkUp")
        XCTAssertEqual(linkUp, "linkUp")
        let answered = try await helloIsAnswered(on: channel)
        XCTAssertTrue(answered)
        XCTAssertEqual(fixture.relay.parks.count, 1)
        XCTAssertEqual(fixture.relay.sleeps, [])
    }

    // MARK: When a live connection ends

    func testQuotaTeardownOfALiveConnectionWaitsBeforeParkingAgain() async throws {
        let (fixture, _, phone) = try await connectedFixture()
        // The relay tears the room down for its daily quota.
        phone.raw.fail(with: .quotaExceeded)

        let linkDown = try await fixture.events.next("linkDown")
        let retry = try await fixture.events.next("retry")
        XCTAssertEqual(linkDown, "linkDown(dropped)")
        XCTAssertEqual(retry, "retry(1800.0s after quota)")
        // It does park again once the wait is over.
        _ = try await fixture.relay.parks.next("the park after the quota wait")
        XCTAssertEqual(fixture.relay.sleeps, [CompanionParkBackoff.quotaRetryNanos])
    }

    // MARK: When a park fails

    func testRoutineParkCloseBacksOffAndTheBackoffResetsOnceParked() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))

        // Two closes in a row without ever being admitted: 5 s, then 10 s. A
        // routine close is not worth showing the user, so there is no fault.
        var park = try await fixture.relay.parks.next("park 1")
        park.fail(TransportError.closed)
        var retry = try await fixture.events.next("retry 1")
        XCTAssertEqual(retry, "retry(5.0s after routineClose)")
        XCTAssertTrue(park.isStopped, "a dead park's listener is released")

        park = try await fixture.relay.parks.next("park 2")
        park.fail(TransportError.closed)
        retry = try await fixture.events.next("retry 2")
        XCTAssertEqual(retry, "retry(10.0s after routineClose)")

        // Being admitted proves the relay reachable: back to the minimum.
        park = try await fixture.relay.parks.next("park 3")
        park.admit()
        let parked = try await fixture.events.next("parked")
        XCTAssertEqual(parked, "parked")
        park.fail(TransportError.closed)
        retry = try await fixture.events.next("retry 3")
        XCTAssertEqual(retry, "retry(5.0s after routineClose)")

        _ = try await fixture.relay.parks.next("park 4")
        XCTAssertEqual(fixture.relay.sleeps, [5 * Self.seconds, 10 * Self.seconds, 5 * Self.seconds])
    }

    func testFaultIsSurfacedAndRetried() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.fail(TransportError.connectionFailed("TLS error"))
        let fault = try await fixture.events.next("fault")
        let retry = try await fixture.events.next("retry")
        XCTAssertEqual(fault, "fault")
        XCTAssertEqual(retry, "retry(5.0s after fault)")
        _ = try await fixture.relay.parks.next("the next park")
    }

    func testDisplacedParkWaitsAMinuteAndIsNotAFault() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.fail(RelayDisplacedError())
        let retry = try await fixture.events.next("retry")
        XCTAssertEqual(retry, "retry(60.0s after displaced)")
        _ = try await fixture.relay.parks.next("the next park")
        XCTAssertEqual(fixture.relay.sleeps, [CompanionParkBackoff.displacedRetryNanos])
    }

    func testQuotaParkCloseWaitsThirtyMinutes() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.fail(TransportError.quotaExceeded)
        let retry = try await fixture.events.next("retry")
        XCTAssertEqual(retry, "retry(1800.0s after quota)")
        _ = try await fixture.relay.parks.next("the next park")
        XCTAssertEqual(fixture.relay.sleeps, [CompanionParkBackoff.quotaRetryNanos])
    }

    func testReshardEvictionReResolvesOnTheNextParkOnly() async throws {
        let fixture = try makeFixture()
        fixture.supervisor.send(.start(fixture.recipe))
        var park = try await fixture.relay.parks.next("park 1")
        XCTAssertFalse(park.forceFreshResolve)
        park.fail(TransportError.reResolve(ownerHint: "relay-2"))
        let retry = try await fixture.events.next("retry")
        XCTAssertEqual(retry, "retry(1.234s after reResolve(ownerHint: Optional(\"relay-2\")))")

        park = try await fixture.relay.parks.next("park 2")
        XCTAssertTrue(park.forceFreshResolve, "the park after a reshard evict must fetch a fresh shard map")
        park.fail(TransportError.closed)
        _ = try await fixture.events.next("retry 2")

        park = try await fixture.relay.parks.next("park 3")
        XCTAssertFalse(park.forceFreshResolve)
        XCTAssertEqual(fixture.relay.sleeps, [FakeRelay.jitteredReparkNanos, 5 * Self.seconds])
    }

    func testListenerBuildFailureIsRetriedQuietly() async throws {
        let fixture = try makeFixture()
        fixture.relay.failNextListenerBuilds(2)
        fixture.supervisor.send(.start(fixture.recipe))
        let first = try await fixture.events.next("retry 1")
        let second = try await fixture.events.next("retry 2")
        XCTAssertEqual([first, second], ["retry(5.0s after fault)", "retry(10.0s after fault)"])
        let park = try await fixture.relay.parks.next("the park")
        park.admit()
        let parked = try await fixture.events.next("parked")
        XCTAssertEqual(parked, "parked", "no fault event: an established pairing has no window to show it in")
    }

    // MARK: Commands

    func testStopCancelsTheParkAndCommandsRunInOrder() async throws {
        let fixture = try makeFixture()
        let otherRecipe = try makeRecipe(pairingID: "fedcba9876543210", phoneKeys: fixture.phoneKeys)
        fixture.supervisor.send(.start(fixture.recipe))
        let firstPark = try await fixture.relay.parks.next("park 1")

        // Sent back to back: stop must finish before the next start begins.
        fixture.supervisor.send(.stop)
        fixture.supervisor.send(.start(otherRecipe))

        let stopped = try await fixture.events.next("stopped")
        XCTAssertEqual(stopped, "stopped")
        let secondPark = try await fixture.relay.parks.next("park 2")
        XCTAssertTrue(firstPark.isStopped, "stop releases the park it cancelled")
        XCTAssertEqual(secondPark.recipe, otherRecipe)
        XCTAssertFalse(secondPark.isStopped)
        XCTAssertEqual(fixture.relay.sleeps, [], "a cancelled park is not a failure and is not retried")
        XCTAssertEqual(fixture.relay.parks.count, 2)
    }

    /// Events are read on the main actor, which may be frozen, so they can be
    /// handled long after they happened: after a later stop, and after a later
    /// start. Each one names the command it belongs to, so the reader can tell
    /// an event from a run it has since replaced and drop it.
    func testEventsCarryTheGenerationOfTheCommandThatProducedThem() async throws {
        let fixture = try makeFixture()
        let otherRecipe = try makeRecipe(pairingID: "fedcba9876543210", phoneKeys: fixture.phoneKeys)

        let first = fixture.supervisor.send(.start(fixture.recipe))
        let firstPark = try await fixture.relay.parks.next("park 1")
        firstPark.admit()
        let parked = try await fixture.taggedEvents.next("parked")
        XCTAssertEqual(parked, "\(first): parked")

        let stop = fixture.supervisor.send(.stop)
        let second = fixture.supervisor.send(.start(otherRecipe))
        XCTAssertLessThan(first, stop)
        XCTAssertLessThan(stop, second)

        let stopped = try await fixture.taggedEvents.next("stopped")
        XCTAssertEqual(stopped, "\(stop): stopped")
        let secondPark = try await fixture.relay.parks.next("park 2")
        secondPark.admit()
        let reparked = try await fixture.taggedEvents.next("parked again")
        XCTAssertEqual(reparked, "\(second): parked")

        // The relay admits the first, long-cancelled park late. The event still
        // says which run it came from, so it cannot pass for the current one.
        firstPark.admit()
        let late = try await fixture.taggedEvents.next("the late parked")
        XCTAssertEqual(late, "\(first): parked")
    }

    /// The reviewer's case: a run that stops itself because parking is no longer
    /// allowed reports that under ITS generation, not the generation of a start
    /// sent since.
    func testARunThatStopsItselfReportsItsOwnGeneration() async throws {
        let fixture = try makeFixture()
        fixture.relay.eligible = false
        let first = fixture.supervisor.send(.start(fixture.recipe))
        let stopped = try await fixture.taggedEvents.next("stopped")
        XCTAssertEqual(stopped, "\(first): stopped")

        fixture.relay.eligible = true
        let second = fixture.supervisor.send(.start(fixture.recipe))
        let park = try await fixture.relay.parks.next("the park")
        park.admit()
        let parked = try await fixture.taggedEvents.next("parked")
        XCTAssertEqual(parked, "\(second): parked")
        XCTAssertNotEqual(first, second)
    }

    func testStopLeavesALiveLinkOpenAndDoesNotParkWhenItDrops() async throws {
        let (fixture, _, channel) = try await connectedFixture()
        fixture.supervisor.send(.stop)
        let stopped = try await fixture.events.next("stopped")
        XCTAssertEqual(stopped, "stopped")

        // Still open: the owner can go on to say farewell on it.
        let answered = try await helloIsAnswered(on: channel)
        XCTAssertTrue(answered)

        // The supervisor no longer watches it, so its drop is not its business.
        await channel.channel.close()
        fixture.supervisor.send(.start(fixture.recipe))
        _ = try await fixture.relay.parks.next("the park from the new start")
        XCTAssertEqual(fixture.relay.parks.count, 2, "the only new park is the one the new start asked for")
    }

    func testAdoptedLinkIsWatchedAndItsDropParks() async throws {
        let fixture = try makeFixture()
        // A fresh pairing just succeeded elsewhere and hands its link over.
        let (macEnd, phoneEnd) = CompanionLoopbackTransport.makePair()
        let link = CompanionLink(transport: macEnd,
                                 aiAvailability: CompanionAIAvailabilityCache(true),
                                 wantsNotificationPermission: { false },
                                 storeRoomSecret: { _ in },
                                 alerts: ModalAlertRegistry(modalWindow: { nil }),
                                 mainStall: CompanionMainThreadMonitor(ticksAutomatically: false))
        link.start()
        fixture.supervisor.send(.adopt(link, fixture.recipe))

        await phoneEnd.close()
        let linkDown = try await fixture.events.next("linkDown")
        XCTAssertEqual(linkDown, "linkDown(dropped)")
        let park = try await fixture.relay.parks.next("the park after the adopted link dropped")
        XCTAssertEqual(park.recipe, fixture.recipe)
        XCTAssertEqual(fixture.relay.parks.count, 1, "adopting must not park while the link is live")
    }

    // MARK: Eligibility

    func testNothingParksWhileParkingIsNotAllowed() async throws {
        let fixture = try makeFixture()
        fixture.relay.eligible = false
        fixture.supervisor.send(.start(fixture.recipe))
        let stopped = try await fixture.events.next("stopped")
        XCTAssertEqual(stopped, "stopped")
        XCTAssertEqual(fixture.relay.parks.count, 0)

        fixture.relay.eligible = true
        fixture.supervisor.send(.start(fixture.recipe))
        _ = try await fixture.relay.parks.next("the park once allowed")
    }

    func testDropWhileNoLongerAllowedDoesNotParkAgain() async throws {
        let (fixture, _, channel) = try await connectedFixture()
        fixture.relay.eligible = false
        await channel.channel.close()
        let linkDown = try await fixture.events.next("linkDown")
        let stopped = try await fixture.events.next("stopped")
        XCTAssertEqual([linkDown, stopped], ["linkDown(dropped)", "stopped"])
        XCTAssertEqual(fixture.relay.parks.count, 1)
    }
}

// MARK: - Pure policy

final class CompanionParkPolicyTests: XCTestCase {
    private let jitter: UInt64 = 777

    func testClassify() {
        XCTAssertEqual(CompanionParkFailure.classify(TransportError.closed, cancelled: true), .cancelled)
        XCTAssertEqual(CompanionParkFailure.classify(CancellationError(), cancelled: false), .cancelled)
        XCTAssertEqual(CompanionParkFailure.classify(RelayDisplacedError(), cancelled: false), .displaced)
        XCTAssertEqual(CompanionParkFailure.classify(TransportError.quotaExceeded, cancelled: false), .quota)
        XCTAssertEqual(CompanionParkFailure.classify(TransportError.reResolve(ownerHint: "h"), cancelled: false),
                       .reResolve(ownerHint: "h"))
        XCTAssertEqual(CompanionParkFailure.classify(TransportError.closed, cancelled: false), .routineClose)
        XCTAssertEqual(CompanionParkFailure.classify(TransportError.connectionFailed("dns"), cancelled: false), .fault)
        XCTAssertEqual(CompanionParkFailure.classify(NSError(domain: "x", code: 1), cancelled: false), .fault)
    }

    func testParkFailureRatchetDoublesToTheMaximumAndResets() {
        var backoff = CompanionParkBackoff()
        let seconds: UInt64 = 1_000_000_000
        var delays: [UInt64] = []
        for failure in [CompanionParkFailure.routineClose, .fault, .routineClose, .fault, .routineClose, .fault] {
            delays.append(backoff.delayNanos(afterParkFailure: failure, jitteredReparkNanos: jitter))
        }
        XCTAssertEqual(delays, [5, 10, 20, 40, 60, 60].map { $0 * seconds },
                       "routine closes and faults share one ratchet")
        backoff.noteParked()
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .routineClose, jitteredReparkNanos: jitter), 5 * seconds)
    }

    func testFixedDelaysLeaveTheRatchetAlone() {
        var backoff = CompanionParkBackoff()
        let seconds: UInt64 = 1_000_000_000
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .routineClose, jitteredReparkNanos: jitter), 5 * seconds)
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .displaced, jitteredReparkNanos: jitter),
                       CompanionParkBackoff.displacedRetryNanos)
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .quota, jitteredReparkNanos: jitter),
                       CompanionParkBackoff.quotaRetryNanos)
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .reResolve(ownerHint: nil), jitteredReparkNanos: jitter),
                       jitter)
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .cancelled, jitteredReparkNanos: jitter), 0)
        XCTAssertEqual(backoff.delayNanos(afterParkFailure: .routineClose, jitteredReparkNanos: jitter), 10 * seconds,
                       "the fixed delays did not advance the ratchet")
    }

    func testLinkCloseDelays() {
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .routineClose, jitteredReparkNanos: jitter), 0)
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .fault, jitteredReparkNanos: jitter), 0)
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .cancelled, jitteredReparkNanos: jitter), 0)
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .quota, jitteredReparkNanos: jitter),
                       CompanionParkBackoff.quotaRetryNanos)
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .displaced, jitteredReparkNanos: jitter),
                       CompanionParkBackoff.displacedRetryNanos)
        XCTAssertEqual(CompanionParkBackoff.delayNanos(afterLinkClose: .reResolve(ownerHint: nil),
                                                       jitteredReparkNanos: jitter), jitter)
    }
}
