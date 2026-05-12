//
//  JSONSchema.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

enum JSONSchemaAnyCodable: Codable, Equatable {
    static let placeholder = JSONSchemaAnyCodable.null
    case string(String)
    case boolean(Bool)
    case array([JSONSchemaAnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()

        if single.decodeNil() {
            self = .null
            return
        }

        if let s = try? single.decode(String.self) {
            self = .string(s)
            return
        }

        if let b = try? single.decode(Bool.self) {
            self = .boolean(b)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var result: [JSONSchemaAnyCodable] = []
            while unkeyed.isAtEnd == false {
                if try unkeyed.decodeNil() {
                    result.append(.null)
                    continue
                }
                if let s = try? unkeyed.decode(String.self) {
                    result.append(.string(s))
                    continue
                }
                if let b = try? unkeyed.decode(Bool.self) {
                    result.append(.boolean(b))
                    continue
                }
                if let sub = try? unkeyed.decode([JSONSchemaAnyCodable].self) {
                    result.append(.array(sub))
                    continue
                }
                throw DecodingError.typeMismatch(
                    JSONSchemaAnyCodable.self,
                    DecodingError.Context(codingPath: unkeyed.codingPath,
                                          debugDescription: "Unsupported element in array")
                )
            }
            self = .array(result)
            return
        }

        throw DecodingError.typeMismatch(
            JSONSchemaAnyCodable.self,
            DecodingError.Context(codingPath: decoder.codingPath,
                                  debugDescription: "Expected string, boolean, array, or null")
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .boolean(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a {
                try c.encode(v)
            }
        }
    }
}

enum JSONSchemaStringNumberOrStringArray: Codable, Equatable {
    static let placeholder = JSONSchemaStringNumberOrStringArray.string("")
    case string(String)
    case number(Int)
    case stringArray([String])

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()

        if let s = try? single.decode(String.self) {
            self = .string(s)
            return
        }

        if let i = try? single.decode(Int.self) {
            self = .number(i)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var result: [String] = []
            while unkeyed.isAtEnd == false {
                if let s = try? unkeyed.decode(String.self) {
                    result.append(s)
                    continue
                }
                throw DecodingError.typeMismatch(
                    JSONSchemaStringNumberOrStringArray.self,
                    DecodingError.Context(codingPath: unkeyed.codingPath,
                                          debugDescription: "Unsupported element in array")
                )
            }
            self = .stringArray(result)
            return
        }

        throw DecodingError.typeMismatch(
            JSONSchemaStringNumberOrStringArray.self,
            DecodingError.Context(codingPath: decoder.codingPath,
                                  debugDescription: "Expected string, number, or strin garray")
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .number(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .stringArray(let a):
            var c = encoder.unkeyedContainer()
            for v in a {
                try c.encode(v)
            }
        }
    }
}
struct JSONSchema: Codable {
    var type = "object"
    var properties: [String: Property] = [:]
    var required: [String] = []
    var additionalProperties: Bool?  // Required by Responses API but not documented.

    // When set, encoding emits this dictionary as the whole schema and
    // ignores the struct fields. Lets callers ship a hand-built JSON
    // Schema (nested objects, enums, etc.) that the reflection init
    // cannot express. The orchestrator's 16-tool surface uses this path.
    private var rawJSONStorage: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties
    }

    init(rawJSON: [String: Any]) {
        var storage = [String: AnyCodable]()
        for (key, value) in rawJSON {
            storage[key] = AnyCodable(value)
        }
        self.rawJSONStorage = storage
    }

    // Strict decode: a JSON schema that doesn't decode cleanly is a bug,
    // and silently substituting an empty-object schema would tell the LLM
    // "any input is valid" for a tool whose contract is actually broken.
    // Surface decode errors at the call site instead.
    //
    // Note: this decoder is intentionally NOT symmetric with init(rawJSON:);
    // schemas built via the raw-dict initializer are encoded via the
    // singleValueContainer path in encode(to:) and are designed to be
    // outbound-only (they don't round-trip through this keyed decoder).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
        properties = try container.decodeIfPresent([String: Property].self,
                                                   forKey: .properties) ?? [:]
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
        additionalProperties = try container.decodeIfPresent(Bool.self,
                                                              forKey: .additionalProperties)
    }

