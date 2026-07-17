//
//  ProcessInfo.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/11/22.
//

import Foundation

@objc(iTermProcessInfo)
class iTermProcessInfo: NSObject {
    @objc let processID: pid_t
    @objc let parentProcessID: pid_t
    private(set) weak var collection: ProcessCollectionProvider?
    @objc let dataSource: ProcessDataSource
    private var childProcessIDs = IndexSet()
    private var buildingTreeString = false
    // Strong (not weak) on purpose: callers hold a deepest-job iTermProcessInfo past
    // the lifetime of the ProcessCollection that built it (PTYSession keeps one in
    // _lastProcessInfo, and the process cache swaps in a fresh collection on its work
    // queue). The ancestor infos are owned only by that collection, so a weak parent
    // would dangle to nil once the collection is freed and foregroundJobAncestorNames
    // would collapse to just the deepest job. To GlobalJobMonitor that looks like the
    // intermediate ancestors (e.g. "claude") exited, firing a spurious job-ended that
    // tears down the claudeCode workgroup. A strong parent keeps a retained leaf's
    // ancestor spine alive. There is no retain cycle: a parent references its children
    // only as pids (childProcessIDs), resolved through the weak `collection`, so there
    // is no parent -> child strong edge.
    @objc var parent: iTermProcessInfo?

    @objc(initWithPid:ppid:collection:dataSource:)
    init(processID: pid_t,
         parentProcessID: pid_t,
         collection: ProcessCollectionProvider,
         dataSource: ProcessDataSource) {
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.collection = collection
        self.dataSource = dataSource

        super.init()

        _deepestForegroundJob = WeakLazyOptional { [weak self] in
            guard let self else {
                return nil
            }
            var level = 0
            var visitedPIDs = Set<pid_t>()
            var cycle = false
            return self.deepestForegroundJob(level: &level, visited: &visitedPIDs, cycle: &cycle, depth: 0)
        }
    }

    override func isEqual(to object: Any?) -> Bool {
        guard let other = object as? iTermProcessInfo else {
            return false
        }
        return self == other
    }

    override var debugDescription: String {
        return "<iTermProcessInfo: pid=\(processID) name=\(name.debugDescriptionOrNil) children.count=\(childProcessIDs.count)>"
    }

    var recursiveDescription: String {
        return recursiveDescription(depth: 0)
    }

    private func recursiveDescription(depth: Int) -> String {
        if depth == 100 {
            return "Truncated at 100 levels"
        }
        let me = String(repeating: " ", count: depth) + String(processID) + " " + name.debugDescriptionOrNil
        if children.isEmpty {
            return me
        }
        let lines = [me] + children.map {
            $0.recursiveDescription(depth: depth + 1)
        }
        return lines.joined(separator: "\n")
    }

    static func ==(lhs: iTermProcessInfo, rhs: iTermProcessInfo) -> Bool {
        return (lhs.processID == rhs.processID &&
                lhs.name == rhs.name &&
                lhs.parentProcessID == rhs.parentProcessID)
    }

    @objc(treeStringWithIndent:)
    func tree(indent: String) -> String {
        guard !buildingTreeString else {
            return "<CYCLE DETECTED AT \(processID)>"
        }
        buildingTreeString = true
        let childArray = children
        var children = childArray.map {
            $0.tree(indent: indent + "    ")
        }.joined(separator: "\n")
        buildingTreeString = false
        if !childArray.isEmpty {
            children = "\n" + children
        }
        return "\(indent)pid=\(processID) name=\(name.debugDescriptionOrNil) fg=\(isForegroundJob)" + children
    }

    @objc var children: [iTermProcessInfo] {
        return childProcessIDs.compactMap {
            collection?.info(forProcessID: pid_t($0))
        }
    }

    @objc var sortedChildren: [iTermProcessInfo] {
        return children.sorted { lhs, rhs in
            lhs.processID < rhs.processID
        }
    }

    @objc(addChildWithProcessID:)
    func addChild(pid: pid_t) {
        childProcessIDs.insert(Int(pid))
    }

    @objc lazy var startTime: Date? = {
         dataSource.startTime(forProcess: processID)
    }()

