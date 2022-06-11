//
//  SSHFileTypes.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/7/22.
//

import Foundation
import FileProviderService
import FileProvider

// Relative or absolute path.
struct FilePath: Codable, Hashable, CustomDebugStringConvertible {
    // I chose String because relative paths in URLs are complicated. I didn't choose Data because
    // the file provider API requires that filenames be strings.
    let path: String

    static let root = FilePath("/")!

    var data: Data {
        return path.data(using: .utf8)!
    }

    var debugDescription: String {
        path
    }

    init?(_ string: String) {
        if string.isEmpty {
            return nil
        }
        path = string
    }

    init(_ url: URL) {
        precondition(url.isFileURL)
        path = url.path
    }

    func appendingPathComponent(_ component: FilePath) -> FilePath {
        return appendingPathComponent(component.path)
    }

    func appendingPathComponent(_ component: String) -> FilePath {
        return FilePath((path as NSString).appendingPathComponent(component) as String)!
    }

    var lastPathComponent: String {
        return (path as NSString).lastPathComponent
    }

    var deletingLastPathComponent: FilePath {
        return FilePath((path as NSString).deletingLastPathComponent as String)!
    }
}

// Absolute path to a file vended by ssh, including the connection on which you can find it.
struct SSHFilePath: CustomDebugStringConvertible {
    let connection: SSHConnectionIdentifier
    let path: FilePath

    init?(_ stringIdentifier: String) {
        let parts = stringIdentifier.components(separatedBy: " ")
        guard parts.count == 2 else {
            return nil
        }
        guard let connection = SSHConnectionIdentifier(stringIdentifier: stringIdentifier),
              let path = FilePath(parts[1]) else {
            return nil
        }
        self.connection = connection
        self.path = path
    }

    // Uniquely codes the ssh server and file path.
    var stringIdentifier: String {
        return [connection.stringIdentifier, path.data.base64EncodedString()].joined(separator: " ")
    }

    init(connection: SSHConnectionIdentifier,
         path: FilePath) {
        self.connection = connection
        self.path = path
    }

    var parentIdentifier: NSFileProviderItemIdentifier {
        if path == FilePath.root {
            return NSFileProviderItemIdentifier.rootContainer
        }
        let parentPath = SSHFilePath(connection: connection,
                                     path: path.deletingLastPathComponent)
        return NSFileProviderItemIdentifier(sshFilePath: parentPath)
    }

    func appendingPathComponent(_ component: FilePath) -> SSHFilePath {
        return SSHFilePath(connection: connection, path: path.appendingPathComponent(component))
    }

    func appendingPathComponent(_ component: String) -> SSHFilePath {
        guard let componentPath = FilePath(component) else {
            return self
        }
        return SSHFilePath(connection: connection,
                           path: path.appendingPathComponent(componentPath))
    }

    var debugDescription: String {
        return connection.debugDescription + ":" + path.debugDescription
    }
}

