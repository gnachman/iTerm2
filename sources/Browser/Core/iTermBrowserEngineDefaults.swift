//
//  iTermBrowserEngineDefaults.swift
//  iTerm2SharedARC
//
//  Browser engine setup shared by the built-in browser and web Quick Look: the persistent
//  login store, the Safari user agent, and proxy configuration.
//

import Foundation
@preconcurrency import WebKit
import Network

enum iTermBrowserEngineDefaults {
    static let regularUserStoreID = UUID(uuidString: "AC0E9812-7F88-478B-B361-5526082EDDB3")!

    static func safariUserAgent() -> String {
        if let safariBundle = Bundle(path: "/Applications/Safari.app"),
           let safariVersion = safariBundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/\(safariVersion) Safari/605.1.15"
        } else {
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/16.4 Safari/605.1.15"
        }
    }

    static func websiteDataStoreForRegularUser() -> WKWebsiteDataStore {
        if #available(macOS 14, *) {
            return WKWebsiteDataStore(forIdentifier: regularUserStoreID)
        }
        return .default()
    }

    static func applyProxyConfiguration(to dataStore: WKWebsiteDataStore) {
        guard #available(macOS 14.0, *) else {
            return
        }

        if iTermAdvancedSettingsModel.browserProxyEnabled() {
            let proxyHost = iTermAdvancedSettingsModel.browserProxyHost() ?? "127.0.0.1"
            let proxyPort = iTermAdvancedSettingsModel.browserProxyPort()

            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxyHost), port: NWEndpoint.Port(integerLiteral: UInt16(proxyPort)))
            let proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint)
            dataStore.proxyConfigurations = [proxyConfig]
            RLog("Configured browser proxy: \(proxyHost):\(proxyPort)")
        } else {
            RLog("Proxy disabled")
            dataStore.proxyConfigurations = []
        }
    }
}
