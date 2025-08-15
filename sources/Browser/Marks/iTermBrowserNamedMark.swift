//
//  iTermBrowserNamedMark.swift
//  iTerm2
//
//  Created by George Nachman on 8/15/25.
//

class iTermBrowserNamedMark: NSObject, iTermGenericNamedMarkReading {
    var url: URL
    var name: String?
    var namedMarkSort: Int
    var guid: String

    init(url: URL, name: String, sort: Int, guid: String) {
        self.url = url
        self.name = name
        self.namedMarkSort = sort
        self.guid = guid

        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case sort
        case guid
    }
    var dictionaryValue: [String: Any] {
        return [CodingKeys.url.rawValue: url.absoluteString,
                CodingKeys.name.rawValue: name!,
                CodingKeys.sort.rawValue: namedMarkSort,
                CodingKeys.guid.rawValue: guid]
    }

    init?(dictionaryValue: [String: Any]) {
        guard let urlString = dictionaryValue[CodingKeys.url.rawValue] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        self.url = url

        guard let name = dictionaryValue[CodingKeys.name.rawValue] as? String else {
            return nil
        }
        self.name = name

        guard let sort = dictionaryValue[CodingKeys.sort.rawValue] as? Int else {
            return nil
        }
        self.namedMarkSort = sort

        guard let guid = dictionaryValue[CodingKeys.guid.rawValue] as? String else {
            return nil
        }
        self.guid = guid

        super.init()
    }
}

extension iTermBrowserNamedMark {
    convenience init?(row dbMark: BrowserNamedMarks) {
        guard let url = URL(string: dbMark.url) else {
            return nil
        }
        self.init(
            url: url,
            name: dbMark.name,
            sort: Int(dbMark.sort ?? 0),
            guid: dbMark.guid)
    }

    var location: iTermBrowserNamedMarkManager.Location? {
        return iTermBrowserNamedMarkManager.Location(url)
    }

    var jsDict: [String: Any]? {
        return location?.jsDict(name: name, guid: guid)
    }
}
