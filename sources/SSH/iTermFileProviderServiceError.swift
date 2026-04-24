//
//  iTermFileProviderServiceError.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

public enum iTermFileProviderServiceError: Error, Codable, CustomDebugStringConvertible {
    case notFound(String)
    case unknown(String)
    case notAFile(String)
    case permissionDenied(String)
    case internalError(String)  // e.g., URL with contents not readable
    case disconnected

    public var debugDescription: String {
        switch self {
        case .notFound(let item):
            return "<notFound \(item)>"
        case .unknown(let reason):
            return "<unknown \(reason)>"
        case .notAFile(let file):
            return "<notAFile \(file)>"
        case .permissionDenied(let file):
            return "<permissionDenied \(file)>"
        case .internalError(let reason):
            return "<internalError \(reason)>"
        case .disconnected:
            return "<disconnected>"
        }
    }

    public static func wrap<T>(_ closure: () throws -> T) throws -> T {
        do {
            return try closure()
        } catch let error as iTermFileProviderServiceError {
            throw error
        } catch {
            throw iTermFileProviderServiceError.internalError(error.localizedDescription)
        }
    }
}

