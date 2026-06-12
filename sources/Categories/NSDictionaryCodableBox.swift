//
//  NSDictionary+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

struct NSDictionaryCodableBox: Codable {
    let dictionary: NSDictionary

    init(dictionary: NSDictionary) {
        self.dictionary = dictionary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard let plist = try PropertyListSerialization.propertyList(from: data,
                                                                      options: [],
                                                                      format: nil) as? NSDictionary else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unable to decode NSDictionary")
        }
        self.dictionary = plist
    }

    func encode(to encoder: Encoder) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .xml,
                                                      options: 0)
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}
