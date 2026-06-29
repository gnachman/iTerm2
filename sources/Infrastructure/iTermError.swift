//
//  iTermError.swift
//  iTerm2
//
//  Created by George Nachman on 8/15/25.
//

@objc(iTermError) public class iTermErrorObjC: NSObject {
    @objc static let domain = "com.iterm2.generic"
    @objc(iTermErrorType) public enum ErrorType: Int, Codable {
        case generic = 0
        case requestTooLarge = 1
    }
}

struct iTermError: LocalizedError, CustomStringConvertible, CustomNSError, Codable {
    public internal(set) var message: String
    public internal(set) var type = iTermErrorObjC.ErrorType.generic

    public init(_ error: Error, adding message: String) {
        self.message = message + ": " + error.localizedDescription
        if let other = error as? iTermError {
            self.type = other.type
        }
    }

    public init(_ message: String) {
        self.message = message
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

    public static var errorDomain: String { iTermErrorObjC.domain }
    public var errorCode: Int { type.rawValue }
}

