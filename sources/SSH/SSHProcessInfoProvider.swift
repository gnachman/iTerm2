//
//  SSHProcessInfoProvider.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/22.
//

import Foundation

fileprivate enum ProcessEdit {
    case add(PSRow)
    case edit(PSRow)
    case remove(pid_t)

    init?(_ line: String) {
        switch line.first {
        case "+":
            if let row = PSRow(String(line.dropFirst())) {
                self = .add(row)
                return
            }
        case "-":
            if let pid = pid_t(line.dropFirst()) {
                self = .remove(pid)
                return
            }
        case "~":
            if let row = PSRow(String(line.dropFirst())) {
                self = .edit(row)
                return
            }
        default:
            break
        }
        return nil
    }
}

fileprivate struct PSRow {
    let pid: pid_t
    let ppid: pid_t
    /// nil from a framer too old to report it.
    let pgid: pid_t?
    let command: String
    let fg: Bool
    /// False when framer marked the process as in the foreground process group with neither its
    /// stdin nor its stdout on a terminal (OFF_TERMINAL_MARKER in framer.py), like the caffeinate
    /// claude starts. True otherwise, including from a framer too old to check.
    let stdioOnTerminal: Bool
    let startTime: Date?

    // framer sends `pid ppid pgid stat start-time command`; one that predates pgid leaves it out.
    // stat always starts with a letter, so the two can't be confused.
    private static func pattern(withPGID: Bool) -> String {
        let whitespace = "\\s+"
        let number = "\\d+"
        let nonspace = "\\S+"
        let letters = "[\\p{Letter}]+"

        return ["^",
                "\\s*",
                "(",
                number,  // pid
                ")",
                whitespace,
                "(",
                number,  // ppid
                ")",
                whitespace,
                withPGID ? "(" + number + ")" + whitespace : "",  // pgid
                "(",
                nonspace,  // stat
                ")",
                whitespace,
                "(",
                letters,  // day of week
                whitespace,
                letters,  // name of month
                whitespace,
                number,  // day of month
                whitespace,
                number,  // hh
                ":",
                number,  // mm
                ":",
                number,  // ss
                whitespace,
                number,  // yyyy
                ")",
                whitespace,
                "(.*)"  // command
        ].joined(separator: "")
    }

    init?(_ line: String) {
        let nsstring = line as NSString
        var ranges = line.captureGroups(regex: Self.pattern(withPGID: true))
        var pgid: pid_t?
        if ranges.count == 7 {
            pgid = pid_t(nsstring.substring(with: ranges[3]))
            ranges.remove(at: 3)
        } else {
            ranges = line.captureGroups(regex: Self.pattern(withPGID: false))
        }
        guard ranges.count == 6,
              let pid = pid_t(nsstring.substring(with: ranges[1])),
              let ppid = pid_t(nsstring.substring(with: ranges[2])) else {
            return nil
        }
        self.pid = pid
        self.ppid = ppid
        self.pgid = pgid
        let stat = nsstring.substring(with: ranges[3])
        self.fg = stat.contains("+")
        self.stdioOnTerminal = !stat.contains("!")

        let ltime = nsstring.substring(with: ranges[4])
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d HH:mm:ss yyyy"
        if let date = formatter.date(from: ltime) {
            startTime = date
        } else {
            startTime = nil
        }
        self.command = nsstring.substring(with: ranges[5])
    }
}

@MainActor
class SSHProcessInfoProvider {
    private weak var runner: SSHCommandRunning?
    private var collection: ProcessCollectionProvider?
    private var closures = [() -> ()]()
    private var _needsUpdate = false
    private let rateLimit = iTermRateLimitedUpdate(
        name: "ssh-process-info-provider",
        minimumInterval: 1)
    private var dirtyPIDs = Set<pid_t>()
    private var cachedDeepestForegroundJob = [pid_t: iTermProcessInfo]()
    private var cachedDisplayForegroundJob = [pid_t: iTermProcessInfo]()
    private var tracked = Set<pid_t>()
    private var rootInfo: iTermProcessInfo?
    private let rootPID: pid_t
    private var haveBumped = false
    private var paneProviders = [pid_t: SSHPaneProcessInfoProvider]()
    private var lastRows = [pid_t: PSRow]()
    private(set) var cpuUtilization: Double?
    let cpuUtilizationPublisher = iTermPublisher<NSNumber>(capacity: 120)

