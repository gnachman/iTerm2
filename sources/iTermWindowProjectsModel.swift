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

    /// Runtime-only mapping: NSWindow.windowNumber → project UUID.
    /// Not persisted — live associations reset when the app restarts.
    private var liveAssociations: [Int: UUID] = [:]

    private static var saveURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("iTerm2")
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent("WindowProjects.json")
    }

    private override init() {
        super.init()
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil)
    }

    // MARK: Persistence

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(rootProjects) else { return }
        try? data.write(to: Self.saveURL)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
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

    @discardableResult
    func deleteProject(_ project: iTermWindowProject) -> Bool {
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
        guard let wn = terminal.window()?.windowNumber, wn > 0 else { return }
        liveAssociations[wn] = project.id
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Removes the project association from `terminal`, leaving the window open but untracked.
    func disassociateWindow(_ terminal: PseudoTerminal) {
        guard let wn = terminal.window()?.windowNumber, wn > 0,
              liveAssociations.removeValue(forKey: wn) != nil else { return }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Returns the project `terminal` is currently associated with, or nil.
    func project(for terminal: PseudoTerminal) -> iTermWindowProject? {
        guard let wn = terminal.window()?.windowNumber, wn > 0,
              let pid = liveAssociations[wn] else { return nil }
        return project(id: pid)
    }

    /// Returns all currently open windows associated with `project`.
    func liveWindows(for project: iTermWindowProject) -> [PseudoTerminal] {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.filter { t in
            guard let wn = t.window()?.windowNumber, wn > 0 else { return false }
            return liveAssociations[wn] == project.id
        }
    }

    /// True if `project` has at least one open window associated with it.
    func hasLiveWindows(for project: iTermWindowProject) -> Bool {
        let all = iTermController.sharedInstance().terminals() ?? []
        return all.contains { t in
            guard let wn = t.window()?.windowNumber, wn > 0 else { return false }
            return liveAssociations[wn] == project.id
        }
    }

    /// Closes and archives every open window currently associated with `project`.
    func closeProject(_ project: iTermWindowProject) {
        for terminal in liveWindows(for: project) {
            guard let wn = terminal.window()?.windowNumber else { continue }
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
            let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
            PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
            let title = terminal.window()?.title ?? "Window"
            project.windows.append(iTermArchivedWindow(name: title, arrangement: arrangement))
            liveAssociations.removeValue(forKey: wn)
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
        guard let terminal = all.first(where: { $0.window()?.windowNumber == wn }) else {
            liveAssociations.removeValue(forKey: wn)
            return
        }
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        let title = window.title.isEmpty ? "Window" : window.title
        project.windows.append(iTermArchivedWindow(name: title, arrangement: arrangement))
        liveAssociations.removeValue(forKey: wn)
        project.lastUsed = Date()
        save()
    }

    // MARK: Window Archiving

    /// Saves `terminal`'s arrangement into `project` and optionally closes the window.
    /// Any existing live association is cleared.
    func archiveWindow(_ terminal: PseudoTerminal,
                       to project: iTermWindowProject,
                       andClose close: Bool) {
        if let wn = terminal.window()?.windowNumber, wn > 0 {
            liveAssociations.removeValue(forKey: wn)
        }
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(true)
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: true) ?? [:]
        PseudoTerminal.setUseUnlimitedHistoryForArrangement(false)
        let title = terminal.window()?.title ?? "Window"
        let entry = iTermArchivedWindow(name: title, arrangement: arrangement)
        project.windows.append(entry)
        project.lastUsed = Date()
        save()
        if close {
            terminal.close()
        }
    }

    func removeWindow(_ window: iTermArchivedWindow, from project: iTermWindowProject) {
        project.windows.removeAll { $0.id == window.id }
        save()
    }

    // MARK: Restoration

    func restoreWindow(_ archived: iTermArchivedWindow) {
        guard let project = parentProject(of: archived) else { return }
        guard let arrangement = archived.arrangement else { return }
        
        let lionFullScreen = PseudoTerminal.arrangementIsLionFullScreen(arrangement)
        PseudoTerminal.performWhenWindowCreationIsSafe(forLionFullScreen: lionFullScreen) { [weak self] in
            guard let self = self else { return }
            guard let term = PseudoTerminal(
                arrangement: arrangement,
                named: nil,
                forceOpeningHotKeyWindow: false) else { return }
            
            iTermController.sharedInstance().addTerminalWindow(term)
            
            // Remove the archived window from the project's list so it cannot be restored twice!
            project.windows.removeAll { $0.id == archived.id }
            
            // Associate the newly opened window with the project!
            if let wn = term.window()?.windowNumber, wn > 0 {
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
                guard let term = PseudoTerminal(
                    arrangement: arrangement,
                    named: nil,
                    forceOpeningHotKeyWindow: false) else { return }
                
                iTermController.sharedInstance().addTerminalWindow(term)
                
                if let wn = term.window()?.windowNumber, wn > 0 {
                    self.liveAssociations[wn] = project.id
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
                }
            }
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
