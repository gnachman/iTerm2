//
//  BrowserBasicAuthCoordinator.swift
//  iTerm2
//
//  A pure state machine for the built-in browser's HTTP basic-auth credential
//  remembering. It is driven by Events (translated from WKNavigationDelegate
//  callbacks and async completions by iTermBrowserManager) and returns Effects
//  (which the manager executes: answer a challenge, look up / prompt / persist).
//  It never touches WebKit, AppKit, or the network directly, so its whole
//  behavior is a transition table that is unit tested without WebKit.
//
//  WHY A SEPARATE OBJECT: whether a basic-auth credential was accepted can only
//  be learned from signals WebKit does not link together. The challenge callback
//  carries no frame or navigation identity; the authoritative accept/reject
//  signal is the main-frame HTTP response, which arrives on a different callback
//  with no back reference to the challenge. Getting that correlation right was
//  the source of every past bug, so it lives here, isolated and testable,
//  instead of smeared across delegate methods and ad hoc state.
//
//  SCOPE: only MAIN-DOCUMENT challenges get the full treatment (auto-fill,
//  remember, persist). A challenge we cannot confidently attribute to the main
//  document (a subframe/iframe, a cross-origin subresource, or anything after the
//  main frame commits) is still PROMPTED so the user can sign in, but it is never
//  auto-filled, remembered, or persisted: we cannot confirm its acceptance (no
//  main-frame response corresponds to it) and WebKit gives no frame identity.
//
//  These behaviors were measured on macOS with the harness in
//  scratchpad/webkitauth (see FINDINGS.md); the design does not depend on any of
//  them except the main-frame response, which is the documented reliable path.
//
//  === WHAT WE HANDLE (guarantees) =========================================
//  1. Exactly one terminal decision per challenge. Every challenge ends in
//     exactly one of .supply / .cancel (a prompt outcome; .defaultHandling
//     remains available but is not currently emitted), so the WKWebView challenge
//     completion is called exactly once and a load never hangs.
//  2. No synthetic HTTP is ever sent. Acceptance is read only from the user's
//     own main-frame navigation response, so we never hit a server (idempotent
//     or not) with a request it did not ask for.
//  3. A remembered credential is persisted ONLY after the main-frame response
//     for its origin is 2xx. Never on 401/3xx/5xx, so a wrong password or a
//     captive-portal / proxy login page cannot be saved.
//  4. A store-derived credential (saved or picked) seen rejected this session is
//     never silently re-supplied for that space, so we cannot loop on a known
//     bad one. Rejection is detected two ways, both from our own tracking: a
//     re-challenge for a space we already supplied this navigation, and a
//     main-frame 401. Neither relies on previousFailureCount.
//  5. Correlation is origin-exact and single-space: a main-frame response
//     resolves at most the one supplied credential whose origin matches, so a
//     redirect chain or a second accumulated space is never blanket-stamped.
//  6. State cannot leak into a permanent lockout: lastEntered is prompt prefill
//     ONLY and never suppresses auto-fill, so a cancelled or abandoned prompt
//     leaves no latch behind.
//  7. Superseded navigations become no-ops: the awaiting slot is cleared on
//     every provisional start and the response is origin-matched, so a late or
//     superseded response finds nothing to resolve.
//
//  === KNOWN FLAWS WE ACCEPT (WebKit API limitations) ======================
//  A. No frame identity on the challenge. "Is this the main document?" is a
//     heuristic: the main frame is provisional (not yet committed) and the
//     challenge origin equals the main provisional origin. A same-origin
//     subframe that challenges while the main frame is still provisional can be
//     misclassified as main. To keep this from persisting or rejecting the wrong
//     credential, mainFrameResponse applies an ambiguity guard: if two distinct
//     spaces at one origin were challenged as main in a single navigation, the
//     response (origin only, no realm) is not attributed to either, so nothing is
//     persisted or marked rejected.
//  B. Subframes are prompt-only (see SCOPE). A protected iframe or cross-origin
//     subresource still gets a sign-in prompt so the user can authenticate, but it
//     is never auto-filled, remembered, or persisted (we cannot confirm its
//     acceptance).
//  C. WebKit owns its credential cache. An accepted credential is cached and
//     reused by WebKit without re-challenging (which is what we want). A rejected
//     credential is not cached and re-challenges on reload, so there is no
//     stuck-on-a-bad-credential lockup; we cannot flush that cache via public API.
//  D. Redirect chains deliver only the FINAL main-frame response. A credential
//     accepted only on an intermediate origin that then redirected away is not
//     persisted (fail-safe: the user re-enters next time).
//
//  Everything above is expressed in reduce(_:). If a transition changes, update
//  these lists.
//

import Foundation

@MainActor
final class BrowserBasicAuthCoordinator {