    init(rootPID: pid_t,
         runner: SSHCommandRunning) {
        self.rootPID = rootPID
        self.runner = runner
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.rateLimit.minimumInterval = 1
                }
            }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.rateLimit.minimumInterval = 5
                }
            }
        needsUpdate = true
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                // We must publish once a second for the status bar component to draw properly.
                if let cpuUtilization = self.cpuUtilization {
                    self.cpuUtilizationPublisher.publish(NSNumber(value: cpuUtilization))
                }
            }
        }
    }

    var needsUpdate: Bool {
        set {
            _needsUpdate = newValue
        }
        get {
            return _needsUpdate
        }
    }

    @objc func updateUrgently() {
        needsUpdate = true
        updateIfNeeded()
    }

    private func updateIfNeeded() {
        guard _needsUpdate else {
            return
        }
        reallyUpdate { [weak self] in
            self?._needsUpdate = false
        }
    }

    private func collectBlockAndUpdate() {
        reallyUpdate {
            let closures = self.closures
            self.closures.removeAll()
            for closure in closures {
                closure()
            }
        }
    }

    private func reallyUpdate(_ completion: @escaping () -> ()) {
        runner?.poll { [weak self] data in
            if let string = String(data: data, encoding: .utf8) {
                self?.finishUpdate(string)
            }
            completion()
        }
    }

    private func finishUpdate(_ psout: String) {
        if psout.isEmpty {
            // No change since last update
            return
        }
        handle(psout)
    }

    func handle(_ output: String) {
        let lines = output.components(separatedBy: "\n")
        // $begin name1
        // [lines of ouptut]
        // $begin name2
        // [lines of output]
        var cats = [String: [String]]()
        var key: String? = nil
        for line in lines {
            if line.isEmpty {
                continue
            }
            let beginPrefix = "$begin "
            if line.hasPrefix(beginPrefix) {
                key = String(line.dropFirst(beginPrefix.count))
                continue
            }
            if let key {
                cats[key] = cats[key, default: []] + [line]
            }
        }
        if let psLines = cats["ps"] {
            handlePS(psLines)
        }
        if let cpuLines = cats["cpu"] {
            handleCPU(cpuLines)
        }
    }

    func handlePS(_ lines: [String]) {
        // Parse output of poll
        let edits = lines.compactMap { line in
            ProcessEdit(line)
        }

        lastRows = apply(edits, to: lastRows)
        let rows = Array(lastRows.values)
        let dataSource = SSHProcessDataSource(rows)
        let collection = ProcessCollection(dataSource: dataSource)
        for row in rows {
            collection.addProcess(withProcessID: row.pid, parentProcessID: row.ppid)
        }
        collection.commit()

        self.collection = collection
        cachedDeepestForegroundJob = newDeepestForegroundJobCache()
        cachedDisplayForegroundJob = newDisplayForegroundJobCache()
        _needsUpdate = false
        rootInfo = collection.info(forProcessID: rootPID)
    }

    func handleCPU(_ lines: [String]) {
        guard let firstLine = lines.first, firstLine.hasPrefix("=") else {
            return
        }

        let trimmedLine = firstLine.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)

        let percentage: Double?
        if trimmedLine.hasSuffix("%") {
            let percentageString = trimmedLine.dropLast()
            percentage = Double(percentageString)
        } else {
            percentage = Double(trimmedLine)
        }
        guard let percentage else {
            return
        }
        cpuUtilization = percentage / 100.0
    }

    private func apply(_ edits: [ProcessEdit], to original: [pid_t: PSRow]) -> [pid_t: PSRow] {
        var result = original
        for edit in edits {
            switch edit {
            case .remove(let pid):
                result.removeValue(forKey: pid)
            case .add(let replacement), .edit(let replacement):
                result[replacement.pid] = replacement
            }
        }
        return result
    }

    /// As for a local session: the deepest foreground job on the terminal, else the deepest
    /// foreground job. framer says which processes are on a terminal; SSHProcessDataSource gives
    /// them all one synthetic tty.
    private func newDisplayForegroundJobCache() -> [pid_t: iTermProcessInfo] {
        var cache = [pid_t: iTermProcessInfo]()
        guard let collection = collection else {
            return cache
        }
        for pid in tracked {
            if let info = collection.info(forProcessID: pid)?.deepestForegroundJob(
                attachedToTTYRdev: SSHProcessDataSource.terminalRdev) {
                cache[pid] = info
            }
        }
        return cache
    }

    private func newDeepestForegroundJobCache() -> [pid_t: iTermProcessInfo] {
        var cache = [pid_t: iTermProcessInfo]()
        guard let collection = collection else {
            return cache
        }
        for pid in tracked {
            if let info = collection.info(forProcessID: pid)?.deepestForegroundJob {
                cache[pid] = info
            }
        }
        return cache
    }
}

