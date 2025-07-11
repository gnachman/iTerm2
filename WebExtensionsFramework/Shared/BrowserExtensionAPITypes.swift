import Foundation

// Shared types used by both the API generator and generated protocols

// Can represent any JSON object.
public struct AnyJSONCodable: Codable, BrowserExtensionJSONRepresentable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.init(())
        } else if let bool = try? container.decode(Bool.self) {
            self.init(bool)
        } else if let int = try? container.decode(Int.self) {
            self.init(int)
        } else if let double = try? container.decode(Double.self) {
            self.init(double)
        } else if let string = try? container.decode(String.self) {
            self.init(string)
        } else if let array = try? container.decode([AnyJSONCodable].self) {
            self.init(array.map { $0.value })
        } else if let dictionary = try? container.decode([String: AnyJSONCodable].self) {
            self.init(dictionary.mapValues { $0.value })
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyJSONCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is Void:
            try container.encodeNil()
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyJSONCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyJSONCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyJSONCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
    
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        // Handle the special cases that AnyJSONCodable supports
        switch value {
        case is Void:
            return .undefined
        case is NSNull:
            return .null
        default:
            do {
                // Use existing encoding logic from AnyJSONCodable
                let data = try JSONEncoder().encode(self)
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                return try .json(jsonObject)
            } catch {
                return .undefined
            }
        }
    }
}

public struct PlatformInfo: Codable, BrowserExtensionJSONRepresentable {
    public var os: String
    public var arch: String
    public var nacl_arch: String
    
    public init(os: String, arch: String, nacl_arch: String) {
        self.os = os
        self.arch = arch
        self.nacl_arch = nacl_arch
    }
}

public struct NoObjectPlaceholder: Equatable {
    public static let instance = NoObjectPlaceholder()
}
