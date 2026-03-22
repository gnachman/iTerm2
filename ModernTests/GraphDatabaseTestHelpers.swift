//
//  GraphDatabaseTestHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 3/17/26.
//

import Foundation
@testable import iTerm2SharedARC

/// Test helper for creating test data and records
class GraphDatabaseTestHelpers {

    /// Creates test data of a specified size
    static func createTestData(size: Int) -> Data {
        var data = Data(count: size)
        // Fill with random-ish data to ensure it compresses realistically
        for i in 0..<size {
            data[i] = UInt8((i * 17 + 13) % 256)
        }
        return data
    }

    /// Creates a dictionary suitable for encoding as node data
    static func createTestPOD(withDataSize dataSize: Int = 0, extraKeys: [String: Any] = [:]) -> [String: Any] {
        var pod: [String: Any] = [
            "testKey": "testValue",
            "testNumber": 42
        ]
        if dataSize > 0 {
            pod["largeData"] = createTestData(size: dataSize)
        }
        for (key, value) in extraKeys {
            pod[key] = value
        }
        return pod
    }

    /// Helper to wait for async operations with a timeout
    static func waitForCondition(timeout: TimeInterval = 5.0, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}

/// Extension to help with testing graph encoder records
extension iTermEncoderGraphRecord {
    /// Creates a simple test record with the given parameters
    static func testRecord(
        key: String,
        identifier: String,
        generation: Int = 0,
        rowid: NSNumber? = nil,
        pod: [String: Any] = [:],
        children: [iTermEncoderGraphRecord] = []
    ) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs(
            pod as [String: Any],
            graphs: children,
            generation: generation,
            key: key,
            identifier: identifier,
            rowid: rowid
        )
    }
}

/// Extension to help with testing graph encoders
extension iTermGraphEncoder {
    /// Creates a root encoder for testing
    static func testEncoder(generation: Int = 1) -> iTermGraphEncoder {
        return iTermGraphEncoder(
            key: "",
            identifier: "",
            generation: generation
        )
    }
}
