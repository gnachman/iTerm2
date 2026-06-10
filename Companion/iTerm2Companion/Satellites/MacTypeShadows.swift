//
//  MacTypeShadows.swift
//  iTerm2 Companion
//
//  Wire-compatible stand-ins for Mac types embedded in the shared chat model
//  that cannot (or need not) compile on iOS. Each has the same name and Codable
//  shape as the Mac original; payload the phone does not model is captured as
//  JSONValue so a round-trip re-encodes losslessly.
//

import Foundation

/// Mac original: a class bridged to ObjC (iTermLocatedString) carrying the
/// selected text plus its grid coordinates. The phone only needs the text.
/// Wire shape: { "string": String, "gridCoords": ... }.
struct iTermCodableLocatedString: Codable {
    private var raw: JSONValue

    /// The located text (the part the phone displays).
    var string: String {
        if case .object(let dict) = raw, case .string(let value)? = dict["string"] {
            return value
        }
        return ""
    }

    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}