    // MARK: - Domain types

    /// Full identity of a protection space. This is the one thing the challenge
    /// callback gives us reliably.
    struct SpaceKey: Hashable {
        let scheme: String   // "http" or "https"
        let host: String
        let port: Int
        let realm: String
        var origin: Origin { Origin(scheme: scheme, host: host, port: port) }
    }

    /// Coarser identity used to match a main-frame response, which carries a URL
    /// (hence an origin) but no realm.
    struct Origin: Hashable {
        let scheme: String
        let host: String
        let port: Int
    }

    struct Credential: Equatable {
        let user: String
        let password: String
    }

    /// Where a supplied credential came from. A typed rejection is private to the
    /// user and marks nothing; a saved or picked rejection marks the space so we
    /// stop auto-filling it this session.
    enum Source: Equatable {
        case saved
        case typed
        case picked
    }

    /// Per-challenge token assigned by the manager so async results and terminal
    /// effects route back to the right completion handler even with concurrent
    /// challenges.
    struct ChallengeID: Hashable {
        let raw: Int
        init(_ raw: Int) { self.raw = raw }
    }

    // MARK: - Events (inputs)

    enum Event: Equatable {
        // Navigation lifecycle. WebKit reports these for the MAIN frame only.
        case mainProvisionalStarted(origin: Origin?)   // didStartProvisionalNavigation (fresh nav)
        case mainFrameRedirect(origin: Origin?)        // didReceiveServerRedirectForProvisionalNavigation
        case mainFrameResponse(origin: Origin, status: Int)
        case mainCommitted
        case mainEndedWithoutResponse

        // Challenge, from any frame. WebKit gives no frame identity.
        // savedLookupPossible: the store is readable without an interactive prompt.
        // storeCanRemember: the store allows remembering at all (false for /dev/null).
        case challenge(id: ChallengeID,
                       space: SpaceKey,
                       isBasic: Bool,
                       proposedUser: String?,
                       savedLookupPossible: Bool,
                       storeCanRemember: Bool)

        // Async results for effects the manager ran.
        case savedLookupResult(id: ChallengeID, credential: Credential?)
        case promptResult(id: ChallengeID, outcome: PromptOutcome)
        case pickerResult(id: ChallengeID, chosen: Credential?, typedFallback: Credential?)
        case saveResult(space: SpaceKey, host: String, success: Bool)
    }

    enum PromptOutcome: Equatable {
        case cancelled
        case submitted(Credential, remember: Bool)
        case openPasswordManager(typed: Credential?)
    }

    // MARK: - Effects (outputs the manager executes)

    enum Effect: Equatable {
        case supply(id: ChallengeID, Credential)   // terminal
        case cancel(id: ChallengeID)               // terminal
        case defaultHandling(id: ChallengeID)      // terminal
        case lookupSaved(id: ChallengeID, space: SpaceKey, preferredUser: String?)
        case prompt(id: ChallengeID, PromptRequest)
        case showPicker(id: ChallengeID, space: SpaceKey, typed: Credential?)
        case persist(space: SpaceKey, Credential)
        case toast(String)
    }

    struct PromptRequest: Equatable {
        let space: SpaceKey
        let prefill: Credential?
        let offerRemember: Bool
        let offerPasswordManager: Bool
        let rememberByDefault: Bool
    }

    // MARK: - State

    private struct SpaceState {
        var savedRejectedThisSession = false
        var lastEntered: Credential?
    }
    private var spaces: [SpaceKey: SpaceState] = [:]

    /// The single main-document credential supplied and awaiting its main-frame
    /// response. At most one, because WebKit runs one provisional main navigation
    /// at a time.
    private struct Awaiting {
        let space: SpaceKey
        let credential: Credential
        let source: Source
        let remember: Bool
    }
    private var awaiting: Awaiting?

    /// Distinct protection spaces challenged as the main document during the current navigation
    /// (accumulated across redirect steps, reset on a fresh provisional start or commit). Used to
    /// detect the flaw-A ambiguity where a same-origin subframe is misclassified as main: if two
    /// distinct spaces at one origin are challenged as main in a single navigation, the main-frame
    /// response (which carries only an origin, no realm) cannot be attributed to one of them.
    private var mainChallengedSpaces: Set<SpaceKey> = []

    private var mainProvisionalOrigin: Origin?
    private var mainProvisional = false

    private struct Context {
        let space: SpaceKey
        let isBasic: Bool
        let storeCanRemember: Bool
    }
    private var contexts: [ChallengeID: Context] = [:]

    // MARK: - Transition table

