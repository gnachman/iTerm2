//
//  ParsedSSHArguments.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/22.
//

import Foundation

struct ParsedSSHArguments: Codable, CustomDebugStringConvertible {
    // The string that matched a Host: entry in ~/.ssh/config, or the hostname
    // otherwise. Those entries can have wildcards or be aliases, in which case
    // this would be the string that matched the wildcard or the alias.
    let host: String

    // The actual hostname we're connected to.
    let hostname: String
    let username: String?
    let port: Int?
    private(set) var paramArgs = ParamArgs()
    private(set) var commandArgs = [String]()

    enum CodingKeys: String, CodingKey {
        case host, hostname, username, port, paramArgs, commandArgs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hostname = try container.decode(String.self, forKey: .hostname)
        self.hostname = hostname
        // host was added after 3.5.0beta26; for backward compatibility assume it was equal to hostname.
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? hostname
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port)
        self.paramArgs = try container.decode(ParamArgs.self, forKey: .paramArgs)
        self.commandArgs = try container.decode([String].self, forKey: .commandArgs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(username, forKey: .username)
        try container.encode(port, forKey: .port)
        try container.encode(paramArgs, forKey: .paramArgs)
        try container.encode(commandArgs, forKey: .commandArgs)
    }

    var debugDescription: String {
        return "recognized params: \(paramArgs.debugDescription); username=\(String(describing: username)); host=\(host); hostname=\(hostname); port=\(String(describing: port)); command=\(commandArgs.joined(separator: ", "))"
    }

    struct ParamArgs: Codable, OptionSet, CustomDebugStringConvertible {
        var rawValue: Set<OptionValue>

        enum Option: String, Codable {
            case loginName = "l"
            case port = "p"
        }

        struct OptionValue: Codable, Equatable, Hashable {
            let option: Option
            let value: String
        }

        init?(_ option: String, value: String) {
            guard let opt = Option(rawValue: option) else {
                return nil
            }
            rawValue = Set([OptionValue(option: opt, value: value)])
        }

        init() {
            rawValue = Set<OptionValue>()
        }

        init(rawValue: Set<OptionValue>) {
            self.rawValue = rawValue
        }

        typealias RawValue = Set<OptionValue>

        mutating func formUnion(_ other: __owned ParsedSSHArguments.ParamArgs) {
            rawValue.formUnion(other.rawValue)
        }

        mutating func formIntersection(_ other: ParsedSSHArguments.ParamArgs) {
            rawValue.formIntersection(other.rawValue)
        }

        mutating func formSymmetricDifference(_ other: __owned ParsedSSHArguments.ParamArgs) {
            rawValue.formSymmetricDifference(other.rawValue)
        }

        func hasOption(_ option: Option) -> Bool {
            return rawValue.contains { ov in
                ov.option == option
            }
        }

        func value(for option: Option) -> String? {
            return rawValue.first { ov in
                ov.option == option
            }?.value
        }

        var debugDescription: String {
            return rawValue.map { "-\($0.option.rawValue) \($0.value)" }.sorted().joined(separator: " ")
        }
    }

    var identity: SSHIdentity {
        return SSHIdentity(host: host, hostname: hostname, username: username, port: port ?? 22)
    }

    init(_ string: String, booleanArgs boolArgsString: String, hostnameFinder: SSHHostnameFinder) {
        let booleanArgs = Set(Array<String.Element>(boolArgsString).map { String($0) })
        guard let args = (string as NSString).componentsInShellCommand() else {
            host = ""
            hostname = ""
            username = nil
            port = nil
            return
        }
        var destination: String? = nil
        var optionsAllowed = true
        var preferredUser: String? = nil
        var preferredPort: Int? = nil
        var i = 0
        while i < args.count {
            defer { i += 1 }
            let arg = args[i]
            if destination != nil && !arg.hasPrefix("-") {
                // ssh localhost /bin/bash
                //               ^^^^^^^^^
                //               parsing this arg. After this point arguments are to /bin/bash, not to ssh client.
                // Note that in "ssh localhost -t /bin/bash", "-t" is an argument to the ssh client.
                optionsAllowed = false
            }
            if optionsAllowed && arg.hasPrefix("-") {
                if arg == "--" {
                    optionsAllowed = false
                    continue
                }
                let splitArg = Array(arg)
                if splitArg.count == 1 {
                    // Invalid argument of "-"
                    continue
                }
                if splitArg.dropFirst().contains(where: { booleanArgs.contains(String($0)) }) {
                    // Is boolean arg, ignore.
                    continue
                }

                if Array(arg).count != 2 {
                    // All unrecognized single-letter args I guess
                    continue
                }

                i += 1
                if i >= args.count {
                    // Missing param. Just ignore it.
                    continue
                }
                guard let paramArg = ParamArgs(String(arg.dropFirst()), value: args[i]) else {
                    continue
                }
                paramArgs.formUnion(paramArg)
                continue
            }
            if destination == nil {
                if let url = URL(string: arg), url.scheme == "ssh" {
                    if let user = url.user, let host = url.host {
                        preferredUser = user
                        destination = host
                    } else if let host = url.host {
                        destination = host
                    }
                    if !paramArgs.hasOption(.port), let urlPort = url.port {
                        preferredPort = urlPort
                    }
                }
                destination = arg
                continue
            }
            commandArgs.append(arg)
        }

        // ssh's behavior seems to be to glue arguments together with spaces and reparse them.
        // ["ssh", "example.com", "cat", "file with space"]   executes ["cat", "file", "with", "space"]
        // ["ssh", "example.com", "cat", "'file with space"'] executes ["cat", "file with space"]

        commandArgs = (commandArgs.joined(separator: " ") as NSString).componentsInShellCommand()
        host = destination ?? ""
        hostname = hostnameFinder.sshHostname(forHost: host)
        username = preferredUser ?? paramArgs.value(for: .loginName)
        port = preferredPort ?? paramArgs.value(for: .port).map { Int($0) } ?? 22
    }
}
