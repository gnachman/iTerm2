//
//  JSONSchema.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

struct JSONSchema: Codable {
    var type = "object"
    var properties: [String: Property] = [:]
    var required: [String] = []
    var additionalProperties: Bool?  // Required by Responses API but not documented.

    struct Property: Codable {
        var type: String  // e.g., "string"
        var description: String?  // Documentation
        var `enum`: [String]?
    }

    init<T>(for instance: T,
            descriptions: [String: String]) {
        let mirror = Mirror(reflecting: instance)

        for child in mirror.children {
            guard let label = child.label else { continue }

            let type = Swift.type(of: child.value)
            let fieldType = JSONSchema.extractFieldType(type)

            var property = Property(type: fieldType)
            property.description = descriptions[label]

            properties[label] = property
            if !(child.value is AnyOptional.Type) {
                required.append(label)
            }
        }
    }

    private static func extractFieldType(_ type: Any.Type) -> String {
        if type == Int.self || type == UInt.self || type == Int8.self || type == UInt8.self ||
            type == Int16.self || type == UInt16.self || type == Int32.self || type == UInt32.self ||
            type == Int64.self || type == UInt64.self || type == Float.self || type == Double.self {
            return "number"
        } else if type == String.self {
            return "string"
        } else if type == Bool.self {
            return "boolean"
        } else if let optionalType = type as? AnyOptional.Type {
            return extractFieldType(optionalType.wrappedType)
        } else {
            return "object"
        }
    }

}

