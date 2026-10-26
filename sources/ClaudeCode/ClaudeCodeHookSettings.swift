//
//  ClaudeCodeHookSettings.swift
//  iTerm2SharedARC
//
//  The edits iTerm2 makes to an agent's hook settings, shared by the install on this Mac and the
//  install on a host reached through SSH Integration. Pure: dictionaries in, dictionaries out.
//
//  Which entries are "ours" is a parameter, because the two installs answer it differently. On
//  this Mac an entry belongs to the iTerm2 instance whose dot dir holds its executable (see
//  ClaudeCodeOnboarding.hookCommand(_:belongsToDotDir:)). On a remote host there is one shared
//  wrapper, ~/.iterm2/bin/it2, and a hook inherits IT2_SOCK and IT2_PY from the agent it runs
//  under, so a single entry serves whichever iTerm2 connection started that agent.
//

import Foundation

/// What an agent's hooks look like. Claude Code is the only one installed today; Codex would be
/// another value (~/.codex/hooks.json, SubagentStart and Interrupt, a 3 second timeout on
/// Interrupt and SessionEnd, `--agent codex`), and neither install should need rewriting for it.
struct AgentHookDescriptor {
    /// Events that must each have our entry.
    let eventNames: [String]
    /// Per-event timeout in seconds, written into the entry. Absent means the agent's default.
    let timeouts: [String: Int]
    /// Appended to `handle-agent-hook`, already shell-safe.
    let extraArguments: [String]

    static let claudeCode = AgentHookDescriptor(eventNames: ClaudeCodeOnboarding.hookEventNames,
                                                timeouts: [:],
                                                extraArguments: [])
}

enum ClaudeCodeHookSettings {
    // MARK: - The remote hook command

    /// The wrapper ssh integration uploads to every host it connects to.
    static let remoteIt2Path = "$HOME/.iterm2/bin/it2"

    /// The command a remote install writes. $HOME rather than the resolved home so the entry still
    /// works if the settings file is synced to another account or host. Double quotes so the hook
    /// runner's shell expands it.
    static func remoteHookCommand(descriptor: AgentHookDescriptor) -> String {
        return (["\"\(remoteIt2Path)\"", "handle-agent-hook"] + descriptor.extraArguments)
            .joined(separator: " ")
    }

    /// Whether a command on a remote host is an entry iTerm2 wrote there: the uploaded wrapper,
    /// named through $HOME or through the absolute `home`, running the hook subcommand with any
    /// further arguments. A Mac-path entry that arrived in a synced settings file is not ours: it
    /// belongs to some Mac install, and that install manages it.
    static func isRemoteHookCommand(_ command: String, home: String) -> Bool {
        guard command.hasPrefix("\""),
              let closing = command.dropFirst().firstIndex(of: "\"") else {
            return false
        }
        let path = String(command[command.index(after: command.startIndex)..<closing])
        let rest = command[command.index(after: closing)...]
        guard rest == " handle-agent-hook" || rest.hasPrefix(" handle-agent-hook ") else {
            return false
        }
        var trimmedHome = home
        while trimmedHome.count > 1 && trimmedHome.hasSuffix("/") {
            trimmedHome.removeLast()
        }
        return path == remoteIt2Path || path == trimmedHome + "/.iterm2/bin/it2"
    }

    // MARK: - Edits

    /// What to do with the first existing entry of ours for an event.
    enum ExistingEntryAction: Equatable {
        /// It runs the hook, or might: keep it as it is.
        case keep
        /// Make it run `command`.
        case rewrite
        /// It can't run the hook but runs something of the user's too: leave it, and add an entry
        /// of ours beside it.
        case addAlongside
    }

