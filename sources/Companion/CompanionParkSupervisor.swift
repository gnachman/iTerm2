//
//  CompanionParkSupervisor.swift
//  iTerm2
//
//  Keeps an ESTABLISHED pairing reachable, off the main actor: park in the relay
//  room, accept the phone, run the Noise handshake, check the pinned phone key,
//  bring up a CompanionLink, and when that link drops, park again.
//
//  CompanionPairingController used to do all of this on the main actor, driven
//  by the bridge's onClose. A modal alert started from a main-queue callout
//  freezes the main actor, so while one was up the Mac never noticed a dropped
//  connection, never parked again, and the phone could not reconnect. Fresh
//  pairing (QR, SAS entry) needs UI and stays in the controller; once it
//  succeeds the controller hands the live link over with `.adopt`.
//
//  The controller talks to the supervisor only through `send`, a synchronous
//  nonisolated call that queues a command. Commands are handled strictly in the
//  order they were sent. Results come back through `events`, which a main-actor
//  task reads; they pile up while the main actor is frozen and are handled in
//  order when it thaws.
//

import Foundation
import CompanionProtocol
import CompanionNoise
import os

/// Why a park (or a live connection) ended, as far as retrying is concerned.
enum CompanionParkFailure: Equatable {
    /// We tore it down ourselves. Not retried.
    case cancelled
    /// Another mac-role connection took the room's single slot.
    case displaced
    /// The relay hit its daily data quota.
    case quota
    /// A reshard moved this pairing to another relay host.
    case reResolve(ownerHint: String?)
    /// The relay or network closed the socket: idle reap, redeploy, sleep/wake.
    case routineClose
    /// Anything else (DNS, TLS, refused). Worth showing the user.
    case fault

    /// `cancelled` is whether the task that hit the error had been cancelled.
    /// Only that is a deliberate local teardown. Every other failure, including
    /// TransportError.closed, is the relay or network closing the socket from
    /// under us and must be recovered from. Conflating the two once left the mac
    /// silently dark: paired, not parked, and unreachable until relaunch.
    static func classify(_ error: Error, cancelled: Bool) -> CompanionParkFailure {
        if cancelled || error is CancellationError {
            return .cancelled
        }
        if error is RelayDisplacedError {
            return .displaced
        }
        switch error as? TransportError {
        case .displaced:
            return .displaced
        case .quotaExceeded:
            return .quota
        case .reResolve(let ownerHint):
            return .reResolve(ownerHint: ownerHint)
        case .closed:
            return .routineClose
        default:
            return .fault
        }
    }
}

/// How long to wait before parking again.
struct CompanionParkBackoff: Sendable {
    static let minimumRetryNanos: UInt64 = 5_000_000_000
    static let maximumRetryNanos: UInt64 = 60_000_000_000
    /// A displaced park backs off much longer than the routine delay so two
    /// instances don't ping-pong evicting each other; finite so the slot is
    /// reclaimed if the other instance exits.
    static let displacedRetryNanos: UInt64 = 60_000_000_000
    /// Reconnecting sooner after a quota teardown just trips the same limit.
    static let quotaRetryNanos: UInt64 = 30 * 60 * 1_000_000_000

    /// The delay before re-parking after a PARK failed (the accept or the
    /// listener setup). Routine closes and faults ratchet from the minimum up to
    /// the maximum, doubling each time; the other cases use fixed delays and
    /// leave the ratchet alone. `.cancelled` is never retried and returns 0.
    mutating func delayNanos(afterParkFailure failure: CompanionParkFailure,
                             jitteredReparkNanos: UInt64) -> UInt64 {
        switch failure {
        case .cancelled:
            return 0
        case .displaced:
            return Self.displacedRetryNanos
        case .quota:
            return Self.quotaRetryNanos
        case .reResolve:
            return jitteredReparkNanos
        case .routineClose, .fault:
            let delay = nextRetryNanos
            nextRetryNanos = min(nextRetryNanos * 2, Self.maximumRetryNanos)
            return delay
        }
    }

