//
//  iTermHostnameFinder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

import Foundation

class iTermHostnameFinder: SSHHostnameFinder {
    private let configs: () -> [NMSSHConfig]

    /// `configs` supplies the parsed ssh config files in precedence order. It is called on
    /// each lookup so edits to the files take effect without restarting.
    init(configs: @escaping () -> [NMSSHConfig] = { iTermSSHHelpers.configs() }) {
        self.configs = configs
    }

    func sshHostname(forHost host: String) -> String {
        for config in configs() {
            if let hostConfig = config.hostConfig(forHost: host),
               let hostname = hostConfig.hostname {
                return hostname
            }
        }
        return host
    }
}
