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

    /// Runtime-only mapping: NSWindow.windowNumber → project UUID.
    /// Not persisted — live associations reset when the app restarts.
    private var liveAssociations: [Int: UUID] = [:]

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
        guard let wn = terminal.ptyWindow()?.windowNumber, wn > 0 else { return }
        liveAssociations[wn] = project.id
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Removes the project association from `terminal`, leaving the window open but untracked.
    func disassociateWindow(_ terminal: PseudoTerminal) {
        guard let wn = terminal.ptyWindow()?.windowNumber, wn > 0,
              liveAssociations.removeValue(forKey: wn) != nil else { return }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Returns the project `terminal` is currently associated with, or nil.
    func project(for terminal: PseudoTerminal) -> iTermWindowProject? {
        guard let wn = terminal.ptyWindow()?.windowNumber, wn > 0,
              let pid = liveAssociations[wn] else { return nil }
        return project(id: pid)
    }

    /// Returns all currently open windows associated with `project`.
    func liveWindows(for project: iTermWindowProject) -> [PseudoTerminal] {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.filter { t in
            guard let wn = t.ptyWindow()?.windowNumber, wn > 0 else { return false }
            return liveAssociations[wn] == project.id
        }
    }

    /// True if `project` has at least one open window associated with it.
    func hasLiveWindows(for project: iTermWindowProject) -> Bool {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.contains { t in
            guard let wn = t.ptyWindow()?.windowNumber, wn > 0 else { return false }
            return liveAssociations[wn] == project.id
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
            liveAssociations.removeValue(forKey: wn)
            
            // If we are freezing and keeping jobs running, cleanly release the client-side socket connections
            if keepJobsRunning {
                if let sessions = terminal.allSessions() as? [PTYSession] {
                    for session in sessions {
                        if let task = session.shell {
                            print("[Freeze-Project] Natively closing file descriptors and deregistering task from TaskNotifier...")
                            task.closeFileDescriptorAndDeregisterIfPossible()
                        }
                    }
                }
            }
            
            terminal.orphanJobsOnClose = keepJobsRunning
            terminal.close()
        }
        project.lastUsed = Date()
        save()
    }

    /// Called when any NSWindow is about to close. Auto-archives the window if it has a
    /// live association, so the project retains the arrangement for later restoration.
    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        let wn = window.windowNumber
        guard let projectID = liveAssociations[wn],
              let project = project(id: projectID) else {
            liveAssociations.removeValue(forKey: wn)
            return
        }
        let all = iTermController.sharedInstance().terminals() ?? []
        guard let terminal = all.first(where: { $0.ptyWindow()?.windowNumber == wn }) else {
            liveAssociations.removeValue(forKey: wn)
            return
        }
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        let title = window.title.isEmpty ? "Window" : window.title
        let uuid = UUID()
        Self.saveThumbnail(for: wn, uuid: uuid)
        project.windows.append(iTermArchivedWindow(id: uuid, name: title, arrangement: arrangement))
        liveAssociations.removeValue(forKey: wn)
        project.lastUsed = Date()
        save()
    }

    @objc private func applicationWillTerminate(_ note: Notification) {
        guard let all = iTermController.sharedInstance().terminals() else { return }
        for terminal in all {
            guard let wn = terminal.ptyWindow()?.windowNumber, wn > 0,
                  let projectID = liveAssociations[wn],
                  let project = project(id: projectID) else { continue }
            
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
            let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
            
            let title = terminal.ptyWindow()?.title ?? "Window"
            let uuid = UUID()
            project.windows.append(iTermArchivedWindow(id: uuid, name: title, arrangement: arrangement))
            liveAssociations.removeValue(forKey: wn)
        }
        save(postNotification: false)
    }

    // MARK: Window Archiving

    /// Saves `terminal`'s arrangement into `project` and optionally closes the window.
    /// Any existing live association is cleared.
    func archiveWindow(_ terminal: PseudoTerminal,
                       to project: iTermWindowProject,
                       andClose close: Bool,
                       keepJobsRunning: Bool = false) {
        let wn = terminal.ptyWindow()?.windowNumber ?? 0
        if wn > 0 {
            liveAssociations.removeValue(forKey: wn)
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
        
        // If we are freezing and keeping jobs running, cleanly release and purge the client-side socket connections
        if close && keepJobsRunning {
            if let sessions = terminal.allSessions() as? [PTYSession] {
                for session in sessions {
                    if let task = session.shell {
                        print("[Freeze] Natively closing file descriptors and deregistering task from TaskNotifier...")
                        task.closeFileDescriptorAndDeregisterIfPossible()
                    }
                    
                    if let task = session.shell,
                       let restorationID = task.sessionRestorationIdentifier as? [AnyHashable: Any],
                       let socketNumber = (restorationID["Socket"] as? Int) ?? (restorationID["Socket"] as? NSNumber)?.intValue {
                        
                        var callbackExecuted = false
                        let thread = iTermThread<iTermMainThreadState>.main()
                        let callback = thread.newCallback { (_, valueObj) in
                            if let result = valueObj as? iTermResult<iTermMultiServerConnection> {
                                result.handleObject({ connection in
                                    print("[Freeze] Purging and releasing client socket connection for Socket \(socketNumber)...")
                                    // Close the client's internal sockets
                                    if let threadObj = (connection as NSObject).value(forKey: "thread") as? iTermThread<AnyObject> {
                                        threadObj.dispatchSync { perConnectionStateObj in
                                            if let state = perConnectionStateObj as? NSObject,
                                               let client = state.value(forKey: "client") as? iTermFileDescriptorMultiClient {
                                                if let clientThread = (client as NSObject).value(forKey: "thread") as? iTermThread<AnyObject> {
                                                    clientThread.dispatchSync { clientStateObj in
                                                        if let clientState = clientStateObj as? NSObject,
                                                           let readFD = clientState.value(forKey: "readFD") as? Int32,
                                                           let writeFD = clientState.value(forKey: "writeFD") as? Int32 {
                                                            clientState.setValue(-1, forKey: "readFD")
                                                            clientState.setValue(-1, forKey: "writeFD")
                                                            if readFD >= 0 { Darwin.close(readFD) }
                                                            if writeFD >= 0 { Darwin.close(writeFD) }
                                                        }
                                                    }
                                                }
                                                connection.fileDescriptorMultiClientDidClose(client)
                                            }
                                        }
                                    }
                                }, error: { _ in })
                            }
                            callbackExecuted = true
                        }
                        let bridgedCallback = callback as! iTermCallback<AnyObject, iTermMultiServerConnection>
                        iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: false, callback: bridgedCallback)
                        
                        // Spin run loop briefly to execute the callback synchronously
                        let limitDate = Date(timeIntervalSinceNow: 0.3)
                        while !callbackExecuted && Date() < limitDate {
                            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                        }
                    }
                }
            }
        }
        
        if close {
            terminal.orphanJobsOnClose = keepJobsRunning
            terminal.close()
        }
    }

    func removeWindow(_ window: iTermArchivedWindow, from project: iTermWindowProject) {
        project.windows.removeAll { $0.id == window.id }
        Self.deleteThumbnail(for: window.id)
        save()
    }

    // MARK: Restoration

    private class func purgeCachedConnection(for arrangement: [AnyHashable: Any]) {
        // Unpack Tabs and Root to find the Session dictionary
        func findSessionDict(in node: [AnyHashable: Any]) -> [AnyHashable: Any]? {
            if node["Server Dict"] != nil {
                return node
            }
            if let session = node["Session"] as? [AnyHashable: Any] {
                return session
            }
            if let subviews = node["Subviews"] as? [Any] {
                for sub in subviews {
                    if let subDict = sub as? [AnyHashable: Any],
                       let found = findSessionDict(in: subDict) {
                        return found
                    }
                }
            }
            return nil
        }
        
        guard let tabs = arrangement["Tabs"] as? [Any],
              let firstTab = tabs.first as? [AnyHashable: Any],
              let root = firstTab["Root"] as? [AnyHashable: Any],
              let firstSessionDict = findSessionDict(in: root),
              let serverDict = firstSessionDict["Server Dict"] as? [AnyHashable: Any],
              let socketNumber = (serverDict["Socket"] as? Int) ?? (serverDict["Socket"] as? NSNumber)?.intValue,
              let childPid = (serverDict["Child PID"] as? Int) ?? (serverDict["Child PID"] as? NSNumber)?.intValue else {
            return
        }
        
        print("[Restoration] Found saved multiserver Socket \(socketNumber), Child PID \(childPid) in arrangement. Purging cached connection to force fresh re-attachment...")
        
        // Fetch and purge cached connection
        var callbackExecuted = false
        var purgedConnection: iTermMultiServerConnection? = nil
        let thread = iTermThread<iTermMainThreadState>.main()
        let callback: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
            guard let result = valueObj as? iTermResult<iTermMultiServerConnection> else {
                callbackExecuted = true
                return
            }
            result.handleObject({ connection in
                purgedConnection = connection
                if let threadObj = (connection as NSObject).value(forKey: "thread") as? iTermThread<AnyObject> {
                    threadObj.dispatchSync { perConnectionStateObj in
                        if let state = perConnectionStateObj as? NSObject,
                           let client = state.value(forKey: "client") as? iTermFileDescriptorMultiClient {
                            connection.fileDescriptorMultiClientDidClose(client)
                        }
                    }
                }
                callbackExecuted = true
            }, error: { _ in
                callbackExecuted = true
            })
        }
        
        let bridgedCallback = callback as! iTermCallback<AnyObject, iTermMultiServerConnection>
        iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: false, callback: bridgedCallback)
        
        // Spin the run loop to allow synchronous main-thread purge to complete
        let limitDate = Date(timeIntervalSinceNow: 1.0)
        while !callbackExecuted && Date() < limitDate {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        
        // If we successfully purged the connection, execute our 5-attempt retry connect loop to pre-establish the fresh connection!
        if purgedConnection != nil {
            var connectionFound = false
            var retryCount = 1
            let maxRetries = 5
            
            while retryCount <= maxRetries {
                var callback2Executed = false
                
                let callback2: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
                    guard let result = valueObj as? iTermResult<iTermMultiServerConnection> else {
                        callback2Executed = true
                        return
                    }
                    result.handleObject({ freshConnection in
                        let unattached = (freshConnection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                        if unattached.contains(where: { $0.pid == Int32(childPid) }) {
                            connectionFound = true
                        }
                        callback2Executed = true
                    }, error: { _ in
                        callback2Executed = true
                    })
                }
                
                let bridgedCallback2 = callback2 as! iTermCallback<AnyObject, iTermMultiServerConnection>
                iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: true, callback: bridgedCallback2)
                
                let limitDate2 = Date(timeIntervalSinceNow: 1.5)
                while !callback2Executed && Date() < limitDate2 {
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
                }
                
                if connectionFound {
                    print("[Restoration] Successfully pre-established fresh multiserver connection to Socket \(socketNumber) and verified Child PID \(childPid) inside unattachedChildren on attempt \(retryCount)!")
                    break
                }
                
                retryCount += 1
                if retryCount <= maxRetries {
                    let pauseDate = Date(timeIntervalSinceNow: 0.4)
                    while Date() < pauseDate {
                        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
                    }
                }
            }
        }
    }

    func restoreWindow(_ archived: iTermArchivedWindow) {
        guard let project = parentProject(of: archived) else { return }
        guard let arrangement = archived.arrangement else { return }
        
        let lionFullScreen = PseudoTerminal.arrangementIsLionFullScreen(arrangement)
        PseudoTerminal.performWhenWindowCreationIsSafe(forLionFullScreen: lionFullScreen) { [weak self] in
            guard let self = self else { return }
            Self.purgeCachedConnection(for: arrangement)
            guard let term = PseudoTerminal(
                arrangement: arrangement,
                named: nil,
                forceOpeningHotKeyWindow: false) else { return }
            
            iTermController.sharedInstance().addTerminalWindow(term)
            
            // Remove the archived window from the project's list so it cannot be restored twice!
            project.windows.removeAll { $0.id == archived.id }
            Self.deleteThumbnail(for: archived.id)
            
            // Associate the newly opened window with the project!
            if let wn = term.ptyWindow()?.windowNumber, wn > 0 {
                self.liveAssociations[wn] = project.id
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
                Self.purgeCachedConnection(for: arrangement)
                guard let term = PseudoTerminal(
                    arrangement: arrangement,
                    named: nil,
                    forceOpeningHotKeyWindow: false) else { return }
                
                iTermController.sharedInstance().addTerminalWindow(term)
                
                if let wn = term.ptyWindow()?.windowNumber, wn > 0 {
                    self.liveAssociations[wn] = project.id
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
    
    @objc public class func tryManualAdoption(on session: PTYSession) -> String {
        var log = "--- EXPERIMENT A: NATIVE HOT-SWAP ATTACHMENT ---\n"
        func logInfo(_ message: String) {
            log += message + "\n"
            print("[Pathfinder-A] " + message)
        }
        
        logInfo("Target Session TTY: \(session.tty ?? "nil")")
        
        // Purge the cached connections first to prevent ECONNREFUSED/stale connection reuse!
        for socketNumber in 1...10 {
            var callbackExecuted = false
            let thread = iTermThread<iTermMainThreadState>.main()
            let callback1: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
                if let result = valueObj as? iTermResult<iTermMultiServerConnection> {
                    result.handleObject({ connection in
                        logInfo("🧹 Socket \(socketNumber): Purging cached connection registry...")
                        
                        // Close the client's internal sockets
                        if let threadObj = (connection as NSObject).value(forKey: "thread") as? iTermThread<AnyObject> {
                            threadObj.dispatchSync { perConnectionStateObj in
                                if let state = perConnectionStateObj as? NSObject,
                                   let client = state.value(forKey: "client") as? iTermFileDescriptorMultiClient {
                                    if let clientThread = (client as NSObject).value(forKey: "thread") as? iTermThread<AnyObject> {
                                        clientThread.dispatchSync { clientStateObj in
                                            if let clientState = clientStateObj as? NSObject,
                                               let readFD = clientState.value(forKey: "readFD") as? Int32,
                                               let writeFD = clientState.value(forKey: "writeFD") as? Int32 {
                                                clientState.setValue(-1, forKey: "readFD")
                                                clientState.setValue(-1, forKey: "writeFD")
                                                if readFD >= 0 { close(readFD) }
                                                if writeFD >= 0 { close(writeFD) }
                                            }
                                        }
                                    }
                                    connection.fileDescriptorMultiClientDidClose(client)
                                }
                            }
                        }
                    }, error: { _ in })
                }
                callbackExecuted = true
            }
            let bridgedCallback1 = callback1 as! iTermCallback<AnyObject, iTermMultiServerConnection>
            iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: false, callback: bridgedCallback1)
            
            let limitDate = Date(timeIntervalSinceNow: 0.5)
            while !callbackExecuted && Date() < limitDate {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
        }
        
        // Now let's find the live background sleep process and orphaned Socket on disk!
        var targetSocket: Int32 = -1
        var targetPID: Int32 = -1
        
        for socketNumber in 1...10 {
            var callbackExecuted = false
            let thread = iTermThread<iTermMainThreadState>.main()
            let callback2: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
                if let result = valueObj as? iTermResult<iTermMultiServerConnection> {
                    result.handleObject({ connection in
                        let unattached = (connection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                        logInfo("🔍 Socket \(socketNumber): Found \(unattached.count) unattached children.")
                        for child in unattached {
                            if child.pid > 0 {
                                targetSocket = Int32(socketNumber)
                                targetPID = child.pid
                                logInfo("   👉 Found background candidate PID: \(child.pid), TTY: \(child.tty ?? "nil")")
                            }
                        }
                    }, error: { _ in })
                }
                callbackExecuted = true
            }
            let bridgedCallback2 = callback2 as! iTermCallback<AnyObject, iTermMultiServerConnection>
            iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: true, callback: bridgedCallback2)
            
            let limitDate = Date(timeIntervalSinceNow: 1.0)
            while !callbackExecuted && Date() < limitDate {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            
            if targetSocket != -1 {
                break
            }
        }
        
        if targetSocket == -1 || targetPID == -1 {
            logInfo("❌ Failed to find any active orphaned children on sockets 1-10!")
            try? log.write(toFile: "/tmp/iterm_projects_log.txt", atomically: true, encoding: .utf8)
            return log
        }
        
        logInfo("🎯 Targeted Candidate: Socket \(targetSocket), PID \(targetPID)")
        
        // Execute Native tryToAttachToMultiserver in-place hot-swap!
        let serverDict: [AnyHashable: Any] = [
            "Socket": targetSocket,
            "Child PID": targetPID,
            "Type": "multiserver",
            "Version": 1
        ]
        
        if let task = session.shell {
            logInfo("🔄 Executing tryToAttachToMultiserver with Restoration Dict...")
            let results = task.tryToAttachToMultiserver(withRestorationIdentifier: serverDict)
            logInfo("   ✅ In-Place Attach Results: \(results)")
            if results.rawValue != 0 {
                logInfo("🎉 SUCCESS: Session has been natively re-attached to background PID \(targetPID) in-place!")
            } else {
                logInfo("❌ Failed to attach natively.")
            }
        } else {
            logInfo("❌ Target session has no active shell task!")
        }
        
        log += "--- EXPLORATION COMPLETE ---"
        try? log.write(toFile: "/tmp/iterm_projects_log.txt", atomically: true, encoding: .utf8)
        return log
    }

    @objc public class func runDiagnostics(on terminal: PseudoTerminal) -> String {
        var log = "--- EXPERIMENT B: SURGICAL RAW FILE DESCRIPTOR SWAP ---\n"
        func logInfo(_ message: String) {
            log += message + "\n"
            print("[Pathfinder-B] " + message)
        }
        
        guard let session = terminal.currentSession() else {
            return "❌ No active session found on terminal"
        }
        
        logInfo("Target Session TTY: \(session.tty ?? "nil")")
        
        // Scan and find the target socket & PID of the orphan
        var targetSocket: Int32 = -1
        var targetPID: Int32 = -1
        
        for socketNumber in 1...10 {
            var callbackExecuted = false
            let thread = iTermThread<iTermMainThreadState>.main()
            let callback2: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
                if let result = valueObj as? iTermResult<iTermMultiServerConnection> {
                    result.handleObject({ connection in
                        let unattached = (connection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                        for child in unattached {
                            if child.pid > 0 {
                                targetSocket = Int32(socketNumber)
                                targetPID = child.pid
                            }
                        }
                    }, error: { _ in })
                }
                callbackExecuted = true
            }
            let bridgedCallback2 = callback2 as! iTermCallback<AnyObject, iTermMultiServerConnection>
            iTermMultiServerConnection.getForSocketNumber(Int32(socketNumber), createIfPossible: true, callback: bridgedCallback2)
            
            let limitDate = Date(timeIntervalSinceNow: 1.0)
            while !callbackExecuted && Date() < limitDate {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            if targetSocket != -1 {
                break
            }
        }
        
        if targetSocket == -1 || targetPID == -1 {
            logInfo("❌ Failed to find any active orphaned children on sockets 1-10!")
            try? log.write(toFile: "/tmp/iterm_projects_log.txt", atomically: true, encoding: .utf8)
            return log
        }
        
        logInfo("🎯 Targeted Candidate: Socket \(targetSocket), PID \(targetPID)")
        
        // Establish Connection and extract raw FD
        var targetChild: iTermFileDescriptorMultiClientChild? = nil
        var callbackExecuted = false
        let thread = iTermThread<iTermMainThreadState>.main()
        let callback3: iTermCallback<iTermMainThreadState, AnyObject> = thread.newCallback { (stateObj, valueObj) in
            if let result = valueObj as? iTermResult<iTermMultiServerConnection> {
                result.handleObject({ connection in
                    let unattached = (connection.unattachedChildren as? [iTermFileDescriptorMultiClientChild]) ?? []
                    for child in unattached {
                        if child.pid == targetPID {
                            targetChild = child
                        }
                    }
                }, error: { _ in })
            }
            callbackExecuted = true
        }
        let bridgedCallback3 = callback3 as! iTermCallback<AnyObject, iTermMultiServerConnection>
        iTermMultiServerConnection.getForSocketNumber(targetSocket, createIfPossible: true, callback: bridgedCallback3)
        
        let limitDate = Date(timeIntervalSinceNow: 1.0)
        while !callbackExecuted && Date() < limitDate {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        
        guard let child = targetChild else {
            logInfo("❌ Failed to connect and retrieve the child object.")
            try? log.write(toFile: "/tmp/iterm_projects_log.txt", atomically: true, encoding: .utf8)
            return log
        }
        
        let rawFD = child.fd
        logInfo("✅ Natively extracted raw TTY master FD: \(rawFD)")
        
        if let task = session.shell {
            logInfo("💉 Surgically injecting raw FD \(rawFD) inside Task's jobManager...")
            
            // Swap jobManager types first to MultiServer
            task.setJobManagerType(iTermGeneralServerConnectionType.multi)
            
            // Inject the new fd
            task.setValue(rawFD, forKey: "fd")
            
            // Update the tty path
            let ttyPath = child.tty
            task.setValue(ttyPath as NSString, forKey: "tty")
            
            // Signal TaskNotifier to rebuild its file descriptors
            TaskNotifier.sharedInstance().unblock()
            
            logInfo("🎉 SUCCESS: Surgically injected raw file descriptor! Task is now listening on FD \(rawFD).")
        } else {
            logInfo("❌ Target session has no active shell task!")
        }
        
        log += "--- EXPLORATION COMPLETE ---"
        try? log.write(toFile: "/tmp/iterm_projects_log.txt", atomically: true, encoding: .utf8)
        return log
    }
}