fileprivate class SSHProcessDataSource: NSObject, ProcessDataSource {
    /// A stand-in for "a terminal": remote device numbers mean nothing here, and all that
    /// matters is whether a process's stdio is on one.
    static let terminalRdev: dev_t = 1

    private let rows: [PSRow]
    private let index: [pid_t: Int]

    init(_ rows: [PSRow]) {
        self.rows = rows
        var index = [pid_t: Int]()
        for (i, row) in rows.enumerated() {
            index[row.pid] = i
        }
        self.index = index
    }

    private func row(pid: pid_t) -> PSRow? {
        guard let i = index[pid] else {
            return nil
        }
        return rows[i]
    }

    func nameOfProcess(withPid thePid: pid_t,
                       isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
        guard let row = self.row(pid: thePid) else {
            return nil
        }
        isForeground.pointee = ObjCBool(row.fg)
        guard let first = (row.command as NSString).componentsInShellCommand().first else {
            return nil
        }
        return first.lastPathComponent
    }

    func commandLineArguments(forProcess pid: pid_t,
                              execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
        guard let row = self.row(pid: pid) else {
            return nil
        }
        let args = (row.command as NSString).componentsInShellCommand()
        if let first = args.first {
            execName?.pointee = (first as NSString).removingPrefix("-") as NSString
        }
        return args
    }

    // No rawCommandLineArguments: ps joins the arguments with spaces, so splitting its command
    // column can't recover them. `claude "update the readme"` comes back as four arguments.

    func processGroupID(forProcess pid: pid_t) -> pid_t {
        return row(pid: pid)?.pgid ?? 0
    }

    func startTime(forProcess pid: pid_t) -> Date? {
        guard let row = self.row(pid: pid) else {
            return nil
        }
        return row.startTime
    }

    func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
        // framer reports only whether a process's stdio is on a terminal, not which fd or which
        // terminal.
        guard let row = row(pid: pid), row.stdioOnTerminal else {
            return 0
        }
        return Self.terminalRdev
    }
}

@MainActor
extension SSHProcessInfoProvider: ProcessInfoProvider {
    func processInfo(for pid: pid_t) -> iTermProcessInfo? {
        return collection?.info(forProcessID: pid)
    }

    func setNeedsUpdate(_ needsUpdate: Bool) {
        self.needsUpdate = needsUpdate
    }

    func requestImmediateUpdate(completion: @escaping () -> ()) {
        closures.append(completion)
        needsUpdate = closures.count == 1
        if !needsUpdate {
            DLog("request immediate update just added block to queue")
            return
        }
        collectBlockAndUpdate()
    }

    func updateSynchronously() {
        // Sadly this is impossible
    }

    func deepestForegroundJob(for pid: pid_t) -> iTermProcessInfo? {
        return cachedDeepestForegroundJob[pid]
    }

    func displayForegroundJob(for pid: pid_t) -> iTermProcessInfo? {
        return cachedDisplayForegroundJob[pid] ?? cachedDeepestForegroundJob[pid]
    }

    /// Idempotent: a pid already tracked is not sent to framer again. reregisterTrackedPIDs is for
    /// after a reset, when framer has forgotten them.
    func register(trackedPID pid: pid_t) {
        guard !tracked.contains(pid) else {
            return
        }
        runner?.registerProcess(pid)
        tracked.insert(pid)
        needsUpdate = true
    }

    func unregister(trackedPID pid: pid_t) {
        runner?.deregisterProcess(pid)
        tracked.remove(pid)
        paneProviders.removeValue(forKey: pid)
    }

    /// Registers every tracked pid with framer again. A framer reset forgets its registrations, and
    /// the tracked set includes tmux panes as well as the login shell.
    func reregisterTrackedPIDs(including extra: pid_t? = nil) {
        if let extra {
            tracked.insert(extra)
        }
        for pid in tracked {
            runner?.registerProcess(pid)
        }
        needsUpdate = true
    }