    /// The delay before re-parking after a LIVE connection ended. An ordinary
    /// drop parks again at once so the phone can reconnect.
    static func delayNanos(afterLinkClose failure: CompanionParkFailure,
                           jitteredReparkNanos: UInt64) -> UInt64 {
        switch failure {
        case .cancelled, .routineClose, .fault:
            return 0
        case .displaced:
            return displacedRetryNanos
        case .quota:
            return quotaRetryNanos
        case .reResolve:
            return jitteredReparkNanos
        }
    }

    /// The relay admitted a park, so it is reachable: the next failure starts
    /// over at the minimum.
    mutating func noteParked() {
        nextRetryNanos = Self.minimumRetryNanos
    }

    private var nextRetryNanos = CompanionParkBackoff.minimumRetryNanos
}

/// What the supervisor needs to park for one established pairing. Built on the
/// main actor; everything in it is immutable.
struct CompanionParkRecipe: Sendable, Equatable {
    let pairingID: String
    let keyPair: NoiseKeyPair
    /// The phone's SAS-confirmed static key. A phone presenting any other key
    /// is rejected after the handshake.
    let pinnedPhoneStatic: Data
    /// Where to park, as configured when the recipe was built: the shard
    /// resolver (resolved mode) or else a fixed relay origin (direct mode).
    /// Captured here because the settings they come from are read on the main
    /// thread.
    let resolverURL: String?
    let relayOrigin: String?

    init(pairingID: String,
         keyPair: NoiseKeyPair,
         pinnedPhoneStatic: Data,
         resolverURL: String? = nil,
         relayOrigin: String? = nil) {
        self.pairingID = pairingID
        self.keyPair = keyPair
        self.pinnedPhoneStatic = pinnedPhoneStatic
        self.resolverURL = resolverURL
        self.relayOrigin = relayOrigin
    }
}

/// The supervisor's dependencies, injected so tests need no relay, plugin, or
/// real delays.
struct CompanionParkEnvironment: Sendable {
    /// Whether parking is still allowed: the companion gate is open, the consent
    /// plugin is present, and the pairing's credentials are complete. Checked
    /// before every park. The main actor keeps the answer current.
    var isEligible: @Sendable () -> Bool
    /// Resolve where to park and build the listener. `forceFreshResolve` is true
    /// for the park that follows a `.reResolve` failure. `onParked` must be
    /// called once the relay admits the park.
    var makeListener: @Sendable (_ recipe: CompanionParkRecipe,
                                 _ forceFreshResolve: Bool,
                                 _ onParked: @escaping @Sendable () -> Void) async throws -> TransportListener
    /// Wrap an authenticated channel in a link. The supervisor starts it.
    var makeLink: @Sendable (MessageTransport) -> CompanionLink
    var sleep: @Sendable (_ nanoseconds: UInt64) async throws -> Void
    /// Full-jitter delay for the re-park after a reshard evict.
    var jitteredReparkNanos: @Sendable () -> UInt64
}

