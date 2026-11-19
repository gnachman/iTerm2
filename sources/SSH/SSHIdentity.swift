//
//  SSHIdentity.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/22.
//

import Foundation

/// Where ssh config sends a connection to a host.
public struct SSHDestination: Equatable {
    /// The host name to connect to: the configured HostName, or the host itself.
    public var hostname: String
    /// From the config. Nil when it gives none or when an explicit one was passed in.
    public var user: String?
    /// From the config. Nil when it gives none or when an explicit one was passed in.
    public var port: Int?

    public init(hostname: String, user: String? = nil, port: Int? = nil) {
        self.hostname = hostname
        self.user = user
        self.port = port
    }
}

public protocol SSHHostnameFinder: AnyObject {
    /// Where `host` leads. `user` and `port` are explicit ones (ssh's -l and -p), which win
    /// over the config and can affect which blocks match.
    func sshDestination(forHost host: String, user: String?, port: Int?) -> SSHDestination
}

extension SSHHostnameFinder {
    func sshHostname(forHost host: String) -> String {
        return sshDestination(forHost: host, user: nil, port: nil).hostname
    }
}

public class SSHIdentity: NSObject, Codable {
    @objc static let localhost = SSHIdentity(host: Host.current().localizedName ?? "My Mac",
                                             hostname: "localhost",
                                             username: nil,
                                             port: 0)

    static func ==(lhs: SSHIdentity, rhs: SSHIdentity) -> Bool {
        return lhs.state == rhs.state
    }

    private struct State: Equatable, Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            let hostport = hostname + ":\(port)"
            if let username = username {
                return username + "@" + hostport
            }
            return hostport
        }

        var compactDescription: String {
            let hostport: String
            if port == 22 {
                hostport = hostname
            } else {
                hostport = hostname + " port \(port)"
            }
            if let username = username, username != NSUserName() {
                return username + "@" + hostport
            }
            return hostport
        }

        let host: String
        let hostname: String
        let username: String?
        let port: Int

        /// ssh arguments that reach this host again. They name the host as typed, not the
        /// resolved hostname, so ssh applies that host's config block again (IdentityFile,
        /// host key checking and so on, which hosts written by Lima and the like rely on).
        var commandLine: String {
            let parts = [username.map { "-l \($0)" },
                         port == 22 ? nil : "-p \(port)",
                         host.isEmpty ? hostname : host].compactMap { $0 }
            return parts.joined(separator: " ")
        }
    }
    private let state: State

    @objc
    var isLocalhost: Bool {
        return host == Self.localhost.host
    }

    @objc public var commandLine: String {
        return state.commandLine
    }

    @objc public var json: Data {
        return try! JSONEncoder().encode(state)
    }

    @objc public var compactDescription: String {
        return state.compactDescription
    }

    public override var debugDescription: String {
        return state.debugDescription
    }

    public override var description: String {
        return state.debugDescription
    }

    var host: String {
        state.host
    }

    @objc public var hostname: String {
        return state.hostname
    }

    @objc public var username: String? {
        return state.username
    }

    @objc public var port: Int {
        return state.port
    }

    public var stringIdentifier: String {
        return state.compactDescription
    }

    /// Whether `identifier` may be what stringIdentifier was for this identity before iTerm2
    /// read ssh config the way ssh does. The hostname could differ: it was the host as typed
    /// when only an included or matched block gives it a HostName, and a HostName kept its
    /// capitalization where it is now lowercased. The user and port could differ too: they
    /// came only from the command line, so a user or port the config supplies was absent
    /// (no user, port 22).
    func mayHaveHadStringIdentifier(_ identifier: String) -> Bool {
        let marker = "\u{1}"
        for username in Set([state.username, nil]) {
            for port in Set([state.port, 22]) {
                let template = State(host: state.host, hostname: marker, username: username, port: port)
                    .compactDescription
                guard let range = template.range(of: marker) else {
                    continue
                }
                let prefix = template[..<range.lowerBound]
                let suffix = template[range.upperBound...]
                guard identifier.count > prefix.count + suffix.count,
                      identifier.hasPrefix(prefix),
                      identifier.hasSuffix(suffix) else {
                    continue
                }
                let hostname = String(identifier.dropFirst(prefix.count).dropLast(suffix.count))
                if [state.hostname, state.host].contains(where: {
                    $0.caseInsensitiveCompare(hostname) == .orderedSame
                }) {
                    return true
                }
            }
        }
        return false
    }

    public init?(stringIdentifier: String, hostnameFinder: SSHHostnameFinder)  {
        guard let at = stringIdentifier.range(of: "@"),
              let colon = stringIdentifier.range(of: ":") else {
            return nil
        }
        guard at.lowerBound < colon.lowerBound else {
            return nil
        }
        let username = stringIdentifier[..<at.lowerBound]
        guard let port = Int(stringIdentifier[colon.upperBound...]) else {
            return nil
        }
        let host = String(stringIdentifier[at.upperBound..<colon.lowerBound])
        state = State(host: host,
                      hostname: hostnameFinder.sshHostname(forHost: host),
                      username: username.isEmpty ? nil : String(username),
                      port: port)
    }

    @objc
    public init?(_ json: Data?) {
        guard let data = json else {
            return nil
        }
        if let state = try? JSONDecoder().decode(State.self, from: data) {
            self.state = state
        } else {
            return nil
        }
    }

    @objc
    public init(host: String, hostname: String, username: String?, port: Int) {
        state = State(host: host, hostname: hostname, username: username, port: port)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SSHIdentity else {
            return false
        }
        return other.state == state
    }

    public override func isEqual(to object: Any?) -> Bool {
        guard let other = object as? SSHIdentity else {
            return false
        }
        return other.state == state
    }

    // We make an effort to figure out the real hostname, but there's no guarantee that we succeed.
    // For example, the user could do `it2ssh foo` where `foo` is only defined in /etc/hosts.
    // The remote host could report itself as either `foo` or `foo.example.com`. In the case where
    // they are both `foo` it's wise to match state.host (derived from the it2ssh command line)
    // against the `host` parameter (derived from shell integration control sequences from the
    // remote host).
    public func matches(host: String?,  // Host of remote file
                        user: String?,
                        discoveredHostname: String?) -> Bool {  // `gethostname -f` of remote host
        DLog("matches: host=\(host.d) user=\(user.d) discoveredHostname=\(discoveredHostname.d) state.host=\(state.host) state.username=\(state.username.d)")

        guard (hostname == host || state.host == host || (discoveredHostname == host && host != nil)) else {
            return false
        }
        if state.username == nil {
            return true
        }
        return state.username == user
    }

    override public var hash: Int {
        var combined = UInt(0)
        combined = iTermCombineHash(UInt(bitPattern: state.host.hashValue), combined)
        combined = iTermCombineHash(UInt(bitPattern: state.hostname.hashValue), combined)
        combined = iTermCombineHash(UInt(bitPattern: state.username.hashValue), combined)
        combined = iTermCombineHash(UInt(bitPattern: state.port.hashValue), combined)
        return Int(bitPattern: combined)
    }
}

