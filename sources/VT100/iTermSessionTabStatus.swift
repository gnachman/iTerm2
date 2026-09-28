// Why a status that was true when it was set can stop being true on its own.
// A program that reports status out of band has no way to announce every way
// its work can end, since an interrupt in particular may run no hook at all,
// so it can instead say up front what should happen when the terminal sees
// the work finish.
@objc(VT100TabStatusExpirationReason)
enum VT100TabStatusExpirationReason: Int {
    // The status stands until something replaces it. The default.
    case never = 0

    // The status was scoped to an operation the program announced through the
    // progress protocol (OSC 9;4), and stops being true when that operation
    // ends.
    case progressEnd = 1
}

// An incremental update from OSC 21337. Each field may be not set (omitted),
// cleared (empty value), or set to a value.
@objc(VT100TabStatusUpdate)
class VT100TabStatusUpdate: NSObject {
    @objc static var clear: VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        update.indicatorPresence = .cleared
        update.statusPresence = .cleared
        update.statusColorPresence = .cleared
        update.detailPresence = .cleared
        // The count and the turn flag are left alone on purpose. A terminal
        // reset wipes the display, but the sub-agents cc-status counted and
        // the turn it is tracking are still running: zeroing the count here
        // would make the next Stop read zero and report idle through live
        // background work, and nothing after that would correct it.
        return update
    }
    @objc var indicatorPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var indicator: iTermSRGBColor = iTermSRGBColor(r: 0, g: 0, b: 0)

    @objc var statusPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var status: String? = nil

    @objc var statusColorPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var statusColor: iTermSRGBColor = iTermSRGBColor(r: 0, g: 0, b: 0)

    @objc var detailPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var detail: String? = nil

    // Count of background tasks/subagents the status-reporting program
    // says are still running. Written by cc-status so that later hook
    // events with no task info (idle_prompt) can read the last known
    // count back instead of keeping state of their own on disk.
    @objc var backgroundTasksPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var backgroundTasks: Int = 0

    // When this status should expire on its own, and what to apply in its
    // place when it does. The fallback is a plain update, so an expiring
    // status can hand off to another status rather than only disappearing.
    // Ignored unless expiresOn is something other than .never.
    @objc var expiresOn: VT100TabStatusExpirationReason = .never
    @objc var expirationFallback: VT100TabStatusUpdate?

    // Whether this update says anything about what the session is doing, as
    // opposed to only parking bookkeeping such as the background-task count.
    // Only a real assertion supersedes the previous one's expiration: a
    // program that updates its task count mid-operation has not changed its
    // mind about what should happen when the operation ends.
    @objc var assertsStatus: Bool {
        return statusPresence != .notSet ||
               indicatorPresence != .notSet ||
               statusColorPresence != .notSet ||
               detailPresence != .notSet ||
               expiresOn != .never
    }

    // Add to the count instead of assigning it, clamped at zero. nil means no
    // change. This exists because a caller that has to compute the count
    // itself would otherwise read it, add one, and write it back, and two hook
    // processes doing that at once lose an increment. Applying the delta here
    // makes it one step, so concurrent callers cannot race. Ignored when
    // backgroundTasksPresence is anything but .notSet: assigning and adding in
    // the same update has no sensible meaning.
    @objc var backgroundTasksDelta: NSNumber? = nil

    // Whether the status-reporting program is in the middle of a turn. Like
    // backgroundTasks this is parked here for cc-status, whose Codex hooks get
    // no Stop when a detached sub-agent finishes after the turn that started
    // it; SubagentStop reads this back to decide whether reporting idle would
    // cut off a turn that is still going. Cleared means unknown again. RAM
    // only, never written to an arrangement.
    @objc var turnOpenPresence: VT100TabStatusUpdateFieldPresence = .notSet
    @objc var turnOpen: Bool = false

    // Preconditions: when set, the whole update is dropped unless the flag
    // and the count already hold these values. cc-status decides to write
    // idle from a status it read a round trip earlier; a prompt submitted in
    // between reopens the turn, and an idle written on the strength of the
    // old reading would cover a running turn. Checking here, where the
    // update is applied, closes that window. nil means no precondition.
    @objc var requiredTurnOpen: NSNumber? = nil
    @objc var requiredBackgroundTasks: NSNumber? = nil

    override var description: String {
        var parts = [String]()
        switch indicatorPresence {
        case .notSet: break
        case .cleared:
            parts.append("indicator=cleared")
        case .set:
            parts.append(String(format: "indicator=#%02x%02x%02x",
                                Int(indicator.r * 255),
                                Int(indicator.g * 255),
                                Int(indicator.b * 255)))
        @unknown default: break
        }
        switch statusPresence {
        case .notSet: break
        case .cleared:
            parts.append("status=cleared")
        case .set:
            parts.append("status=\(status ?? "")")
        @unknown default: break
        }
        switch statusColorPresence {
        case .notSet: break
        case .cleared:
            parts.append("status-color=cleared")
        case .set:
            parts.append(String(format: "status-color=#%02x%02x%02x",
                                Int(statusColor.r * 255),
                                Int(statusColor.g * 255),
                                Int(statusColor.b * 255)))
        @unknown default: break
        }
        switch detailPresence {
        case .notSet: break
        case .cleared:
            parts.append("detail=cleared")
        case .set:
            parts.append("detail=\(detail ?? "")")
        @unknown default: break
        }
        switch backgroundTasksPresence {
        case .notSet: break
        case .cleared:
            parts.append("background-tasks=cleared")
        case .set:
            parts.append("background-tasks=\(backgroundTasks)")
        @unknown default: break
        }
        if expiresOn != .never {
            parts.append("expires-on=\(expiresOn)")
            parts.append("then=\(expirationFallback?.description ?? "nothing")")
        }
        if let backgroundTasksDelta {
            parts.append("background-tasks-delta=\(backgroundTasksDelta)")
        }
        switch turnOpenPresence {
        case .notSet: break
        case .cleared:
            parts.append("turn-open=cleared")
        case .set:
            parts.append("turn-open=\(turnOpen)")
        @unknown default: break
        }
        if let requiredTurnOpen {
            parts.append("if-turn-open=\(requiredTurnOpen.boolValue)")
        }
        if let requiredBackgroundTasks {
            parts.append("if-background-tasks=\(requiredBackgroundTasks)")
        }
        if parts.isEmpty {
            return "VT100TabStatusUpdate{empty}"
        }
        return "VT100TabStatusUpdate{\(parts.joined(separator: ", "))}"
    }
}

