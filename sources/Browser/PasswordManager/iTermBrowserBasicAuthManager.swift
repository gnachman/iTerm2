//
//  iTermBrowserBasicAuthManager.swift
//  iTerm2
//
//  The WebKit/AppKit adapter for the built-in browser's HTTP basic-auth handling. It owns the
//  pure BrowserBasicAuthCoordinator state machine (which decides everything and is unit tested
//  without WebKit) and does the impure work the coordinator's Effects describe: answer a WKWebView
//  challenge, look up / prompt / pick / persist a credential, and feed the coordinator the
//  navigation-lifecycle Events translated from WKNavigationDelegate callbacks.
//
//  iTermBrowserManager forwards its navigation-delegate callbacks here and otherwise knows nothing
//  about basic auth. See BrowserBasicAuthCoordinator for the guarantees provided and the WebKit
//  limitations accepted.
//

@preconcurrency import WebKit
import AppKit

@MainActor
final class iTermBrowserBasicAuthManager {
    private let store: iTermBrowserBasicAuthStore
    // Provides the parent window for prompts, the picker sheet, and store auth dialogs. A closure
    // rather than a webView reference so this class stays decoupled from the webView's identity and
    // sees the current window even if the host swaps its webView.
    private let hostWindow: () -> NSWindow?

    // The state machine that decides all basic-auth handling.
    private let coordinator = BrowserBasicAuthCoordinator()

    // Retained while the basic-auth password-manager picker is on screen.
    private var picker: iTermBrowserBasicAuthPasswordPicker?

    // Outstanding WKWebView challenge completion handlers, keyed by the ChallengeID we handed the
    // coordinator, so a terminal effect (.supply/.cancel/.defaultHandling) answers exactly the
    // right challenge. Each is removed as it is answered, enforcing exactly-once completion.
    private struct ChallengeSlot {
        let completion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        let proposedUser: String?
    }
    private var slots = [BrowserBasicAuthCoordinator.ChallengeID: ChallengeSlot]()
    private var nextChallengeID = 0

    // The current main-frame provisional navigation, so a late commit/failure for a superseded
    // load does not clear the live load's coordinator state. WebKit hands these callbacks a
    // WKNavigation; the coordinator is WebKit-free, so the identity guard lives here.
    private weak var mainNavigation: WKNavigation?

    // The URL of the pending main-frame navigation, captured in decidePolicyForNavigationAction
    // (main frame only) and updated on each redirect step. Used to classify a basic-auth challenge
    // as main-vs-subframe. This is deliberately NOT navigationState.lastRequestedURL, which is also
    // written by subframe navigation actions and so could carry a subframe origin at provisional
    // start, misclassifying a genuine main-frame challenge.
    private var mainFrameURL: URL?

    // True when mainFrameURL was captured by decidePolicyForNavigationAction for the main-frame
    // navigation that is about to start (or redirect) provisionally, and has not yet been consumed.
    // Reset to false as soon as it is read, so a stale URL left over from a PRIOR navigation is
    // never treated as the current provisional navigation's origin. A navigation that provides no
    // main-frame navigation action (so decidePolicyForNavigationAction did not run for it) leaves
    // this false, and the coordinator is told the origin is unknown (nil), which is fail-safe
    // (default handling) rather than inheriting the previous navigation's origin and misclassifying
    // a genuine main-frame challenge.
    private var mainFrameURLIsFresh = false

    init(user: iTermBrowserUser, hostWindow: @escaping () -> NSWindow?) {
        self.store = iTermBrowserBasicAuthStore(user: user)
        self.hostWindow = hostWindow
    }

    // MARK: - Navigation-delegate hooks (called by iTermBrowserManager)