    @objc var deepestForegroundJob: iTermProcessInfo? {
        return _deepestForegroundJob.value
    }

    private var _deepestForegroundJob: WeakLazyOptional<iTermProcessInfo>!

    func deepestForegroundJob(level levelInOut: inout Int,
                              visited: inout Set<pid_t>,
                              cycle: inout Bool,
                              depth: Int) -> iTermProcessInfo? {
        return deepestJob(matching: { $0.isForegroundJob },
                          level: &levelInOut,
                          visited: &visited,
                          cycle: &cycle,
                          depth: depth)
    }

    // Shared recursion behind deepestForegroundJob and its tty-attached variant: it
    // returns the deepest descendant (including self) for which `predicate` is true,
    // breaking ties toward the first one found. `predicate` decides what counts as a
    // candidate (e.g. "is a foreground job", optionally "and attached to the tty")
    // and is also where the filtered variant emits its per-candidate logging.
    private func deepestJob(matching predicate: (iTermProcessInfo) -> Bool,
                            level levelInOut: inout Int,
                            visited: inout Set<pid_t>,
                            cycle: inout Bool,
                            depth: Int) -> iTermProcessInfo? {
        if depth > 50 || visited.contains(processID) {
            cycle = true
            RLog("Failed to find deepest job at \(processID) because depth is \(depth) or found a cycle")
            return nil
        }
        visited.insert(processID)

        var bestLevel = levelInOut
        var bestProcessInfo: iTermProcessInfo? = nil
        if predicate(self) {
            bestProcessInfo = self
        }
        for child in children {
            var level = levelInOut + 1
            let candidate = child.deepestJob(matching: predicate,
                                             level: &level,
                                             visited: &visited,
                                             cycle: &cycle,
                                             depth: depth + 1)
            if cycle {
                return nil
            }
            if let candidate = candidate, (level > bestLevel || bestProcessInfo == nil) {
                bestLevel = level
                bestProcessInfo = candidate
            }
        }
        levelInOut = bestLevel
        return bestProcessInfo
    }

    // The rdevs of the terminal devices backing this process's stdin and stdout,
    // in fd order (fd 0 then fd 1), deduplicated. Empty when neither is a tty
    // (pipes, files, sockets, or non-terminal character devices like /dev/null).
    // Used to decide whether the process is attached to a given tty. Lazily
    // computed (at most two proc_pidfdinfo syscalls) and only consulted for
    // foreground-job candidates, so the common single-foreground-job case pays for
    // at most one process per cache generation. Order matters: controllingTTYRdev
    // prefers fd 0, so a process with stdin on the tty but stdout redirected
    // resolves to the tty.
    private lazy var stdioTTYRdevs: [dev_t] = {
        var result = [dev_t]()
        for fd in [Int32(0), Int32(1)] {
            let rdev = dataSource.ttyRdev(forFileDescriptor: fd, ofProcess: processID)
            if rdev != 0 && !result.contains(rdev) {
                result.append(rdev)
            }
        }
        return result
    }()

    @objc(stdioAttachedToTTYRdev:)
    func stdioAttached(toTTYRdev rdev: dev_t) -> Bool {
        guard rdev != 0 else {
            return false
        }
        return stdioTTYRdevs.contains(rdev)
    }

    // The rdev of the terminal on this process's stdin (preferred) or stdout, or 0
    // if neither is a tty (or its fds can't be read). fd 0 is preferred
    // deterministically so a process whose stdout is redirected doesn't resolve to
    // the redirected device.
    var controllingTTYRdev: dev_t {
        return stdioTTYRdevs.first ?? 0
    }

    // Identifies the session's controlling tty by searching this process and its
    // descendants for the first one whose stdin or stdout is a character device,
    // and returning that device's rdev (0 if none is found). We search rather than
    // just reading this process's own stdio because the session's root pid is
    // often `login`, which is owned by root: iTerm runs as the user and can't read
    // root-owned fds, so login's stdio looks empty. The user-owned shell just below
    // it holds the controlling tty on its stdio, so we find it there. The search is
    // breadth-limited because in the normal case the shell is an immediate child,
    // and the result is cached per session by the process cache so this runs at
    // most once per session.
    @objc var sessionControllingTTYRdev: dev_t {
        return firstStdioTTYRdev(depth: 0)
    }

