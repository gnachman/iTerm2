import Foundation

/// Host and user are part of directory identity; unknown paths never merge.
struct SessionDirectoryKey: Hashable {
    let host: String?
    let user: String?
    let path: String?
    private let unknownSessionID: String?

    init(host: String?, user: String?, path: String?, sessionID: String) {
        self.host = host.flatMap { $0.isEmpty ? nil : $0 }
        self.user = user.flatMap { $0.isEmpty ? nil : $0 }
        // Do not resolve symlinks or expand ~ using the local machine for remote paths.
        self.path = path.flatMap { value in
            guard value.hasPrefix("/") else { return nil }
            let trimmed = String(value.reversed().drop(while: { $0 == "/" }).reversed())
            return trimmed.isEmpty ? "/" : trimmed
        }
        unknownSessionID = self.path == nil ? sessionID : nil
    }

    static func harnessName(executable: String?, arguments: [String]? = nil) -> String? {
        if let executable, (executable as NSString).lastPathComponent == "node",
           let script = arguments?.dropFirst().first {
            // Known launcher scripts, not text appearing anywhere in user arguments.
            if script.hasSuffix("/@openai/codex/bin/codex.js") { return "Codex" }
            if script.hasSuffix("/@anthropic-ai/claude-code/cli.js") { return "Claude" }
            if script.hasSuffix("/@google/gemini-cli/dist/index.js") { return "Gemini" }
        }
        guard let executable else { return nil }
        // Match executable names, never arbitrary titles or command arguments.
        switch (executable as NSString).lastPathComponent {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "agy", "antigravity": return "Antigravity"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "aider": return "Aider"
        default: return nil
        }
    }
}
