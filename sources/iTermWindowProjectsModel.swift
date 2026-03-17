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

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.children = []
        self.windows = []
    }

    enum CodingKeys: String, CodingKey { case id, name, children, windows }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,                 forKey: .id)
        name     = try c.decode(String.self,               forKey: .name)
        children = try c.decode([iTermWindowProject].self, forKey: .children)
        windows  = try c.decode([iTermArchivedWindow].self,forKey: .windows)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(name,     forKey: .name)
        try c.encode(children, forKey: .children)
        try c.encode(windows,  forKey: .windows)
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

    // MARK: Window Archiving

    /// Saves `terminal`'s arrangement into `project` and optionally closes the window.
    func archiveWindow(_ terminal: PseudoTerminal,
                       to project: iTermWindowProject,
                       andClose close: Bool) {
        let arrangement = terminal.arrangementExcludingTmuxTabs(true, includingContents: false)
        let title = terminal.window()?.title ?? "Window"
        let entry = iTermArchivedWindow(name: title, arrangement: arrangement)
        project.windows.append(entry)
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
        guard let arrangement = archived.arrangement else { return }
        iTermController.sharedInstance().tryOpenArrangement(
            arrangement as? [AnyHashable: Any],
            named: nil,
            asTabsInWindow: nil)
    }

    func restoreAllWindows(in project: iTermWindowProject) {
        project.windows.forEach { restoreWindow($0) }
    }

    // MARK: Helpers

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
}
