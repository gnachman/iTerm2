import Cocoa

@objc(iTermDockBadgeController)
class iTermDockBadgeController: NSObject {
    @objc static let sharedInstance = iTermDockBadgeController()

    private var bellCount: Int = 0
    private var waitingSessionGUIDs = Set<String>()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - Bell Badge

    @objc func incrementBellCount() -> Bool {
        guard iTermAdvancedSettingsModel.indicateBellsInDockBadgeLabel() else {
            return false
        }
        guard !NSApp.isActive else {
            return false
        }
        bellCount += 1
        updateBadge()
        return true
    }

    @objc func resetBellCount() {
        guard bellCount > 0 else {
            return
        }
        bellCount = 0
        updateBadge()
    }

    // MARK: - Tab Status Badge

    @objc func sessionDidEnterWaiting(_ sessionGUID: String) {
        guard !NSApp.isActive else {
            return
        }
        if waitingSessionGUIDs.insert(sessionGUID).inserted {
            updateBadge()
        }
    }

    @objc func sessionDidLeaveWaiting(_ sessionGUID: String) {
        if waitingSessionGUIDs.remove(sessionGUID) != nil {
            updateBadge()
        }
    }

    @objc func tabWasSelected(_ tab: PTYTab) {
        var changed = false
        for case let session in tab.sessions() {
            if waitingSessionGUIDs.remove(session.guid) != nil {
                changed = true
            }
        }
        if changed {
            updateBadge()
        }
    }

    // MARK: - Private

    private func updateBadge() {
        let total = bellCount + waitingSessionGUIDs.count
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : ""
    }

    @objc private func applicationDidBecomeActive() {
        waitingSessionGUIDs.removeAll()
        // Don't reset bellCount here — that's done by resetBellCount
        // when the window becomes key.
        updateBadge()
    }
}
