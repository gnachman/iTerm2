//
//  iTermSuppressedAlerts.swift
//  iTerm2
//
//  Tracks alerts (iTermWarning) that were auto-answered because the user
//  previously chose "remember my choice"/"suppress this message". Provides the
//  data needed to show the user which alerts are being silently suppressed and to
//  un-suppress them.
//
//  Main-actor isolated: iTermWarning is only ever used on the main thread, so all
//  access here is serialized by the main actor and needs no lock.
//

import AppKit

extension Notification.Name {
    // Posted when the set of suppressed alerts changes.
    static let iTermSuppressedAlertsDidChange = Notification.Name("iTermSuppressedAlertsDidChangeNotification")
}

// Keys within a persisted catalog entry, plus the catalog's own user-defaults key.
private enum CatalogKey {
    static let title = "title"
    static let heading = "heading"
    static let selectionLabel = "selectionLabel"
    static let lastSuppressed = "lastSuppressed"
    static let count = "count"
    // Identifies the silence episode the count belongs to, so re-silencing after a
    // lapse starts the count over instead of continuing the old episode's total.
    static let episode = "episode"
    // NoSync because this is local runtime state, not a configuration setting.
    static let catalog = "NoSyncSuppressedAlertsCatalog"
}

// One suppressed alert. Immutable snapshot.
@objc(iTermSuppressedAlert)
class iTermSuppressedAlert: NSObject {
    // The iTermWarning identifier (also the user defaults key).
    @objc let identifier: String
    // The message text that would have been shown to the user.
    @objc let title: String
    // The bold heading that would have been shown, if any.
    @objc let heading: String?
    // The label of the button that was automatically chosen on the user's behalf.
    @objc let selectionLabel: String
    // When this alert was most recently auto-answered.
    @objc let lastSuppressed: Date
    // How many times this alert has been auto-answered.
    @objc let count: Int

    init(identifier: String, dictionary: [String: Any]) {
        self.identifier = identifier
        title = (dictionary[CatalogKey.title] as? String) ?? ""
        heading = dictionary[CatalogKey.heading] as? String
        selectionLabel = (dictionary[CatalogKey.selectionLabel] as? String) ?? ""
        let t = (dictionary[CatalogKey.lastSuppressed] as? Double) ?? 0
        lastSuppressed = Date(timeIntervalSinceReferenceDate: t)
        count = (dictionary[CatalogKey.count] as? Int) ?? 0
        super.init()
    }
}

@MainActor
@objc(iTermSuppressedAlerts)
class iTermSuppressedAlerts: NSObject {
    // How long to coalesce persistence and change notifications after a burst of
    // suppressions before writing user defaults and telling the panel to refresh.
    private static let flushDelay: TimeInterval = 0.5

    @objc static let sharedInstance = iTermSuppressedAlerts()

    // In-memory source of truth (identifier -> entry dictionary). Loaded from user
    // defaults at init and written back on a debounce.
    private var catalog: [String: [String: Any]] = [:]
    // True if a debounced flush to user defaults + change notification is pending.
    private var flushScheduled = false