extension SSHIdentity {
    @objc
    var displayName: String {
        let hostport: String
        if state.port == 22 || state.port == 0 {
            hostport = state.host
        } else {
            hostport = state.host + ":\(state.port)"
        }
        if let username = state.username, username != NSUserName() {
            return username + "@" + hostport
        }
        return hostport
    }
}

// MARK: - UserDefaults Support
extension SSHIdentity {
    /// Convert the SSHIdentity to a dictionary that can be stored in UserDefaults
    @objc public func toUserDefaultsObject() -> [String: Any] {
        var dict: [String: Any] = [
            "host": state.host,
            "hostname": state.hostname,
            "port": state.port
        ]

        if let username = state.username {
            dict["username"] = username
        }

        return dict
    }

    /// Create an SSHIdentity from a UserDefaults object (dictionary)
    @objc public convenience init?(userDefaultsObject: Any?) {
        guard let dict = userDefaultsObject as? [String: Any],
              let host = dict["host"] as? String,
              let hostname = dict["hostname"] as? String,
              let port = dict["port"] as? Int else {
            return nil
        }

        let username = dict["username"] as? String

        self.init(host: host, hostname: hostname, username: username, port: port)
    }
}

@MainActor
extension SSHIdentity {
    var endpoint: SSHEndpoint? {
        if isLocalhost {
            return LocalhostEndpoint.instance
        }
        return ConductorRegistry.instance[self].first
    }

    @objc
    var homeDirectory: String? {
        return endpoint?.homeDirectory
    }
}

extension SSHIdentity {
    func scpPath(filename: String) -> SCPPath {
        let scppath = SCPPath()
        scppath.path = filename
        scppath.hostname = host
        scppath.username = username
        return scppath
    }
}
