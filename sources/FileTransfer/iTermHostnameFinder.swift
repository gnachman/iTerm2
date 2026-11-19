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

    /// The config's user and port are reported only along with a HostName. That's when hosts
    /// can share a hostname, as the ones Lima, OrbStack, Colima and Vagrant write (all
    /// 127.0.0.1, told apart by Port), and they keep such hosts' identities apart. Other
    /// hosts are already distinct by name, so their identities stay as they were.
    func sshDestination(forHost host: String, user: String?, port: Int?) -> SSHDestination {
        let resolver = iTermSSHHelpers.resolver(forFiles: configFiles())
        let config = resolver.hostConfig(forHost: host,
                                         user: user,
                                         port: port.map { NSNumber(value: $0) })
        guard let hostname = config.hostname else {
            return SSHDestination(hostname: host)
        }
        return SSHDestination(hostname: hostname,
                              user: user == nil ? config.user : nil,
                              port: port == nil ? config.port?.intValue : nil)
    }
}