    /// The jobs in `pid`'s subtree, as a session sees them: for a tmux pane on this host, whose
    /// pid is registered here. One per pid, so its update state survives between calls.
    func sessionProcessInfoProvider(forPID pid: pid_t) -> SSHPaneProcessInfoProvider {
        if let existing = paneProviders[pid] {
            return existing
        }
        let pane = SSHPaneProcessInfoProvider(provider: self, pid: pid)
        paneProviders[pid] = pane
        return pane
    }

    /// The deepest foreground job under `pid`, asking for an update the first time there is none.
    fileprivate func cachedJob(for pid: pid_t, haveBumped: inout Bool) -> iTermProcessInfo? {
        if let info = deepestForegroundJob(for: pid) {
            return info
        }
        if !haveBumped {
            haveBumped = true
            needsUpdate = true
        }
        return nil
    }

    fileprivate func fetchJob(for pid: pid_t,
                              haveBumped: inout Bool,
                              completion: @escaping (iTermProcessInfo?) -> ()) {
        if let info = deepestForegroundJob(for: pid), info.name != nil {
            completion(info)
            return
        }
        if pid <= 0 {
            completion(nil)
            return
        }
        if haveBumped {
            needsUpdate = true
            return
        }
        haveBumped = true
        requestImmediateUpdate { [weak self] in
            completion(self?.deepestForegroundJob(for: pid))
        }
    }

    func processIsDirty(_ pid: pid_t) -> Bool {
        return dirtyPIDs.contains(pid)
    }

    func send(signal: Int32, toPID pid: Int32) {
        runner?.runRemoteCommand("kill -\(signal) \(pid)") { _, _ in }
    }
}

@MainActor
extension SSHProcessInfoProvider: SessionProcessInfoProvider {
    func cachedProcessInfoIfAvailable() -> iTermProcessInfo? {
        return cachedJob(for: rootPID, haveBumped: &haveBumped)
    }

    func fetchProcessInfoForCurrentJob(completion: @escaping (iTermProcessInfo?) -> ()) {
        fetchJob(for: rootPID, haveBumped: &haveBumped, completion: completion)
    }
}

/// A tmux pane's view of the host's processes. The provider answers for the connection's login
/// shell; this answers for one pane's pid, which must be registered with the provider so framer
/// reports its subtree.
@MainActor
final class SSHPaneProcessInfoProvider: NSObject, SessionProcessInfoProvider {
    private weak var provider: SSHProcessInfoProvider?
    let pid: pid_t
    private var haveBumped = false

    fileprivate init(provider: SSHProcessInfoProvider, pid: pid_t) {
        self.provider = provider
        self.pid = pid
        super.init()
    }

    func cachedProcessInfoIfAvailable() -> iTermProcessInfo? {
        return provider?.cachedJob(for: pid, haveBumped: &haveBumped)
    }

    func fetchProcessInfoForCurrentJob(completion: @escaping (iTermProcessInfo?) -> ()) {
        guard let provider else {
            completion(nil)
            return
        }
        provider.fetchJob(for: pid, haveBumped: &haveBumped, completion: completion)
    }
}

class NullProcessInfoProvider: ProcessInfoProvider, SessionProcessInfoProvider {
    func processInfo(for pid: pid_t) -> iTermProcessInfo? {
        return nil
    }

    func setNeedsUpdate(_ needsUpdate: Bool) {
    }

    func requestImmediateUpdate(completion: @escaping () -> ()) {
    }

    func updateSynchronously() {
    }

    func deepestForegroundJob(for pid: pid_t) -> iTermProcessInfo? {
        return nil
    }

    func displayForegroundJob(for pid: pid_t) -> iTermProcessInfo? {
        return nil
    }

    func register(trackedPID pid: pid_t) {
    }

    func unregister(trackedPID pid: pid_t) {
    }

    func processIsDirty(_ pid: pid_t) -> Bool {
        return false
    }

    func cachedProcessInfoIfAvailable() -> iTermProcessInfo? {
        return nil
    }

    func fetchProcessInfoForCurrentJob(completion: @escaping (iTermProcessInfo?) -> ()) {
        completion(nil)
    }

    func send(signal: Int32, toPID: Int32) {
    }
}

extension String {
    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }
}
