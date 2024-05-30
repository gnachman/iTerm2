//
//  CommandURLBuilder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/24.
//

import Foundation

@objc(iTermCommandURLBuilder)
class CommandURLBuilderObjC: NSObject {
    @objc
    static func url(mark: VT100ScreenMarkReading,
                    absLine: Int64,
                    dataSource: PTYTextViewDataSource?) -> URL? {
        guard let dataSource, let command = mark.command else {
            return nil
        }
        var builder = CommandURLBuilder(command: command)
        let offset = dataSource.totalScrollbackOverflow()

        if let line = Int32(from: absLine - offset), line >= 0 {
            builder.directory = dataSource.workingDirectory(onLine: line)
            builder.remoteHost = dataSource.remoteHost(onLine: line)
        }

        return builder.url
    }
}


struct CommandURLBuilder {
    var command: String
    var directory: String?
    var remoteHost: VT100RemoteHostReading?

    var url: URL? {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "/command"
        components.queryItems = [ URLQueryItem(name: "c", value: command) ]
        if let directory {
            components.queryItems?.append(URLQueryItem(name: "d", value: directory))
        }
        if let remoteHost, !remoteHost.isLocalhost {
            if let username = remoteHost.username {
                components.user = username
            }
            if let hostname = remoteHost.hostname {
                components.host = hostname
            }
        }
        return components.url
    }
}

extension Int32 {
    init?(from int64Value: Int64) {
        if int64Value >= Int64(Int32.min) && int64Value <= Int64(Int32.max) {
            self.init(int64Value)
        } else {
            return nil
        }
    }
}
