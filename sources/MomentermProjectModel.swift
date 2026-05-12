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
    case gemini = 4
    case localLLM = 5

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .both: return "Both"
        case .none: return "None"
        case .gemini: return "Gemini"
        case .localLLM: return "Local LLM"
        }
    }
}

@objc enum MomentermLocalLLMBackend: Int, Codable, CaseIterable {
    case none = 0
    case ollama = 1
    case lmStudio = 2

    var displayName: String {
        switch self {
        case .none: return "None"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        }
    }

    var defaultEndpoint: URL? {
        switch self {
        case .ollama: return URL(string: "http://localhost:11434")
        case .lmStudio: return URL(string: "http://localhost:1234")
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
    var localLLMBackend: MomentermLocalLLMBackend?
    var localLLMModel: String?

    init(name: String, path: String, aiTool: MomentermAITool = .claudeCode, tmuxMode: MomentermTmuxMode = .disabled) {
        self.id = UUID().uuidString
        self.name = name
        self.path = path
        self.aiTool = aiTool
        self.tmuxMode = tmuxMode
        self.createdAt = Date()
    }

    /// Command to start the configured AI tool. Project-aware so localLLM can reference its backend/model.
    var aiLaunchCommand: String? {
        switch aiTool {
        case .claudeCode: return "claude --dangerously-skip-permissions"
        case .codex:      return "codex"
        case .gemini:     return "gemini"
        case .localLLM:
            guard let backend = localLLMBackend, let model = localLLMModel else { return nil }
            switch backend {
            case .ollama:   return "ollama run \(model)"
            case .lmStudio: return "lms chat \(model)"
            case .none:     return nil
            }
        case .both, .none: return nil
        }
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
        if let cmd = aiLaunchCommand {
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
