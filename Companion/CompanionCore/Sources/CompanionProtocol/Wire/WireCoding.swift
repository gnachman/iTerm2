//
//  WireCoding.swift
//  CompanionCore
//
//  Shared JSON coders for the companion protocol. Both peers must agree on the
//  date strategy or every Date would round-trip incorrectly, so the coders are
//  defined once here and used on both sides.
//

import Foundation

public enum WireCoding {
    /// Encoder for application envelopes. millisecondsSince1970 keeps dates
    /// compact and unambiguous across the iOS and macOS clocks.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }
}