extension iTermSRGBColor: Equatable {
    public static func == (lhs: iTermSRGBColor, rhs: iTermSRGBColor) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b
    }
}

// Accumulated per-session tab status state from one or more VT100TabStatusUpdate messages.
@objc(iTermSessionTabStatus)
class iTermSessionTabStatus: NSObject {
    let sessionID: String
    private struct State: Equatable {
        var hasIndicator: Bool = false
        var indicatorColor: iTermSRGBColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        var statusText: String? = nil
        var hasStatusTextColor: Bool = false
        var statusTextColor: iTermSRGBColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        var detailText: String? = nil
    }
    // Only what is displayed lives in State: apply() compares it before and
    // after to decide whether anything changed, and a change is what makes
    // PTYSession repaint the tab, reload the Session Status tool and bump the
    // recency that picks a workgroup's representative. The bookkeeping below
    // is kept outside State so that parking a count or a turn flag, which
    // cc-status does on events that change nothing visible, does none of that.
    private var state = State()
    // Last background-task count reported via set_status. RAM only:
    // deliberately excluded from arrangementDictionary() so it never
    // reaches disk (see that method).
    @objc var backgroundTasks: Int = 0
    // Whether the reporting program is mid-turn, or nil when it has not
    // said. RAM only for the same reason as backgroundTasks.
    var turnOpen: Bool? = nil
    // Whether mutations post the global iTermSessionTabStatusDidChange
    // notification. True for a real per-session status (the one
    // SessionStatusController tracks by sessionID). False for the
    // tab-internal aggregate rollup produced by copyStatus(): that
    // copy borrows the winning session's sessionID, so if it
    // broadcast, its clear() (PTYTab.updateAggregatedTabStatus, when
    // the tab's active session changes to one with no status — e.g. a
    // workgroup peer swap) would post a "no active status" for that
    // sessionID and make SessionStatusController drop the real
    // session's still-live status.
    private let broadcastsChanges: Bool
    @objc var hasIndicator: Bool {
        get {
            state.hasIndicator
        }
        set {
            state.hasIndicator = newValue
        }
    }
    @objc var indicatorColor: iTermSRGBColor {
        get {
            state.indicatorColor
        }
        set {
            state.indicatorColor = newValue
        }
    }
    @objc var statusText: String? {
        get {
            state.statusText
        }
        set {
            state.statusText = newValue
        }
    }
    @objc var hasStatusTextColor: Bool {
        get {
            state.hasStatusTextColor
        }
        set {
            state.hasStatusTextColor = newValue
        }
    }
    @objc var statusTextColor: iTermSRGBColor {
        get {
            state.statusTextColor
        }
        set {
            state.statusTextColor = newValue
        }
    }
    @objc var detailText: String? {
        get {
            state.detailText
        }
        set {
            state.detailText = newValue
        }
    }

