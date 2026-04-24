//
//  iTermHostnameFinder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

import Foundation

class iTermHostnameFinder: SSHHostnameFinder {
    func sshHostname(forHost host: String) -> String {
        for config in iTermSSHHelpers.configs() {
            if let hostConfig = config.hostConfig(forHost: host),
               let hostname = hostConfig.hostname {
                return hostname
            }
        }
        return host
    }
}
