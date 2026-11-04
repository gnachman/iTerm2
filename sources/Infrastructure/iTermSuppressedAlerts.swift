//
//  iTermSuppressedAlerts.swift
//  iTerm2
//
//  Tracks alerts (iTermWarning) that were auto-answered because the user
//  previously chose "remember my choice"/"suppress this message", and
//  announcements (the bars at the top of a session) that were not shown because
//  of a saved "never"/"always"/"silence" choice. Provides the data needed to show
//  the user which alerts are being silently suppressed and to un-suppress them.
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
    // Present only for announcements: the user-defaults key holding the choice that
    // suppresses it, and the value it held when the announcement was suppressed.
    static let userDefaultsKey = "userDefaultsKey"
    static let suppressingValue = "suppressingValue"
    // NoSync because this is local runtime state, not a configuration setting.
    static let catalog = "NoSyncSuppressedAlertsCatalog"
}

// One suppressed alert. Immutable snapshot.
@objc(iTermSuppressedAlert)
class iTermSuppressedAlert: NSObject {
    // For an alert, the iTermWarning identifier. For an announcement, “Announcement:” followed by
    // the user-defaults key holding the choice that suppresses it. Either way, pass it to
    // unsuppressIdentifier; it isn't itself a user-defaults key for announcements.
    @objc let identifier: String
    // The message text that would have been shown to the user.
    @objc let title: String
    // The bold heading that would have been shown, if any.
    @objc let heading: String?
    // The label of the button that was automatically chosen on the user's behalf.
    @objc let selectionLabel: String
    // When this alert was most recently auto-answered, or when the user made the choice that
    // suppresses it if it hasn't been auto-answered since.
    @objc let lastSuppressed: Date
    // How many times this alert has been auto-answered. 0 if the user made the choice but it
    // hasn't been auto-answered yet.
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

    // Catalog identifiers for announcements are namespaced by this prefix so they
    // can't collide with iTermWarning identifiers.
    private static let announcementPrefix = "Announcement:"

    private static func userDefaultsKey(_ entry: [String: Any]) -> String? {
        return entry[CatalogKey.userDefaultsKey] as? String
    }

    // An announcement stays suppressed while its user-defaults key still holds the
    // value it had when it was suppressed. If the setting was changed some other way
    // (e.g., in Advanced Settings), the announcement could be shown again.
    private func isStillSuppressed(identifier: String, entry: [String: Any]) -> Bool {
        guard let key = Self.userDefaultsKey(entry) else {
            return iTermWarning.identifierIsSilenced(identifier)
        }
        guard let current = iTermUserDefaults.userDefaults().object(forKey: key) as? NSObject,
              let suppressing = entry[CatalogKey.suppressingValue] as? NSObject else {
            return false
        }
        return current.isEqual(suppressing)
    }

    // Removes whatever causes the entry to be suppressed so it is shown again.
    private func clearSuppression(identifier: String, entry: [String: Any]?) {
        if let entry, let key = Self.userDefaultsKey(entry) {
            // A lapsed entry may linger until the next prune. Its key now holds a newer
            // choice made elsewhere (e.g., in Advanced Settings) that must not be deleted.
            guard isStillSuppressed(identifier: identifier, entry: entry) else {
                return
            }
            iTermUserDefaults.userDefaults().removeObject(forKey: key)
        } else {
            iTermWarning.clearSavedSelection(forIdentifier: identifier)
        }
    }

    // Drops entries whose silence has lapsed.
    private func prune() {
        let lapsed = catalog.filter { !isStillSuppressed(identifier: $0.key, entry: $0.value) }.keys
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
        recordAlert(identifier: identifier, title: title, heading: heading, selectionLabel: selectionLabel, automatic: true)
    }

    // Record that the user just chose to remember their answer to an alert, so the panel lists
    // it right away instead of the next time it is auto-answered. Doesn't count as an
    // auto-answer.
    @objc(recordRememberedSelectionWithIdentifier:title:heading:selectionLabel:)
    func recordRememberedSelection(withIdentifier identifier: String?,
                                   title: String?,
                                   heading: String?,
                                   selectionLabel: String?) {
        recordAlert(identifier: identifier, title: title, heading: heading, selectionLabel: selectionLabel, automatic: false)
    }

