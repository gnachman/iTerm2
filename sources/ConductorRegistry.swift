//
//  ConductorRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import FileProviderService

enum SSHEndpointException: Error {
    case connectionClosed
    case fileNotFound
    case internalError  // e.g., non-decodable data from fetch
}

protocol SSHEndpoint: AnyObject {
    @available(macOS 11.0, *)
    func listFiles(_ path: String) async throws -> [String]

    @available(macOS 11.0, *)
    func download(_ path: String) async throws -> Data

    var sshIdentity: SSHIdentity { get }
}

@available(macOS 11.0, *)
class ConductorRegistry: SSHFileGatewayDelegate {
    static let instance = ConductorRegistry()
    private var endpoints: [String: WeakBox<SSHEndpoint>] = [:]
    init() {
        SSHFileGateway.instance.start(delegate: self)
    }

    func register(_ endpoint: SSHEndpoint) {
        endpoints[endpoint.sshIdentity.stringIdentifier] = WeakBox(endpoint)
    }

    func handleSSHFileRequest(_ request: ExtensionToMainAppPayload.Event.Kind) async -> MainAppToExtensionPayload.Event.Kind {
        logger.debug("handleSSHFileRequest: \(request.debugDescription, privacy: .public)")
        switch request {
        case .invalid:
            return .invalidConnection
        case .listConnections:
            return .connectionList(endpoints.compactMap({ (identifier, box) in
                guard let endpoint = box.value else {
                    return nil
                }
                logger.debug("handleSSHFileRequest: found \(endpoint.sshIdentity.debugDescription, privacy: .public)")
                return SSHConnectionIdentifier(endpoint.sshIdentity)
            }))
        case .listFiles(connection: let connection, path: let path):
            guard let endpoint = self.endpoint(connection) else {
                logger.debug("handleSSHFileRequest: endpoint not found. Return .invalidConnection")
                return .invalidConnection
            }
            do {
                let files = try await endpoint.listFiles(path)
                logger.debug("handleSSHFileRequest: got file list: \(files.debugDescription, privacy: .public)")
                return .fileList(.success(files.map {
                    SSHListFilesItem($0)
                }))
            } catch let error as FetchError {
                logger.debug("handleSSHFileRequest: failed with \(error.localizedDescription, privacy: .public)")
                return .fileList(.failure(error))
            } catch {
                logger.debug("handleSSHFileRequest: failed with non-FetchError \(error.localizedDescription, privacy: .public)")
                return .fileList(.failure(.other))
            }
        case .fetch(connection: let connection, path: let path):
            guard let endpoint = self.endpoint(connection) else {
                return .invalidConnection
            }
            do {
                let content = try await endpoint.download(path)
                return .fetch(.success(content))
            } catch let error as FetchError {
                return .fetch(.failure(error))
            } catch {
                return .fetch(.failure(.other))
            }
        }
    }

    private func endpoint(_ connection: SSHConnectionIdentifier) -> SSHEndpoint? {
        return endpoints[connection.stringIdentifier]?.value
    }
}

