import Foundation
import iTermProxy

class iTermBrowserAdblockRustManager {
    static let shared = iTermBrowserAdblockRustManager()
    private(set) var engine: iTermBrowserAdblockRustWrapper?

    struct Configuration {
        var url: String?
        var enabled: Bool

        init() {
            dispatchPrecondition(condition: .onQueue(.main))
            url = iTermAdvancedSettingsModel.rustAdblockListURL()
            enabled = iTermAdvancedSettingsModel.adblockEnabled()
        }
    }
    private var configuration: MutableAtomicObject<Configuration>
    private let userDefaultsObserver: iTermUserDefaultsObserver

    private var filterListURL: URL? {
        guard let urlString = configuration.value.url,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    private init() {
        configuration = .init(Configuration())

        userDefaultsObserver = iTermUserDefaultsObserver()
        userDefaultsObserver.observeKey("rustAdblockListURL") { [weak self] in
            self?.updateConfiguration()
        }
        userDefaultsObserver.observeKey("adblockEnabled") { [weak self] in
            self?.updateConfiguration()
        }
        if configuration.value.enabled {
            Task {
                await loadFilterLists()
            }
        }
    }

    private func updateConfiguration() {
        configuration.mutate { _ in
            return Configuration()
        }
    }

    private func loadFilterLists() async {
        guard let url = filterListURL else {
            DLog("No valid Rust adblock filter list URL configured")
            engine = nil
            return
        }

        DLog("Downloading Rust adblock filter list from: \(url)")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rulesString = String(data: data, encoding: .utf8) else {
                DLog("Failed to decode filter list")
                engine = nil
                return
            }

            DLog("Filter list size: \(data.count) bytes, \(rulesString.count) characters")
            DLog("First 200 chars of rules: \(String(rulesString.prefix(200)))")

            engine = iTermBrowserAdblockRustWrapper(rules: rulesString)
            if engine == nil {
                DLog("Failed to create Rust adblock engine")
            } else {
                DLog("Successfully loaded filter list into Rust adblock engine")
            }
        } catch {
            DLog("Failed to download filter list: \(error)")
            engine = nil
        }
    }

    func shouldBlockRequest(url: URL, tabHost: String? = nil) -> Bool {
        guard configuration.value.enabled,
              let engine = engine,
              let host = url.host else {
            return false
        }

        let urlString = url.absoluteString
        let effectiveTabHost = tabHost ?? host

        return engine.shouldBlockRequest(url: urlString, host: host, tabHost: effectiveTabHost)
    }

    func getCosmeticResources(for url: URL) async -> (hideSelectors: [String], injectedScript: String?) {
        guard configuration.value.enabled,
              let engine = engine else {
            return ([], nil)
        }

        return engine.getCosmeticResources(for: url.absoluteString)
    }

    func reload() async {
        await loadFilterLists()
    }

    func updateInternalProxyInstalled(desired: Bool) {
        let server = iTermProxy.Server.instance
        if desired {
            if server.portIfRunning != nil && server.monitor == nil {
                server.monitor = self
            }
        } else {
            server.monitor = nil
        }
    }
}

extension iTermBrowserAdblockRustManager: ConnectionMonitor {
    func connectionMonitorShouldConnect(method: String, host: String, port: Int, headers: [String : String]) -> Bool {
        let hostHeaderKey = headers.keys.first(where: { $0.lowercased() == "host"})
        let hostHeaderValue = hostHeaderKey.compactMap { headers[$0] }
        let host = hostHeaderValue ?? host
        let scheme = switch method {
        case "CONNECT":
            "https"
        default:
            "http"
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        guard let url = components.url else {
            return false
        }
        return !shouldBlockRequest(url: url)
    }
}
