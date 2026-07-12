//
//  DictationController.swift
//  iTerm2 Companion
//
//  Single owner of on-device dictation: the recorder, the ownership token, and
//  the tab the owner lives on, all managed as one unit so claim / start / stop /
//  relinquish are atomic.
//
//  Why this exists: two composer bars can be mounted at once (a chat's bar behind
//  a session overlay), only one may record, and starting is async (model load +
//  mic permission). Previously ownership lived on AppModel, the recorder was a
//  separate singleton, and each bar's live-transcript span was per-view @State -
//  three things mutated from ~8 sites, with the async start splitting every
//  transition. That produced a steady stream of races: a hot mic on a hidden tab,
//  a second bar stealing ownership mid-record, a send delivering a draft missing
//  its dictated tail. Centralizing every token mutation and recorder transition
//  here removes those: nothing outside this type touches `owner` or the recorder,
//  and the async gaps are closed by re-checking `owner == token` after each await.
//

import Foundation
import Observation

@MainActor
@Observable
final class DictationController {
    /// The speech model manager (shared with Settings for model selection). The
    /// recorder transcribes with whatever it has loaded.
    let whisper: WhisperModelManager
    /// The microphone recorder. Exposed for the owning bar to observe liveText /
    /// state / level; only this controller starts and stops it.
    let voice: VoiceCaptureController

    /// The token of the bar that owns the current dictation cycle, or nil. THE
    /// single source of truth for ownership - nothing else mutates it.
    private(set) var owner: UUID?
    /// The tab the owning bar was on when it started, so switching away cancels.
    private var ownerTab: AppModel.AppTab?

    init(whisper: WhisperModelManager) {
        self.whisper = whisper
        self.voice = VoiceCaptureController(modelManager: whisper)
        // An audio-session interruption resets the recorder to .idle on its own;
        // release ownership so the mic button isn't left dead (owner == token while
        // state == .idle would make a re-tap return .alreadyActive and never
        // restart).
        voice.onInterrupted = { [weak self] in self?.releaseOnInterruption() }
    }

    /// The recorder stopped itself (interruption): drop ownership so a tap can start
    /// a fresh dictation. The recorder is already .idle, so nothing to cancel.
    private func releaseOnInterruption() {
        owner = nil
        ownerTab = nil
    }

    /// Whether `token` owns dictation right now.
    func owns(_ token: UUID) -> Bool { owner == token }

    /// Whether `token` owns dictation AND the recorder is running/finalizing, so a
    /// non-owning or not-yet-started bar doesn't react to the shared recorder.
    func isActive(_ token: UUID) -> Bool { owner == token && voice.state != .idle }

    enum StartOutcome: Equatable {
        case started
        case alreadyActive      // a start for this token is already in flight/active
        case busy               // another bar owns the cycle
        case superseded         // this bar was dismissed / switched away during startup
        case failed(String)     // startup error, message ready for an alert
    }

    /// Claim ownership and start the recorder for `token`, atomically. Refuses if
    /// ANY start is already in flight or active (owner is set synchronously at the
    /// top, before the first await), so a re-entrant same-token call (a double tap,
    /// which schedules two start Tasks before the recorder reaches .listening) does
    /// NOT re-claim + re-prepare - otherwise its post-await release would tear down
    /// the FIRST call's live recorder, stranding a hot mic no one owns. The model
    /// load and mic-permission awaits are then bracketed by `owner == token`
    /// re-checks, so a dismissal (onDisappear -> relinquish) or tab switch
    /// (tabChanged -> cancelActive) during startup bails and cancels a recorder
    /// that had already started.
    func start(token: UUID, tab: AppModel.AppTab) async -> StartOutcome {
        guard owner == nil else {
            return owner == token ? .alreadyActive : .busy
        }
        owner = token
        ownerTab = tab
        await whisper.prepare()
        guard owner == token, voice.state == .idle else {
            release(token)
            return .superseded
        }
        do {
            let didStart = try await voice.start()
            // Ownership may have been revoked during start()'s permission await.
            guard owner == token else {
                if didStart { voice.cancel() }   // stop a recorder we just orphaned
                release(token)
                return .superseded
            }
            guard didStart else {
                // The recorder was busy for someone else; drop our claim.
                release(token)
                return .busy
            }
            return .started
        } catch {
            release(token)
            return .failed(Self.message(for: error))
        }
    }

    /// Stop the recorder and return the final transcript, but only if `token`
    /// still owns it. nil means ownership was lost during stop() (a tab switch /
    /// dismissal), so the caller must not deliver a draft now missing its dictated
    /// tail.
    func finish(token: UUID) async -> String? {
        guard owner == token else { return nil }
        let text = await voice.stop()
        guard owner == token else { return nil }
        release(token)
        return text
    }

    /// Relinquish: cancel the recorder and drop ownership if `token` owns it (its
    /// bar left the screen).
    func relinquish(_ token: UUID) {
        guard owner == token else { return }
        voice.cancel()
        release(token)
    }

    /// The visible tab changed; cancel dictation if its owner is no longer on it.
    func tabChanged(to tab: AppModel.AppTab) {
        if let ownerTab, ownerTab != tab { cancelActive() }
    }

    /// Force teardown regardless of owner (e.g. unpair). No-op when idle.
    func cancelActive() {
        guard let owner else { return }
        voice.cancel()
        release(owner)
    }

    private func release(_ token: UUID) {
        guard owner == token else { return }
        owner = nil
        ownerTab = nil
    }

    static func message(for error: Error) -> String {
        switch error {
        case VoiceCaptureError.microphonePermissionDenied:
            return "Allow microphone access for iTerm2 Buddy in the Settings app to dictate."
        case VoiceCaptureError.modelNotReady:
            return "The voice model is not ready yet. Try again in a moment."
        default:
            return "Could not start dictation."
        }
    }
}
