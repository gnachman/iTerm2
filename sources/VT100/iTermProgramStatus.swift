//
//  iTermProgramStatus.swift
//  iTerm2SharedARC
//

import Foundation

// The Program Status Protocol (OSC 7501). A program reports what it is doing
// (idle, working, blocked on the user, done, or failed) as a list of key=value
// pairs, and the terminal keeps one record per id. The terminal decides how to
// show the records; here the most urgent one drives the session's tab status
// and progress bar.
//
// Spec: https://www.superlogical.com/rex/docs/build/program-status

/// One parsed, validated OSC 7501 report. A report that breaks any rule of the
/// protocol is never constructed, so nothing downstream has to recheck it.
@objc(iTermProgramStatusReport)
final class ProgramStatusReport: NSObject {
    enum State: String {
        case idle
        case working
        case done
        case blocked
        case error
        case clear
    }

    enum Kind: String {
        case permission
        case question
        case auth
    }

    let state: State
    /// Path segments of the record's id. Empty means the root record.
    let id: [String]
    let kind: Kind?
    let progress: Int?
    let app: String?
    let title: String?
    let msg: String?

    // MARK: - Limits

    private static let maxSequenceBytes = 4096
    // ESC ] 7501 ; ... BEL is the shortest framing around the body.
    private static let minimumFramingBytes = 8
    private static let maxKeyBytes = 16
    private static let maxMsgEncodedBytes = 2732
    private static let maxMsgDecodedBytes = 2048
    private static let maxTitleEncodedBytes = 256
    private static let maxTitleDecodedBytes = 192
    private static let maxAppBytes = 32
    private static let maxIDBytes = 128
    private static let maxIDSegmentBytes = 32
    private static let maxIDDepth = 8

    private init(state: State,
                 id: [String],
                 kind: Kind?,
                 progress: Int?,
                 app: String?,
                 title: String?,
                 msg: String?) {
        self.state = state
        self.id = id
        self.kind = kind
        self.progress = progress
        self.app = app
        self.title = title
        self.msg = msg
    }

    /// Whether the body is the feature detection query, which the terminal
    /// answers with the same body.
    @objc static func isFeatureQuery(_ body: String) -> Bool {
        return body.trimmingCharacters(in: .whitespaces) == "?"
    }

    /// The fixed reply to the feature detection query. Nothing else is ever
    /// written back.
    @objc static var featureQueryReply: Data {
        return Data("\u{1b}]7501;?\u{1b}\\".utf8)
    }

