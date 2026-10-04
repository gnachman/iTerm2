//
//  ClaudeCodeRemoteHostState.swift
//  iTerm2SharedARC
//
//  Claude Code integration state for hosts reached through SSH Integration.
//
//  This Mac's state stays where it always was (iTermUserDefaults.claudeCodeConfigDirPath,
//  claudeCodeHooksInstalled, claudeCodeIntegrationCompleted), so nothing migrates. Every other
//  host is keyed by its SSHIdentity.stringIdentifier, the same key an it2 grant uses. A session's
//  host is its conductor's identity; in a nested chain that conductor is the innermost one, where
//  the agent actually runs.
//
//  Two facts per host:
//  - Where its Claude Code settings live: CLAUDE_CONFIG_DIR as resolved on that host at install,
//    so later reads need not ask the host again. Unset means Claude Code's default, ~/.claude
//    under that host's home.
//  - Whether the user completed an install there. Sticky until uninstall, like the local
//    claudeCodeIntegrationCompleted: a later health check compares it with what is on the host
//    to notice hooks that something else removed.
//

import Foundation

protocol ClaudeCodeRemoteHostStateBacking: AnyObject {
    var configDirPathByHost: [String: String] { get set }
    var hooksInstalledHosts: [String] { get set }
}

/// NoSync: this is state, not configuration, and syncing it would prompt a user who loads
/// settings from a shared folder every time a host is installed.
final class ClaudeCodeRemoteHostStateUserDefaultsBacking: ClaudeCodeRemoteHostStateBacking {
    static let configDirPathByHostKey = "NoSyncClaudeCodeConfigDirPathByHost"
    static let hooksInstalledHostsKey = "NoSyncClaudeCodeHooksInstalledHosts"

    var configDirPathByHost: [String: String] {
        get {
            let raw = iTermUserDefaults.userDefaults().dictionary(forKey: Self.configDirPathByHostKey) ?? [:]
            return raw.compactMapValues { $0 as? String }
        }
        set {
            if newValue.isEmpty {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.configDirPathByHostKey)
            } else {
                iTermUserDefaults.userDefaults().set(newValue, forKey: Self.configDirPathByHostKey)
            }
        }
    }

    var hooksInstalledHosts: [String] {
        get {
            return iTermUserDefaults.userDefaults().stringArray(forKey: Self.hooksInstalledHostsKey) ?? []
        }
        set {
            if newValue.isEmpty {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.hooksInstalledHostsKey)
            } else {
                iTermUserDefaults.userDefaults().set(newValue, forKey: Self.hooksInstalledHostsKey)
            }
        }
    }
}

final class ClaudeCodeRemoteHostState {
    static let shared = ClaudeCodeRemoteHostState(backing: ClaudeCodeRemoteHostStateUserDefaultsBacking())

    private let backing: ClaudeCodeRemoteHostStateBacking

    init(backing: ClaudeCodeRemoteHostStateBacking) {
        self.backing = backing
    }

    // MARK: - Config directory

    /// The CLAUDE_CONFIG_DIR resolved on `host` at install, or nil when it never has been.
    func configDirectoryPath(forHost host: String) -> String? {
        guard let path = backing.configDirPathByHost[host], !path.isEmpty else {
            return nil
        }
        return path
    }

    func recordConfigDirectory(_ path: String, forHost host: String) {
        var map = backing.configDirPathByHost
        map[host] = path
        backing.configDirPathByHost = map
    }

    /// Where `host`'s settings.json is, given its home directory. The default matches Claude Code's
    /// own when CLAUDE_CONFIG_DIR is unset.
    func settingsPath(forHost host: String, home: String) -> String {
        let directory = configDirectoryPath(forHost: host) ?? Self.joined(home, ".claude")
        return Self.joined(directory, "settings.json")
    }

    private static func joined(_ directory: String, _ name: String) -> String {
        var trimmed = directory
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed + "/" + name
    }

    // MARK: - Installed hosts

    func hooksInstalled(onHost host: String) -> Bool {
        return backing.hooksInstalledHosts.contains(host)
    }

    /// Clearing keeps the config directory, as uninstall does locally, so a reinstall goes back to
    /// the same place.
    func setHooksInstalled(_ installed: Bool, onHost host: String) {
        var hosts = backing.hooksInstalledHosts.filter { $0 != host }
        if installed {
            hosts.append(host)
        }
        backing.hooksInstalledHosts = hosts
    }

    /// Hosts with an install, in a stable order for menus and uninstall.
    var hostsWithHooksInstalled: [String] {
        return backing.hooksInstalledHosts.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
