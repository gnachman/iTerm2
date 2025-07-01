//
//  SSHReconnectionInfo.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

struct SSHReconnectionInfo: Codable {
    var sshargs: String
    var initialDirectory: String?
    var boolargs: String
}

@objc(iTermSSHReconnectionInfo)
class SSHReconnectionInfoObjC: NSObject {
    private(set) var state: SSHReconnectionInfo
    init(_ info: SSHReconnectionInfo) {
        self.state = info
    }

    @objc(initWithData:) init?(serialized: Data) {
        do {
            state = try JSONDecoder().decode(SSHReconnectionInfo.self, from: serialized)
        } catch {
            return nil
        }
    }

    @objc var sshargs: String { state.sshargs }
    @objc var initialDirectory: String? { state.initialDirectory }
    @objc var boolargs: String { state.boolargs }

    @objc var serialized: Data {
        return try! JSONEncoder().encode(state)
    }
}
