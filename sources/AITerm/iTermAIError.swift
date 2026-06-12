//
//  iTermAIError.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

@objc public class iTermAIError: NSObject {
    @objc static let domain = "com.iterm2.ai"
    @objc(iTermAIErrorType) public enum ErrorType: Int, Codable {
        case generic = 0
        case requestTooLarge = 1
    }
}

public struct AIError: LocalizedError, CustomStringConvertible, CustomNSError, Codable {
    public internal(set) var message: String
    public internal(set) var type = iTermAIError.ErrorType.generic

    public init(_ message: String) {
        self.message = message
    }

    public init(_ message: String, type: iTermAIError.ErrorType) {
        self.message = message
        self.type = type
    }

    public var errorDescription: String? {
        message
    }

    public var description: String {
        message
    }

    var localizedDescription: String {
        message
    }

    static var requestTooLarge: AIError {
        AIError("AI token limit exceeded because the conversation reached its maximum length", type: .requestTooLarge)
    }

    static func wrapping(error: Error, context: String) -> AIError {
        return AIError(context + ": " + error.localizedDescription)
    }

    public static var errorDomain: String { iTermAIError.domain }
    public var errorCode: Int { type.rawValue }
}
