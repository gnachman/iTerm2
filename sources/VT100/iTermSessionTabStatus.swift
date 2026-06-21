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
    // Provenance for the current visible state. Non-nil when set by a client-side
    // shim (today: CodexTitleStatusAdaptor) rather than by an OSC 21337 emitter.
    // Lets us clear only state we own without trampling a real OSC 21337 status.
    // Kept outside `State` so equality on visible fields is independent of ownership.
    private var _synthesizedStatusSource: String? = nil
    private var state = State()
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

    @objc func apply(_ update: VT100TabStatusUpdate) -> Bool {
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
        if state == before {
            return false
        }
        // A real OSC 21337 update that actually changed visible state claims
        // ownership going forward, so subsequent synthesized clears don't
        // stomp on it. Updates that don't change anything don't reassign
        // ownership.
        _synthesizedStatusSource = nil
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
        _synthesizedStatusSource = nil
        notify()
    }

    // MARK: - Synthesized status (set by client-side adaptors, e.g. Codex title decoder)

    /// State an adaptor maps its agent's lifecycle to. Mirrors the convention Claude
    /// Code's OSC 21337 emitter uses so synthesized agents render with the same colors
    /// and labels (orange "Working", blue "Waiting", green "Idle"). `none` means
    /// "this adaptor owns nothing here right now" and is the value to use after the
    /// adaptor's process has exited the foreground.
    @objc(iTermSynthesizedTabStatusState)
    enum SynthesizedState: Int {
        case none = 0
        case working = 1
        case idle = 2
        case waiting = 3

        fileprivate var indicatorColor: iTermSRGBColor {
            switch self {
            case .none: return iTermSRGBColor(r: 0, g: 0, b: 0)
            case .working: return iTermSRGBColor(r: 1.0, g: 0.58, b: 0.0)  // #ff9500
            case .idle:    return iTermSRGBColor(r: 0.0, g: 0.84, b: 0.37) // #00d75f
            case .waiting: return iTermSRGBColor(r: 0.37, g: 0.53, b: 1.0) // #5f87ff
            }
        }
        fileprivate var statusText: String? {
            switch self {
            case .none: return nil
            case .working: return "Working"
            case .idle: return "Idle"
            case .waiting: return "Waiting"
            }
        }
        fileprivate var statusTextColor: iTermSRGBColor {
            switch self {
            case .none, .idle: return iTermSRGBColor(r: 0.53, g: 0.53, b: 0.53) // #888888 - dim for idle
            case .working: return iTermSRGBColor(r: 1.0, g: 0.58, b: 0.0)
            case .waiting: return iTermSRGBColor(r: 0.37, g: 0.53, b: 1.0)
            }
        }
        fileprivate var hasStatusTextColor: Bool {
            switch self {
            case .none: return false
            case .working, .idle, .waiting: return true
            }
        }
    }

    /// Apply a synthesized status owned by `source`. Returns true iff state changed.
    ///
    /// Today only `CodexTitleStatusAdaptor` is a caller; the source-tag design lets
    /// additional shims coexist later without overwriting each other or a real
    /// OSC 21337 emitter.
    @objc(applySynthesizedState:source:)
    @discardableResult
    func applySynthesizedStatus(_ newState: SynthesizedState, source: String) -> Bool {
        if newState == .none {
            // Only clear what we own.
            guard _synthesizedStatusSource == source else { return false }
            let before = state
            state.hasIndicator = false
            state.indicatorColor = iTermSRGBColor(r: 0, g: 0, b: 0)
            state.statusText = nil
            state.hasStatusTextColor = false
            state.statusTextColor = iTermSRGBColor(r: 0, g: 0, b: 0)
            state.detailText = nil
            _synthesizedStatusSource = nil
            if state == before { return false }
            notify()
            return true
        }
        // Don't overwrite a real OSC 21337 status. Any visible status that
        // we don't own (dot-only or with text) is owned by the emitter.
        if _synthesizedStatusSource == nil && hasActiveStatus {
            return false
        }
        let before = state
        state.hasIndicator = true
        state.indicatorColor = newState.indicatorColor
        state.statusText = newState.statusText
        state.hasStatusTextColor = newState.hasStatusTextColor
        state.statusTextColor = newState.statusTextColor
        // Reset detailText: if a prior emitter left only `detail` behind
        // (hasActiveStatus=false), the synthesized state replaces the visible
        // status and any stale detail would otherwise render next to it.
        state.detailText = nil
        if state == before && _synthesizedStatusSource == source {
            return false
        }
        _synthesizedStatusSource = source
        notify()
        return true
    }

    @objc var synthesizedStatusSource: String? {
        return _synthesizedStatusSource
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

    @objc func arrangementDictionary() -> NSDictionary? {
        guard hasActiveStatus else {
            return nil
        }
        // Synthesized status (owned by a client-side shim like CodexTitleStatusAdaptor)
        // must not be persisted: on restore it would be re-instantiated with no
        // provenance, indistinguishable from a real OSC 21337 status, and locked
        // against the shim's normal clear-on-loss path. The shim re-derives state
        // on the next title/foreground update post-restore.
        if _synthesizedStatusSource != nil {
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
