//
//  iTermHostnameFinder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

import Foundation

class iTermHostnameFinder: SSHHostnameFinder {
    private let configFiles: () -> [SSHConfigFile]

    /// `configFiles` supplies the ssh config files to read, in precedence order. It is called
    /// on each lookup, and the files are reread each time, so edits take effect immediately.
    init(configFiles: @escaping () -> [SSHConfigFile] = { iTermSSHHelpers.defaultConfigFiles() }) {
        self.configFiles = configFiles
    }

    func sshHostname(forHost host: String) -> String {
        let resolver = iTermSSHHelpers.resolver(forFiles: configFiles())
        return resolver.hostConfig(forHost: host, user: nil, port: nil).hostname ?? host
    }
}