    /// Parses the body of an OSC 7501 report (everything between the `;` after
    /// 7501 and the terminator). Returns nil when the report must be ignored
    /// or discarded.
    @objc(reportFromBody:)
    static func parse(_ body: String) -> ProgramStatusReport? {
        guard body.utf8.count + minimumFramingBytes <= maxSequenceBytes else {
            DLog("Discard OSC 7501 report of \(body.utf8.count) bytes: too long")
            return nil
        }
        var pairs = [String: String]()
        for rawPair in body.split(separator: ":", omittingEmptySubsequences: false) {
            guard let equals = rawPair.firstIndex(of: "=") else {
                DLog("Skip malformed OSC 7501 pair \(rawPair): no =")
                continue
            }
            let key = rawPair[..<equals].trimmingCharacters(in: .whitespaces)
            let value = rawPair[rawPair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            // The key limit is a limit, not a syntax rule, so it discards the
            // whole report rather than skipping the pair.
            guard key.utf8.count <= maxKeyBytes else {
                DLog("Discard OSC 7501 report: key \(key) too long")
                return nil
            }
            guard !key.isEmpty, key.utf8.allSatisfy(isKeyByte) else {
                DLog("Skip malformed OSC 7501 pair \(rawPair): bad key")
                continue
            }
            guard value.utf8.allSatisfy(isValueByte) else {
                DLog("Skip malformed OSC 7501 pair \(rawPair): bad value")
                continue
            }
            // Every occurrence is checked against the limits, not just the
            // last one, so a report that breaks a limit is discarded whole even
            // if a later pair would have replaced the offending value.
            guard valueWithinLimits(key: key, value: value) else {
                DLog("Discard OSC 7501 report: \(key) exceeds its limit")
                return nil
            }
            pairs[key] = value
        }

        guard let stateValue = pairs["state"], let state = State(rawValue: stateValue) else {
            DLog("Ignore OSC 7501 report with missing or unknown state")
            return nil
        }

        var id = [String]()
        if let idValue = pairs["id"] {
            guard let parsed = parseID(idValue) else {
                DLog("Ignore OSC 7501 report with malformed id \(idValue)")
                return nil
            }
            id = parsed
        }

        // Text is decoded for every report that carries it, even where it
        // would go unused, because undecodable text discards the report.
        let title: String?
        let msg: String?
        switch decodeText(pairs["title"], maxDecodedBytes: maxTitleDecodedBytes) {
        case .invalid:
            return nil
        case .absent:
            title = nil
        case .text(let text):
            title = text
        }
        switch decodeText(pairs["msg"], maxDecodedBytes: maxMsgDecodedBytes) {
        case .invalid:
            return nil
        case .absent:
            msg = nil
        case .text(let text):
            msg = text
        }

        let kind: Kind? = state == .blocked ? pairs["kind"].flatMap { Kind(rawValue: $0) } : nil

        var progress: Int? = nil
        if state == .working || state == .blocked,
           let progressValue = pairs["progress"],
           !progressValue.isEmpty,
           progressValue.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
           let number = Int(progressValue),
           (0...100).contains(number) {
            progress = number
        }

        let app = pairs["app"].flatMap { isIDSegment($0) ? $0 : nil }

        return ProgramStatusReport(state: state,
                                   id: id,
                                   kind: kind,
                                   progress: progress,
                                   app: app,
                                   title: title,
                                   msg: msg)
    }

    override var description: String {
        var parts = ["state=\(state.rawValue)"]
        if !id.isEmpty {
            parts.append("id=\(id.joined(separator: "/"))")
        }
        if let kind {
            parts.append("kind=\(kind.rawValue)")
        }
        if let progress {
            parts.append("progress=\(progress)")
        }
        if let app {
            parts.append("app=\(app)")
        }
        if let title {
            parts.append("title=\(title)")
        }
        if let msg {
            parts.append("msg=\(msg)")
        }
        return "<ProgramStatusReport \(parts.joined(separator: " "))>"
    }

    // MARK: - Private

    private enum DecodedText {
        case absent
        case invalid
        case text(String)
    }

    private static func isKeyByte(_ byte: UInt8) -> Bool {
        return byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        return (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) ||
               (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ||
               (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }

    // value := [A-Za-z0-9_.,+/=-]*
    private static func isValueByte(_ byte: UInt8) -> Bool {
        return isAlphanumeric(byte) || "_.,+/=-".utf8.contains(byte)
    }

    // segment := [A-Za-z0-9_.+-]{1,32}, which is also the grammar for app.
    private static func isIDSegment(_ segment: String) -> Bool {
        return !segment.isEmpty &&
               segment.utf8.count <= maxIDSegmentBytes &&
               segment.utf8.allSatisfy { isAlphanumeric($0) || "_.+-".utf8.contains($0) }
    }

    private static func valueWithinLimits(key: String, value: String) -> Bool {
        let length = value.utf8.count
        switch key {
        case "msg":
            return length <= maxMsgEncodedBytes
        case "title":
            return length <= maxTitleEncodedBytes
        case "app":
            return length <= maxAppBytes
        case "id":
            return length <= maxIDBytes &&
                   value.split(separator: "/", omittingEmptySubsequences: false).count <= maxIDDepth
        default:
            return true
        }
    }

    private static func parseID(_ value: String) -> [String]? {
        let segments = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.allSatisfy(isIDSegment) else {
            return nil
        }
        return segments
    }

    private static func decodeText(_ encoded: String?, maxDecodedBytes: Int) -> DecodedText {
        guard let encoded, !encoded.isEmpty else {
            return .absent
        }
        // Padding is optional on the wire but required by Foundation.
        var padded = encoded
        let remainder = padded.utf8.count % 4
        if remainder == 1 {
            return .invalid
        }
        if remainder > 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: padded),
              data.count <= maxDecodedBytes,
              let text = String(data: data, encoding: .utf8) else {
            return .invalid
        }
        let hasControl = text.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || (scalar.value >= 0x7F && scalar.value <= 0x9F)
        }
        if hasControl {
            return .invalid
        }
        return .text(text)
    }
}

/// The records a terminal holds, one per id. Each report replaces its record
/// completely.
struct ProgramStatusRecords {
    struct Record: Equatable {
        var state: ProgramStatusReport.State
        var id: [String]
        var kind: ProgramStatusReport.Kind?
        var progress: Int?
        var app: String?
        var title: String?
        var msg: String?
        /// When the record was last written, for eviction and for breaking
        /// ties between equally urgent records.
        var serial: Int
    }

