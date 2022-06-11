//
//  FileProviderServiceError.swift
//  FileProviderService
//
//  Created by George Nachman on 6/5/22.
//

import Foundation

public enum FileProviderServiceError: Error, Codable, LocalizedError {
    public static let errorHeader = "X-API-Error"

    internal enum Values: String, Codable {
        case internalError
    }

    internal enum CodingKeys: String, CodingKey {
        case value
        case entry
        case identifier
        case errorDomain
        case errorCode
        case errorLocalizedDescription
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Values.self, forKey: .value) {
        case .internalError:
            self = .internalError
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .internalError:
            try container.encode(Values.internalError, forKey: .value)
        }
    }

    case internalError

    public var errorDescription: String? {
        return "\(self)"
    }

    public func toPresentableError() -> NSError {
        switch self {
        case .internalError:
            return NSError(domain: NSCocoaErrorDomain,
                           code: NSXPCConnectionReplyInvalid,
                           userInfo: [NSUnderlyingErrorKey: self])
        }
    }
}


