// iTermWindowProjectsModel.swift
// iTerm2
//
// Data model and persistence for per-window project archives.

import Foundation
import AppKit

// MARK: - Archived Window

/// A single archived (closed) window belonging to a project.
struct iTermArchivedWindow: Codable {
    let id: UUID
    var name: String
    let timestamp: Date
    /// Binary-plist–encoded NSDictionary from PseudoTerminal.arrangementExcludingTmuxTabs.
    private let arrangementBase64: String

    init(id: UUID = UUID(),
         name: String,
         timestamp: Date = Date(),
         arrangement: [AnyHashable: Any]) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        let data = try? PropertyListSerialization.data(
            fromPropertyList: arrangement,
            format: .binary,
            options: 0)
        self.arrangementBase64 = data?.base64EncodedString() ?? ""
    }

    /// Decoded arrangement dict, or nil if data is corrupt.
    var arrangement: [AnyHashable: Any]? {
        guard !arrangementBase64.isEmpty,
              let data = Data(base64Encoded: arrangementBase64) else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil)) as? [AnyHashable: Any]
    }

    /// Returns true if this archived window contains live background server process IDs.
    var isOrphanedAndRunning: Bool {
        guard let arrangement = arrangement else { return false }
        return hasLiveServerPID(in: arrangement)
    }

    private func hasLiveServerPID(in value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            if let pidNum = dict["Server PID"] as? Int, pidNum > 0 {
                if kill(pid_t(pidNum), 0) == 0 {
                    return true
                }
            }
            for val in dict.values {
                if hasLiveServerPID(in: val) { return true }
            }
        } else if let array = value as? [Any] {
            for val in array {
                if hasLiveServerPID(in: val) { return true }
            }
        }
        return false
    }
}

// MARK: - Window Project Node

/// A named project that holds subprojects and archived windows.
final class iTermWindowProject: NSObject, Codable {
    var id: UUID
    var name: String
    var children: [iTermWindowProject]
    var windows: [iTermArchivedWindow]
    /// Updated whenever a window is archived to or restored from this project.
    var lastUsed: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.children = []
        self.windows = []
        self.lastUsed = Date()
    }

    enum CodingKeys: String, CodingKey { case id, name, children, windows, lastUsed }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,                 forKey: .id)
        name     = try c.decode(String.self,               forKey: .name)
        children = try c.decode([iTermWindowProject].self, forKey: .children)
        windows  = try c.decode([iTermArchivedWindow].self,forKey: .windows)
        lastUsed = (try? c.decode(Date.self,               forKey: .lastUsed)) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(name,     forKey: .name)
        try c.encode(children, forKey: .children)
        try c.encode(windows,  forKey: .windows)
        try c.encode(lastUsed, forKey: .lastUsed)
    }

    /// Total archived windows in this project and all descendants.
    var totalWindowCount: Int {
        windows.count + children.reduce(0) { $0 + $1.totalWindowCount }
    }
}

// MARK: - Model Singleton

@objc final class iTermWindowProjectsModel: NSObject {
    @objc static let shared = iTermWindowProjectsModel()
    @objc static let didChangeNotification = NSNotification.Name("iTermWindowProjectsModelDidChange")

    private(set) var rootProjects: [iTermWindowProject] = []

    func testOnlySetRootProjects(_ projects: [iTermWindowProject]) {
        self.rootProjects = projects
        save()
    }

    /// Persisted mapping: stable PseudoTerminal.terminalGuid → project UUID.
    /// Keyed by GUID (not window number) so an open associated window that is
    /// brought back by native window restoration after a quit/crash re-joins its
    /// project automatically — the restored window keeps its terminalGuid.
    private var liveAssociations: [String: UUID] = [:]

    /// Set true once applicationWillTerminate fires, so the per-window
    /// willClose notifications that fire during app teardown don't get treated
    /// as user-initiated closes (which would archive + drop associations).
    private var isTerminating = false

    /// terminalGuid for a window, or nil if it has none yet.
    private static func guid(for terminal: PseudoTerminal) -> String? {
        let g = terminal.terminalGuid
        return (g?.isEmpty == false) ? g : nil
    }

    private static var isTesting: Bool {
        return NSClassFromString("XCTestCase") != nil
    }