    // Handle a basic/digest/NTLM challenge. Terminal disposition is delivered via completionHandler
    // exactly once.
    func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let ps = challenge.protectionSpace
        // Lowercase the scheme and host so the SpaceKey origin matches the URL-derived main-frame
        // response origin (see origin(from:), which lowercases both) and so Example.com /
        // example.com (or a mixed-case protocol) do not create two separate password-manager
        // entries or misclassify a genuine main-frame challenge as a subframe.
        let space = BrowserBasicAuthCoordinator.SpaceKey(scheme: (ps.protocol ?? "").lowercased(),
                                                         host: ps.host.lowercased(),
                                                         port: ps.port,
                                                         realm: ps.realm ?? "")
        let id = BrowserBasicAuthCoordinator.ChallengeID(nextChallengeID)
        nextChallengeID += 1
        slots[id] = ChallengeSlot(completion: completionHandler,
                                  proposedUser: challenge.proposedCredential?.user)
        let isBasic = (ps.authenticationMethod == NSURLAuthenticationMethodHTTPBasic)
        // A silent saved lookup is only possible when the store can be read without an interactive
        // auth prompt; otherwise the coordinator prompts instead of auto-filling.
        let savedLookupPossible = store.canRemember && store.isUnlockedWithoutPrompt
        DLog("BasicAuth: challenge for \(space.host):\(space.port) realm=\(space.realm) isBasic=\(isBasic)")
        run(coordinator.reduce(.challenge(id: id,
                                          space: space,
                                          isBasic: isBasic,
                                          proposedUser: challenge.proposedCredential?.user,
                                          savedLookupPossible: savedLookupPossible,
                                          storeCanRemember: store.canRemember)))
    }

    func didStartProvisionalNavigation(_ navigation: WKNavigation?) {
        // A new main-frame load supersedes any earlier one. Tell the coordinator so it drops any
        // credential still awaiting a response from the prior load and records this navigation's
        // origin for main-vs-subframe classification.
        mainNavigation = navigation
        run(coordinator.reduce(.mainProvisionalStarted(origin: consumeMainFrameOrigin())))
    }

    func didReceiveServerRedirect(_ navigation: WKNavigation?) {
        // Same main navigation, new target origin. Update the coordinator's origin so a challenge
        // for the redirect target is still recognized as the main document; the pending supply is
        // kept (the final response resolves whatever is pending then). Only for the live nav.
        if navigation === mainNavigation {
            run(coordinator.reduce(.mainFrameRedirect(origin: consumeMainFrameOrigin())))
        }
    }

    func didCommit(_ navigation: WKNavigation?) {
        // The main document has committed; a basic-auth challenge from here on is a subresource or
        // iframe (out of scope), not the main document. Only clear the coordinator's main-nav state
        // if THIS is the navigation that owns it: a late commit for a superseded load must not wipe
        // the live load's state.
        if navigation === mainNavigation {
            mainNavigation = nil
            run(coordinator.reduce(.mainCommitted))
        }
    }

    func didFailProvisionalNavigation(_ navigation: WKNavigation?) {
        // The main-frame load failed before any response, so no main-frame response will arrive to
        // confirm a credential supplied during it. Tell the coordinator to drop it. Only if THIS is
        // the navigation that owns the state: a late provisional failure for a superseded load must
        // not wipe the live load's state.
        if navigation === mainNavigation {
            mainNavigation = nil
            run(coordinator.reduce(.mainEndedWithoutResponse))
        }
    }

    // Record the main-frame navigation target from decidePolicyForNavigationAction. This runs for
    // the initial request and for each server-redirect step (WebKit calls the action policy for
    // redirect targets with isMainFrame == true), so it stays current for both
    // didStartProvisionalNavigation and didReceiveServerRedirect.
    func recordMainFrameNavigationAction(url: URL?) {
        mainFrameURL = url
        mainFrameURLIsFresh = true
    }

    // The main-frame HTTP response is the authoritative signal for whether a basic-auth credential
    // we supplied for the main document was accepted (2xx) or rejected (401). Feed it to the
    // coordinator, which matches it to the pending credential by origin.
    func handleNavigationResponse(_ navigationResponse: WKNavigationResponse) {
        guard navigationResponse.isForMainFrame,
              let httpResponse = navigationResponse.response as? HTTPURLResponse,
              let origin = origin(from: navigationResponse.response.url) else {
            return
        }
        run(coordinator.reduce(.mainFrameResponse(origin: origin, status: httpResponse.statusCode)))
    }

    // MARK: - Effect execution

    private func run(_ effects: [BrowserBasicAuthCoordinator.Effect]) {
        for effect in effects {
            execute(effect)
        }
    }

    private func execute(_ effect: BrowserBasicAuthCoordinator.Effect) {
        switch effect {
        case let .supply(id, credential):
            DLog("BasicAuth: supplying credential for user '\(credential.user)'")
            // Persistence MUST be .forSession, not .none: empirically WKWebView drops a .none
            // credential entirely (no Authorization header is sent), so every login silently fails.
            // .forSession is the credential that is actually transmitted and cached by WebKit for
            // reuse on later same-space requests.
            answer(id, .useCredential,
                   URLCredential(user: credential.user,
                                 password: credential.password,
                                 persistence: .forSession))
        case let .cancel(id):
            answer(id, .cancelAuthenticationChallenge, nil)
        case let .defaultHandling(id):
            answer(id, .performDefaultHandling, nil)
        case let .lookupSaved(id, space, preferredUser):
            store.lookup(scheme: space.scheme, host: space.host, port: space.port,
                         realm: space.realm, preferredUser: preferredUser,
                         window: hostWindow()) { [weak self] remembered in
                // The backend may call back off the main thread; hop back before touching state.
                DispatchQueue.main.async {
                    guard let self else { return }
                    let credential = remembered.map {
                        BrowserBasicAuthCoordinator.Credential(user: $0.user, password: $0.password)
                    }
                    self.run(self.coordinator.reduce(.savedLookupResult(id: id, credential: credential)))
                }
            }
        case let .prompt(id, request):
            showPrompt(id: id, request: request)
        case let .showPicker(id, space, typed):
            showPicker(id: id, space: space, typed: typed)
        case let .persist(space, credential):
            persist(space: space, credential: credential)
        case let .toast(message):
            ToastWindowController.showToast(withMessage: message)
        }
    }

    // Answers a challenge exactly once: the completion is removed as it is called, so a stray
    // duplicate terminal effect for the same id is a no-op rather than a double-call (which would
    // crash) or a missing call (which would hang the load).
    private func answer(_ id: BrowserBasicAuthCoordinator.ChallengeID,
                        _ disposition: URLSession.AuthChallengeDisposition,
                        _ credential: URLCredential?) {
        guard let slot = slots.removeValue(forKey: id) else {
            return
        }
        slot.completion(disposition, credential)
    }

    private func showPrompt(id: BrowserBasicAuthCoordinator.ChallengeID,
                            request: BrowserBasicAuthCoordinator.PromptRequest) {
        let host = request.space.host
        let realm = request.space.realm
        let promptText: String
        if !realm.isEmpty {
            promptText = "The website “\(host)” requires a user name and password for “\(realm)”."
        } else {
            promptText = "The website “\(host)” requires a user name and password."
        }
        let alert = ModalPasswordAlert(promptText)
        // A non-nil username makes ModalPasswordAlert show a user name field.
        alert.username = request.prefill?.user.nilIfEmpty ?? slots[id]?.proposedUser ?? ""
        alert.initialPassword = request.prefill?.password
        if request.offerPasswordManager {
            alert.showPasswordManagerButton = true
        }
        if request.offerRemember {
            alert.showRememberCheckbox = true
            alert.rememberByDefault = request.rememberByDefault
        }
        // runAsyncOutcome presents a sheet when the window is visible and an app-modal panel
        // otherwise. Passing a non-visible window would call beginSheetModal on it, whose
        // completion may never fire and would hang the WKWebView challenge forever, so mirror
        // ModalPasswordAlert.run and only pass a visible window.
        let window = hostWindow()
        let sheetWindow = (window?.isVisible == true) ? window : nil
        alert.runAsyncOutcome(window: sheetWindow) { [weak self] outcome in
            guard let self else { return }
            let mapped: BrowserBasicAuthCoordinator.PromptOutcome
            switch outcome {
            case .cancel:
                mapped = .cancelled
            case .ok(let password):
                mapped = .submitted(BrowserBasicAuthCoordinator.Credential(user: alert.username ?? "",
                                                                           password: password),
                                    remember: alert.rememberChecked)
            case .passwordManager(let typedPassword):
                let typed = BrowserBasicAuthCoordinator.Credential(user: alert.username ?? "",
                                                                   password: typedPassword)
                mapped = .openPasswordManager(typed: typed)
            }
            self.run(self.coordinator.reduce(.promptResult(id: id, outcome: mapped)))
        }
    }

    private func showPicker(id: BrowserBasicAuthCoordinator.ChallengeID,
                            space: BrowserBasicAuthCoordinator.SpaceKey,
                            typed: BrowserBasicAuthCoordinator.Credential?) {
        let picker = iTermBrowserBasicAuthPasswordPicker()
        self.picker = picker
        let accountName = iTermBrowserBasicAuthStore.accountName(scheme: space.scheme, host: space.host,
                                                                 port: space.port, realm: space.realm)
        picker.present(in: hostWindow(), accountName: accountName) { [weak self] credential in
            guard let self else { return }
            self.picker = nil
            let chosen = credential.map {
                BrowserBasicAuthCoordinator.Credential(user: $0.user, password: $0.password)
            }
            self.run(self.coordinator.reduce(.pickerResult(id: id, chosen: chosen, typedFallback: typed)))
        }
    }

    private func persist(space: BrowserBasicAuthCoordinator.SpaceKey,
                         credential: BrowserBasicAuthCoordinator.Credential) {
        DLog("BasicAuth: saving remembered credential for \(space.host)")
        let storeCredential = iTermBrowserBasicAuthStore.Credential(user: credential.user,
                                                                    password: credential.password)
        let host = space.host
        // A save completion may arrive off the main thread (CLI-backed adapters); hop back before
        // feeding the coordinator. We do NOT bound this with a timeout that fabricates a failure: a
        // slow-but-successful write must not surface a spurious "Could not save" toast. Only a real
        // completion drives the outcome; if a backend drops its completion, the credential simply is
        // not confirmed saved and no toast is shown.
        store.save(storeCredential, scheme: space.scheme, host: space.host,
                   port: space.port, realm: space.realm, window: hostWindow()) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.run(self.coordinator.reduce(.saveResult(space: space, host: host, success: success)))
            }
        }
    }

    // MARK: - Helpers

    // The origin of the current main-frame provisional navigation, or nil if
    // decidePolicyForNavigationAction did not capture a URL for it (see mainFrameURLIsFresh).
    // Consuming resets the freshness flag so a stale URL cannot be reused for a subsequent
    // navigation that provides no navigation action of its own.
    private func consumeMainFrameOrigin() -> BrowserBasicAuthCoordinator.Origin? {
        defer { mainFrameURLIsFresh = false }
        guard mainFrameURLIsFresh else {
            return nil
        }
        return origin(from: mainFrameURL)
    }

    private func origin(from url: URL?) -> BrowserBasicAuthCoordinator.Origin? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host else {
            return nil
        }
        let defaultPort = (scheme == "https") ? 443 : (scheme == "http" ? 80 : -1)
        // Lowercase the host so this origin (built from a URL) compares equal to the SpaceKey origin
        // (built from the protection space) even if the two WebKit sources disagree on case; DNS is
        // case-insensitive so this loses nothing.
        return BrowserBasicAuthCoordinator.Origin(scheme: scheme, host: host.lowercased(), port: url.port ?? defaultPort)
    }
}