    static let defaultCapacity = 256

    private(set) var records = [String: Record]()
    /// The serial of the most recent write. Records written later have a
    /// higher one.
    private(set) var serial = 0
    private let capacity: Int

    init(capacity: Int = Self.defaultCapacity) {
        self.capacity = capacity
    }

    var isEmpty: Bool {
        return records.isEmpty
    }

    mutating func apply(_ report: ProgramStatusReport) {
        let key = report.id.joined(separator: "/")
        if report.state == .clear {
            if report.id.isEmpty {
                records.removeAll()
            } else {
                let prefix = key + "/"
                records = records.filter { $0.key != key && !$0.key.hasPrefix(prefix) }
            }
            return
        }
        if records[key] == nil && records.count >= capacity,
           let oldest = records.min(by: { $0.value.serial < $1.value.serial }) {
            records.removeValue(forKey: oldest.key)
        }
        serial += 1
        records[key] = Record(state: report.state,
                              id: report.id,
                              kind: report.kind,
                              progress: report.progress,
                              app: report.app,
                              title: report.title,
                              msg: report.msg,
                              serial: serial)
    }

    /// Removes records in any of the given states that were written no later
    /// than `serial` (all of them, by default). Returns whether anything was
    /// removed.
    @discardableResult
    mutating func remove(states: Set<ProgramStatusReport.State>, writtenThrough serial: Int = .max) -> Bool {
        let before = records.count
        records = records.filter { !states.contains($0.value.state) || $0.value.serial > serial }
        return records.count != before
    }

    mutating func removeAll() {
        records.removeAll()
    }

    /// Turns records in any of the given states idle, keeping their text.
    /// The program did not write this, so the records keep their serials.
    /// Returns whether anything changed.
    @discardableResult
    mutating func markSeen(states: Set<ProgramStatusReport.State>) -> Bool {
        var changed = false
        for (key, record) in records where states.contains(record.state) {
            var idle = record
            idle.state = .idle
            records[key] = idle
            changed = true
        }
        return changed
    }

    /// The record most in need of the user, with its app filled in from its
    /// nearest ancestor when it has none of its own. Among equally urgent
    /// records the most recently written one wins.
    var mostUrgent: Record? {
        guard var best = records.values.max(by: { lhs, rhs in
            let (l, r) = (Self.urgency(lhs.state), Self.urgency(rhs.state))
            if l != r {
                return l < r
            }
            return lhs.serial < rhs.serial
        }) else {
            return nil
        }
        if best.app == nil {
            best.app = inheritedApp(for: best.id)
        }
        return best
    }

    private func inheritedApp(for id: [String]) -> String? {
        var path = id
        while !path.isEmpty {
            path.removeLast()
            if let app = records[path.joined(separator: "/")]?.app {
                return app
            }
        }
        return nil
    }

    private static func urgency(_ state: ProgramStatusReport.State) -> Int {
        switch state {
        case .blocked: return 5
        case .error: return 4
        case .done: return 3
        case .working: return 2
        case .idle: return 1
        case .clear: return 0
        }
    }
}

/// Owns a session's OSC 7501 records and keeps the session's tab status and
/// progress bar in line with them. The tab status is shared with OSC 21337,
/// triggers and the scripting API: whichever wrote last is what shows.
///
/// Main thread only.
@objc(iTermProgramStatusController)
final class ProgramStatusController: NSObject {
    private var records = ProgramStatusRecords()
    private let applyStatus: (VT100TabStatusUpdate) -> Void
    private let currentProgress: () -> VT100ScreenProgress
    private let setProgress: (VT100ScreenProgress) -> Void

