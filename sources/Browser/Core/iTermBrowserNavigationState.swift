//
//  iTermBrowserNavigationState.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit

@available(macOS 11.0, *)
class iTermBrowserNavigationState {
    private(set) var lastTransitionType: BrowserTransitionType = .other
    private(set) var lastRequestedURL: URL?
    private enum State {
        case ground
        case loading(URL, CheckedContinuation<Void, Error>?)
        case loaded(URL)
    }
    enum NavigationError: Error {
        case interrupted
    }
    private var state = State.ground

    func willLoadURL(_ url: URL, continuation: CheckedContinuation<Void, Error>) {
        switch state {
        case .loading(_, let continuation):
            continuation?.resume(throwing: NavigationError.interrupted)
        case .loaded, .ground:
            break
        }

        lastRequestedURL = url
        state = .loading(url, continuation)
    }

    func willLoadURL(_ url: URL) {
        lastRequestedURL = url
        switch state {
        case .loading:
            // No change. Assume the URL did not change.
            break
        case .loaded, .ground:
            state = .loading(url, nil)
        }
    }

    func didCompleteLoading(error: Error?) {
        switch state {
        case .ground, .loaded:
            break
        case .loading(let url, let continuation):
            if let error, let continuation {
                continuation.resume(throwing: error)
            } else {
                continuation?.resume(with: .success(()))
            }
            state = .loaded(url)
        }
    }

    func willNavigate(action navigationAction: WKNavigationAction) {
        switch navigationAction.navigationType {
        case .linkActivated:
            lastTransitionType = .link
        case .formSubmitted:
            lastTransitionType = .formSubmit
        case .backForward:
            lastTransitionType = .backForward
        case .reload:
            lastTransitionType = .reload
        case .formResubmitted:
            lastTransitionType = .formSubmit
        case .other:
            // Check if this looks like a typed URL (from loadURL method)
            if navigationAction.request.url == lastRequestedURL {
                lastTransitionType = .typed
            } else {
                lastTransitionType = .other
            }
        @unknown default:
            lastTransitionType = .other
        }
    }
}
