import Foundation

/// Protocol for types that can be represented in Chrome extension messaging
public protocol BrowserExtensionJSONRepresentable {
    var browserExtensionEncodedValue: BrowserExtensionEncodedValue { get }
}

/// Struct to represent undefined values
public struct BrowserExtensionUndefined: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        return .undefined
    }
}

/// Extensions for common types
extension Optional: BrowserExtensionJSONRepresentable where Wrapped: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        if let value = self {
            return value.browserExtensionEncodedValue
        } else {
            return .undefined
        }
    }
}

extension String: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            // This should never happen for a String
            return .undefined
        }
    }
}

extension Int: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            // This should never happen for an Int
            return .undefined
        }
    }
}

extension Bool: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            // This should never happen for a Bool
            return .undefined
        }
    }
}

extension Double: BrowserExtensionJSONRepresentable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            // This should never happen for a Double
            return .undefined
        }
    }
}

extension Array: BrowserExtensionJSONRepresentable where Element: Codable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            return .undefined
        }
    }
}

extension Dictionary: BrowserExtensionJSONRepresentable where Key == String, Value: Codable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(self)
        } catch {
            return .undefined
        }
    }
}

// For Codable types
extension BrowserExtensionJSONRepresentable where Self: Codable {
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            return try .json(jsonObject)
        } catch {
            return .undefined
        }
    }
}
