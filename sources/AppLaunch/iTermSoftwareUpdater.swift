//
//  iTermSoftwareUpdater.swift
//  iTerm2
//
//  Created by George Nachman on 11/4/26.
//

import Foundation
import Sparkle

@objc(iTermSoftwareUpdaterDelegate)
protocol SoftwareUpdaterDelegate: AnyObject {
    // Sparkle is about to ask the app to quit so it can install an update and relaunch.
    // Called on the main thread before the quit request is sent. Save anything that must
    // survive the relaunch. May be called more than once per update.
    func softwareUpdaterWillInstallUpdateAndRelaunch()
}

// Owns Sparkle's updater and acts as its delegate.
//
// Sparkle 2 has no shared updater. This object creates one SPUStandardUpdaterController for the
// main bundle, starts it when the app has finished launching, and routes the handful of decisions
// iTerm2 makes (which appcast to read, what to do before the app is quit for an update) through
// here. Everything else is Sparkle's standard behavior and UI.
//
// Test hosts never start the updater, so they never check for updates and never show the
// permission prompt that used to stall UI tests behind a modal window.
@objc(iTermSoftwareUpdater)
class SoftwareUpdater: NSObject {
    @objc static let shared = SoftwareUpdater()

    @objc weak var delegate: SoftwareUpdaterDelegate?

    // True when Sparkle has an update staged that it will install after the app next quits, and
    // it will not tell us again at quit time. That happens when the user chooses “Install on
    // Quit” (or closes the alert) for an update that is already downloaded, and when automatic
    // installation is on. applicationShouldTerminate: checks this so the quit saves restorable
    // state as if Sparkle were relaunching us. Cleared when the user skips the update instead.
    @objc private(set) var installPendingOnQuit = false

    // The controller holds its delegates weakly; this singleton outlives it.
    private var controller: SPUStandardUpdaterController!
    private var started = false
    // A user asked to check for updates before start() ran (the old-nightly
    // warning is shown earlier in launch than the updater starts).
    private var checkRequestedBeforeStart = false

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
    }

    @objc var updater: SPUUpdater {
        return controller.updater
    }

    // Reflects the “Check for updates automatically” setting, which Sparkle stores under
    // SUEnableAutomaticChecks. Safe to read before the updater starts.
    @objc var automaticallyChecksForUpdates: Bool {
        return updater.automaticallyChecksForUpdates
    }

    // For validating the “Check for Updates…” menu item.
    @objc var canCheckForUpdates: Bool {
        return started && updater.canCheckForUpdates
    }

    // Starts scheduled checks. Call once, from applicationDidFinishLaunching:. Sparkle shows
    // its permission prompt on the second launch if the user has never answered it.
    @objc func start() {
        guard !started else {
            return
        }
        if TestHostIsolation.isTestHost(environment: ProcessInfo.processInfo.environment) {
            DLog("Not starting the updater in a test host")
            return
        }
        started = true
        controller.startUpdater()

        // iTerm2 used to pick the appcast by writing SUFeedURL into user defaults at every
        // launch. Sparkle 2 deprecates that and warns about it on each launch. The feed is now
        // chosen in feedURLString(for:), so remove the stored value and the companion key the
        // old Sparkle fork read to accept a zip whose app folder is named iTerm.app.
        if let stale = updater.clearFeedURLFromUserDefaults() {
            RLog("Removed stale feed URL from user defaults: \(stale)")
        }
        iTermUserDefaults.userDefaults().removeObject(forKey: "SUFeedAlternateAppNameKey")

        // The checkbox in Settings > General writes SUEnableAutomaticChecks directly. Tell
        // Sparkle so it reschedules now rather than at the next launch.
        iTermPreferences.addObserver(forKey: kPreferenceKeyCheckForUpdatesAutomatically) { [weak self] _, after in
            guard let self, let value = after as? Bool, value != self.updater.automaticallyChecksForUpdates else {
                return
            }
            DLog("Automatic update checks changed to \(value)")
            self.updater.automaticallyChecksForUpdates = value
        }

        if checkRequestedBeforeStart {
            checkRequestedBeforeStart = false
            DLog("Running the check for updates that was requested before start")
            controller.checkForUpdates(nil)
        }
    }

    // User-initiated check with Sparkle's progress UI. If called before start(),
    // the check runs as soon as the updater starts.
    @objc func checkForUpdates(_ sender: Any?) {
        guard started else {
            DLog("Deferring check for updates until the updater has started")
            checkRequestedBeforeStart = true
            return
        }
        controller.checkForUpdates(sender)
    }

    private func willInstallAndRelaunch(reason: String) {
        RLog("Sparkle will install an update and relaunch (\(reason))")
        delegate?.softwareUpdaterWillInstallUpdateAndRelaunch()
    }
}

extension SoftwareUpdater: SPUUpdaterDelegate {
    // Stable releases read the final appcast. Users who opted in to test releases read the
    // testing appcast, and nightly builds point both keys at the nightly appcast. The shard
    // lets the server stage a rollout. Returning nil would fall back to SUFeedURL in Info.plist.
    func feedURLString(for updater: SPUUpdater) -> String? {
        let key = iTermPreferences.bool(forKey: kPreferenceKeyCheckForTestReleases) ? "SUFeedURLForTesting" : "SUFeedURLForFinal"
        guard let base = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = NSURL(string: base) else {
            DLog("No usable appcast URL for \(key)")
            return nil
        }
        let feedURL = url.appendingQueryParameter("shard=\(iTermController.shard())")
        DLog("Appcast URL is \(feedURL.absoluteString)")
        return feedURL.absoluteString
    }

    // The two methods below fire, in this order, before Sparkle asks the app to quit for an
    // interactive install. Sparkle also posts SUUpdaterWillRestartNotification between them.
    // The app delegate observes all three so that saving state does not hinge on any one.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        willInstallAndRelaunch(reason: "willInstallUpdate \(item.displayVersionString)")
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        willInstallAndRelaunch(reason: "updaterWillRelaunchApplication")
    }

    func updater(_ updater: SPUUpdater,
                 userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem,
                 state: SPUUserUpdateState) {
        RLog("User chose \(choice.rawValue) for update \(updateItem.displayVersionString) at stage \(state.stage.rawValue)")
        switch choice {
        case .dismiss:
            if state.stage == .installing {
                // The alert’s button read “Install on Quit”. Sparkle installs after the next
                // quit without any further callback to us.
                installPendingOnQuit = true
            }
        case .skip:
            installPendingOnQuit = false
        case .install:
            break
        @unknown default:
            break
        }
    }

    // Only reached when the user has opted in to automatic installation. Returning false leaves
    // Sparkle in charge of when to install (after quit, or by prompting later), but it will
    // install after the next quit with no further callback, so remember that.
    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        RLog("Update \(item.displayVersionString) will install on quit")
        installPendingOnQuit = true
        return false
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        RLog("Failed to download update \(item.displayVersionString): \(error)")
        installPendingOnQuit = false
    }

    // Choosing “Install on Quit” ends the update cycle with no error, so this is not called for
    // it and the pending flag survives. Any error means the staged update is gone: Sparkle
    // filters out SUInstallationAuthorizeLaterError (the one case where it keeps the update)
    // before calling this, and SUInstallationCanceledError comes from the user declining to
    // authorize the install, which also abandons it.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // SUNoUpdateError and SUInstallationCanceledError are routine; log them all anyway so a
        // field report shows the whole update cycle.
        RLog("Update cycle ended: \(error)")
        if installPendingOnQuit {
            RLog("Clearing pending install because the update cycle aborted")
            installPendingOnQuit = false
        }
    }
}