    @objc var hasActiveStatus: Bool {
        return hasIndicator || statusText != nil
    }

    @objc var priority: Int {
        StatusPrioritySettings.shared.priority(for: statusText)
    }

    @objc init(sessionID: String) {
        self.sessionID = sessionID
        self.broadcastsChanges = true
        super.init()
    }

    private init(sessionID: String, broadcastsChanges: Bool) {
        self.sessionID = sessionID
        self.broadcastsChanges = broadcastsChanges
        super.init()
    }

    // What an update says should happen when the status stops being true is
    // not kept here. iTermTabStatusController owns that, along with
    // the timing that decides when it happens, so this stays a plain record of
    // what the session is showing: something that can be copied for the tab
    // aggregate and written to an arrangement without dragging live state
    // along.
    /// Whether the update's preconditions hold. An unknown flag satisfies
    /// nothing: cc-status treats a flag it was never told as unknown rather
    /// than closed, and the check here has to agree with it. apply() checks
    /// this itself; iTermTabStatusController also asks first, so an update
    /// that is going to be dropped does not disturb an armed expiration.
    @objc func preconditionsHold(for update: VT100TabStatusUpdate) -> Bool {
        if let required = update.requiredTurnOpen, turnOpen != required.boolValue {
            return false
        }
        if let required = update.requiredBackgroundTasks, backgroundTasks != required.intValue {
            return false
        }
        return true
    }

