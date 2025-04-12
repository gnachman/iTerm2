//
//  PathMark.swift
//  iTerm2
//
//  Created by George Nachman on 4/10/25.
//

import Foundation

@objc(iTermPathMarkReading)
protocol PathMarkReading: AnyObject, iTermMarkProtocol {
    var path: String { get }
    var isLocalhost: Bool { get }
    var hostname: String? { get }
    var username: String? { get }
}

@objc(iTermPathMark)
class PathMark: iTermMark, PathMarkReading {
    private struct State: Codable {
        enum CodingKeys: String, CodingKey {
            case path
            case hostname
            case username
            case isLocalhost
        }

        var path: String
        var hostname: String?
        var username: String?
        var isLocalhost: Bool

        init(path: String,
             hostname: String?,
             username: String?,
             isLocalhost: Bool) {
            self.path = path
            self.hostname = hostname
            self.username = username
            self.isLocalhost = isLocalhost
        }

        init(_ dict: [AnyHashable: Any]) {
            path = dict[CodingKeys.path.rawValue] as? String ?? ""
            hostname = dict[CodingKeys.hostname.rawValue] as? String
            username = dict[CodingKeys.username.rawValue] as? String
            isLocalhost = dict[CodingKeys.isLocalhost.rawValue] as? Bool ?? true
        }

        func update(_ dict: inout [AnyHashable: Any]) {
            dict[CodingKeys.path.rawValue] = path
            if let hostname { dict[CodingKeys.hostname.rawValue] = hostname }
            if let username { dict[CodingKeys.username.rawValue] = username }
            dict[CodingKeys.isLocalhost.rawValue] = isLocalhost
        }
    }
    private let state: State
    @objc var path: String { state.path }
    @objc var hostname: String? { state.hostname }
    @objc var username: String? { state.username }
    @objc var isLocalhost: Bool { state.isLocalhost }

    override var description: String {
        return "<PathMark \(username.d)@\(hostname.d):\(path) local=\(isLocalhost)>"
    }

    override var shortDebugDescription: String {
        return description
    }

    @objc
    init(remoteHost: VT100RemoteHostReading?, path: String) {
        state = State(path: path,
                      hostname: remoteHost?.hostname,
                      username: remoteHost?.username,
                      isLocalhost: remoteHost?.isLocalhost ?? true)
        super.init()
    }

    required init!(dictionary dict: [AnyHashable : Any]!) {
        state = State(dict)
        super.init(dictionary: dict)
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        var dict = super.dictionaryValue()!
        state.update(&dict)
        return dict
    }
}
