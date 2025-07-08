import Foundation

/// Represents special values that can't be JSON-encoded
public enum BrowserExtensionSpecialValue: String, Codable {
    case null = "null"
    case undefined = "undefined"
}

/// Represents an encoded value that can be passed through Chrome extension messaging
/// Handles null, undefined, and JSON-serializable values
public struct BrowserExtensionEncodedValue: Codable {
    /// For null and undefined values
    public var value: BrowserExtensionSpecialValue?
    /// For all other values (JSON-encoded)
    public var json: String?
    
    public init(value: BrowserExtensionSpecialValue) {
        self.value = value
        self.json = nil
    }
    
    public init(json: String) {
        self.value = nil
        self.json = json
    }
    
    /// Convenience initializer from raw message body value (for decoding from JavaScript)
    public init(_ messageValue: Any?) throws {
        enum BrowserExtensionEncodedValueError: Error {
            case invalidFormat(String)
        }
        
        guard let dict = messageValue as? [String: Any] else {
            throw BrowserExtensionEncodedValueError.invalidFormat("Expected dictionary for encoded value")
        }
        
        if let valueString = dict["value"] as? String {
            guard let specialValue = BrowserExtensionSpecialValue(rawValue: valueString) else {
                throw BrowserExtensionEncodedValueError.invalidFormat("Unknown special value: \(valueString)")
            }
            self.value = specialValue
            self.json = nil
        } else if let jsonString = dict["json"] as? String {
            self.value = nil
            self.json = jsonString
        } else {
            throw BrowserExtensionEncodedValueError.invalidFormat("Invalid encoded value: missing both value and json fields")
        }
    }
    
    /// Create an encoded value representing null
    public static var null: BrowserExtensionEncodedValue {
        return BrowserExtensionEncodedValue(value: .null)
    }
    
    /// Create an encoded value representing undefined
    public static var undefined: BrowserExtensionEncodedValue {
        return BrowserExtensionEncodedValue(value: .undefined)
    }
    
    /// Create an encoded value from any JSON-serializable object
    public static func json(_ object: Any) throws -> BrowserExtensionEncodedValue {
        enum BrowserExtensionEncodedValueError: Error {
            case invalidFormat(String)
        }
        
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw BrowserExtensionEncodedValueError.invalidFormat("Failed to convert JSON data to string")
        }
        return BrowserExtensionEncodedValue(json: jsonString)
    }
    
    /// Decode back to the original value
    public func decode() throws -> Any? {
        if let value = self.value {
            switch value {
            case .null:
                return NSNull()
            case .undefined:
                return nil
            }
        }
        
        if let json = self.json {
            enum BrowserExtensionEncodedValueError: Error {
                case invalidFormat(String)
            }
            
            guard let data = json.data(using: .utf8) else {
                throw BrowserExtensionEncodedValueError.invalidFormat("Failed to convert JSON string to data")
            }
            return try JSONSerialization.jsonObject(with: data, options: [])
        }
        
        enum BrowserExtensionEncodedValueError: Error {
            case invalidFormat(String)
        }
        throw BrowserExtensionEncodedValueError.invalidFormat("Invalid encoded value: missing both value and json fields")
    }
    
    /// Validate that the encoded value is properly formed
    public func validate() throws {
        let hasValue = (value != nil)
        let hasJson = (json != nil)
        
        enum BrowserExtensionEncodedValueError: Error {
            case invalidFormat(String)
        }
        
        // Must have exactly one field
        if hasValue && hasJson {
            throw BrowserExtensionEncodedValueError.invalidFormat("Invalid encoded value: has both value and json fields")
        }
        if !hasValue && !hasJson {
            throw BrowserExtensionEncodedValueError.invalidFormat("Invalid encoded value: missing both value and json fields")
        }
    }
}