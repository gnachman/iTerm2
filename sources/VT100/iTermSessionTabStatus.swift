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
    private var state = State()
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
        notify()
    }

    @objc static let didChangeNotificationName = NSNotification.Name("iTermSessionTabStatusDidChange")

    private func notify() {
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
        let copy = iTermSessionTabStatus(sessionID: sessionID)
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