    func encode(to encoder: Encoder) throws {
        if let rawJSONStorage {
            var single = encoder.singleValueContainer()
            try single.encode(rawJSONStorage)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(properties, forKey: .properties)
        try container.encode(required, forKey: .required)
        try container.encodeIfPresent(additionalProperties,
                                       forKey: .additionalProperties)
    }

    struct Property: Codable {
        var type: AnyCodable?  // e.g., "string"
        var description: String?  // Documentation
        var `enum`: [String]?  // ["red", "black"]
        var items: AnyCodable?  // {"type": "string"} or { type: "object", properties: { … }, required: […], additionalProperties: false }
        var additionalProperties: Bool?
    }

    init<T>(for instance: T,
            descriptions: [String: String]) {
        let mirror = Mirror(reflecting: instance)

        for child in mirror.children {
            guard let label = child.label else { continue }

            let type = Swift.type(of: child.value)
            let fieldType = JSONSchema.extractFieldType(type, value: child.value)

            var property = Property(type: AnyCodable(fieldType))
            property.description = descriptions[label]
            if (child.value as? JSONSchemaAnyCodable) == JSONSchemaAnyCodable.placeholder {
                property.`type` = AnyCodable(["string", "boolean", "null", "array"])
                property.items = AnyCodable(["type": "string"])
            } else if child.value as? JSONSchemaStringNumberOrStringArray == JSONSchemaStringNumberOrStringArray.placeholder {
                property.type = AnyCodable([
                    "string",
                    "number",
                    "array",
                  ])
                property.items = AnyCodable(["type": "string"])
            }
            if fieldType == "array" {
                guard let label = child.label else {
                    continue
                }
                let array = child.value as! [Any]
                // Empty arrays are the default value for any `var foo: [T] = []`
                // property. We can't reflect element type from an empty array;
                // declare it as an untyped array (items omitted) and let the
                // caller layer on the proper element schema if needed.
                guard !array.isEmpty else {
                    property.items = AnyCodable("string")
                    properties[label] = property
                    if !(child.value is AnyOptional.Type)
                        && Mirror(reflecting: child.value).displayStyle != .optional {
                        required.append(label)
                    }
                    continue
                }
                let elementType = JSONSchema.extractFieldType(Swift.type(of: array[0]),
                                                              value: array[0])
                if elementType == "object" {
                    var innerDescriptions = [String: String]()
                    let prefix = label + "."
                    for entry in descriptions {
                        if entry.key.hasPrefix(prefix) {
                            innerDescriptions[String(entry.key.dropFirst(prefix.count))] = entry.value
                        }
                    }
                    var nested = JSONSchema(for: array[0], descriptions: innerDescriptions)
                    nested.additionalProperties = false
                    let json = try! JSONEncoder().encode(nested)
                    let obj = try! JSONSerialization.jsonObject(with: json, options: []) as! [String: Any]
                    property.items = AnyCodable(obj)
                } else {
                    property.items = AnyCodable(elementType)
                }
            }
            properties[label] = property
            if !(child.value is AnyOptional.Type) && Mirror(reflecting: child.value).displayStyle != .optional {
                required.append(label)
            }
        }
    }

    private static func extractFieldType<T>(_ type: Any.Type, value: T) -> String {
        if type == Int.self || type == UInt.self || type == Int8.self || type == UInt8.self ||
            type == Int16.self || type == UInt16.self || type == Int32.self || type == UInt32.self ||
            type == Int64.self || type == UInt64.self || type == Float.self || type == Double.self {
            return "number"
        } else if type == String.self {
            return "string"
        } else if type == Bool.self {
            return "boolean"
        } else if let optionalType = type as? AnyOptional.Type {
            return extractFieldType(optionalType.wrappedType, value: value)
        } else if value is Array<Any> {
            return "array"
        } else {
            return "object"
        }
    }

}