    /// Whether the tab status currently showing came from a record. Once
    /// something else writes the status, record changes that the program did
    /// not report (a prompt, a keypress) must not overwrite it.
    private var isShowingStatus = false

    /// The progress a record last put on the bar, or nil when the bar is not
    /// the records' to change. A bar from OSC 9;4 is left alone by records
    /// that do not themselves carry progress. Remembered rather than read back
    /// from the screen, which catches up with a change only after the next
    /// sync and so may not yet show the last one made here.
    private var ownedProgress: VT100ScreenProgress?

    /// When the records changed a bar they did not put there (pausing or
    /// reddening an OSC 9;4 bar), the value it had before, so it can be given
    /// back as it was. nil when the bar came from a record's own progress.
    private var borrowedProgress: VT100ScreenProgress?

    private static let transientStates: Set<ProgramStatusReport.State> = [.working, .blocked, .idle]
    private static let finishedStates: Set<ProgramStatusReport.State> = [.done, .error]

    @objc
    /// - Parameters:
    ///   - applyStatus: Sets the session's tab status.
    ///   - currentProgress: The progress the screen is showing, which may lag
    ///     a change made through setProgress.
    ///   - setProgress: Changes the screen's progress without going through
    ///     OSC 9;4, so it never starts or ends an operation that a status set
    ///     with expires-on=progress-end is waiting on.
    init(applyStatus: @escaping (VT100TabStatusUpdate) -> Void,
         currentProgress: @escaping () -> VT100ScreenProgress,
         setProgress: @escaping (VT100ScreenProgress) -> Void) {
        self.applyStatus = applyStatus
        self.currentProgress = currentProgress
        self.setProgress = setProgress
        super.init()
    }

    /// The program sent a report.
    @objc(handleReport:)
    func handle(_ report: ProgramStatusReport) {
        DLog("Handle \(report)")
        records.apply(report)
        render()
    }

    /// The serial of the most recent record write, for commandDidEnd(through:).
    @objc var serial: Int {
        return records.serial
    }

    /// The program exited. Working, blocked and idle records end with it;
    /// done and error stay until the user has seen them. The caller has just
    /// cleared the tab status, so whatever records survive are shown again.
    @objc
    func commandDidEnd() {
        commandDidEnd(through: .max)
    }

    /// A new shell prompt began after the record write with the given serial.
    /// The prompt's own cleanup runs later than the reports around it, so a
    /// record written after the prompt (by a background job, say) is spared.
    @objc(commandDidEndThroughSerial:)
    func commandDidEnd(through serial: Int) {
        records.remove(states: Self.transientStates, writtenThrough: serial)
        statusWasCleared()
    }

    /// Something cleared the tab status without saying anything about the
    /// records, such as a reset other than RIS. Shows the records again.
    @objc
    func statusWasCleared() {
        isShowingStatus = false
        refresh(showingStatus: !records.isEmpty)
    }

    /// The user pressed a key in the session, which means they have seen any
    /// result that was waiting for them. Finished and failed records become
    /// idle, keeping their message, the same as a done or error status set any
    /// other way (see TabStatusController.userDidPressKey).
    @objc
    func userDidPressKey() {
        guard records.markSeen(states: Self.finishedStates) else {
            return
        }
        DLog("Keypress marked finished records seen")
        refresh(showingStatus: isShowingStatus)
    }

    /// A full reset (RIS, or a reset the user asked for) removes every record.
    @objc
    func removeAllRecords() {
        records.removeAll()
        refresh(showingStatus: isShowingStatus)
    }

    /// Something other than a record set the tab status.
    @objc
    func otherWriterDidSetStatus() {
        isShowingStatus = false
    }

    /// A reset stopped the progress bar behind this controller's back. What it
    /// remembers setting is no longer showing, so forget it and put the bar
    /// back for whatever records survived the reset.
    @objc
    func progressWasReset() {
        ownedProgress = nil
        borrowedProgress = nil
        // The reset stopped the bar, but the screen's progress as seen from
        // here may not have caught up yet, and pausing that stale value would
        // borrow a bar that no longer exists.
        refresh(showingStatus: false, screenProgress: .stopped)
    }

    /// The program reported progress through OSC 9;4, which now owns the bar.
    @objc
    func progressProtocolDidReport() {
        ownedProgress = nil
        borrowedProgress = nil
    }

