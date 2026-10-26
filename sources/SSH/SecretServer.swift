//
//  SecretServer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/22.
//

import Foundation

// The result of redeeming a secret.
@objc(iTermSecretClaim)
class SecretClaim: NSObject {
    // The nearest ancestors of the process that fetched the secret, nearest first.
    // When it2ssh fetched it locally, it2ssh is among them.
    @objc let clientAncestors: [SSHClientProcessIdentity]
    // The modes of the fetching process's controlling tty when it fetched the secret.
    // it2ssh fetches it before it starts ssh, so these are the modes ssh will change
    // (F-460).
    @objc let ttyModes: TTYModes?

    init(clientAncestors: [SSHClientProcessIdentity], ttyModes: TTYModes?) {
        self.clientAncestors = clientAncestors
        self.ttyModes = ttyModes
    }
}

@objc(iTermSecretServer)
class SecretServer: NSObject {
    enum Exception: Error {
        case badAddress
        case bindFailed
        case listenFailed
    }
    private let socketURL: URL
    private let unixSocket: iTermSocket
    // Accessed from the accept queue and the main thread.
    private let mutex = Mutex()
    // Maps each outstanding secret to what was learned about the process that fetched it.
    private var secrets = [String: SecretClaim]()
    private static let defaultURLBase = URL(fileURLWithPath: FileManager.default.homeDirectoryDotDir() ?? NSHomeDirectory())
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
            RLog("\(error)")
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

    // Returns nil if the secret is not valid. Each secret can be claimed only once.
    @objc func claim(_ secret: String) -> SecretClaim? {
        return mutex.sync {
            return secrets.removeValue(forKey: secret)
        }
    }

    private func peerPID(_ fd: Int32) -> pid_t {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0 else {
            DLog("LOCAL_PEERPID failed: \(String(cString: strerror(errno)))")
            return 0
        }
        return pid
    }

    private func didAccept(_ fd: Int32) {
        autoreleasepool {
            let fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard let secret = makeSecret() else {
                return
            }
            // Record the peer's ancestry and tty modes now, while it is still connected.
            let pid = peerPID(fd)
            let ancestors = SSHClientProcessLocator.shared.ancestors(ofPeer: pid)
            let ttyModes = TTYModes.ofControllingTTY(ofProcessID: pid)
            DLog("Secret requested by a process with ancestors \(ancestors) on \(ttyModes?.path ?? "no tty")")
            let claim = SecretClaim(clientAncestors: ancestors, ttyModes: ttyModes)
            mutex.sync {
                secrets[secret] = claim
            }
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
