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
                return "Connection closed"
            case .fileNotFound:
                return "File not found"
            case .internalError:
                return "Internal error"
            case .transferCanceled:
                return "File transfer canceled"
            }
        }
    }
}

