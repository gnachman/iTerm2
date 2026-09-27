//
//  CompanionError.swift
//  CompanionCore
//

import Foundation

/// An error reported by the mac in response to a client message, or surfaced
/// locally by the transport. Codable so it can travel on the wire.
public struct CompanionError: Codable, Equatable, Error {
    public enum Code: String, Codable, Equatable {
        case unknownChat
        case unknownSession
        case badRequest
        case notPaired
        case internalError
        case unsupported
        /// AI is turned off on the paired mac, so an AI-only request (chat, agent,
        /// orchestrator) cannot be served. Session browsing, live video, and
        /// keyboard input still work. Sent only to a phone at
        /// aiDecouplingRevision or newer (an older phone cannot decode this string
        /// and would drop the frame, so the bridge sends it .internalError instead).
        case aiUnavailable
    }
    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}
