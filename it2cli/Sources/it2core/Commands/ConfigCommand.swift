import ArgumentParser
import Foundation
import ProtobufRuntime
import Yams

// MARK: - Config data model

struct IT2Config {
    var profiles: [String: [[String: String]]] = [:]
    var aliases: [String: String] = [:]

    static func load() -> IT2Config {
        let path = configPath()
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let yaml = String(data: data, encoding: .utf8) else {
            return IT2Config()
        }

        do {
            guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
                FileHandle.standardError.write(Data("Warning: Could not parse config file at \(path)\n".utf8))
                return IT2Config()
            }

            var config = IT2Config()
            if let profiles = dict["profiles"] as? [String: [[String: String]]] {
                config.profiles = profiles
            }
            if let aliases = dict["aliases"] as? [String: String] {
                config.aliases = aliases
            }
            return config
        } catch {
            FileHandle.standardError.write(Data("Warning: Error parsing config file at \(path): \(error.localizedDescription)\n".utf8))
            return IT2Config()
        }
    }

    static func configPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["IT2_CONFIG_PATH"] {
            return envPath
        }
        return NSHomeDirectory() + "/.it2rc.yaml"
    }
}

// MARK: - Top-level config commands registered on IT2

struct LoadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "load",
        abstract: "Load a custom profile from config file."
    )

    @Argument(help: "Profile name from ~/.it2rc.yaml.")
    var profileName: String

    func run() throws {
        let config = IT2Config.load()
        guard let steps = config.profiles[profileName] else {
            throw IT2Error.targetNotFound("Profile '\(profileName)' not found in config")
        }

        let client = try APIClient.connect()
        defer { client.disconnect() }

        print("Loading profile: \(profileName)")

        let sessionId = try client.resolveSessionId(nil)
        var createdSessions: [String] = [sessionId]

        for step in steps {
            if let command = step["command"] {
                let sendText = ITMSendTextRequest()
                sendText.session = sessionId
                sendText.text = command + "\r"

                let request = ITMClientOriginatedMessage()
                request.id_p = client.nextId()
                request.sendTextRequest = sendText
                let _ = try client.send(request)
                print("  Running: \(command)")
            }

            if let splitType = step["split"] {
                if splitType == "vertical" || splitType == "horizontal" {
                    let newId = try splitSession(client: client, sessionId: sessionId,
                                                 vertical: splitType == "vertical")
                    if let id = newId {
                        createdSessions.append(id)
                    } else {
                        FileHandle.standardError.write(Data("  Warning: Split failed\n".utf8))
                    }
                    print("  Split: \(splitType)")
                } else if splitType == "2x2" {
                    // Special case matching Python: split original vertically,
                    // then split each half horizontally.
                    if let s1 = try splitSession(client: client, sessionId: sessionId, vertical: true) {
                        let _ = try splitSession(client: client, sessionId: sessionId, vertical: false)
                        let _ = try splitSession(client: client, sessionId: s1, vertical: false)
                        createdSessions.append(s1)
                    }
                    print("  Split: \(splitType)")
                } else if let (cols, rows) = parseGrid(splitType), cols > 0, rows > 0 {
                    // NxM grid: create columns first, then rows in each column.
                    var columnSessions = [sessionId]

                    for _ in 0..<(cols - 1) {
                        if let newId = try splitSession(client: client,
                                                        sessionId: columnSessions[0],
                                                        vertical: true) {
                            columnSessions.insert(newId, at: 0)
                        }
                    }

                    for colSession in columnSessions {
                        createdSessions.append(colSession)
                        for _ in 0..<(rows - 1) {
                            if let newId = try splitSession(client: client,
                                                            sessionId: colSession,
                                                            vertical: false) {
                                createdSessions.append(newId)
                            }
                        }
                    }
                    print("  Split: \(splitType)")
                } else {
                    FileHandle.standardError.write(Data("  Warning: Invalid split format '\(splitType)'\n".utf8))
                }
            }

            // Handle pane-specific commands (pane1, pane2, etc.).
            // Match Python: target the nth session across ALL tabs in the current window.
            let hasPaneCommands = (1...9).contains { step["pane\($0)"] != nil }
            if hasPaneCommands {
                let windowId = try resolveCurrentWindowId(client: client)
                let windows = try fetchWindows(client: client)
                var allSessions: [String] = []
                for win in windows {
                    if win.windowId == windowId,
                       let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                        for tab in tabs {
                            allSessions.append(contentsOf: collectSessionIds(from: tab.root))
                        }
                    }
                }
                for i in 1...9 {
                    if let paneCmd = step["pane\(i)"], i <= allSessions.count {
                        let targetSession = allSessions[i - 1]
                        let sendText = ITMSendTextRequest()
                        sendText.session = targetSession
                        sendText.text = paneCmd + "\r"

                        let request = ITMClientOriginatedMessage()
                        request.sendTextRequest = sendText
                        let _ = try client.send(request)
                        print("  Pane \(i): \(paneCmd)")
                    }
                }
            }
        }

        print("Profile '\(profileName)' loaded successfully")
    }

    private func splitSession(client: APIClient, sessionId: String, vertical: Bool) throws -> String? {
        let split = ITMSplitPaneRequest()
        split.session = sessionId
        split.splitDirection = vertical ? .vertical : .horizontal

        let request = ITMClientOriginatedMessage()
        request.id_p = client.nextId()
        request.splitPaneRequest = split

        let response = try client.send(request)
        guard response.submessageOneOfCase == .splitPaneResponse,
              let splitResp = response.splitPaneResponse,
              splitResp.status == ITMSplitPaneResponse_Status.ok,
              splitResp.sessionIdArray_Count > 0,
              let newId = splitResp.sessionIdArray.object(at: 0) as? String else {
            return nil
        }
        return newId
    }

    private func parseGrid(_ s: String) -> (Int, Int)? {
        let parts = s.lowercased().split(separator: "x")
        guard parts.count == 2,
              let cols = Int(parts[0]),
              let rows = Int(parts[1]),
              cols > 0, rows > 0 else {
            return nil
        }
        return (cols, rows)
    }
}

