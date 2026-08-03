//
//  iTermLocalNetworkPermissionPrompter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/16/26.
//

import Foundation
import Network

/// Prompts for local network permission by briefly browsing for Bonjour services.
/// This is needed because macOS doesn't show the permission prompt until an app actually
/// tries to access the local network. Without this, users may find that commands like
/// `ping 10.0.0.1` fail with "No route to host" until they reboot.
///
/// The probe runs on every launch. macOS shows its prompt only when TCC has no recorded
/// decision for the app, so re-probing an app that's already been allowed or denied is
/// silent. Probing unconditionally lets us recover the permission after events that clear
/// the TCC record (a `tccutil reset`, or an OS upgrade) without waiting for an app-version
/// bump, which a version-gated probe could not do (see issue 12956).
@objc(iTermLocalNetworkPermissionPrompter)
class LocalNetworkPermissionPrompter: NSObject {
    private var browser: NWBrowser?

    @objc static let shared = LocalNetworkPermissionPrompter()

    private override init() {
        super.init()
    }

    /// Probes the local network to surface the permission prompt if macOS hasn't recorded a
    /// decision yet. Should be called early in app launch (e.g., applicationWillFinishLaunching).
    @objc func prompt() {
        RLog("Probing local network to request permission if needed")
        startBrowsing()
    }

    private func startBrowsing() {
        // Use NWBrowser to browse for SSH services on the local network.
        // This prompts for local network permission on macOS 15+.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_ssh._tcp", domain: "local.")
        browser = NWBrowser(for: descriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            RLog("Local network browser state: \(state)")
            switch state {
            case .ready:
                // Browser is ready - permission was granted or prompt shown
                // Stop after a short delay to ensure the system registers the access
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.stopBrowser()
                }
            case .failed(let error):
                RLog("Local network browser failed: \(error)")
                self?.stopBrowser()
            case .cancelled:
                break
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { results, changes in
            // We don't care about the actual results, just that we prompted for permission
            DLog("Local network browser found \(results.count) services")
        }

        browser?.start(queue: .main)

        // Safety timeout - stop the browser after 5 seconds regardless
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.stopBrowser()
        }
    }

    private func stopBrowser() {
        guard let browser = browser else { return }
        DLog("Stopping local network browser")
        browser.cancel()
        self.browser = nil
    }
}
