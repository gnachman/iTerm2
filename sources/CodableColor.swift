//
//  CodableColor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/7/21.
//

import Foundation

// This is a little more involved than you might expect because encoding an sRGB color with
// NSKeyedArchiver (which is very common in this app) uses 5k of space. Therefore, an efficient path
// exists to encode these in 7 bytes instead :)
struct CodableColor: Codable {
    struct ColorNotDecodable: Error { }
    enum CodingKeys: String, CodingKey {
        case hexString
        case fallback
    }

    let color: NSColor

    init(_ color: NSColor) {
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let hexString = try? container.decode(String.self, forKey: .hexString) {
            guard let color = NSColor.init(fromHexString: hexString) else {
                throw ColorNotDecodable()
            }
            self.color = color
            return
        }
        let data = try container.decode(Data.self, forKey: .fallback)
        let keyedUnarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        guard let color = NSColor(coder: keyedUnarchiver) else {
            throw ColorNotDecodable()
        }
        self.color = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if Self.hexEncodableColorSpaces.contains(color.it_colorSpace) {
            try container.encode(color.hexString(), forKey: .hexString)
        } else  {
            let keyedArchiver = NSKeyedArchiver(requiringSecureCoding: true)
            color.encode(with: keyedArchiver)
            try container.encode(keyedArchiver.encodedData, forKey: .fallback)
        }
    }

    static var hexEncodableColorSpaces: [NSColorSpace?] = [NSColorSpace.sRGB, NSColorSpace.displayP3]
}

extension CodableColor: CustomDebugStringConvertible {
    var debugDescription: String {
        if Self.hexEncodableColorSpaces.contains(color.it_colorSpace) {
            return color.hexString()
        }
        return color.debugDescription
    }
}

