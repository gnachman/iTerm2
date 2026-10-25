//
//  SSHEndpointException.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

enum SSHEndpointException: LocalizedError {
    case connectionClosed
    // The remote host said the file does not exist (ENOENT).
    case fileNotFound
    // The remote host reported some other failure, such as a permission error.
    case fileOperationFailed
    case internalError  // e.g., non-decodable data from fetch
    case transferCanceled

    var errorDescription: String? {
        get {
            switch self {
            case .connectionClosed:
                return String(localized: "SSHEndpointException.ConnectionClosed", defaultValue: "Connection closed", comment: "Error shown when an SSH connection is closed")
            case .fileNotFound:
                return String(localized: "SSHEndpointException.FileNotFound", defaultValue: "File not found", comment: "Error shown when a file cannot be found on an SSH endpoint")
            case .fileOperationFailed:
                return String(localized: "SSHEndpointException.FileOperationFailed", defaultValue: "The file operation failed on the remote host", comment: "Error shown when a file operation on an SSH endpoint fails for a reason other than the file not existing, such as a permission error")
            case .internalError:
                return String(localized: "SSHEndpointException.InternalError", defaultValue: "Internal error", comment: "Error shown when an internal SSH endpoint error occurs")
            case .transferCanceled:
                return String(localized: "SSHEndpointException.TransferCanceled", defaultValue: "File transfer canceled", comment: "Error shown when an SSH file transfer is canceled")
            }
        }
    }
}

