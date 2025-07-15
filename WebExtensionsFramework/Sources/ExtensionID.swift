// ExtensionID.swift
// Represents a unique identifier for browser extensions

import Foundation

/// Unique identifier for browser extensions
public struct ExtensionID: Hashable, Codable, Sendable {
    /// The string representation of the extension ID
    public let stringValue: String
    
    /// Initialize with a string value
    /// - Parameter stringValue: The string representation of the ID
    public init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    /// Initialize with a new random UUID-based ID
    public init() {
        self.stringValue = UUID().uuidString
    }
    
    /// Initialize from a UUID (for compatibility)
    /// - Parameter uuid: The UUID to convert to an ExtensionID
    public init(uuid: UUID) {
        self.stringValue = uuid.uuidString
    }
    
    /// Initialize from a UUID string (for compatibility)
    /// - Parameter uuidString: The UUID string to convert to an ExtensionID
    public init?(uuidString: String) {
        guard UUID(uuidString: uuidString) != nil else {
            return nil
        }
        self.stringValue = uuidString
    }
}

// MARK: - String Conversion
extension ExtensionID: CustomStringConvertible {
    public var description: String {
        return stringValue
    }
}

extension ExtensionID: LosslessStringConvertible {
    public init?(_ description: String) {
        // For now, validate that it's a valid UUID string
        guard UUID(uuidString: description) != nil else {
            return nil
        }
        self.stringValue = description
    }
}

// MARK: - Codable
extension ExtensionID {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let extensionID = ExtensionID(string) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                    debugDescription: "Invalid extension ID: \(string)")
            )
        }
        self = extensionID
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}