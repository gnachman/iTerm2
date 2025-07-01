//
//  CodableNSDictionary.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

struct CodableNSDictionary: Codable {
    let dictionary: NSDictionary

    init(_ dictionary: NSDictionary) {
        self.dictionary = dictionary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, format: &format)
        if let dictionary = plist as? NSDictionary {
            self.dictionary = dictionary
        } else {
            throw DecodingError.typeMismatch(Swift.type(of: plist),
                                             .init(codingPath: [],
                                                   debugDescription: "Not a dictionary"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .binary,
                                                      options: 0)
        try container.encode(data)
    }
}

