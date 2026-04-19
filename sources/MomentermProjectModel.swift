//
//  MomentermProjectModel.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//

import Foundation

// MARK: - Enums

@objc enum MomentermAITool: Int, Codable, CaseIterable {
    case claudeCode = 0
    case codex = 1
    case both = 2
    case none = 3

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .both: return "Both"
        case .none: return "None"
        }
    }

    var launchCommand: String? {
        switch self {
        case .claudeCode: return "claude --dangerously-skip-permissions"
        case .codex: return "codex"
        case .both: return nil
        case .none: return nil
        }
    }
}

@objc enum MomentermTmuxMode: Int, Codable, CaseIterable {
    case disabled = 0
    case newSession = 1
    case existingSession = 2

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .newSession: return "New Session"
        case .existingSession: return "Existing Session"
        }
    }
}

// MARK: - Project Model

struct MomentermProject: Codable, Identifiable {
    var id: String
    var name: String
    var path: String
    var aiTool: MomentermAITool
    var tmuxMode: MomentermTmuxMode
    var tmuxSession: String?
    var createdAt: Date
    var lastOpenedAt: Date?

    init(name: String, path: String, aiTool: MomentermAITool = .claudeCode, tmuxMode: MomentermTmuxMode = .disabled) {
        self.id = UUID().uuidString
        self.name = name
        self.path = path
        self.aiTool = aiTool
        self.tmuxMode = tmuxMode
        self.createdAt = Date()
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var pathExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Build the shell command to open this project
    func buildOpenCommand() -> String {
        var parts: [String] = ["cd \"\(path)\""]
        switch tmuxMode {
        case .newSession:
            let session = name.lowercased().replacingOccurrences(of: " ", with: "-")
            parts.append("tmux new-session -s \"\(session)\"")
        case .existingSession:
            let session = tmuxSession ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
            parts.append("tmux attach -t \"\(session)\" 2>/dev/null || tmux new-session -s \"\(session)\"")
        case .disabled:
            break
        }
        if let cmd = aiTool.launchCommand {
            parts.append(cmd)
        }
        return parts.joined(separator: " && ")
    }
}

// MARK: - Project Space

struct MomentermProjectSpace: Codable, Identifiable {
    var id: String
    var name: String
    var projects: [MomentermProject]

    init(name: String) {
        self.id = UUID().uuidString
        self.name = name
        self.projects = []
    }

    mutating func addProject(_ project: MomentermProject) {
        guard !projects.contains(where: { $0.id == project.id }) else { return }
        projects.append(project)
    }

    mutating func removeProject(withId id: String) {
        projects.removeAll { $0.id == id }
    }
}

// MARK: - Root Store

struct MomentermProjectStore: Codable {
    var version: Int = 1
    var spaces: [MomentermProjectSpace]

    init() {
        self.spaces = [MomentermProjectSpace(name: "Default")]
    }

    var allProjects: [MomentermProject] {
        spaces.flatMap { $0.projects }
    }

    func findProject(withId id: String) -> (spaceIndex: Int, projectIndex: Int)? {
        for (si, space) in spaces.enumerated() {
            for (pi, project) in space.projects.enumerated() {
                if project.id == id {
                    return (si, pi)
                }
            }
        }
        return nil
    }

    func findProject(atPath path: String) -> MomentermProject? {
        let resolved = (path as NSString).standardizingPath
        return allProjects.first {
            ($0.path as NSString).standardizingPath == resolved
        }
    }

    mutating func addSpace(named name: String) -> MomentermProjectSpace {
        let space = MomentermProjectSpace(name: name)
        spaces.append(space)
        return space
    }

    mutating func removeSpace(withId id: String) {
        spaces.removeAll { $0.id == id }
    }
}
