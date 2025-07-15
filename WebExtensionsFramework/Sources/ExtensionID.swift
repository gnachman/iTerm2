// ExtensionID.swift
// Represents a unique identifier for browser extensions

import Foundation
import CryptoKit

/// Unique identifier for browser extensions
public struct ExtensionID: Hashable, Codable, Sendable {
    /// The string representation of the extension ID
    public let stringValue: String
    
    /// Initialize with a string value
    /// - Parameter stringValue: The string representation of the ID
    public init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    /// Initialize with a new path-based ID using default paths
    /// This is a convenience initializer that generates a unique ID
    public init() {
        // Generate a unique temporary path for default initialization
        self.init(baseDirectory: URL(fileURLWithPath: "/tmp/extensions"), extensionLocation: UUID().uuidString)
    }
    
    /// Initialize from a base directory and relative extension location
    /// - Parameters:
    ///   - baseDirectory: The base directory containing extensions
    ///   - extensionLocation: The relative path to the extension folder
    public init(baseDirectory: URL, extensionLocation: String) {
        // 1. Normalize & UTF-8-encode the absolute path to the extension folder
        let absolutePath = baseDirectory.appendingPathComponent(extensionLocation).standardized.path
        let pathData = absolutePath.data(using: .utf8)!
        
        // 2. SHA-256 that path string, but only keep the first 16 bytes
        let hash = SHA256.hash(data: pathData)
        let first16Bytes = hash.prefix(16)
        
        // 3. Hex-encode those 16 bytes into 32 hex characters (lower-case)
        let hexString = first16Bytes.map { String(format: "%02x", $0) }.joined()
        
        // 4. Remap each hex digit (0–f) to the letters a–p (so the final ID never looks like an IP)
        let remappedString = hexString.map { char in
            switch char {
            case "0": return "a"
            case "1": return "b"
            case "2": return "c"
            case "3": return "d"
            case "4": return "e"
            case "5": return "f"
            case "6": return "g"
            case "7": return "h"
            case "8": return "i"
            case "9": return "j"
            case "a": return "k"
            case "b": return "l"
            case "c": return "m"
            case "d": return "n"
            case "e": return "o"
            case "f": return "p"
            default: return String(char) // Should never happen with hex string
            }
        }.joined()
        
        self.stringValue = remappedString
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
        // Only accept path-based IDs (32 chars, only letters a-p)
        if description.count == 32 && description.allSatisfy({ char in
            char >= "a" && char <= "p"
        }) {
            self.stringValue = description
            return
        }
        
        // Invalid format
        return nil
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