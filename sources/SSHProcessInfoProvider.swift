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
    let command: String
    let fg: Bool
    let startTime: Date?

    init?(_ line: String) {
        let nsstring = line as NSString
        let whitespace = "\\s+"
        let number = "\\d+"
        let nonspace = "\\S+"
        let letters = "[\\p{Letter}]+"

        let pattern = ["^",
                       "\\s*",
                       "(",
                       number,  // pid [capture 1]
                       ")",
                       whitespace,
                       "(",
                       number,  // ppid [capture 2]
                       ")",
                       whitespace,
                       "(",
                       nonspace,  // stat [capture 3]
                       ")",
                       whitespace,
                       "(",
                       letters,  // day of week  [capture 4]
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
                       "(.*)"  // command  [capture 5]
        ].joined(separator: "")

        let ranges = line.captureGroups(regex: pattern)
        guard ranges.count == 6,
              let pid = pid_t(nsstring.substring(with: ranges[1])),
              let ppid = pid_t(nsstring.substring(with: ranges[2])) else {
            return nil
        }
        self.pid = pid
        self.ppid = ppid
        self.fg = nsstring.substring(with: ranges[3]).contains("+")

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

class SSHProcessInfoProvider {
    private let runner: SSHCommandRunning
    private var collection: ProcessCollectionProvider?
    private var closures = [() -> ()]()
    private var _needsUpdate = false
    private let rateLimit = iTermRateLimitedUpdate(
        name: "ssh-process-info-provider",
        minimumInterval: 1)
    private var dirtyPIDs = Set<pid_t>()
    private var cachedDeepestForegroundJob = [pid_t: iTermProcessInfo]()
    private var tracked = Set<pid_t>()
    private var rootInfo: iTermProcessInfo?
    private let rootPID: pid_t
    private var haveBumped = false
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
                self?.rateLimit.minimumInterval = 1
            }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil) { [weak self] _ in
                self?.rateLimit.minimumInterval = 5
            }
        needsUpdate = true
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // We must publish once a second for the status bar component to draw properly.
            if let cpuUtilization {
                cpuUtilizationPublisher.publish(NSNumber(value: cpuUtilization))
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
        runner.poll { [weak self] data in
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
        return (row.command as NSString).componentsInShellCommand()[0].lastPathComponent
    }

    func commandLineArguments(forProcess pid: pid_t,
                              execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
        guard let row = self.row(pid: pid) else {
            return nil
        }
        let args = (row.command as NSString).componentsInShellCommand() ?? []
        execName?.pointee = (args[0] as NSString).removingPrefix("-")! as NSString
        return args
    }

    func startTime(forProcess pid: pid_t) -> Date? {
        guard let row = self.row(pid: pid) else {
            return nil
        }
        return row.startTime
    }
}

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

    func register(trackedPID pid: pid_t) {
        runner.registerProcess(pid)
        tracked.insert(pid)
        needsUpdate = true
    }

    func unregister(trackedPID pid: pid_t) {
        runner.deregisterProcess(pid)
        tracked.remove(pid)
    }

    func processIsDirty(_ pid: pid_t) -> Bool {
        return dirtyPIDs.contains(pid)
    }

    func send(signal: Int32, toPID pid: Int32) {
        runner.runRemoteCommand("kill -\(signal) \(pid)") { _, _ in }
    }
}

extension SSHProcessInfoProvider: SessionProcessInfoProvider {
    func cachedProcessInfoIfAvailable() -> iTermProcessInfo? {
        if let info = deepestForegroundJob(for: rootPID) {
            return info
        }
        if !haveBumped {
            haveBumped = true
            needsUpdate = true
        }
        return nil
    }

    func fetchProcessInfoForCurrentJob(completion: @escaping (iTermProcessInfo?) -> ()) {
        let pid = rootPID
        if let info = deepestForegroundJob(for: pid), info.name != nil {
            completion(info)
            return
        }
        if rootPID <= 0 {
            completion(nil)
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
