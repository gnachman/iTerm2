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
    // The remote host said permission was denied (EPERM or EACCES).
    case permissionDenied
    // The remote host said part of the path is not a folder (ENOTDIR).
    case notADirectory
    // The remote host reported some other failure.
    case fileOperationFailed
    case internalError  // e.g., non-decodable data from fetch
    case transferCanceled

    // Exit codes from file_error in framer.py.
    static let framerPermissionDeniedCode: Int32 = 1
    static let framerFileNotFoundCode: Int32 = 2
    static let framerNotADirectoryCode: Int32 = 3

    // The error a framer file command's exit code stands for, or nil if it succeeded.
    static func forFramerExitCode(_ code: Int32) -> SSHEndpointException? {
        if code < 0 {
            return .connectionClosed
        }
        switch code {
        case 0:
            return nil
        case framerPermissionDeniedCode:
            return .permissionDenied
        case framerFileNotFoundCode:
            return .fileNotFound
        case framerNotADirectoryCode:
            return .notADirectory
        default:
            return .fileOperationFailed
        }
    }

    // The reason to show when an SSH Integration download or upload fails with `error`. A
    // permission error says what the transfer needed permission to do.
    static func transferFailureReason(for error: Error, isDownload: Bool) -> String {
        if let error = error as? SSHEndpointException, error == .permissionDenied {
            if isDownload {
                return String(localized: "SSHEndpointException.DownloadPermissionDenied",
                              defaultValue: "The file couldn’t be read because you don’t have permission to read it on the remote host.",
                              comment: "Reason shown when an SSH Integration download fails because the remote file's permissions do not allow reading it")
            }
            return String(localized: "SSHEndpointException.UploadPermissionDenied",
                          defaultValue: "The file couldn’t be saved because you don’t have permission to write to the destination folder on the remote host.",
                          comment: "Reason shown when an SSH Integration upload fails because the remote destination folder's permissions do not allow writing to it")
        }
        return error.localizedDescription
    }

    var errorDescription: String? {
        get {
            switch self {
            case .connectionClosed:
                return String(localized: "SSHEndpointException.ConnectionClosed", defaultValue: "Connection closed", comment: "Error shown when an SSH connection is closed")
            case .fileNotFound:
                return String(localized: "SSHEndpointException.FileNotFound", defaultValue: "File not found", comment: "Error shown when a file cannot be found on an SSH endpoint")
            case .permissionDenied:
                return String(localized: "SSHEndpointException.PermissionDenied", defaultValue: "You don’t have permission to access this file on the remote host.", comment: "Error shown when a file operation on an SSH endpoint fails because the permissions of the remote file or folder do not allow it")
            case .notADirectory:
                return String(localized: "SSHEndpointException.NotADirectory", defaultValue: "Part of the path on the remote host is not a folder.", comment: "Error shown when a file operation on an SSH endpoint fails because a component of the remote path is a file rather than a folder")
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
