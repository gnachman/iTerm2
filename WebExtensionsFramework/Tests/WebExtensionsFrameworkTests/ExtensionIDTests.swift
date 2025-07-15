// ExtensionIDTests.swift
// Tests for ExtensionID functionality

import XCTest
@testable import WebExtensionsFramework

final class ExtensionIDTests: XCTestCase {
    
    func testDefaultInitializer() {
        // Test default initializer creates path-based ID
        let id = ExtensionID()
        XCTAssertFalse(id.stringValue.isEmpty)
        XCTAssertEqual(id.stringValue.count, 32)
        XCTAssertTrue(id.stringValue.allSatisfy { char in
            char >= "a" && char <= "p"
        })
    }
    
    func testStringInitializer() {
        // Test valid path-based ID string
        let validPathId = "abcdefghijklmnopabcdefghijklmnop"
        let id = ExtensionID(validPathId)
        XCTAssertNotNil(id)
        XCTAssertEqual(id?.stringValue, validPathId)
        
        // Test invalid string formats
        let invalidId1 = ExtensionID("not-a-valid-format")
        XCTAssertNil(invalidId1)
        
        let invalidId2 = ExtensionID("abcdefghijklmnopq") // contains 'q'
        XCTAssertNil(invalidId2)
        
        let invalidId3 = ExtensionID("abcdefghijklmnopabcdefghijklmno") // too short
        XCTAssertNil(invalidId3)
    }
    
    func testPathBasedInitializer() {
        // Test path-based initializer
        let baseURL = URL(fileURLWithPath: "/users/george/extensions")
        let extensionLocation = "my-extension"
        
        let id = ExtensionID(baseDirectory: baseURL, extensionLocation: extensionLocation)
        
        // Should be 32 characters long
        XCTAssertEqual(id.stringValue.count, 32)
        
        // Should only contain letters a-p
        XCTAssertTrue(id.stringValue.allSatisfy { char in
            char >= "a" && char <= "p"
        })
        
        // Should be consistent for same inputs
        let id2 = ExtensionID(baseDirectory: baseURL, extensionLocation: extensionLocation)
        XCTAssertEqual(id.stringValue, id2.stringValue)
        
        // Should be different for different inputs
        let id3 = ExtensionID(baseDirectory: baseURL, extensionLocation: "different-extension")
        XCTAssertNotEqual(id.stringValue, id3.stringValue)
    }
    
    func testPathBasedIDMapping() {
        // Test that hex digits are properly remapped
        let baseURL = URL(fileURLWithPath: "/test")
        let id = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        
        // Verify no numeric digits or letters beyond 'p'
        XCTAssertTrue(id.stringValue.allSatisfy { char in
            char >= "a" && char <= "p"
        })
        
        // Verify it doesn't contain characters that could make it look like an IP
        XCTAssertFalse(id.stringValue.contains("."))
        XCTAssertFalse(id.stringValue.contains(":"))
        XCTAssertFalse(id.stringValue.contains("0"))
        XCTAssertFalse(id.stringValue.contains("1"))
        XCTAssertFalse(id.stringValue.contains("2"))
        XCTAssertFalse(id.stringValue.contains("3"))
        XCTAssertFalse(id.stringValue.contains("4"))
        XCTAssertFalse(id.stringValue.contains("5"))
        XCTAssertFalse(id.stringValue.contains("6"))
        XCTAssertFalse(id.stringValue.contains("7"))
        XCTAssertFalse(id.stringValue.contains("8"))
        XCTAssertFalse(id.stringValue.contains("9"))
    }
    
    func testStringConversion() {
        // Test path-based string conversion
        let baseURL = URL(fileURLWithPath: "/test")
        let pathId = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        let convertedPathId = ExtensionID(pathId.stringValue)
        XCTAssertNotNil(convertedPathId)
        XCTAssertEqual(convertedPathId?.stringValue, pathId.stringValue)
        
        // Test invalid string
        let invalidId = ExtensionID("invalid-format")
        XCTAssertNil(invalidId)
    }
    
    func testCodable() {
        // Test path-based ID encoding/decoding
        let baseURL = URL(fileURLWithPath: "/test")
        let originalId = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try! encoder.encode(originalId)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedId = try! decoder.decode(ExtensionID.self, from: data)
        
        XCTAssertEqual(originalId.stringValue, decodedId.stringValue)
    }
    
    func testHashable() {
        let baseURL = URL(fileURLWithPath: "/test")
        let id1 = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        let id2 = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        let id3 = ExtensionID(baseDirectory: baseURL, extensionLocation: "different")
        
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
        XCTAssertEqual(id1.hashValue, id2.hashValue)
    }
    
    func testDescriptionAndStringConvertible() {
        let baseURL = URL(fileURLWithPath: "/test")
        let id = ExtensionID(baseDirectory: baseURL, extensionLocation: "test")
        
        XCTAssertEqual(id.description, id.stringValue)
        XCTAssertEqual(String(id), id.stringValue)
    }
}