    /// `hooks` with the hook run once for every event. The first existing entry of ours is kept,
    /// rewritten in place to run `command`, or left beside a new entry, as `action` decides (by
    /// default always rewritten). Further entries of ours for the same event are removed if they
    /// only run the hook (the agent would run it once per entry); one that also runs something of
    /// the user's is left. A group emptied by that is dropped. Foreign entries are left alone.
    static func merged(_ hooks: [String: Any],
                       command: String,
                       descriptor: AgentHookDescriptor,
                       isOurs: (String) -> Bool,
                       action: (String) -> ExistingEntryAction = { _ in .rewrite }) -> [String: Any] {
        var hooks = hooks
        for eventName in descriptor.eventNames {
            var entry: [String: Any] = ["type": "command", "command": command]
            if let timeout = descriptor.timeouts[eventName] {
                entry["timeout"] = timeout
            }
            var groups = (hooks[eventName] as? [[String: Any]]) ?? []
            var foundOurs = false
            var groupIndex = 0
            while groupIndex < groups.count {
                guard var entries = groups[groupIndex]["hooks"] as? [[String: Any]] else {
                    groupIndex += 1
                    continue
                }
                var changed = false
                var entryIndex = 0
                while entryIndex < entries.count {
                    guard let existing = entries[entryIndex]["command"] as? String, isOurs(existing) else {
                        entryIndex += 1
                        continue
                    }
                    if foundOurs {
                        if CCStatusHookCommand.runsOnlyCCStatus(existing) {
                            entries.remove(at: entryIndex)
                            changed = true
                            DLog("Hook settings: removed duplicate entry for \(eventName): \(existing)")
                            continue
                        }
                        DLog("Hook settings: leaving \(existing) for \(eventName) because it runs more than the hook")
                        entryIndex += 1
                        continue
                    }
                    switch action(existing) {
                    case .keep:
                        foundOurs = true
                    case .rewrite:
                        foundOurs = true
                        for (key, value) in entry where !isEqual(entries[entryIndex][key], value) {
                            entries[entryIndex][key] = value
                            changed = true
                        }
                    case .addAlongside:
                        DLog("Hook settings: \(existing) for \(eventName) can't run the hook but runs more than it; leaving it")
                    }
                    entryIndex += 1
                }
                if changed {
                    if entries.isEmpty {
                        groups.remove(at: groupIndex)
                        continue
                    }
                    groups[groupIndex]["hooks"] = entries
                }
                groupIndex += 1
            }
            if !foundOurs {
                groups.append(["hooks": [entry]])
                DLog("Hook settings: added entry for \(eventName)")
            }
            hooks[eventName] = groups
        }
        return hooks
    }

    /// `settings` with every entry of ours removed from the descriptor's events, or nil when there
    /// was nothing of ours to remove. An entry that also runs something of the user's stays, since
    /// removing it would stop that from running too. A group whose only entry was ours goes, an event left with
    /// no groups goes, and an empty `hooks` goes, so the file looks as if we had never installed.
    static func stripped(_ settings: [String: Any],
                         descriptor: AgentHookDescriptor,
                         isOurs: (String) -> Bool) -> [String: Any]? {
        guard var hooks = settings["hooks"] as? [String: Any] else {
            return nil
        }
        var changed = false
        for eventName in descriptor.eventNames {
            guard var groups = hooks[eventName] as? [[String: Any]] else {
                continue
            }
            var groupsChanged = false
            for i in (0..<groups.count).reversed() {
                guard var entries = groups[i]["hooks"] as? [[String: Any]] else {
                    continue
                }
                let before = entries.count
                entries.removeAll { entry in
                    guard let command = entry["command"] as? String, isOurs(command) else {
                        return false
                    }
                    guard CCStatusHookCommand.runsOnlyCCStatus(command) else {
                        DLog("Hook settings: leaving \(command) because it runs more than the hook")
                        return false
                    }
                    return true
                }
                if entries.count != before {
                    groupsChanged = true
                    if entries.isEmpty {
                        groups.remove(at: i)
                    } else {
                        groups[i]["hooks"] = entries
                    }
                }
            }
            if groupsChanged {
                changed = true
                if groups.isEmpty {
                    hooks.removeValue(forKey: eventName)
                } else {
                    hooks[eventName] = groups
                }
            }
        }
        guard changed else {
            return nil
        }
        var result = settings
        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    /// The commands of ours, per event, or nil when some event has none. The caller decides what
    /// else a healthy install needs (the executable must exist, for one).
    static func ourCommandsCoveringEveryEvent(_ settings: [String: Any],
                                              descriptor: AgentHookDescriptor,
                                              isOurs: (String) -> Bool) -> [String: [String]]? {
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return nil
        }
        var result = [String: [String]]()
        for eventName in descriptor.eventNames {
            let groups = (hooks[eventName] as? [[String: Any]]) ?? []
            let commands = groups.flatMap { group -> [String] in
                let entries = (group["hooks"] as? [[String: Any]]) ?? []
                return entries.compactMap { $0["command"] as? String }.filter(isOurs)
            }
            guard !commands.isEmpty else {
                return nil
            }
            result[eventName] = commands
        }
        return result
    }

    /// The settings object a settings file holds, or nil when its root is not a JSON object.
    /// Throws when it is not JSON at all. An empty or whitespace-only file is an empty object:
    /// it holds nothing to lose, but JSONSerialization rejects it. Shared by the install on this
    /// Mac and the remote one so that they agree on which files are malformed.
    static func settingsObject(from data: Data) throws -> [String: Any]? {
        let blank = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? false
        if blank {
            return [:]
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// settingsObject(from:), with both failures as nil.
    static func settingsObjectIfValid(from data: Data) -> [String: Any]? {
        return (try? settingsObject(from: data)) ?? nil
    }

    /// The bytes iTerm2 writes a settings file as.
    static func serialized(_ settings: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        guard let lhs else {
            return false
        }
        return (lhs as? NSObject)?.isEqual(rhs) ?? false
    }
}