    private override init() {
        super.init()
        if let stored = iTermUserDefaults.userDefaults().object(forKey: CatalogKey.catalog) as? [String: Any] {
            for (identifier, value) in stored {
                if let entry = value as? [String: Any] {
                    catalog[identifier] = entry
                }
            }
        }
        // Persist synchronously on quit so a suppression recorded within the
        // debounce window isn't lost from the panel/menu across a quick restart.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillTerminate(_:)),
                                               name: NSApplication.willTerminateNotification,
                                               object: nil)
    }

    // MARK: - Persistence

    // Drops entries whose silence has lapsed.
    private func prune() {
        let lapsed = catalog.keys.filter { !iTermWarning.identifierIsSilenced($0) }
        for identifier in lapsed {
            catalog.removeValue(forKey: identifier)
        }
    }

    // Prunes, then writes the in-memory catalog to user defaults so stale entries
    // are never persisted.
    private func persist() {
        prune()
        iTermUserDefaults.userDefaults().set(catalog, forKey: CatalogKey.catalog)
    }

    // Coalesces persistence + change notification so a burst of suppressions
    // results in a single defaults write and a single panel refresh rather than
    // one per occurrence. Uses the main run loop, which is where everything here
    // runs.
    private func scheduleFlush() {
        if flushScheduled {
            return
        }
        flushScheduled = true
        perform(#selector(flush), with: nil, afterDelay: Self.flushDelay)
    }

    @objc private func flush() {
        flushScheduled = false
        persist()
        postDidChange()
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .iTermSuppressedAlertsDidChange, object: self)
    }

    // MARK: - Recording

    // Record that a silenced alert was auto-answered without being shown. Called by
    // iTermWarning on the main thread.
    @objc(recordSuppressionWithIdentifier:title:heading:selectionLabel:)
    func recordSuppression(withIdentifier identifier: String?,
                           title: String?,
                           heading: String?,
                           selectionLabel: String?) {
        guard let identifier else {
            return
        }
        let episode = iTermWarning.silenceEpisodeToken(forIdentifier: identifier)
        var previousCount = 0
        // Continue the running count only within the same silence episode. If the
        // silence lapsed and was re-established (a new episode token), start over
        // at 1.
        if let existing = catalog[identifier],
           let episode,
           existing[CatalogKey.episode] as? String == episode {
            previousCount = existing[CatalogKey.count] as? Int ?? 0
        }
        var entry: [String: Any] = [
            CatalogKey.title: title ?? "",
            CatalogKey.selectionLabel: selectionLabel ?? "",
            CatalogKey.lastSuppressed: Date().timeIntervalSinceReferenceDate,
            CatalogKey.count: previousCount + 1,
        ]
        if let heading {
            entry[CatalogKey.heading] = heading
        }
        if let episode {
            entry[CatalogKey.episode] = episode
        }
        catalog[identifier] = entry
        // Debounce the write + notification: this can fire rapidly for a warning
        // that a program keeps re-triggering.
        scheduleFlush()
        DLog("Recorded suppression of \(identifier) (chose \(selectionLabel ?? ""))")
    }

    // MARK: - Queries

    // Alerts that are currently silenced (i.e., would be auto-answered), sorted
    // most recently suppressed first.
    @objc func currentlySuppressedAlerts() -> [iTermSuppressedAlert] {
        prune()
        return catalog
            .map { iTermSuppressedAlert(identifier: $0.key, dictionary: $0.value) }
            .sorted { $0.lastSuppressed > $1.lastSuppressed }
    }

    // Number of currently silenced alerts we know about.
    @objc func count() -> Int {
        return currentlySuppressedAlerts().count
    }

    // The most recent suppression time among currently silenced alerts, or nil.
    @objc func mostRecentSuppression() -> Date? {
        // currentlySuppressedAlerts is sorted most-recent-first.
        return currentlySuppressedAlerts().first?.lastSuppressed
    }

    // MARK: - Mutation

    // Un-suppress a specific alert so it will be shown again.
    @objc func unsuppressIdentifier(_ identifier: String?) {
        guard let identifier else {
            return
        }
        iTermWarning.clearSavedSelection(forIdentifier: identifier)
        catalog.removeValue(forKey: identifier)
        persist()
        DLog("Un-suppressed \(identifier)")
        // User-initiated and infrequent: update the panel right away.
        postDidChange()
    }

    // Un-suppress all known suppressed alerts.
    @objc func unsuppressAll() {
        for identifier in catalog.keys {
            iTermWarning.clearSavedSelection(forIdentifier: identifier)
        }
        catalog.removeAll()
        persist()
        DLog("Un-suppressed all alerts")
        postDidChange()
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(flush),
                                               object: nil)
        flushScheduled = false
        persist()
    }
}