    // MARK: - Private

    private func render() {
        refresh(showingStatus: true)
    }

    /// Brings the progress bar, and the tab status if `showingStatus`, in
    /// line with the most urgent record. With no records left, a status the
    /// records put up is cleared.
    /// - Parameter screenProgress: What the bar shows when the records do not
    ///   own it, if known better than currentProgress() can say.
    private func refresh(showingStatus: Bool, screenProgress: VT100ScreenProgress? = nil) {
        let record = records.mostUrgent
        if showingStatus {
            if let record {
                applyStatus(Self.statusUpdate(for: record))
                isShowingStatus = true
            } else if isShowingStatus {
                applyStatus(VT100TabStatusUpdate.clear)
                isShowingStatus = false
            }
        }
        if let record {
            updateProgressBar(for: record, screenProgress: screenProgress ?? currentProgress())
        } else {
            releaseProgressBar()
        }
    }

    private func updateProgressBar(for record: ProgramStatusRecords.Record,
                                   screenProgress: VT100ScreenProgress) {
        let current = ownedProgress ?? screenProgress
        let currentPercentage = Int(VT100ScreenProgressPercentage(current))
        switch record.state {
        case .working:
            if let progress = record.progress {
                takeProgressBar(base: .successBase, percentage: progress)
            } else if let borrowedProgress {
                // The block or error that changed someone else's bar is
                // gone, so give it back as it was.
                giveBackProgressBar(borrowedProgress)
            } else {
                // Each report replaces its record completely, so a record
                // with no progress shows none, whatever an earlier one said.
                releaseProgressBar()
            }
        case .blocked:
            if let progress = record.progress {
                takeProgressBar(base: .warningBase, percentage: progress)
            } else if currentPercentage >= 0 {
                // Keep the percentage that is showing and mark it paused, as
                // OSC 9;4;4 does when it has no percentage of its own.
                borrowProgressBar(base: .warningBase, percentage: currentPercentage, from: screenProgress)
            } else if VT100ScreenProgressIsVisible(current) {
                // A spinner (or an error with no percentage) has no amount to
                // keep, so pause it as a spinner.
                borrowProgressBar(.pausedIndeterminate, from: screenProgress)
            }
        case .error:
            if ownedProgress != nil {
                if currentPercentage >= 0 {
                    borrowProgressBar(base: .errorBase, percentage: currentPercentage, from: screenProgress)
                } else {
                    borrowProgressBar(.error, from: screenProgress)
                }
            }
        case .done, .idle, .clear:
            releaseProgressBar()
        }
    }

    /// Puts a record's own progress on the bar.
    private func takeProgressBar(base: VT100ScreenProgress, percentage: Int) {
        guard let progress = VT100ScreenProgress(rawValue: base.rawValue + percentage) else {
            return
        }
        borrowedProgress = nil
        setOwnedProgress(progress)
    }

    /// Changes how the bar looks without being its source: pausing or
    /// reddening it. Remembers what it was if the records did not put it there.
    private func borrowProgressBar(base: VT100ScreenProgress,
                                   percentage: Int,
                                   from screenProgress: VT100ScreenProgress) {
        guard let progress = VT100ScreenProgress(rawValue: base.rawValue + percentage) else {
            return
        }
        borrowProgressBar(progress, from: screenProgress)
    }

    private func borrowProgressBar(_ progress: VT100ScreenProgress,
                                   from screenProgress: VT100ScreenProgress) {
        if ownedProgress == nil {
            borrowedProgress = screenProgress
        }
        setOwnedProgress(progress)
    }

    private func setOwnedProgress(_ progress: VT100ScreenProgress) {
        guard progress != ownedProgress else {
            return
        }
        ownedProgress = progress
        setProgress(progress)
    }

    /// Restores a bar the records borrowed and stops being responsible for it.
    private func giveBackProgressBar(_ original: VT100ScreenProgress) {
        let changed = ownedProgress != original
        ownedProgress = nil
        borrowedProgress = nil
        if changed {
            setProgress(original)
        }
    }

