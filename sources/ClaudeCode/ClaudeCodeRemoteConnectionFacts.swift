//
//  ClaudeCodeRemoteConnectionFacts.swift
//  iTerm2SharedARC
//
//  What iTerm2 has learned about Claude Code on a host it is connected to through SSH
//  Integration: where Claude Code keeps its settings there, and whether iTerm2's hook is in them.
//
//  Kept per connection, in memory only, and gone with the connection. Nothing about remote hosts
//  is written to disk: a record of them would be a history of where the user has been, and it
//  would disagree with the hosts themselves (another build, or the user, can install or remove
//  the hook). The host is always the authority; this only saves asking it twice per connection.
//
//  This Mac's own state stays in iTermUserDefaults (claudeCodeConfigDirPath and friends).
//

import Foundation

final class ClaudeCodeRemoteConnectionFacts {
    static let shared = ClaudeCodeRemoteConnectionFacts()

    private final class Entry {
        var configDirectory: String?
        var hookPresent: Bool?
    }

    // Weak keys: an entry disappears with its connection.
    private let table = NSMapTable<AnyObject, Entry>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    private func entry(for connection: AnyObject) -> Entry {
        if let existing = table.object(forKey: connection) {
            return existing
        }
        let created = Entry()
        table.setObject(created, forKey: connection)
        return created
    }

    /// CLAUDE_CONFIG_DIR as resolved on the host during this connection, if it has been.
    func configDirectory(for connection: AnyObject) -> String? {
        return table.object(forKey: connection)?.configDirectory
    }

    func setConfigDirectory(_ directory: String, for connection: AnyObject) {
        entry(for: connection).configDirectory = directory
    }

    /// Whether the host's settings had iTerm2's hook (complete or not) when last looked at during
    /// this connection; nil if nobody has looked.
    func hookPresent(for connection: AnyObject) -> Bool? {
        return table.object(forKey: connection)?.hookPresent
    }

    func setHookPresent(_ present: Bool, for connection: AnyObject) {
        entry(for: connection).hookPresent = present
    }

    /// Whether any open connection is known to have the hook on its host.
    var anyHookPresent: Bool {
        guard let keys = table.keyEnumerator().allObjects as [AnyObject]? else {
            return false
        }
        return keys.contains { table.object(forKey: $0)?.hookPresent == true }
    }

    /// Where the settings are, given the host's home. The default matches Claude Code's own when
    /// CLAUDE_CONFIG_DIR is unset.
    static func settingsPath(configDirectory: String?, home: String) -> String {
        let directory = configDirectory ?? joined(home, ".claude")
        return joined(directory, "settings.json")
    }

    private static func joined(_ directory: String, _ name: String) -> String {
        var trimmed = directory
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed + "/" + name
    }
}