    func reduce(_ event: Event) -> [Effect] {
        switch event {

        case let .mainProvisionalStarted(origin):
            mainProvisional = true
            mainProvisionalOrigin = origin
            awaiting = nil                      // supersede: an earlier supply will not be resolved
            mainChallengedSpaces.removeAll()    // fresh navigation: forget the prior chain's spaces
            return []

        case let .mainFrameRedirect(origin):
            // Same navigation, new target origin. Keep any pending supply: the
            // later challenge in the chain overwrites it, and the final response
            // resolves whatever is pending then. mainChallengedSpaces accumulates across the
            // redirect chain (not reset here) so intermediate origins stay distinguishable.
            mainProvisional = true
            mainProvisionalOrigin = origin
            return []

        case .mainCommitted, .mainEndedWithoutResponse:
            mainProvisional = false
            mainProvisionalOrigin = nil
            awaiting = nil                      // response, if any, already resolved before commit
            mainChallengedSpaces.removeAll()
            return []

        case let .challenge(id, space, isBasic, proposedUser, savedLookupPossible, storeCanRemember):
            let isMain = mainProvisional && mainProvisionalOrigin == space.origin
            let ctx = Context(space: space, isBasic: isBasic, storeCanRemember: storeCanRemember)
            contexts[id] = ctx
            guard isMain else {
                // Subframe / post-commit / cross-origin. We cannot confirm acceptance for these
                // (no corresponding main-frame response) and WebKit gives us no frame identity, so
                // we never auto-fill, remember, or persist them. We DO still prompt so the user can
                // sign in to a protected iframe or cross-origin subresource; the credential is
                // supplied for this one challenge and never tracked (isChallengeLive is false for a
                // non-main challenge, so supply() records nothing). See flaw B.
                return [promptEffect(id: id, ctx: ctx, forceNoStore: true)]
            }
            // Best-effort main document. Record its space so a same-origin flaw-A ambiguity (a
            // subframe misclassified as main) can be detected at response time.
            mainChallengedSpaces.insert(space)

            if awaiting?.space == space {
                // A credential we already supplied for this space this navigation was
                // rejected (WebKit re-challenges). Never re-auto-fill it.
                if let a = awaiting, a.source != .typed {
                    spaces[space, default: .init()].savedRejectedThisSession = true
                }
                awaiting = nil
                return [promptEffect(id: id, ctx: ctx)]
            }

            if !isBasic {
                // Digest / NTLM: plain prompt, no remember, no store round-tripping.
                return [promptEffect(id: id, ctx: ctx, forceNoStore: true)]
            }

            let rejected = spaces[space]?.savedRejectedThisSession ?? false
            if savedLookupPossible && !rejected {
                return [.lookupSaved(id: id, space: space, preferredUser: proposedUser)]
            }
            return [promptEffect(id: id, ctx: ctx)]

        case let .savedLookupResult(id, credential):
            guard let ctx = contexts[id] else { return [] }
            if let credential {
                return supply(id: id, ctx: ctx, credential: credential, source: .saved, remember: false)
            }
            // Nothing saved: prompt. But if the navigation was superseded while the async
            // lookup was outstanding, this challenge is for a page the user already left;
            // surfacing an unsolicited prompt for a dead navigation is confusing, so cancel
            // it instead. (The credential-found branch above defers to supply(), which
            // performs the same liveness check before recording anything.)
            guard isChallengeLive(ctx) else {
                contexts[id] = nil
                return [.cancel(id: id)]
            }
            return [promptEffect(id: id, ctx: ctx)]

        case let .promptResult(id, outcome):
            guard let ctx = contexts[id] else { return [] }
            switch outcome {
            case .cancelled:
                contexts[id] = nil
                return [.cancel(id: id)]
            case let .submitted(credential, remember):
                spaces[ctx.space, default: .init()].lastEntered = credential
                let willRemember = remember && ctx.isBasic && ctx.storeCanRemember
                return supply(id: id, ctx: ctx, credential: credential, source: .typed, remember: willRemember)
            case let .openPasswordManager(typed):
                return [.showPicker(id: id, space: ctx.space, typed: typed)]
            }

        case let .pickerResult(id, chosen, typedFallback):
            guard let ctx = contexts[id] else { return [] }
            if let chosen, !chosen.user.isEmpty {
                spaces[ctx.space, default: .init()].lastEntered = chosen
                return supply(id: id, ctx: ctx, credential: chosen, source: .picked, remember: false)
            }
            // Backed out, or an entry with no username (basic auth needs one).
            // Re-prompt, prefilling what we know so the user does not retype it.
            let prefill = mergePrefill(picked: chosen,
                                       typed: typedFallback,
                                       last: spaces[ctx.space]?.lastEntered)
            let offer = ctx.isBasic && ctx.storeCanRemember
            return [.prompt(id: id, PromptRequest(space: ctx.space,
                                                  prefill: prefill,
                                                  offerRemember: offer,
                                                  offerPasswordManager: offer,
                                                  rememberByDefault: offer))]

        case let .mainFrameResponse(origin, status):
            guard let a = awaiting, a.space.origin == origin else {
                awaiting = nil                  // redirected away or superseded: drop, fail-safe
                return []
            }
            awaiting = nil
            // Ambiguity guard (flaw A): if two or more distinct protection spaces at this origin
            // were challenged as the main document this navigation (main document + a same-origin
            // subframe misclassified as main), the response carries only an origin and cannot be
            // attributed to a specific space. Refuse to persist or mark-rejected - either would act
            // on the wrong credential. Fail-safe: the user re-enters next time. (A redirect chain
            // is NOT ambiguous: its extra spaces live on different origins, so only one shares this
            // response origin.)
            if mainChallengedSpaces.filter({ $0.origin == origin }).count > 1 {
                return []
            }
            return resolve(a, status: status)

        case let .saveResult(space, host, success):
            if success {
                spaces[space, default: .init()].savedRejectedThisSession = false
                return []
            }
            return [.toast("Could not save the password for \(host)")]
        }
    }