    private func recordAlert(identifier: String?,
                             title: String?,
                             heading: String?,
                             selectionLabel: String?,
                             automatic: Bool) {
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
            CatalogKey.count: automatic ? previousCount + 1 : previousCount,
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

    // Record that an announcement was not shown because of a choice saved in user
    // defaults under `userDefaultsKey`. `response` is the label of the button whose
    // effect was applied automatically, or nil if the announcement was simply hidden.
    // Un-suppressing removes the key, so it must hold nothing but that choice. Returns false
    // if nothing is saved under the key, in which case nothing is recorded.
    @discardableResult
    @objc(recordAnnouncementSuppressionWithUserDefaultsKey:title:response:)
    func recordAnnouncementSuppression(userDefaultsKey: String,
                                       title: String,
                                       response: String?) -> Bool {
        guard let value = Self.savedValue(userDefaultsKey) else {
            return false
        }
        recordAnnouncement(userDefaultsKey: userDefaultsKey, value: value, title: title, response: response, automatic: true)
        return true
    }

    // Record that the user just answered an announcement with a choice saved under
    // `userDefaultsKey`, so the panel lists it right away instead of the next time it is
    // suppressed. Doesn't count as a suppression.
    @objc(recordAnnouncementChoiceWithUserDefaultsKey:title:response:)
    func recordAnnouncementChoice(userDefaultsKey: String,
                                  title: String,
                                  response: String?) {
        guard let value = Self.savedValue(userDefaultsKey) else {
            return
        }
        recordAnnouncement(userDefaultsKey: userDefaultsKey, value: value, title: title, response: response, automatic: false)
    }

    // The choice saved under `userDefaultsKey`, or nil if there is none, in which case the
    // announcement can't be listed.
    private static func savedValue(_ userDefaultsKey: String) -> Any? {
        guard let value = iTermUserDefaults.userDefaults().object(forKey: userDefaultsKey) else {
            DLog("No value for \(userDefaultsKey)")
            return nil
        }
        return value
    }

    // `value` is what's saved under `userDefaultsKey`.
    private func recordAnnouncement(userDefaultsKey: String,
                                    value: Any,
                                    title: String,
                                    response: String?,
                                    automatic: Bool) {
        let identifier = Self.announcementPrefix + userDefaultsKey
        var previousCount = 0
        // Continue the running count only while the saved choice is unchanged.
        if let existing = catalog[identifier],
           let suppressing = existing[CatalogKey.suppressingValue] as? NSObject,
           suppressing.isEqual(value) {
            previousCount = existing[CatalogKey.count] as? Int ?? 0
        }
        let selectionLabel = response.map { $0.replacingOccurrences(of: "_", with: "") } ??
            String(localized: "SuppressedAlerts.AnnouncementHidden", defaultValue: "Not Shown", comment: "Automatic response shown for an announcement that is hidden because the user chose not to see it again")
        catalog[identifier] = [
            CatalogKey.title: title,
            CatalogKey.selectionLabel: selectionLabel,
            CatalogKey.lastSuppressed: Date().timeIntervalSinceReferenceDate,
            CatalogKey.count: automatic ? previousCount + 1 : previousCount,
            CatalogKey.userDefaultsKey: userDefaultsKey,
            CatalogKey.suppressingValue: value,
        ]
        scheduleFlush()
        DLog("Recorded suppression of announcement \(userDefaultsKey) (response \(selectionLabel))")
    }

    // Call where a choice saved under `userDefaultsKey` would keep an announcement from
    // being shown. Returns false if nothing is saved under the key (so it could not be
    // listed in the panel and un-suppressed there), or if it should be shown anyway because
    // “Always show alerts with remembered selections” is on. Otherwise records the
    // suppression (see recordAnnouncementSuppression) and returns true.
    //
    // Some keys are Advanced Settings, which could also have been set by hand. That is rare, so
    // a saved value is always treated as the user's answer to the announcement.
    @objc(shouldSuppressAnnouncementWithUserDefaultsKey:title:response:)
    func shouldSuppressAnnouncement(userDefaultsKey: String,
                                    title: String,
                                    response: String?) -> Bool {
        guard let value = Self.savedValue(userDefaultsKey) else {
            return false
        }
        if iTermWarning.showRememberedAlerts {
            DLog("Showing announcement \(userDefaultsKey) despite its saved choice because showRememberedAlerts is on")
            return false
        }
        recordAnnouncement(userDefaultsKey: userDefaultsKey, value: value, title: title, response: response, automatic: true)
        return true
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
        clearSuppression(identifier: identifier, entry: catalog.removeValue(forKey: identifier))
        persist()
        DLog("Un-suppressed \(identifier)")
        // User-initiated and infrequent: update the panel right away.
        postDidChange()
    }

    // Drops what was recorded about an alert without un-suppressing it, for when its
    // remembered choice was changed some other way and the record may be wrong. It is
    // recorded again, correctly, the next time it is auto-answered.
    @objc func forgetIdentifier(_ identifier: String) {
        guard catalog.removeValue(forKey: identifier) != nil else {
            return
        }
        persist()
        DLog("Forgot \(identifier)")
        postDidChange()
    }

    // Un-suppress all known suppressed alerts.
    @objc func unsuppressAll() {
        for (identifier, entry) in catalog {
            clearSuppression(identifier: identifier, entry: entry)
        }
        catalog.removeAll()
        persist()
        DLog("Un-suppressed all alerts")
        postDidChange()
    }

    // Empties the in-memory catalog without un-suppressing anything, so tests don't
    // delete the test host's real remembered choices.
    func resetForTesting() {
        catalog.removeAll()
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(flush),
                                               object: nil)
        flushScheduled = false
        persist()
    }
}

