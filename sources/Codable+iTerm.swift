//
//  Codable+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/12/25.
//

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
            return
        }
        if let b = try? container.decode(Bool.self) {
            value = b
            return
        }
        if let i = try? container.decode(Int.self) {
            value = i
            return
        }
        if let d = try? container.decode(Double.self) {
            value = d
            return
        }
        if let s = try? container.decode(String.self) {
            value = s
            return
        }
        if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
            return
        }
        if let dict = try? container.decode([String: AnyCodable].self) {
            var d = [String: Any]()
            for (key, any) in dict {
                d[key] = any.value
            }
            value = d
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case _ as NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            let wrapped = arr.map { AnyCodable($0) }
            try container.encode(wrapped)
        case let dict as [String: Any]:
            let wrapped = dict.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unsupported JSON value"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}