    private func firstStdioTTYRdev(depth: Int) -> dev_t {
        let mine = controllingTTYRdev
        if mine != 0 {
            return mine
        }
        if depth >= 8 {
            return 0
        }
        for child in children {
            let rdev = child.firstStdioTTYRdev(depth: depth + 1)
            if rdev != 0 {
                return rdev
            }
        }
        return 0
    }

    // The deepest foreground job whose stdin or stdout is the given tty, or the
    // raw deepest foreground job when none qualifies (or rdev is 0). See the
    // protocol comment on ProcessInfoProvider for the rationale.
    @objc(deepestForegroundJobAttachedToTTYRdev:)
    func deepestForegroundJob(attachedToTTYRdev rdev: dev_t) -> iTermProcessInfo? {
        guard let raw = deepestForegroundJob else {
            DLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): no deepest foreground job under \(processID)")
            return nil
        }
        guard rdev != 0 else {
            DLog("deepestForegroundJobAttachedToTTYRdev: ttyRdev is 0 (unknown tty), using raw deepest \(raw.processID) (\(raw.name.debugDescriptionOrNil))")
            return raw
        }
        // Fast path: the deepest foreground job already owns the tty (an
        // interactive program, or the idle shell). This is the overwhelmingly
        // common case and costs just the two fd lookups on the leaf.
        if raw.stdioAttached(toTTYRdev: rdev) {
            DLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): raw deepest \(raw.processID) (\(raw.name.debugDescriptionOrNil)) is attached to the tty; using it")
            return raw
        }
        // The deepest foreground job is a helper that runs in the foreground
        // process group but isn't attached to the terminal. Search for the
        // deepest foreground job that is, and fall back to the raw deepest if
        // none qualifies.
        DLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): raw deepest \(raw.processID) (\(raw.name.debugDescriptionOrNil)) is NOT attached (its stdio rdevs are \(raw.stdioTTYRdevs)); searching descendants of \(processID) for an attached foreground job")
        let attachedForegroundJob: (iTermProcessInfo) -> Bool = { node in
            guard node.isForegroundJob else {
                return false
            }
            let attached = node.stdioAttached(toTTYRdev: rdev)
            DLog("deepestJob(attachedToTTYRdev:\(rdev)): foreground job \(node.processID) (\(node.name.debugDescriptionOrNil)) stdio rdevs=\(node.stdioTTYRdevs) attached=\(attached)")
            return attached
        }
        var level = 0
        var visited = Set<pid_t>()
        var cycle = false
        let filtered = deepestJob(matching: attachedForegroundJob,
                                  level: &level,
                                  visited: &visited,
                                  cycle: &cycle,
                                  depth: 0)
        if cycle {
            RLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): cycle while searching under \(processID); using raw deepest \(raw.processID) (\(raw.name.debugDescriptionOrNil))")
            return raw
        }
        if let filtered {
            DLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): using attached foreground job \(filtered.processID) (\(filtered.name.debugDescriptionOrNil))")
        } else {
            RLog("deepestForegroundJobAttachedToTTYRdev(\(rdev)): no attached foreground job found under \(processID); falling back to raw deepest \(raw.processID) (\(raw.name.debugDescriptionOrNil))")
        }
        return filtered ?? raw
    }

    var flattenedTree: [iTermProcessInfo] {
        [self] + children.flatMap {
            $0.flattenedTree
        }
    }

    @objc(descendantsSkippingLevels:)
    func descendants(skipping levels: Int) -> [iTermProcessInfo] {
        if levels < 0 {
            return flattenedTree
        }
        return children.flatMap {
            $0.descendants(skipping: levels - 1)
        }
    }

    // Returns true if prematurely stopped.
    @objc(enumerateTree:)
    @discardableResult
    func objcEnumerateTree(_ block: (iTermProcessInfo, UnsafeMutablePointer<ObjCBool>) -> ()) -> Bool {
        enumerateTree { info, stop in
            var temp = ObjCBool(false)
            block(info, &temp)
            stop = temp.boolValue
        }
    }

    func enumerateTree(_ block: (iTermProcessInfo, inout Bool) -> ()) -> Bool {
        var stop = false
        block(self, &stop)
        if stop {
            return true
        }
        for child in children {
            block(child, &stop)
            if stop {
                return true
            }
            if child.enumerateTree(block) {
                return true
            }
        }
        return false
    }

    lazy var executable: String? = {
        var execName = NSString()
        guard dataSource.commandLineArguments(forProcess: processID, execName: &execName) != nil else {
            return nil
        }
        return execName as String
    }()

    private struct ExpensiveValues {
        var isForegroundJob: Bool
        var commandLineValue: String?
        var argv0Value: String?
        var nameValue: String?

        init(processID: pid_t, parent: iTermProcessInfo?, dataSource: ProcessDataSource) {
            var fg = ObjCBool(false)
            nameValue = dataSource.nameOfProcess(withPid: processID, isForeground: &fg)
            DLog("Making expensive values for \(processID). fg=\(fg) parent.name=\(parent?.name ?? "(nil)")")
            if fg.boolValue || parent?.name == "login" || parent == nil {
                // Full command line with hacked command name
                let argv = dataSource.commandLineArguments(forProcess: processID, execName: nil)
                DLog("argv=\(argv?.joined(separator: " ") ?? "(nil)")")
                commandLineValue = argv?.joined(separator: " ")
                if let argv0 = argv?.first, !argv0.isEmpty {
                    argv0Value = argv0
                } else {
                    argv0Value = nil
                }
            }
            isForegroundJob = fg.boolValue
        }
    }

    private lazy var expensiveValues: ExpensiveValues = {
        ExpensiveValues(processID: processID,
                        parent: parent,
                        dataSource: dataSource)
    }()

    @objc var name: String? {
        return expensiveValues.nameValue
    }

    @objc var argv0: String? {
        return expensiveValues.argv0Value
    }

    @objc var commandLine: String? {
        return expensiveValues.commandLineValue
    }

    var _testValueForForegroundJob: Bool? = nil
    @objc var isForegroundJob: Bool {
        return _testValueForForegroundJob ?? expensiveValues.isForegroundJob
    }

    /// One canonical walk of the foreground-job ancestry, deepest first, stopping
    /// before the login shell (title starts with "-") or iTermServer. Returns each
    /// surviving ancestor as its pid paired with its lowercased title.
    /// `foregroundJobAncestorNames` and `foregroundJobAncestorChainPids` both derive
    /// from this single traversal, so a title and its pid are emitted together and
    /// stay aligned by construction. The diagnostics depend on that alignment to
    /// attribute a vanished ancestor name to the right pid, and it must hold even for
    /// an ancestor that survives via the last-known-title cache below (branch 2) or
    /// that stops the walk at a cached login/server boundary.
    ///
    /// Reading a process's name/argv0 can transiently fail for a process that is very
    /// much alive: `sysctl(KERN_PROC_PID)` can momentarily return an empty `p_comm`
    /// while the process table is churning (which busy children like `claude` do
    /// constantly). A missing intermediate ancestor here is indistinguishable from an
    /// exited one to `GlobalJobMonitor`, which turns the difference into a spurious
    /// "Job Ended" event (and, for the claude-code workgroup, a whole peer teardown).
    /// So when a name comes back empty we reuse the last-known title for that pid
    /// (validated by ppid to guard against pid reuse) instead of dropping it.
    /// Successfully-read titles are recorded to keep that cache warm.
    private func foregroundJobAncestorChain() -> [(pid: pid_t, name: String)] {
        var result = [(pid: pid_t, name: String)]()
        var current: iTermProcessInfo? = self
        while let info = current {
            let title = info.argv0 ?? info.name
            if let title, !title.isEmpty {
                ProcessNameCache.shared.record(pid: info.processID,
                                               ppid: info.parentProcessID,
                                               title: title)
                if title.hasPrefix("-") || title.hasPrefix("iTermServer") {
                    break
                }
                result.append((pid: info.processID, name: title.lowercased()))
                current = info.parent
            } else if let cached = ProcessNameCache.shared.lastKnownTitle(pid: info.processID,
                                                                          ppid: info.parentProcessID) {
                // The process is still in the tree (we reached it by walking parent
                // links) but its name read came back empty this cycle. Reuse the
                // last-known title so a transient process-info failure doesn't
                // masquerade as the job exiting. Log once per episode (not every
                // update while it keeps failing).
                if ProcessNameCache.shared.shouldLogAnomaly(pid: info.processID) {
                    RLog("foregroundJobAncestorNames: pid \(info.processID) (ppid \(info.parentProcessID)) read an empty name; reusing last-known title \"\(cached)\"")
                }
                if cached.hasPrefix("-") || cached.hasPrefix("iTermServer") {
                    break
                }
                result.append((pid: info.processID, name: cached.lowercased()))
                current = info.parent
            } else {
                // No fresh name and nothing cached. This is the case that can produce
                // a spurious "Job Ended", so capture precisely why the read failed.
                // Log (and run the diagnostic sysctl) once per episode, not every
                // update, so a persistently-nameless process can't spam the log.
                if ProcessNameCache.shared.shouldLogAnomaly(pid: info.processID) {
                    RLog("foregroundJobAncestorNames: pid \(info.processID) (ppid \(info.parentProcessID)) has no name and no cached title (\(iTermLSOF.nameFailureDiagnosis(forPid: info.processID) ?? "unknown")); dropping it from the ancestry")
                }
                current = info.parent
            }
        }
        return result
    }

    /// Lowercased argv0 (or name) values for this process and its ancestors, ordered
    /// from this process (deepest) toward the root, stopping before the login shell
    /// (argv0 starts with "-") or iTermServer. See `foregroundJobAncestorChain()` for
    /// the transient-name-failure handling.
    @objc var foregroundJobAncestorNames: [String] {
        return foregroundJobAncestorChain().map { $0.name }
    }

    // Diagnostics helper for the logForegroundJobAncestryDiagnostics advanced setting.
    // The pids of the nodes whose titles `foregroundJobAncestorNames` returns, in the
    // same order: index i here is the pid that produced name i there. Both derive from
    // the same `foregroundJobAncestorChain()` traversal, so that invariant holds even
    // for an ancestor that survived via the last-known-title cache. Lets the process
    // cache report exactly what became of the pid behind a vanished ancestor name.
    @objc var foregroundJobAncestorChainPids: [NSNumber] {
        return foregroundJobAncestorChain().map { NSNumber(value: $0.pid) }
    }

    // Diagnostics helper for the logForegroundJobAncestryDiagnostics advanced setting.
    // Verbose trace of the upward foreground-job ancestry walk starting at this node
    // (the deepest foreground job). For each node it records the state that decides
    // whether the node stays in the ancestry, cross-checks the `parent` pointer against
    // the collection's own lookup of the recorded ppid, and probes liveness of the ppid
    // with kill(_,0). Explains a spurious ancestry shrink (an intermediate ancestor
    // like the claude CLI dropping out for a single process-cache update, which fires a
    // bogus job-ended event and tears down the claudeCode workgroup even though the
    // process never exited). Deliberately does more work than the normal walk; the
    // process cache only calls it on the anomaly, and only while the setting is on.
    @objc func foregroundJobAncestryDiagnostic() -> String {
        var lines = [String]()
        var current: iTermProcessInfo? = self
        var depth = 0
        var visited = Set<pid_t>()
        while let info = current {
            if visited.contains(info.processID) {
                lines.append("  [\(depth)] pid=\(info.processID): CYCLE; stopping")
                break
            }
            visited.insert(info.processID)

            let title = info.argv0 ?? info.name
            let parentPtr = info.parent
            let ppidInCollection = info.collection?.info(forProcessID: info.parentProcessID)
            let ppidAlive = (kill(info.parentProcessID, 0) == 0)
            let startDesc = info.startTime.map { String($0.timeIntervalSince1970) } ?? "nil"

            let parentPtrDesc = parentPtr.map { "pid=\($0.processID) name=\($0.name.debugDescriptionOrNil)" } ?? "nil"
            let ppidLookupDesc: String
            if let c = ppidInCollection {
                ppidLookupDesc = "present(pid=\(c.processID) name=\(c.name.debugDescriptionOrNil) ppid=\(c.parentProcessID))"
            } else {
                ppidLookupDesc = "ABSENT"
            }

            lines.append("  [\(depth)] pid=\(info.processID) ppid=\(info.parentProcessID) name=\(info.name.debugDescriptionOrNil) argv0=\(info.argv0.debugDescriptionOrNil) fg=\(info.isForegroundJob) start=\(startDesc) title=\(title.debugDescriptionOrNil)")
            lines.append("         parentPtr=\(parentPtrDesc) | collection[ppid \(info.parentProcessID)]=\(ppidLookupDesc) | ppidAliveNow=\(ppidAlive)")

            guard let title, !title.isEmpty else {
                lines.append("         -> title empty; skipping this node (walk would drop it from the ancestry)")
                current = info.parent
                depth += 1
                continue
            }
            if title.hasPrefix("-") || title.hasPrefix("iTermServer") {
                lines.append("         -> STOP: login/server boundary (title starts with '-' or 'iTermServer')")
                break
            }
            current = info.parent
            if current == nil {
                lines.append("         -> STOP: parent pointer nil, ran off the top with NO login/server boundary  <-- BROKEN CHAIN (ppid \(info.parentProcessID) \(ppidInCollection == nil ? "absent from collection" : "present in collection but not linked as parent"), aliveNow=\(ppidAlive))")
            }
            depth += 1
            if depth > 64 {
                lines.append("  -> aborted at depth cap")
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}

// Remembers the most recently resolved title (argv0 or comm) for a pid so a single
// transient failure to read a live process's name doesn't erase it from
// `iTermProcessInfo.foregroundJobAncestorNames` (see that property for why an erased
// ancestor is harmful). Entries are keyed by pid and validated against ppid so a
// reused pid doesn't inherit an unrelated process's name. Only foreground-chain
// ancestors are ever recorded, so the map is naturally small; it is pruned to the
// live pid set once per process-cache update (see `-[iTermProcessCache reallyUpdate]`)
// so it stays bounded over a long-lived session.
@objc(iTermProcessNameCache)
class ProcessNameCache: NSObject {
    @objc static let shared = ProcessNameCache()

    private struct Entry {
        let ppid: pid_t
        let title: String
    }
    private var entriesByPID = [pid_t: Entry]()
    // Pids for which a name-read anomaly (empty name) has already been logged, so a
    // process whose name keeps reading empty across updates is logged once per
    // episode rather than every cycle. Cleared for a pid as soon as its name reads
    // normally again (see record) or when it dies (see prune).
    private var loggedAnomalyPIDs = Set<pid_t>()
    private let mutex = Mutex()

    // Records a freshly-resolved title for a live process. Overwrites any prior entry
    // and ends any open anomaly episode for the pid.
    func record(pid: pid_t, ppid: pid_t, title: String) {
        mutex.sync {
            entriesByPID[pid] = Entry(ppid: ppid, title: title)
            loggedAnomalyPIDs.remove(pid)
        }
    }

    // The last-known title for this pid, but only if the ppid still matches. A
    // different ppid means the pid was reused by an unrelated process, so the cached
    // name would be wrong; return nil and let the caller fall back.
    func lastKnownTitle(pid: pid_t, ppid: pid_t) -> String? {
        mutex.sync {
            guard let entry = entriesByPID[pid], entry.ppid == ppid else {
                return nil
            }
            return entry.title
        }
    }

    // Returns true the first time an anomaly is reported for this pid since its name
    // last read normally, and false on repeats. Callers gate logging (and any
    // diagnostic sysctl) on this so a persistently-nameless process can't spam.
    func shouldLogAnomaly(pid: pid_t) -> Bool {
        mutex.sync {
            loggedAnomalyPIDs.insert(pid).inserted
        }
    }

    // Drops entries for pids that are no longer alive to bound the maps' size.
    @objc(pruneToLivePids:)
    func prune(toLivePids livePids: [NSNumber]) {
        let live = Set(livePids.map { $0.int32Value })
        mutex.sync {
            entriesByPID = entriesByPID.filter { live.contains($0.key) }
            loggedAnomalyPIDs.formIntersection(live)
        }
    }

    // Test hook: forget everything.
    @objc func removeAll() {
        mutex.sync {
            entriesByPID.removeAll()
            loggedAnomalyPIDs.removeAll()
        }
    }
}