    /// The records are done with the bar. One they put up comes down; one they
    /// only paused or reddened goes back to what its owner last said.
    private func releaseProgressBar() {
        guard ownedProgress != nil else {
            return
        }
        if let borrowedProgress {
            giveBackProgressBar(borrowedProgress)
            return
        }
        ownedProgress = nil
        setProgress(.stopped)
    }

    private static func color(_ hex: UInt32) -> iTermSRGBColor {
        return iTermSRGBColor(r: Double((hex >> 16) & 0xff) / 255.0,
                              g: Double((hex >> 8) & 0xff) / 255.0,
                              b: Double(hex & 0xff) / 255.0)
    }

    /// Sets the status text and both colors for a state. The same text and
    /// colors cc-status writes, so a program using this protocol looks like
    /// Claude Code with its hooks installed, and StatusPrioritySettings'
    /// default patterns rank it the same way.
    static func setStatusAndColors(for state: ProgramStatusReport.State, on update: VT100TabStatusUpdate) {
        let wire: String
        let indicator: UInt32
        let textColor: UInt32
        switch state {
        case .idle:
            wire = "idle"
            indicator = 0x00d75f
            textColor = 0x888888
        case .working:
            wire = "working"
            indicator = 0xff9500
            textColor = 0xff9500
        case .blocked:
            wire = "waiting"
            indicator = 0x5f87ff
            textColor = 0x5f87ff
        case .done:
            wire = "done"
            indicator = 0x00d75f
            textColor = 0x00d75f
        case .error, .clear:
            wire = "error"
            indicator = 0xff3b30
            textColor = 0xff3b30
        }
        update.statusPresence = .set
        update.status = wire
        update.indicatorPresence = .set
        update.indicator = color(indicator)
        update.statusColorPresence = .set
        update.statusColor = color(textColor)
    }

    /// Builds a complete status (every field set or cleared), since each
    /// report replaces its record completely and the status should show
    /// nothing left over from an earlier one.
    static func statusUpdate(for record: ProgramStatusRecords.Record) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        setStatusAndColors(for: record.state, on: update)
        if let detail = detail(for: record) {
            update.detailPresence = .set
            update.detail = detail
        } else {
            update.detailPresence = .cleared
        }
        return update
    }

    private static func detail(for record: ProgramStatusRecords.Record) -> String? {
        let message = record.msg.map(sanitized) ?? kindDescription(record.kind)
        // The root record's label is normally the window title already, so
        // only a child record's title adds anything.
        guard !record.id.isEmpty, let title = record.title.map(sanitized), !title.isEmpty else {
            return message
        }
        guard let message, !message.isEmpty else {
            return title
        }
        return String(format: String(localized: "ProgramStatus.TitledDetail",
                                     defaultValue: "%1$@: %2$@",
                                     comment: "Detail line for a program status that names one of several tasks. %1$@ is the task's name, %2$@ is what the task is doing or waiting for."),
                      title, message)
    }

    private static func kindDescription(_ kind: ProgramStatusReport.Kind?) -> String? {
        switch kind {
        case .permission:
            return String(localized: "ProgramStatus.NeedsApproval",
                          defaultValue: "Waiting for approval",
                          comment: "Detail line when a program is waiting for the user to approve something")
        case .question:
            return String(localized: "ProgramStatus.NeedsAnswer",
                          defaultValue: "Waiting for an answer",
                          comment: "Detail line when a program is waiting for the user to type an answer")
        case .auth:
            return String(localized: "ProgramStatus.NeedsLogin",
                          defaultValue: "Waiting for login",
                          comment: "Detail line when a program is waiting for a password, token or other credential")
        case nil:
            return nil
        }
    }

    /// Removes invisible formatting characters, including text direction
    /// overrides, and line separators, since this text is shown outside the
    /// terminal grid. Keeps the format characters that text needs to render
    /// correctly rather than to rearrange it: the joiners that build emoji
    /// sequences and shape Persian and Indic text, and the tag characters in
    /// subdivision flags.
    static func sanitized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format where !Self.keptFormatCharacters.contains(scalar.value):
                continue
            case .lineSeparator, .paragraphSeparator:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // ZWNJ, ZWJ, and the tag characters.
    private static let keptFormatCharacters: Set<UInt32> =
        Set([0x200C, 0x200D]).union(Set(0xE0020...0xE007F))
}