    /// Applies the update and returns whether anything visible changed. The
    /// background-task count and the turn flag are always stored but never
    /// count as a change on their own (see State). An update whose
    /// preconditions do not hold is dropped whole and changes nothing.
    @objc func apply(_ update: VT100TabStatusUpdate) -> Bool {
        guard preconditionsHold(for: update) else {
            DLog("Dropping \(update) because its preconditions do not hold: turnOpen=\(String(describing: turnOpen)) backgroundTasks=\(backgroundTasks)")
            return false
        }
        let before = state
        switch update.indicatorPresence {
        case .notSet:
            break
        case .cleared:
            hasIndicator = false
            indicatorColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        case .set:
            hasIndicator = true
            indicatorColor = update.indicator
        @unknown default:
            break
        }

        switch update.statusPresence {
        case .notSet:
            break
        case .cleared:
            statusText = nil
        case .set:
            statusText = update.status
        @unknown default:
            break
        }

        switch update.statusColorPresence {
        case .notSet:
            break
        case .cleared:
            hasStatusTextColor = false
            statusTextColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        case .set:
            hasStatusTextColor = true
            statusTextColor = update.statusColor
        @unknown default:
            break
        }

        switch update.detailPresence {
        case .notSet:
            break
        case .cleared:
            detailText = nil
        case .set:
            detailText = update.detail
        @unknown default:
            break
        }

        switch update.backgroundTasksPresence {
        case .notSet:
            if let delta = update.backgroundTasksDelta {
                // The delta comes straight from a CLI argument, so it can be
                // anything; a plain + would trap on overflow and take the app
                // down with it. Saturate instead.
                let (sum, overflow) = backgroundTasks.addingReportingOverflow(delta.intValue)
                if overflow {
                    backgroundTasks = delta.intValue > 0 ? Int.max : 0
                } else {
                    backgroundTasks = Swift.max(0, sum)
                }
            }
        case .cleared:
            backgroundTasks = 0
        case .set:
            backgroundTasks = update.backgroundTasks
        @unknown default:
            break
        }
        switch update.turnOpenPresence {
        case .notSet:
            break
        case .cleared:
            turnOpen = nil
        case .set:
            turnOpen = update.turnOpen
        @unknown default:
            break
        }
        if state == before {
            return false
        }
        notify()
        return true
    }

    @objc func clear() {
        hasIndicator = false
        indicatorColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        statusText = nil
        hasStatusTextColor = false
        statusTextColor = iTermSRGBColor(r: 0, g: 0, b: 0)
        detailText = nil
        backgroundTasks = 0
        turnOpen = nil
        notify()
    }

    @objc static let didChangeNotificationName = NSNotification.Name("iTermSessionTabStatusDidChange")

    private func notify() {
        guard broadcastsChanges else {
            return
        }
        NotificationCenter.default.post(name: Self.didChangeNotificationName, object: self)
    }

    /// Creates a colored dot image suitable for tab status indicators.
    /// - Parameters:
    ///   - color: The dot color.
    ///   - size: The image size (square). Defaults to 16.
    ///   - dotDiameter: The diameter of the dot. Defaults to 8.
    ///   - prominent: Whether to draw a ring around the dot for unacknowledged status.
    ///   - isDark: Whether the current appearance is dark (affects ring color).
    @objc static func dotImage(color: NSColor,
                               size: CGFloat = 16,
                               dotDiameter: CGFloat = 8,
                               prominent: Bool = false,
                               isDark: Bool = false) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let lightCenter = color.blended(withFraction: 0.3, of: .white) ?? color

            let dotRect = NSRect(x: (size - dotDiameter) / 2,
                                 y: (size - dotDiameter) / 2,
                                 width: dotDiameter,
                                 height: dotDiameter)

            if prominent {
                let ringDiameter = min(size, dotDiameter + 4)
                let ringRect = NSRect(x: (size - ringDiameter) / 2,
                                      y: (size - ringDiameter) / 2,
                                      width: ringDiameter,
                                      height: ringDiameter)
                let ringColor: NSColor = isDark ? .white : .black
                ringColor.setFill()
                NSBezierPath(ovalIn: ringRect).fill()
            }

            if let gradient = NSGradient(starting: lightCenter, ending: color) {
                let dotPath = NSBezierPath(ovalIn: dotRect)
                gradient.draw(in: dotPath, relativeCenterPosition: .zero)
            }

