//
//  SecretServer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/22.
//

import Foundation

@objc(iTermSecretServer)
class SecretServer: NSObject {
    enum Exception: Error {
        case badAddress
        case bindFailed
        case listenFailed
    }
    private let socketURL: URL
    private let unixSocket: iTermSocket
    private var secrets = Set<String>()
    private static let defaultURLBase = URL(fileURLWithPath: FileManager.default.homeDirectoryDotDir())
    private static let defaultURL = defaultURLBase.appendingPathComponents(["sockets", "secrets"])
    @objc static let instance = SecretServer(socketURL: defaultURL)
    @objc init?(socketURL: URL) {
        self.socketURL = socketURL
        guard let socket = iTermSocket.unixDomain() else {
            return nil
        }
        unixSocket = socket
    }

    @objc func listen() throws {
        do {
            try FileManager.default.createDirectory(atPath: socketURL.deletingLastPathComponent().path,
                                                    withIntermediateDirectories: true,
                                                    attributes: [ FileAttributeKey.posixPermissions: S_IRWXU ])
        } catch {
            DLog("\(error)")
        }
        guard let address = iTermSocketAddress(path: socketURL.path) else {
            throw Exception.badAddress
        }
        unlink(socketURL.path)
        guard unixSocket.bind(to: address) else {
            throw Exception.bindFailed
        }
        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard unixSocket.listen(withBacklog: 5, accept: { [weak self] fd, clientAddress, euid in
            self?.didAccept(fd)
        }) else {
            throw Exception.listenFailed
        }
    }

    @objc func check(_ secret: String) -> Bool {
        if secrets.contains(secret) {
            secrets.remove(secret)
            return true
        }
        return false
    }

    private func didAccept(_ fd: Int32) {
        autoreleasepool {
            let fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard let secret = makeSecret() else {
                return
            }
            secrets.insert(secret)
            try? ObjCTry {
                fileHandle.write(secret.data(using: .utf8)!)
            }
        }
    }

    private func makeSecret() -> String? {
        let count = 16
        var bytes = [Int8](repeating: 0, count: count)

        // Fill bytes with secure random data
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            count,
            &bytes
        )

        // A status of errSecSuccess indicates success
        if status == errSecSuccess {
            let data = Data(bytes: bytes, count: count)
            return (data as NSData).it_hexEncoded()
        }

        return nil
    }
}

extension URL {
    func appendingPathComponents<T>(_ components: T) -> URL where T: Collection, T.Element == String {
        guard let first = components.first else {
            return self
        }
        return appendingPathComponent(first).appendingPathComponents(components.dropFirst())
    }
}