actor CompanionParkSupervisor {
    enum Command {
        /// Park for this pairing. Replaces whatever the supervisor was doing; a
        /// link it was watching is left open and no longer watched.
        case start(CompanionParkRecipe)
        /// A fresh pairing just succeeded and this is its live link. Watch it,
        /// and park for the pairing when it drops.
        case adopt(CompanionLink, CompanionParkRecipe)
        /// Stop parking. A live link is left open and no longer watched, so the
        /// caller can still say farewell on it.
        case stop
    }

    enum StopReason {
        /// A `.stop` command.
        case commanded
        /// Parking is no longer allowed (see CompanionParkEnvironment.isEligible).
        case notEligible
    }

    enum Event {
        /// The relay admitted the park: the phone can reach this Mac.
        case parked
        /// A phone connected and authenticated. The link is already started.
        case linkUp(CompanionLink)
        /// A link the supervisor was watching ended.
        case linkDown(CompanionLink, Error?)
        /// The supervisor will park again after this delay.
        case retryScheduled(nanoseconds: UInt64, after: CompanionParkFailure)
        /// A park failed for a reason worth showing the user.
        case fault(Error)
        /// The supervisor is idle. It does nothing more until the next `.start`
        /// or `.adopt`.
        case stopped(StopReason)
    }

    /// Single consumer: a @MainActor task in CompanionPairingController.
    nonisolated let events: AsyncStream<Event>

    private nonisolated let environment: CompanionParkEnvironment
    private nonisolated let eventsContinuation: AsyncStream<Event>.Continuation
    private nonisolated let commandsContinuation: AsyncStream<Command>.Continuation
    /// Lock-protected, not actor state, because the relay reports a successful
    /// park from its own thread and `.parked` must be emitted right then, in
    /// order with the events the run emits.
    private nonisolated let backoff = OSAllocatedUnfairLock(initialState: CompanionParkBackoff())

    /// The current park-and-watch loop. At most one runs at a time.
    private var runTask: Task<Void, Never>?
    /// What the run is blocked on, so a cancel can unblock it.
    private var currentListener: TransportListener?
    private var handshakingTransport: MessageTransport?

    init(environment: CompanionParkEnvironment) {
        self.environment = environment
        (events, eventsContinuation) = AsyncStream<Event>.makeStream()
        let (commands, commandsContinuation) = AsyncStream<Command>.makeStream()
        self.commandsContinuation = commandsContinuation
        Task.detached { [self] in
            // One at a time, in the order they were sent.
            for await command in commands {
                await self.handle(command)
            }
        }
    }

    /// Queue a command. Synchronous and safe to call from the main actor even
    /// if it is about to freeze.
    nonisolated func send(_ command: Command) {
        commandsContinuation.yield(command)
    }

    // MARK: Commands

    private func handle(_ command: Command) async {
        // Each command first ends the previous run completely, so two runs
        // never overlap and a stop is finished before the next start begins.
        await cancelRun()
        switch command {
        case .start(let recipe):
            runTask = Task { await self.run(recipe: recipe, adopted: nil) }
        case .adopt(let link, let recipe):
            runTask = Task { await self.run(recipe: recipe, adopted: link) }
        case .stop:
            eventsContinuation.yield(.stopped(.commanded))
        }
    }

    private func cancelRun() async {
        guard let task = runTask else { return }
        runTask = nil
        task.cancel()
        // Cancellation alone does not unblock an accept or a handshake; closing
        // what they wait on does. A watched link is deliberately left alone.
        currentListener?.stop()
        if let transport = handshakingTransport {
            await transport.close()
        }
        await task.value
    }

    // MARK: The run

    private func run(recipe: CompanionParkRecipe, adopted: CompanionLink?) async {
        var link = adopted
        var forceFreshResolve = false
        while !Task.isCancelled {
            if let live = link {
                // Connected. The relay room has a single mac slot, so parking
                // again now would displace this very connection: just wait.
                guard case .some(let closeError) = await waitForClose(of: live) else {
                    return  // Cancelled: the link stays open, no longer watched.
                }
                link = nil
                RLog("Companion supervisor: link down (\(closeError.map { "\($0)" } ?? "closed locally"))")
                eventsContinuation.yield(.linkDown(live, closeError))
                let failure = closeError.map { CompanionParkFailure.classify($0, cancelled: false) } ?? .cancelled
                if case .reResolve = failure {
                    forceFreshResolve = true
                }
                let delay = CompanionParkBackoff.delayNanos(
                    afterLinkClose: failure,
                    jitteredReparkNanos: environment.jitteredReparkNanos())
                guard await pause(delay, after: failure) else { return }
                continue
            }

            guard environment.isEligible() else {
                RLog("Companion supervisor: parking is not allowed; idle")
                eventsContinuation.yield(.stopped(.notEligible))
                return
            }
            let listener: TransportListener
            do {
                let continuation = eventsContinuation
                let backoff = self.backoff
                listener = try await environment.makeListener(recipe, forceFreshResolve) {
                    // Parked = admitted to the relay room = reachable, which
                    // proves the relay works: the failure backoff starts over.
                    backoff.withLock { $0.noteParked() }
                    continuation.yield(.parked)
                }
            } catch {
                if Task.isCancelled { return }
                // A resolve or listener build failed before we could park. For
                // an established pairing there is usually no window to show it
                // in, so just retry.
                RLog("Companion supervisor: park setup failed: \(error); will retry")
                guard await pause(afterParkFailure: .fault) else { return }
                continue
            }
            forceFreshResolve = false
            if Task.isCancelled {
                listener.stop()
                return
            }
            currentListener = listener
            let outcome = await accept(on: listener, recipe: recipe)
            listener.stop()
            currentListener = nil
            switch outcome {
            case .connected(let newLink):
                link = newLink
            case .cancelled:
                return
            case .failed(let error, let failure):
                RLog("Companion supervisor: park ended: \(error) (\(failure))")
                if failure == .fault {
                    eventsContinuation.yield(.fault(error))
                }
                if case .reResolve = failure {
                    forceFreshResolve = true
                }
                guard await pause(afterParkFailure: failure) else { return }
            }
        }
    }

    private enum AcceptOutcome {
        case connected(CompanionLink)
        case cancelled
        case failed(Error, CompanionParkFailure)
    }

    /// Accept connections on one park until the pinned phone gets in or the
    /// park dies.
    private func accept(on listener: TransportListener, recipe: CompanionParkRecipe) async -> AcceptOutcome {
        while true {
            let transport: MessageTransport
            do {
                transport = try await listener.accept()
            } catch {
                let failure = CompanionParkFailure.classify(error, cancelled: Task.isCancelled)
                return failure == .cancelled ? .cancelled : .failed(error, failure)
            }
            if Task.isCancelled {
                await transport.close()
                return .cancelled
            }
            handshakingTransport = transport
            let channel: NoiseChannel
            do {
                let code = PairingCode(responderStaticPublicKey: recipe.keyPair.publicKey,
                                       pairingID: recipe.pairingID)
                channel = try await NoiseHandshake.perform(role: .responder,
                                                           transport: transport,
                                                           localKeyPair: recipe.keyPair,
                                                           remoteStaticPublicKey: nil,
                                                           prologue: code.handshakePrologue())
            } catch {
                handshakingTransport = nil
                RLog("Companion supervisor: handshake failed: \(error); still listening")
                // The parked socket was consumed by the failed handshake; close
                // it so the next accept() can park a fresh one.
                await transport.close()
                if Task.isCancelled { return .cancelled }
                continue
            }
            handshakingTransport = nil
            if Task.isCancelled {
                await channel.close()
                return .cancelled
            }
            // The relay is untrusted: it cannot vouch for who connected.
            // Authenticate the phone end-to-end by its Noise static key, and
            // REQUIRE the SAS-confirmed pinned one. Anything else (a QR-photo
            // attacker reaching the relay, or no key at all) is rejected, since
            // admitting it would be trust-on-first-use.
            guard channel.remoteStaticPublicKey == recipe.pinnedPhoneStatic else {
                RLog("Companion supervisor: reconnect static missing or mismatched; rejecting")
                await channel.close()
                continue
            }
            let link = environment.makeLink(channel)
            link.start()
            // Connected: stop accepting before announcing it. The relay room has
            // a single mac slot, so a park left open would displace this very
            // connection.
            listener.stop()
            RLog("Companion supervisor: link up")
            eventsContinuation.yield(.linkUp(link))
            return .connected(link)
        }
    }

    /// Suspends until the link closes. The outer optional is nil when this task
    /// was cancelled first; the inner one is what the link's close carried.
    private func waitForClose(of link: CompanionLink) async -> Error?? {
        let (stream, continuation) = AsyncStream<Error?>.makeStream()
        Task.detached {
            continuation.yield(await link.waitUntilClosed())
            continuation.finish()
        }
        // Iterating an AsyncStream ends early when the task is cancelled, which
        // is what lets a stop leave the link open and stop watching it.
        for await closeError in stream {
            return .some(closeError)
        }
        return nil
    }

    private func pause(afterParkFailure failure: CompanionParkFailure) async -> Bool {
        let jitter = environment.jitteredReparkNanos()
        let delay = backoff.withLock { $0.delayNanos(afterParkFailure: failure, jitteredReparkNanos: jitter) }
        return await pause(delay, after: failure)
    }

    /// Wait before parking again. Returns false if the run was cancelled.
    private func pause(_ delayNanos: UInt64, after failure: CompanionParkFailure) async -> Bool {
        if delayNanos > 0 {
            eventsContinuation.yield(.retryScheduled(nanoseconds: delayNanos, after: failure))
            do {
                try await environment.sleep(delayNanos)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }
}