            return true
        }
    }

    private static let arrangementIndicatorColorKey = "Indicator Color"
    private static let arrangementStatusTextKey = "Status Text"
    private static let arrangementStatusTextColorKey = "Status Text Color"
    private static let arrangementDetailTextKey = "Detail Text"

    // backgroundTasks and turnOpen are deliberately NOT encoded here: they
    // exist so stateless hook invocations (cc-status) can park state in RAM
    // between events, and it must not leak to disk via arrangements.
    // It would also be wrong after a restore, since the tasks it
    // counted and the turn it tracked died with the original session's
    // program.
    @objc func arrangementDictionary() -> NSDictionary? {
        guard hasActiveStatus else {
            return nil
        }
        var dict = [String: Any]()
        if hasIndicator {
            dict[Self.arrangementIndicatorColorKey] = iTermSRGBColorToDictionary(indicatorColor)
        }
        if let statusText {
            dict[Self.arrangementStatusTextKey] = statusText
        }
        if hasStatusTextColor {
            dict[Self.arrangementStatusTextColorKey] = iTermSRGBColorToDictionary(statusTextColor)
        }
        if let detailText {
            dict[Self.arrangementDetailTextKey] = detailText
        }
        return dict as NSDictionary
    }

    @objc static func fromArrangementDictionary(_ dict: NSDictionary, sessionID: String) -> iTermSessionTabStatus {
        let status = iTermSessionTabStatus(sessionID: sessionID)
        if let colorDict = dict[arrangementIndicatorColorKey] as? [AnyHashable: Any] {
            var color = iTermSRGBColor()
            if iTermSRGBColorFromDictionary(colorDict, &color) {
                status.hasIndicator = true
                status.indicatorColor = color
            }
        }
        status.statusText = dict[arrangementStatusTextKey] as? String
        if let colorDict = dict[arrangementStatusTextColorKey] as? [AnyHashable: Any] {
            var color = iTermSRGBColor()
            if iTermSRGBColorFromDictionary(colorDict, &color) {
                status.hasStatusTextColor = true
                status.statusTextColor = color
            }
        }
        status.detailText = dict[arrangementDetailTextKey] as? String
        return status
    }

    @objc func copyStatus() -> iTermSessionTabStatus {
        // The copy is the tab-internal aggregate; it must not broadcast
        // (see broadcastsChanges) so its clear()/changes don't make
        // SessionStatusController drop the source session's real status.
        let copy = iTermSessionTabStatus(sessionID: sessionID,
                                         broadcastsChanges: false)
        copy.hasIndicator = hasIndicator
        copy.indicatorColor = indicatorColor
        copy.statusText = statusText
        copy.hasStatusTextColor = hasStatusTextColor
        copy.statusTextColor = statusTextColor
        copy.detailText = detailText
        copy.backgroundTasks = backgroundTasks
        copy.turnOpen = turnOpen
        return copy
    }
}

@objc(iTermSessionStatusController)
class SessionStatusController: NSObject {
    @objc static let instance = SessionStatusController()
    private(set) var statuses = NotifyingDictionary<String, iTermSessionTabStatus>()

    override init() {
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionStatusDidChange(_:)),
                                               name: iTermSessionTabStatus.didChangeNotificationName,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWillTerminate(_:)),
                                               name: NSNotification.Name.iTermSessionWillTerminate,
                                               object: nil)

        // Pick up tab statuses that were set before this controller was created.
        for session in iTermController.sharedInstance()?.allSessions() ?? [] {
            guard let tabStatus = session.tabStatus, tabStatus.hasActiveStatus else {
                continue
            }
            statuses[tabStatus.sessionID] = tabStatus
        }
    }

    @objc
    private func sessionStatusDidChange(_ notification: Notification) {
        let status = notification.object as! iTermSessionTabStatus
        if status.hasActiveStatus {
            statuses[status.sessionID] = status
        } else {
            statuses.removeValue(forKey: status.sessionID)
        }
    }

    @objc
    private func sessionWillTerminate(_ notification: Notification) {
        let session = notification.object as! PTYSession
        statuses.removeValue(forKey: session.guid)
    }

    func addObserver(_ observer: @escaping NotifyingDictionaryObserver<String, iTermSessionTabStatus>) -> NotifyingDictionaryObserverToken {
        return statuses.addObserver(observer)
    }

    @objc(tabStatusDidChange:)
    func tabStatusDidChange(_ tabStatus: iTermSessionTabStatus) {
        NotificationCenter.default.post(name: iTermSessionTabStatus.didChangeNotificationName,
                                        object: tabStatus)
    }
}
