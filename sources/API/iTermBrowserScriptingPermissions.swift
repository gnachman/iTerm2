//
//  iTermBrowserScriptingPermissions.swift
//  iTerm2
//
//  The websites on which Python API scripts may load URLs (iterm2.load_url) or run
//  JavaScript (iterm2.browser_eval_js) in a browser session. Each is the remembered
//  answer to a permanently silenceable iTermWarning, so the warning's identifier is
//  the user defaults key. Both prompts offer OK then Cancel, so a remembered
//  kiTermWarningSelection0 means allowed and anything else means denied.
//

import Foundation

@objc(iTermBrowserScriptingPermissions)
final class iTermBrowserScriptingPermissions: NSObject {
    enum Kind: CaseIterable {
        case runJavaScript
        case loadURL

        // Localization unneeded
        fileprivate var prefix: String {
            switch self {
            case .runJavaScript: "NoSyncBrowserJavaScriptAllowed_"
            case .loadURL: "NoSyncLoadURLAllowed_"
            }
        }

        var localizedName: String {
            switch self {
            case .runJavaScript:
                String(localized: "BrowserScriptingPermissions.RunJavaScript",
                       defaultValue: "Run JavaScript",
                       comment: "Kind of permission a website can grant to scripts: running JavaScript in its pages")
            case .loadURL:
                String(localized: "BrowserScriptingPermissions.LoadURLs",
                       defaultValue: "Load URLs",
                       comment: "Kind of permission a website can grant to scripts: loading its URLs in a browser session")
            }
        }
    }

    struct Entry: Hashable {
        var kind: Kind
        // An origin like https://example.com for runJavaScript; a host like example.com for loadURL.
        var site: String
        var allowed: Bool

        fileprivate var identifier: String {
            kind.prefix + site
        }
    }

    // MARK: - Identifiers

    @objc(javaScriptIdentifierForOrigin:)
    static func javaScriptIdentifier(origin: String) -> String {
        return Kind.runJavaScript.prefix + origin
    }

    @objc(loadURLIdentifierForHost:)
    static func loadURLIdentifier(host: String) -> String {
        return Kind.loadURL.prefix + host
    }

    // The web origin of `url`, if scripts may run JavaScript on it. Approval is per
    // origin, so only http and https pages qualify: about:blank and file:// pages would
    // otherwise all share a single approval. Default ports are omitted so that
    // https://example.com and https://example.com:443 are the same origin.
    static func javaScriptOrigin(for url: URL?) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let bareHost = url.host?.lowercased(),
              !bareHost.isEmpty else {
            return nil
        }
        // URL.host drops the brackets around an IPv6 address. Put them back so this
        // matches location.origin.
        let host = bareHost.contains(":") ? "[\(bareHost)]" : bareHost
        let defaultPort: Int
        switch scheme {
        case "https":
            defaultPort = 443
        case "http":
            defaultPort = 80
        default:
            return nil
        }
        if let port = url.port, port != defaultPort {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    // Turns what a user typed (example.com, https://example.com/page, …) into the form
    // `kind` is keyed by. A missing scheme means https.
    static func site(from input: String, kind: Kind) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme) else {
            return nil
        }
        switch kind {
        case .runJavaScript:
            return javaScriptOrigin(for: url)
        case .loadURL:
            guard let host = url.host?.lowercased(), !host.isEmpty else {
                return nil
            }
            return host
        }
    }

    // MARK: - Reading and writing

    // Every remembered answer, sorted by site. Call on the main thread.
    static func entries() -> [Entry] {
        migrateMixedCaseLoadURLAnswers()
        let keys = iTermUserDefaults.userDefaults().dictionaryRepresentation().keys
        var result = [Entry]()
        for key in keys {
            guard let kind = Kind.allCases.first(where: { key.hasPrefix($0.prefix) }),
                  !key.hasSuffix("_selection"),
                  !key.hasSuffix("_SilenceUntil"),
                  let selection = iTermWarning.conditionalSavedSelection(forIdentifier: key) else {
                continue
            }
            let site = String(key.dropFirst(kind.prefix.count))
            guard !site.isEmpty else {
                continue
            }
            result.append(Entry(kind: kind,
                                site: site,
                                allowed: selection.intValue == iTermWarningSelection.kiTermWarningSelection0.rawValue))
        }
        return result.sorted {
            if $0.site != $1.site {
                return $0.site.localizedStandardCompare($1.site) == .orderedAscending
            }
            return $0.kind.localizedName < $1.kind.localizedName
        }
    }

    // Call on the main thread.
    static func save(_ entry: Entry) {
        DLog("Save \(entry)")
        iTermWarning.setIdentifier(entry.identifier,
                                   permanentSelection: entry.allowed ? .kiTermWarningSelection0 : .kiTermWarningSelection1)
        MainActor.assumeIsolated {
            // The Suppressed Alerts panel may have recorded the old answer.
            iTermSuppressedAlerts.sharedInstance.forgetIdentifier(entry.identifier)
        }
    }

    // MARK: - Migration

    // load_url used to key its answer by the host exactly as given, and NSURL keeps the
    // host's case. Moves an answer saved under `host` to the lowercased key now used.
    // Call on the main thread.
    @objc(migrateLoadURLAnswerForHost:)
    static func migrateLoadURLAnswer(host: String) {
        let lowercased = host.lowercased()
        guard host != lowercased else {
            return
        }
        let oldIdentifier = loadURLIdentifier(host: host)
        guard let selection = iTermWarning.conditionalSavedSelection(forIdentifier: oldIdentifier),
              let iTermSelection = iTermWarningSelection(rawValue: selection.intValue) else {
            return
        }
        DLog("Migrate \(oldIdentifier)")
        let newIdentifier = loadURLIdentifier(host: lowercased)
        // An answer already saved under the lowercased host is newer, so keep it.
        if !iTermWarning.identifierIsSilenced(newIdentifier) {
            iTermWarning.setIdentifier(newIdentifier, permanentSelection: iTermSelection)
        }
        MainActor.assumeIsolated {
            iTermSuppressedAlerts.sharedInstance.unsuppressIdentifier(oldIdentifier)
        }
    }

    private static func migrateMixedCaseLoadURLAnswers() {
        let prefix = Kind.loadURL.prefix
        let hosts = iTermUserDefaults.userDefaults().dictionaryRepresentation().keys.compactMap { key -> String? in
            guard key.hasPrefix(prefix),
                  !key.hasSuffix("_selection"),
                  !key.hasSuffix("_SilenceUntil") else {
                return nil
            }
            let host = String(key.dropFirst(prefix.count))
            return host == host.lowercased() ? nil : host
        }
        for host in hosts {
            migrateLoadURLAnswer(host: host)
        }
    }

    // MARK: - Removing

    // Call on the main thread.
    static func remove(_ entry: Entry) {
        DLog("Remove \(entry)")
        MainActor.assumeIsolated {
            // Also drops it from the Suppressed Alerts panel.
            iTermSuppressedAlerts.sharedInstance.unsuppressIdentifier(entry.identifier)
        }
    }
}
