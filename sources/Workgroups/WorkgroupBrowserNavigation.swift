//
//  WorkgroupBrowserNavigation.swift
//  iTerm2
//
//  What a workgroup needs so an agent can show pages in its browser member,
//  and the text that tells the agent how. See WorkgroupBrowserURLBinding for
//  the mechanism itself.
//

import Foundation

enum WorkgroupBrowserNavigation {
    /// The variable the Claude Code setup binds the browser to.
    // Localization unneeded: a variable name, typed by agents.
    static let defaultVariablePath = "user.browserURL"

    /// A browser member's URL that is just `defaultVariablePath`, so it goes
    /// wherever the variable points.
    static let defaultURLTemplate = "\\(\(defaultVariablePath))"

    /// The name given to a browser peer the setup adds. It is stored in the
    /// workgroup when the peer is created, and every command is built from
    /// whatever name is stored, so this can be localized safely.
    static var defaultPeerName: String {
        return String(localized: "WorkgroupBrowserNavigation.DefaultPeerName",
                      defaultValue: "Browser",
                      comment: "Name of the browser session added to a workgroup so an agent can show web pages in it. Agents use this name to address it, so prefer a short single word.")
    }

    /// A member that follows a user variable, as the agent sees it.
    struct Target: Equatable {
        var peerName: String
        var variablePath: String
    }

    /// The member `config` describes, if it is a browser, its URL is exactly
    /// one user variable, and it has a name to address it by. A member
    /// switched to a terminal profile keeps its URL, but nothing would
    /// navigate. The generated instructions have the agent pass a whole URL,
    /// so a URL with text around the variable, such as
    /// https://github.com/\(user.path), would load a mangled address, and one
    /// that needs several variables never forms from the one the command sets.
    static func target(for config: iTermWorkgroupSessionConfig,
                       isBrowser: (iTermWorkgroupSessionConfig) -> Bool = { $0.resolvedProfileIsBrowser }) -> Target? {
        guard !config.displayName.isEmpty,
              isBrowser(config),
              let path = soleVariable(in: config.urlString) else {
            return nil
        }
        return Target(peerName: config.displayName, variablePath: path)
    }

    /// The variable `urlString` consists of, if it is exactly one variable
    /// with nothing around it, so that setting it to a URL loads that URL.
    static func soleVariable(in urlString: String) -> String? {
        guard case .template(let template) = WorkgroupBrowserURLBinding.Template.parse(urlString),
              template.pieces.count == 1,
              case .variable(let path) = template.pieces[0] else {
            return nil
        }
        return path
    }

    static func targets(in workgroup: iTermWorkgroup,
                        isBrowser: (iTermWorkgroupSessionConfig) -> Bool = { $0.resolvedProfileIsBrowser }) -> [Target] {
        return workgroup.sessions.compactMap { target(for: $0, isBrowser: isBrowser) }
    }

    // MARK: - Text for agents

    /// `value` quoted for a POSIX shell, unless it needs no quoting.
    static func shellQuoted(_ value: String) -> String {
        let safe = !value.isEmpty && value.allSatisfy { ch in
            ch.isLetter || ch.isNumber || "-_.".contains(ch)
        }
        if safe {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The command that shows `url` in `target`'s browser. `it2` is how to run
    /// it2: a bare name relies on PATH, which shell startup files often rebuild
    /// without iTerm2's utilities, so the Claude Code setup passes a path.
    static func command(for target: Target, url: String, it2: String = "it2") -> String {
        // Localization unneeded: a shell command.
        return "\(it2) session set-var --peer-name \(shellQuoted(target.peerName)) \(target.variablePath) \(url)"
    }

    /// A Claude Code permission rule that lets the agent run `command(for:url:)`
    /// for this peer, and nothing broader.
    static func claudeAllowRule(for target: Target, it2: String = "it2") -> String {
        // Localization unneeded: a Claude Code settings value.
        return "Bash(\(it2) session set-var --peer-name \(shellQuoted(target.peerName)) \(target.variablePath):*)"
    }

    /// Instructions to paste into a skill or CLAUDE.md.
    static func agentInstructions(for target: Target, it2: String = "it2") -> String {
        // Just the command, with no `|| true` or redirection: Claude Code checks
        // each part of a compound command against the allow rules separately,
        // so anything more would prompt. The text says to ignore failure instead.
        let command = command(for: target, url: "'<URL>'", it2: it2)
        // Localization unneeded: a prompt for an AI model (see docs/localization.md).
        return """
            When you start working on something that has a web page, such as an issue, a pull request, or documentation the user mentioned, show that page in the workgroup’s browser so the user can follow along. Run this, and ignore any failure:
            \(command)
            """
    }

    // MARK: - Adding a browser member

    /// A browser profile's GUID, creating a profile if there is none.
    static func browserProfileGUID() -> String? {
        guard let model = ProfileModel.sharedInstance() else {
            return nil
        }
        if let existing = model.bookmarks().first(where: { ($0 as NSDictionary).profileIsBrowser }),
           let guid = existing[KEY_GUID] as? String {
            return guid
        }
        return createBrowserProfile()
    }

    /// Adds a browser profile and returns its GUID.
    static func createBrowserProfile() -> String? {
        guard let model = ProfileModel.sharedInstance(),
              let guid = ProfileModel.freshGuid() else {
            return nil
        }
        let dict: [AnyHashable: Any] = [
            KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue,
            KEY_NAME: iTermBrowserSessionTitle.defaultProfileName,
            KEY_GUID: guid
        ]
        model.addBookmark(dict)
        model.flush()
        NotificationCenter.default.post(name: NSNotification.Name(kReloadAllProfiles),
                                        object: nil,
                                        userInfo: nil)
        RLog("WorkgroupBrowserNavigation: created browser profile \(guid)")
        return guid
    }

    /// `workgroup` with a browser peer of its root that follows
    /// `defaultVariablePath`, or nil if it has no root. The name is made unique
    /// within the workgroup, since agents address the peer by it.
    static func addingBrowserPeer(to workgroup: iTermWorkgroup,
                                  profileGUID: String) -> iTermWorkgroup? {
        guard let root = workgroup.root else {
            return nil
        }
        let existingNames = Set(workgroup.sessions.map { $0.displayName.lowercased() })
        let base = defaultPeerName
        var name = base
        var suffix = 2
        while existingNames.contains(name.lowercased()) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        let peer = iTermWorkgroupSessionConfig(
            uniqueIdentifier: UUID().uuidString,
            parentID: root.uniqueIdentifier,
            kind: .peer,
            profileGUID: profileGUID,
            command: "",
            urlString: defaultURLTemplate,
            toolbarItems: [.modeSwitcher],
            displayName: name)
        var result = workgroup
        result.sessions.append(peer)
        return result
    }
}

extension iTermWorkgroupSessionConfig {
    /// Whether this member runs in a browser: its profile, or the default
    /// profile when it names none or one that no longer exists.
    var resolvedProfileIsBrowser: Bool {
        guard let model = ProfileModel.sharedInstance() else {
            return false
        }
        let profile = profileGUID.flatMap { model.bookmark(withGuid: $0) } ?? model.defaultBookmark()
        return (profile as NSDictionary?)?.profileIsBrowser ?? false
    }
}