    // MARK: - Resolution of an accepted or rejected main-document credential

    private func resolve(_ a: Awaiting, status: Int) -> [Effect] {
        if status == 401 {
            // Rejected. A store-derived credential is marked bad so we stop
            // auto-filling it this session; a typed one persists nothing.
            if a.source != .typed {
                spaces[a.space, default: .init()].savedRejectedThisSession = true
            }
            return []
        }
        // Any non-401 means the login itself worked (even a 403: authenticated
        // but forbidden). Re-enable auto-fill of the saved value ONLY when the
        // saved value is what succeeded. A typed or picked success says nothing
        // about the saved credential (which is unchanged in the store), so it must
        // not clear the flag - otherwise a session where the user overrode a bad
        // saved credential without re-saving would auto-fill the known-bad saved
        // value again on the next challenge (guarantee 4). When the user typed a
        // new credential with Remember on, the persist path clears the flag via
        // .saveResult instead.
        if a.source == .saved {
            spaces[a.space, default: .init()].savedRejectedThisSession = false
        }
        if a.remember, (200..<300).contains(status) {
            return [.persist(space: a.space, a.credential)]
        }
        return []
    }

    // MARK: - Supply bookkeeping

    private func supply(id: ChallengeID,
                        ctx: Context,
                        credential: Credential,
                        source: Source,
                        remember: Bool) -> [Effect] {
        contexts[id] = nil                      // terminal for this challenge
        if isChallengeLive(ctx) {
            // Live main navigation: track for the coming main-frame response. If the
            // navigation moved on while an async lookup / prompt was outstanding, we
            // still answer the (dead) challenge but record nothing.
            awaiting = Awaiting(space: ctx.space, credential: credential,
                                source: source, remember: remember)
        }
        return [.supply(id: id, credential)]
    }

    // True when the challenge's navigation is still the live main provisional navigation.
    // Once the user navigates away (supersede) or the document commits, a challenge captured
    // earlier is stale: we answer it but neither record it as awaiting nor prompt for it.
    private func isChallengeLive(_ ctx: Context) -> Bool {
        return mainProvisional && mainProvisionalOrigin == ctx.space.origin
    }

    // MARK: - Prompt construction

    private func promptEffect(id: ChallengeID, ctx: Context, forceNoStore: Bool = false) -> Effect {
        let canStore = !forceNoStore && ctx.isBasic && ctx.storeCanRemember
        let state = spaces[ctx.space]
        // Default the Remember checkbox to ON only when a saved credential for this space was
        // rejected this session: the user is being asked to correct a known-bad stored password,
        // so pre-checking Remember lets the correction replace it. Do NOT default it on merely
        // because the user typed a credential here before (lastEntered != nil): if they typed one
        // earlier with Remember unchecked, that was an explicit decline and must be honored, not
        // silently reversed on the next prompt.
        let rememberByDefault = canStore && (state?.savedRejectedThisSession == true)
        return .prompt(id: id, PromptRequest(space: ctx.space,
                                             prefill: state?.lastEntered,
                                             offerRemember: canStore,
                                             offerPasswordManager: canStore,
                                             rememberByDefault: rememberByDefault))
    }

    private func mergePrefill(picked: Credential?, typed: Credential?, last: Credential?) -> Credential? {
        let user = nonEmpty(typed?.user) ?? nonEmpty(picked?.user) ?? nonEmpty(last?.user)
        let password = nonEmpty(picked?.password) ?? nonEmpty(typed?.password) ?? nonEmpty(last?.password)
        if user == nil && password == nil {
            return nil
        }
        return Credential(user: user ?? "", password: password ?? "")
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
