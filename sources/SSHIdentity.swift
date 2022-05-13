//
//  SSHIdentity.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/22.
//

import Foundation

class SSHIdentity: NSObject {
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
                hostport = hostname + ":\(port)"
            }
            if let username = username {
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

    @objc var commandLine: String {
        return state.commandLine
    }

    @objc var json: Data {
        return try! JSONEncoder().encode(state)
    }

    @objc var compactDescription: String {
        return state.compactDescription
    }

    override var debugDescription: String {
        return state.debugDescription
    }

    override var description: String {
        return state.debugDescription
    }

    @objc
    init?(_ json: Data?) {
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
    init(_ hostname: String, username: String?, port: Int) {
        state = State(hostname: hostname, username: username, port: port)
    }

    override func isEqual(to object: Any?) -> Bool {
        guard let other = object as? SSHIdentity else {
            return false
        }
        return other.state == state
    }
}
