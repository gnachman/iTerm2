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

    func willLoadURL(_ url: URL) {
        lastRequestedURL = url
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
