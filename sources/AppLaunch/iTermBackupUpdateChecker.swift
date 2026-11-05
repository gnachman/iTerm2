//
//  iTermBackupUpdateChecker.swift
//  iTerm2
//
//  Created by George Nachman on 11/5/26.
//

import Foundation

// A backstop for Sparkle, used by hand, and sharing nothing with it: its own URL, its own
// version comparison, no Sparkle framework. Once a day it fetches an appcast-shaped file
// that is normally absent. When a Sparkle bug is found in a shipped version, publishing
// that file with the fixed version in it makes every affected copy tell its user, once per
// version, where to download the fix by hand. The query parameter says whether the user
// takes beta releases, so the server can answer per channel. Nothing is downloaded or
// installed here, and it makes no request at all unless the user has said yes to automatic
// update checks.
@objc(iTermBackupUpdateChecker)
class BackupUpdateChecker: NSObject {
    @objc static let shared = BackupUpdateChecker()

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "NoSyncBackupUpdateLastCheck"
    private static let warnedVersionKey = "NoSyncBackupUpdateWarnedVersion"
    private static let feed = "https://iterm2.com/appcasts/backup_update.xml"
    private static let downloadsPage = "https://iterm2.com/download-backup.html"

    private var timer: Timer?

    // Call once at launch. Checks a few minutes in and then every few hours, each check
    // being skipped unless a day has passed since the last one.
    @objc func start() {
        guard timer == nil else {
            return
        }
        if TestHostIsolation.isTestHost(environment: ProcessInfo.processInfo.environment) {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        let defaults = iTermUserDefaults.userDefaults()
        // Privacy: fetch nothing unless the user has said yes to automatic update checks.
        // The stored value is the answer to Sparkle's permission prompt or the checkbox in
        // Settings > General. Unset means they have not been asked yet, which also counts
        // as no. Read the stored value itself because iTermPreferences defaults it to YES.
        guard defaults.object(forKey: kPreferenceKeyCheckForUpdatesAutomatically) as? Bool == true else {
            DLog("Backup update check skipped: automatic checks not enabled")
            return
        }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           -last.timeIntervalSinceNow < Self.checkInterval {
            return
        }
        let url = Self.feedURL(wantsBetas: iTermPreferences.bool(forKey: kPreferenceKeyCheckForTestReleases))
        defaults.set(Date(), forKey: Self.lastCheckKey)
        DLog("Backup update check fetching \(url)")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            // The file does not exist most of the time; that is the normal, quiet case.
            guard let data, let text = String(data: data, encoding: .utf8),
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                DLog("Backup update check got nothing: \(error.map { String(describing: $0) } ?? "no data")")
                return
            }
            DispatchQueue.main.async {
                self?.handleAppcast(text)
            }
        }.resume()
    }

    private func handleAppcast(_ appcast: String) {
        let defaults = iTermUserDefaults.userDefaults()
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard let newest = Self.newestVersion(inAppcast: appcast,
                                              runningOn: ProcessInfo.processInfo.operatingSystemVersion),
              Self.version(newest, isNewerThan: current) else {
            DLog("Backup update check: nothing newer than \(current)")
            return
        }
        if defaults.string(forKey: Self.warnedVersionKey) == newest {
            return
        }
        RLog("Backup update check: \(newest) is available but still running \(current)")
        defaults.set(newest, forKey: Self.warnedVersionKey)
        warn(newest: newest, current: current)
    }

    static func feedURL(wantsBetas: Bool) -> URL {
        return URL(string: feed + "?betas=" + (wantsBetas ? "1" : "0"))!
    }

    private func warn(newest: String, current: String) {
        let download = iTermWarningAction.localOnlyAction(withLabel: String(localized: "BackupUpdate.Download",
                                                                      defaultValue: "Download",
                                                                      comment: "Button that opens the iTerm2 downloads page in a browser"))
        let selection = iTermWarning.show(withTitle: String(localized: "BackupUpdate.Message",
                                                            defaultValue: "iTerm2 \(newest) is available, but automatic updates may not be working in this version (\(current)). You can download the new version from iterm2.com.",
                                                            comment: "Alert shown when the developer has flagged this version's automatic updates as broken; the placeholders are the available version and the installed version"),
                                          actions: [download,
                                                    String(localized: "BackupUpdate.NotNow",
                                                           defaultValue: "Not Now",
                                                           comment: "Button that dismisses the failed-update alert")],
                                          accessory: nil,
                                          identifier: nil,
                                          silenceable: .kiTermWarningTypePersistent,
                                          heading: String(localized: "BackupUpdate.Heading",
                                                          defaultValue: "Software Update Problem?",
                                                          comment: "Heading of the alert shown when automatic updates seem to have failed"),
                                          window: nil)
        if selection == .kiTermWarningSelection0, let url = URL(string: Self.downloadsPage) {
            NSWorkspace.shared.open(url)
        }
    }

    // The newest sparkle:version among the appcast's items whose minimumSystemVersion this
    // Mac meets. Deliberately not an XML parser: the appcast is machine-written, and all
    // that matters here is the two attributes.
    static func newestVersion(inAppcast appcast: String, runningOn os: OperatingSystemVersion) -> String? {
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var newest: String?
        for item in appcast.components(separatedBy: "<item>").dropFirst() {
            guard let itemVersion = firstMatch(of: "sparkle:version=\"([^\"]+)\"", in: item) else {
                continue
            }
            if let minimum = firstMatch(of: "<sparkle:minimumSystemVersion>\\s*([0-9.]+)\\s*<", in: item),
               version(minimum, isNewerThan: osString) {
                continue
            }
            if let best = newest, !version(itemVersion, isNewerThan: best) {
                continue
            }
            newest = itemVersion
        }
        return newest
    }

    // Compares dot-separated versions numerically, so 3.7.10 beats 3.7.9. A component with a
    // suffix after its number (8beta1, 20261105-nightly) sorts below the bare number, and two
    // suffixes compare as text with embedded numbers compared numerically, so beta10 beats
    // beta9. Covers the release, beta and nightly version strings iTerm2 ships.
    static func version(_ a: String, isNewerThan b: String) -> Bool {
        let lhs = a.split(separator: ".", omittingEmptySubsequences: false).map(component)
        let rhs = b.split(separator: ".", omittingEmptySubsequences: false).map(component)
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : (0, "")
            let r = i < rhs.count ? rhs[i] : (0, "")
            if l.0 != r.0 {
                return l.0 > r.0
            }
            if l.1 != r.1 {
                // No suffix is the release; any suffix is an earlier pre-release of it.
                if l.1.isEmpty || r.1.isEmpty {
                    return l.1.isEmpty
                }
                return l.1.compare(r.1, options: .numeric) == .orderedDescending
            }
        }
        return false
    }

    private static func component(_ s: Substring) -> (Int, String) {
        let digits = s.prefix { $0.isNumber }
        return (Int(digits) ?? 0, String(s.dropFirst(digits.count)))
    }

    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