    private static var saveURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("iTerm2")
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        let filename = isTesting ? "WindowProjects_test.json" : "WindowProjects.json"
        return dir.appendingPathComponent(filename)
    }

    private static var thumbnailsDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let folderName = isTesting ? "WindowProjectThumbnails_test" : "WindowProjectThumbnails"
        let dir = support.appendingPathComponent("iTerm2").appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    @objc static func thumbnailURL(for uuid: UUID) -> URL {
        return thumbnailsDirectoryURL.appendingPathComponent("\(uuid.uuidString).png")
    }

    static func deleteThumbnail(for uuid: UUID) {
        try? FileManager.default.removeItem(at: thumbnailURL(for: uuid))
    }

    static func saveThumbnail(for windowNumber: Int, uuid: UUID) {
        guard windowNumber > 0 else { return }
        let windowID = CGWindowID(windowNumber)
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) else { return }
        
        let aspectW: CGFloat = 320
        let aspectH = cgImage.height == 0 ? 200 : aspectW * CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let size = NSSize(width: aspectW, height: min(aspectH, 240))
        
        guard let bitmapRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: Int(size.width),
                                                pixelsHigh: Int(size.height),
                                                bitsPerSample: 8,
                                                samplesPerPixel: 4,
                                                hasAlpha: true,
                                                isPlanar: false,
                                                colorSpaceName: .calibratedRGB,
                                                bytesPerRow: 0,
                                                bitsPerPixel: 0) else { return }
        
        bitmapRep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        nsImage.draw(in: NSRect(origin: .zero, size: size),
                     from: .zero,
                     operation: .copy,
                     fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: thumbnailURL(for: uuid))
        }
    }

    private override init() {
        super.init()
        load()
        loadAssociations()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil)
    }

    // MARK: Persistence

    private static var associationsURL: URL {
        let filename = isTesting ? "WindowProjectAssociations_test.json" : "WindowProjectAssociations.json"
        return saveURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    func save(postNotification: Bool = true) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(rootProjects) else { return }
        try? data.write(to: Self.saveURL)
        if postNotification {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Persists the guid→project association map (separate file so the projects
    /// JSON format is untouched).
    private func saveAssociations() {
        let stringMap = liveAssociations.mapValues { $0.uuidString }
        guard let data = try? JSONEncoder().encode(stringMap) else { return }
        try? data.write(to: Self.associationsURL)
    }

    private func loadAssociations() {
        guard let data = try? Data(contentsOf: Self.associationsURL),
              let stringMap = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        liveAssociations = stringMap.compactMapValues { UUID(uuidString: $0) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        rootProjects = (try? decoder.decode([iTermWindowProject].self, from: data)) ?? []
    }

    // MARK: Project CRUD

    @discardableResult
    func createProject(named name: String, parent: iTermWindowProject? = nil) -> iTermWindowProject {
        let p = iTermWindowProject(name: name)
        if let parent = parent {
            parent.children.append(p)
        } else {
            rootProjects.append(p)
        }
        save()
        return p
    }

    func renameProject(_ project: iTermWindowProject, to newName: String) {
        project.name = newName
        save()
    }

    private func deleteThumbnails(for project: iTermWindowProject) {
        for w in project.windows {
            Self.deleteThumbnail(for: w.id)
        }
        for sub in project.children {
            deleteThumbnails(for: sub)
        }
    }

    @discardableResult
    func deleteProject(_ project: iTermWindowProject) -> Bool {
        deleteThumbnails(for: project)
        if removeProject(project, from: &rootProjects) {
            save()
            return true
        }
        return false
    }

    private func removeProject(_ target: iTermWindowProject,
                                from list: inout [iTermWindowProject]) -> Bool {
        if let idx = list.firstIndex(where: { $0.id == target.id }) {
            list.remove(at: idx)
            return true
        }
        for p in list where removeProject(target, from: &p.children) { return true }
        return false
    }

    // MARK: Live Window Associations

    /// Marks `terminal` as belonging to `project` without closing it.
    /// When the window later closes, it will be auto-archived to this project.
    func associateWindow(_ terminal: PseudoTerminal, with project: iTermWindowProject) {
        guard let guid = Self.guid(for: terminal) else { return }
        liveAssociations[guid] = project.id
        saveAssociations()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Removes the project association from `terminal`, leaving the window open but untracked.
    func disassociateWindow(_ terminal: PseudoTerminal) {
        guard let guid = Self.guid(for: terminal),
              liveAssociations.removeValue(forKey: guid) != nil else { return }
        saveAssociations()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Returns the project `terminal` is currently associated with, or nil.
    func project(for terminal: PseudoTerminal) -> iTermWindowProject? {
        guard let guid = Self.guid(for: terminal),
              let pid = liveAssociations[guid] else { return nil }
        return project(id: pid)
    }

    /// Returns all currently open windows associated with `project`.
    func liveWindows(for project: iTermWindowProject) -> [PseudoTerminal] {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.filter { t in
            guard let guid = Self.guid(for: t) else { return false }
            return liveAssociations[guid] == project.id
        }
    }

    /// True if `project` has at least one open window associated with it.
    func hasLiveWindows(for project: iTermWindowProject) -> Bool {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.contains { t in
            guard let guid = Self.guid(for: t) else { return false }
            return liveAssociations[guid] == project.id
        }
    }

    /// Closes and archives every open window currently associated with `project`.
    func closeProject(_ project: iTermWindowProject, keepJobsRunning: Bool = false) {
        for terminal in liveWindows(for: project) {
            guard let wn = terminal.ptyWindow()?.windowNumber else { continue }
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
            let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
            let title = terminal.ptyWindow()?.title ?? "Window"
            let uuid = UUID()
            Self.saveThumbnail(for: wn, uuid: uuid)
            project.windows.append(iTermArchivedWindow(id: uuid, name: title, arrangement: arrangement))
            if let guid = Self.guid(for: terminal) { liveAssociations.removeValue(forKey: guid) }

            // Park live children so the thawed window can re-adopt them in-place
            // (see parkSessionsForReattachment). Must run before close().
            if keepJobsRunning {
                Self.parkSessionsForReattachment(terminal)
            }

            terminal.orphanJobsOnClose = keepJobsRunning
            terminal.close()
        }
        project.lastUsed = Date()
        saveAssociations()
        save()
    }

    /// Called when any NSWindow is about to close. For a *user-initiated* close
    /// of an associated window, archives a snapshot into its project (the
    /// "closed" state). During app termination this is a no-op: the association
    /// is preserved on disk and native window restoration brings the window back
    /// live on next launch (re-associated by guid) — archiving here would create
    /// a duplicate.
    @objc private func windowWillClose(_ note: Notification) {
        if isTerminating { return }
        guard let window = note.object as? NSWindow else { return }
        let wn = window.windowNumber
        let all = iTermController.sharedInstance().terminals() ?? []
        guard let terminal = all.first(where: { $0.ptyWindow()?.windowNumber == wn }),
              let guid = Self.guid(for: terminal) else { return }
        guard let projectID = liveAssociations[guid],
              let project = project(id: projectID) else { return }
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        let title = window.title.isEmpty ? "Window" : window.title
        let uuid = UUID()
        Self.saveThumbnail(for: wn, uuid: uuid)
        project.windows.append(iTermArchivedWindow(id: uuid, name: title, arrangement: arrangement))
        liveAssociations.removeValue(forKey: guid)
        saveAssociations()
        project.lastUsed = Date()
        save()
    }

    @objc private func applicationWillTerminate(_ note: Notification) {
        // Option A: open associated windows come back via native window
        // restoration and are re-associated by guid on next launch — do NOT
        // archive them here (that produced a live window + a stale archive
        // duplicate). Just mark terminating so the willClose notifications fired
        // during teardown don't archive/drop their associations.
        isTerminating = true
        saveAssociations()
    }

    // MARK: Window Archiving

    /// Saves `terminal`'s arrangement into `project` and optionally closes the window.
    /// Any existing live association is cleared.
    func archiveWindow(_ terminal: PseudoTerminal,
                       to project: iTermWindowProject,
                       andClose close: Bool,
                       keepJobsRunning: Bool = false) {
        let wn = terminal.ptyWindow()?.windowNumber ?? 0
        if let guid = Self.guid(for: terminal) {
            liveAssociations.removeValue(forKey: guid)
            saveAssociations()
        }
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        let title = terminal.ptyWindow()?.title ?? "Window"
        let uuid = UUID()
        Self.saveThumbnail(for: wn, uuid: uuid)
        let entry = iTermArchivedWindow(id: uuid, name: title, arrangement: arrangement)
        project.windows.append(entry)
        project.lastUsed = Date()
        save()
        
        if close && keepJobsRunning {
            Self.parkSessionsForReattachment(terminal)
        }

        if close {
            terminal.orphanJobsOnClose = keepJobsRunning
            terminal.close()
        }
    }

    // MARK: Freeze/Thaw diagnostics

    /// Parks each of `terminal`'s live multiserver children back onto their
    /// (shared) connection's unattachedChildren list so a thawed window can
    /// re-adopt the running process in-place — without closing the fd, tearing
    /// down the connection, or re-handshaking. Must be called while the sessions
    /// are still live and BEFORE `terminal.close()`. Gated by ITERM_WP_PARK so
    /// the pre-fix failure mode stays reproducible (set ITERM_WP_PARK=0).
    static func parkSessionsForReattachment(_ terminal: PseudoTerminal) {
        let park = (ProcessInfo.processInfo.environment["ITERM_WP_PARK"] ?? "1") != "0"
        guard let sessions = terminal.allSessions() as? [PTYSession] else { return }
        guard park else {
            Self.wpLog("FREEZE park: DISABLED (ITERM_WP_PARK=0). Process kept running but NOT parked — thaw is expected to fall back to a fresh shell.")
            return
        }
        for session in sessions {
            guard let task = session.shell else { continue }
            let pid = task.parkChildForReattachment()
            Self.wpLog("FREEZE park: session=\(session.guid) parkedPid=\(pid) tty=\(task.tty ?? "nil")")
        }
    }

    /// Appends a timestamped line to /tmp/iterm_wp.log and the system log so the
    /// freeze/thaw cycle can be inspected without a debugger.
    static func wpLog(_ message: String) {
        NSLog("[WindowProjects] %@", message)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/iterm_wp.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Collects every multiserver child PID referenced by `arrangement` (one per
    /// session/split pane), not just the first.
    static func allServerChildPIDs(in arrangement: [AnyHashable: Any]) -> [Int32] {
        var pids: [Int32] = []
        func walk(_ node: Any) {
            if let dict = node as? [AnyHashable: Any] {
                if let sd = dict["Server Dict"] as? [AnyHashable: Any],
                   let p = (sd["Child PID"] as? Int) ?? (sd["Child PID"] as? NSNumber)?.intValue {
                    pids.append(Int32(p))
                }
                for v in dict.values { walk(v) }
            } else if let arr = node as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(arrangement)
        return pids
    }

    /// Child PIDs owned by archived (detached) windows across all projects. The
    /// orphan-server adopter consults this at startup so it leaves these parked
    /// for on-demand project restore instead of pulling them into a generic
    /// recovered window. (ObjC bridges Set<Int> to NSSet<NSNumber>.)
    @objc func claimedMultiserverChildPIDs() -> Set<Int> {
        var result = Set<Int>()
        func walk(_ projects: [iTermWindowProject]) {
            for p in projects {
                for w in p.windows {
                    guard let arr = w.arrangement else { continue }
                    for pid in Self.allServerChildPIDs(in: arr) {
                        result.insert(Int(pid))
                    }
                }
                walk(p.children)
            }
        }
        walk(rootProjects)
        Self.wpLog("claimedMultiserverChildPIDs: \(result.sorted())")
        return result
    }

    /// Extracts (socket, childPid) from an arrangement's multiserver Server Dict.
    static func serverDict(in arrangement: [AnyHashable: Any]) -> (socket: Int32, childPid: Int32)? {
        func walk(_ node: Any) -> (Int32, Int32)? {
            if let dict = node as? [AnyHashable: Any] {
                if let sd = dict["Server Dict"] as? [AnyHashable: Any],
                   let s = (sd["Socket"] as? Int) ?? (sd["Socket"] as? NSNumber)?.intValue,
                   let p = (sd["Child PID"] as? Int) ?? (sd["Child PID"] as? NSNumber)?.intValue {
                    return (Int32(s), Int32(p))
                }
                for v in dict.values {
                    if let r = walk(v) { return r }
                }
            } else if let arr = node as? [Any] {
                for v in arr {
                    if let r = walk(v) { return r }
                }
            }
            return nil
        }
        return walk(arrangement)
    }

    /// Logs whether the orphaned child named in `arrangement` is currently
    /// present in its multiserver connection's unattachedChildren list. This is
    /// the precondition the native attach path requires; it is the single fact
    /// that distinguishes "will re-attach" from "will spawn a fresh shell".
    static func logUnattachedState(forArrangement arrangement: [AnyHashable: Any], phase: String) {
        guard let (socket, childPid) = serverDict(in: arrangement) else {
            wpLog("\(phase): arrangement has no multiserver Server Dict")
            return
        }
        var done = false
        var present = false
        var total = -1
        let thread = iTermThread<iTermMainThreadState>.main()
        let callback = thread.newCallback { (_: Any?, value: Any?) in
            if let result = value as? iTermResult<iTermMultiServerConnection> {
                result.handleObject({ connection in
                    let kids = (connection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                    total = kids.count
                    present = kids.contains { $0.pid == childPid }
                }, error: { _ in })
            }
            done = true
        }
        let bridged = callback as! iTermCallback<AnyObject, iTermMultiServerConnection>
        // createIfPossible:false returns the cached connection without
        // re-handshaking when it already exists (the in-process case), so this
        // observes — does not mutate — the live state.
        iTermMultiServerConnection.getForSocketNumber( socket, createIfPossible: false, callback: bridged)
        let limit = Date(timeIntervalSinceNow: 1.0)
        while !done && Date() < limit {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        wpLog("\(phase): socket=\(socket) childPid=\(childPid) unattachedCount=\(total) childPresent=\(present)")
    }

    /// After a window is restored, logs whether its session actually re-attached
    /// to the expected orphaned child (pid matches) or fell back to a brand-new
    /// shell (pid differs). This is the ground-truth success signal.
    static func logRestoredAttachment(_ term: PseudoTerminal, expectedFrom arrangement: [AnyHashable: Any], phase: String) {
        guard let (socket, childPid) = serverDict(in: arrangement) else { return }
        guard let session = term.allSessions()?.first as? PTYSession, let task = session.shell else {
            wpLog("\(phase): restored window has no session/shell")
            return
        }
        let actualPid = task.pid
        let reattached = (actualPid == childPid)
        wpLog("\(phase): socket=\(socket) expectedChildPid=\(childPid) restoredShellPid=\(actualPid) reattached=\(reattached)")
    }

    func removeWindow(_ window: iTermArchivedWindow, from project: iTermWindowProject) {
        project.windows.removeAll { $0.id == window.id }
        Self.deleteThumbnail(for: window.id)
        save()
    }

    // MARK: Restoration

    func restoreWindow(_ archived: iTermArchivedWindow) {
        guard let project = parentProject(of: archived) else { return }
        guard let arrangement = archived.arrangement else { return }
        
        let lionFullScreen = PseudoTerminal.arrangementIsLionFullScreen(arrangement)
        PseudoTerminal.performWhenWindowCreationIsSafe(forLionFullScreen: lionFullScreen) { [weak self] in
            guard let self = self else { return }
            Self.logUnattachedState(forArrangement: arrangement, phase: "THAW before restore")
            guard let term = PseudoTerminal(
                arrangement: arrangement,
                named: nil,
                forceOpeningHotKeyWindow: false) else { return }

            iTermController.sharedInstance().addTerminalWindow(term)
            Self.logRestoredAttachment(term, expectedFrom: arrangement, phase: "THAW after restore")

            // Remove the archived window from the project's list so it cannot be restored twice!
            project.windows.removeAll { $0.id == archived.id }
            Self.deleteThumbnail(for: archived.id)

            // Associate the newly opened window with the project!
            if let guid = Self.guid(for: term) {
                self.liveAssociations[guid] = project.id
                self.saveAssociations()
            }

            project.lastUsed = Date()
            self.save()
        }
    }

    func restoreAllWindows(in project: iTermWindowProject) {
        project.lastUsed = Date()
        let windowsToRestore = project.windows
        for archived in windowsToRestore {
            guard let arrangement = archived.arrangement else { continue }
            let lionFullScreen = PseudoTerminal.arrangementIsLionFullScreen(arrangement)
            PseudoTerminal.performWhenWindowCreationIsSafe(forLionFullScreen: lionFullScreen) { [weak self] in
                guard let self = self else { return }
                Self.logUnattachedState(forArrangement: arrangement, phase: "THAW before restore")
                guard let term = PseudoTerminal(
                    arrangement: arrangement,
                    named: nil,
                    forceOpeningHotKeyWindow: false) else { return }

                iTermController.sharedInstance().addTerminalWindow(term)
                Self.logRestoredAttachment(term, expectedFrom: arrangement, phase: "THAW after restore")

                if let guid = Self.guid(for: term) {
                    self.liveAssociations[guid] = project.id
                    self.saveAssociations()
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
                }
            }
            Self.deleteThumbnail(for: archived.id)
        }
        project.windows.removeAll()
        save()
    }

    // MARK: Lookup Helpers

    func project(id: UUID) -> iTermWindowProject? {
        findProject(id: id, in: rootProjects)
    }

    private func findProject(id: UUID, in list: [iTermWindowProject]) -> iTermWindowProject? {
        for p in list {
            if p.id == id { return p }
            if let found = findProject(id: id, in: p.children) { return found }
        }
        return nil
    }

    func parentProject(of archived: iTermArchivedWindow) -> iTermWindowProject? {
        findParent(of: archived, in: rootProjects)
    }

    private func findParent(of archived: iTermArchivedWindow,
                             in projects: [iTermWindowProject]) -> iTermWindowProject? {
        for p in projects {
            if p.windows.contains(where: { $0.id == archived.id }) { return p }
            if let found = findParent(of: archived, in: p.children) { return found }
        }
        return nil
    }

    /// Finds a specific archived window by UUID anywhere in the tree.
    func archivedWindow(id: UUID) -> (window: iTermArchivedWindow, project: iTermWindowProject)? {
        findArchivedWindow(id: id, in: rootProjects)
    }

    private func findArchivedWindow(id: UUID,
                                    in projects: [iTermWindowProject]
    ) -> (window: iTermArchivedWindow, project: iTermWindowProject)? {
        for p in projects {
            if let w = p.windows.first(where: { $0.id == id }) { return (w, p) }
            if let found = findArchivedWindow(id: id, in: p.children) { return found }
        }
        return nil
    }
}

@objc public final class iTermWindowProjectsPathfinder: NSObject {

    /// Dumps, for daemon sockets 1...10, the cached/established multiserver
    /// connection state and any unattached (orphaned, adoptable) children. This
    /// is the same precondition the native session-restore attach path depends
    /// on, surfaced for manual inspection.
    private class func dumpConnectionState() -> String {
        var log = ""
        func line(_ s: String) {
            log += s + "\n"
            NSLog("[WindowProjects-Pathfinder] %@", s)
        }
        let thread = iTermThread<iTermMainThreadState>.main()
        for socketNumber in 1...10 {
            var done = false
            var summary = "socket \(socketNumber): <no connection>"
            let callback = thread.newCallback { (_: Any?, value: Any?) in
                if let result = value as? iTermResult<iTermMultiServerConnection> {
                    result.handleObject({ connection in
                        let kids = (connection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                        let pids = kids.map { "\($0.pid)(fd \($0.fd))" }.joined(separator: ", ")
                        summary = "socket \(socketNumber): serverPid=\(connection.pid) unattachedChildren=[\(pids)]"
                    }, error: { _ in })
                }
                done = true
            }
            let bridged = callback as! iTermCallback<AnyObject, iTermMultiServerConnection>
            // createIfPossible:false: observe the cached connection without
            // re-handshaking (so we don't perturb live sessions on the daemon).
            iTermMultiServerConnection.getForSocketNumber( Int32(socketNumber),
                                                     createIfPossible: false,
                                                     callback: bridged)
            let limit = Date(timeIntervalSinceNow: 0.5)
            while !done && Date() < limit {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            line(summary)
        }
        return log
    }

    @objc public class func tryManualAdoption(on session: PTYSession) -> String {
        var log = "--- Pathfinder: multiserver connection state ---\n"
        log += "Target session TTY: \(session.tty ?? "nil"), shell pid: \(session.shell?.pid ?? -1)\n\n"
        log += dumpConnectionState()
        try? log.write(toFile: "/tmp/iterm_wp_pathfinder.log", atomically: true, encoding: .utf8)
        return log
    }

    @objc public class func runDiagnostics(on terminal: PseudoTerminal) -> String {
        var log = "--- Pathfinder: multiserver connection state ---\n"
        if let session = terminal.currentSession() {
            log += "Current session TTY: \(session.tty ?? "nil"), shell pid: \(session.shell?.pid ?? -1)\n\n"
        }
        log += dumpConnectionState()
        try? log.write(toFile: "/tmp/iterm_wp_pathfinder.log", atomically: true, encoding: .utf8)
        return log
    }
}
