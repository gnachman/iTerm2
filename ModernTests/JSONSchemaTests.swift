//
//  JSONSchemaTests.swift
//  iTerm2 ModernTests
//
//  Pins the documented asymmetry between JSONSchema(rawJSON:) on the
//  encode side and init(from:) on the decode side. rawJSON-built
//  schemas are outbound-only by design (no round-trip), but the
//  encoder must still produce a well-formed top-level JSON object
//  carrying every entry from the raw dict, not a wrapper around
//  {type, properties, required}.
//

import XCTest
@testable import iTerm2SharedARC

final class JSONSchemaTests: XCTestCase {

    func test_rawJSON_encodesAsSingleValueContainer() throws {
        let schema = JSONSchema(rawJSON: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "age": ["type": "integer"],
            ],
            "required": ["name"],
            "additionalProperties": false,
        ])
        let data = try JSONEncoder().encode(schema)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(dict["type"] as? String, "object")
        XCTAssertEqual(dict["required"] as? [String], ["name"])
        XCTAssertEqual(dict["additionalProperties"] as? Bool, false)
        let props = try XCTUnwrap(dict["properties"] as? [String: Any])
        XCTAssertEqual(props.keys.sorted(), ["age", "name"])
    }

    func test_decodeIfPresent_missingFields_defaultsApplied() throws {
        // Empty object: the strict init(from:) is intentionally lenient
        // on missing fields via decodeIfPresent + defaults. Pin that
        // contract so a future "drop the override" refactor doesn't
        // silently break stored schemas that were emitted before any
        // given field existed.
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONSchema.self, from: data)
        XCTAssertEqual(decoded.type, "object")
        XCTAssertTrue(decoded.properties.isEmpty)
        XCTAssertEqual(decoded.required, [])
        XCTAssertNil(decoded.additionalProperties)
    }
}
