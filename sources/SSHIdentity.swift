//
//  SSHIdentity.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/22.
//

import Foundation

public class SSHIdentity: NSObject, Codable {
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
        
        let hostname: String
        let username: String?
        let port: Int

        var commandLine: String {
            let parts = [username.map { "-l \($0)" },
                         port == 22 ? nil : "-p \(port)",
                         "\(hostname)"].compactMap { $0 }
            return parts.joined(separator: " ")
        }
    }
    private let state: State

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

    @objc public  var hostname: String {
        return state.hostname
    }

    public var stringIdentifier: String {
        return state.compactDescription
    }

    public init?(stringIdentifier: String)  {
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
        state = State(hostname: String(stringIdentifier[at.upperBound..<colon.lowerBound]),
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
    public init(_ hostname: String, username: String?, port: Int) {
        state = State(hostname: hostname, username: username, port: port)
    }

    public override func isEqual(to object: Any?) -> Bool {
        guard let other = object as? SSHIdentity else {
            return false
        }
        return other.state == state
    }
}
