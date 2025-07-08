//
//  JSONExtensions.swift
//  WebExtensionsFramework
//
//  Created by Assistant on 7/7/25.
//

import Foundation

extension Encodable {
    /// Convert any Encodable value to a JSON string
    func toJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BrowserExtensionError.internalError("Failed to convert JSON data to string")
        }
        return string
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Convert a dictionary to a JSON string
    func toJSONString() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: self, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw BrowserExtensionError.internalError("Failed to convert JSON data to string")
        }
        return string
    }
}

extension Array where Element == Any {
    /// Convert an array to a JSON string
    func toJSONString() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: self, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw BrowserExtensionError.internalError("Failed to convert JSON data to string")
        }
        return string
    }
}