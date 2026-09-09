//
//  SSHEndpointException.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

enum SSHEndpointException: LocalizedError {
    case connectionClosed
    case fileNotFound
    case internalError  // e.g., non-decodable data from fetch
    case transferCanceled

    var errorDescription: String? {
        get {
            switch self {
            case .connectionClosed:
                return String(localized: "SSHEndpointException.ConnectionClosed", defaultValue: "Connection closed", comment: "Error shown when an SSH connection is closed")
            case .fileNotFound:
                return String(localized: "SSHEndpointException.FileNotFound", defaultValue: "File not found", comment: "Error shown when a file cannot be found on an SSH endpoint")
            case .internalError:
                return String(localized: "SSHEndpointException.InternalError", defaultValue: "Internal error", comment: "Error shown when an internal SSH endpoint error occurs")
            case .transferCanceled:
                return String(localized: "SSHEndpointException.TransferCanceled", defaultValue: "File transfer canceled", comment: "Error shown when an SSH file transfer is canceled")
            }
        }
    }
}