struct AliasCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        abstract: "Execute an alias from config file."
    )

    @Argument(help: "Alias name from ~/.it2rc.yaml.")
    var aliasName: String

    func run() throws {
        let config = IT2Config.load()

        guard let aliasCmd = config.aliases[aliasName] else {
            if config.aliases.isEmpty {
                FileHandle.standardError.write(Data("No aliases defined in config file\n".utf8))
            } else {
                FileHandle.standardError.write(Data("Available aliases:\n".utf8))
                for (name, cmd) in config.aliases.sorted(by: { $0.key < $1.key }) {
                    FileHandle.standardError.write(Data("  \(name): \(cmd)\n".utf8))
                }
            }
            Foundation.exit(3)
        }

        print("Running alias '\(aliasName)': \(aliasCmd)")

        // Parse the alias command with shell-style quoting (like shlex.split).
        var args = shellSplit(aliasCmd)
        // Remove leading "it2" if present.
        if args.first == "it2" { args.removeFirst() }

        var cmd = try IT2.parseAsRoot(args)
        try cmd.run()
    }
}

struct ConfigPath: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config-path",
        abstract: "Show configuration file path."
    )

    func run() {
        let path = IT2Config.configPath()
        print("Configuration file: \(path)")
        if FileManager.default.fileExists(atPath: path) {
            print("Status: File exists")
        } else {
            print("Status: File not found")
            print("Create it with: touch \(path)")
        }
    }
}

struct ConfigReload: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config-reload",
        abstract: "Reload configuration file."
    )

    func run() {
        let config = IT2Config.load()
        print("Configuration reloaded")

        if !config.profiles.isEmpty {
            print("Loaded \(config.profiles.count) profiles: \(config.profiles.keys.sorted().joined(separator: ", "))")
        }
        if !config.aliases.isEmpty {
            print("Loaded \(config.aliases.count) aliases: \(config.aliases.keys.sorted().joined(separator: ", "))")
        }
    }
}

// MARK: - Helpers

/// Split a string respecting shell-style quoting (like Python's shlex.split).
func shellSplit(_ s: String) -> [String] {
    var args: [String] = []
    var current = ""
    var inSingleQuote = false
    var inDoubleQuote = false
    var escape = false

    for ch in s {
        if escape {
            current.append(ch)
            escape = false
            continue
        }
        if ch == "\\" && !inSingleQuote {
            escape = true
            continue
        }
        if ch == "'" && !inDoubleQuote {
            inSingleQuote.toggle()
            continue
        }
        if ch == "\"" && !inSingleQuote {
            inDoubleQuote.toggle()
            continue
        }
        if ch == " " && !inSingleQuote && !inDoubleQuote {
            if !current.isEmpty {
                args.append(current)
                current = ""
            }
            continue
        }
        current.append(ch)
    }
    if !current.isEmpty {
        args.append(current)
    }
    return args
}