// What to do about an announcement that offers Always and Never, saved as YES and NO.
@objc(iTermSavedAlwaysOrNeverChoice)
enum SavedAlwaysOrNeverChoice: Int {
    // No saved choice, or “Always show alerts with remembered selections” is on: show it.
    case ask
    // Apply the Always action without showing it.
    case always
    // Do nothing and don't show it.
    case never
}

// Pairs the user-defaults key holding the saved choice for one announcement with the title
// listed for it in the Suppressed Alerts panel, so the check made before showing it and the
// record made when the user answers always agree on both.
@MainActor
@objc(iTermAnnouncementSuppression)
class AnnouncementSuppression: NSObject {
    @objc let userDefaultsKey: String
    @objc let title: String

    @objc(suppressionWithUserDefaultsKey:title:)
    static func suppression(userDefaultsKey: String, title: String) -> AnnouncementSuppression {
        return AnnouncementSuppression(userDefaultsKey: userDefaultsKey, title: title)
    }

    init(userDefaultsKey: String, title: String) {
        self.userDefaultsKey = userDefaultsKey
        self.title = title
        super.init()
    }

    // Labels of the Yes, Always, and Never buttons shared by many announcements.
    @objc static var yesLabel: String {
        String(localized: "NaggingController.YesShortcut", defaultValue: "_Yes", comment: "Yes button label; underscore marks the keyboard shortcut key")
    }

    @objc static var alwaysLabel: String {
        String(localized: "NaggingController.Always", defaultValue: "Always", comment: "Always button label")
    }

    @objc static var neverLabel: String {
        String(localized: "NaggingController.Never", defaultValue: "Never", comment: "Never button label")
    }

    @objc static var alwaysAllowLabel: String {
        String(localized: "NaggingController.AlwaysAllowShortcut", defaultValue: "Always _Allow", comment: "Always Allow button label; underscore marks the keyboard shortcut key")
    }

    @objc static var alwaysDenyLabel: String {
        String(localized: "NaggingController.AlwaysDenyShortcut", defaultValue: "Always _Deny", comment: "Always Deny button label; underscore marks the keyboard shortcut key")
    }

    // Call where the saved choice would keep the announcement from being shown. See
    // iTermSuppressedAlerts.shouldSuppressAnnouncement. `response` is the label of the button
    // whose effect is applied, or nil if the announcement is just hidden.
    @objc(shouldSuppressWithResponse:)
    func shouldSuppress(response: String?) -> Bool {
        return iTermSuppressedAlerts.sharedInstance.shouldSuppressAnnouncement(userDefaultsKey: userDefaultsKey,
                                                                               title: title,
                                                                               response: response)
    }

    // Call after the user answers with a choice saved under the key, so the Suppressed Alerts
    // panel lists it right away instead of the next time it is suppressed. `response` should
    // match what is passed to shouldSuppress(response:) for that choice.
    @objc(recordChoiceWithResponse:)
    func recordChoice(response: String?) {
        iTermSuppressedAlerts.sharedInstance.recordAnnouncementChoice(userDefaultsKey: userDefaultsKey,
                                                                      title: title,
                                                                      response: response)
    }

    // Saves the user's answer under the key and records it (see recordChoice(response:)).
    // Don't use this for an Advanced Setting, whose setter must be called instead.
    @objc(saveChoice:response:)
    func saveChoice(_ value: Any, response: String?) {
        iTermUserDefaults.userDefaults().set(value, forKey: userDefaultsKey)
        recordChoice(response: response)
    }

    // For the common case of an announcement hidden while the key holds YES.
    @objc(shouldSuppressIfSavedBoolWithResponse:)
    func shouldSuppressIfSavedBool(response: String?) -> Bool {
        return iTermUserDefaults.userDefaults().bool(forKey: userDefaultsKey) && shouldSuppress(response: response)
    }

    // For an announcement offering Always and Never, saved as YES and NO. Reads the saved
    // choice once and records the suppression unless it returns .ask.
    @objc func savedAlwaysOrNeverChoice() -> SavedAlwaysOrNeverChoice {
        guard let number = iTermUserDefaults.userDefaults().object(forKey: userDefaultsKey) as? NSNumber else {
            return .ask
        }
        let always = number.boolValue
        guard shouldSuppress(response: always ? Self.alwaysLabel : Self.neverLabel) else {
            return .ask
        }
        return always ? .always : .never
    }

    // Saves and records the Always or Never choice the user just made.
    @objc(saveAlwaysOrNeverChoice:)
    func saveAlwaysOrNeverChoice(_ always: Bool) {
        saveChoice(always, response: always ? Self.alwaysLabel : Self.neverLabel)
    }
}
