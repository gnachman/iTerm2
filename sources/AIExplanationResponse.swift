//
//  AIExplanationResponse.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

struct Annotation: Codable {
    var line: Int  // line number
    var utf16OffsetInLine: Int  // count from the start of `line` where the annotation begins
    var utf16Length: Int  // length of the text that is being annotated
    var note: String
    var annotatedText: String
}

class AIAnnotationCollection: Codable {
    let rawResponse: String
    let annotations: [Annotation]
    let mainResponse: String?
    private var _boxedUserInfo: NSDictionaryCodableBox?
    var userInfo: NSDictionary? {
        get { _boxedUserInfo?.dictionary }
        set { _boxedUserInfo = newValue.map { NSDictionaryCodableBox(dictionary: $0) } }
    }

    init(_ response: String, request: AIExplanationRequest) {
        rawResponse = response
        let inputLines = request.originalString.string.components(separatedBy: "\n")
        let ambiguousAnnotations: [AmbiguousAnnotation] = Self.parseAmbiguous(response)
        annotations = ambiguousAnnotations.compactMap { annotation -> Annotation? in
            guard let line = inputLines[safe: annotation.line] else {
                return nil
            }
            guard let range = line.range(of: annotation.substring) else {
                return nil
            }
            return Annotation(line: annotation.line,
                              utf16OffsetInLine: line.utf16.distance(from: line.startIndex,
                                                                     to: range.lowerBound),
                              utf16Length: annotation.substring.utf16.count,
                              note: annotation.text,
                              annotatedText: annotation.substring)
        }
        mainResponse = Self.parseMainResponse(response)
        self.userInfo = request.userInfo
    }

    private enum CodingKeys: String, CodingKey {
        case annotations
        case mainResponse
        case userInfo
        case rawResponse
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainResponse = try container.decodeIfPresent(String.self, forKey: .mainResponse)
        annotations = try container.decode([Annotation].self, forKey: .annotations)
        _boxedUserInfo = try container.decode(NSDictionaryCodableBox.self, forKey: .userInfo)
        rawResponse = try container.decode(String.self, forKey: .rawResponse)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mainResponse, forKey: .mainResponse)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(_boxedUserInfo, forKey: .userInfo)
        try container.encode(rawResponse, forKey: .rawResponse)
    }

    private struct AmbiguousAnnotation {
        var line: Int
        var text: String
        var substring: String
    }

    private static func parseAmbiguous(_ response: String) -> [AmbiguousAnnotation] {
        let pattern = #"<annotation line="(\d+)" text="(.*?)" substring="(.*?)" */>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsResponse = response as NSString
        let matches = regex.matches(in: response,
                                    options: [],
                                    range: NSRange(location: 0, length: nsResponse.length))

        return matches.compactMap { match in
            guard match.numberOfRanges == 4 else {
                return nil
            }

            let lineStr = nsResponse.substring(with: match.range(at: 1))
            let text = unescapeHTML(nsResponse.substring(with: match.range(at: 2)))
            let substring = unescapeHTML(nsResponse.substring(with: match.range(at: 3)))

            guard let line = Int(lineStr) else { return nil }

            return AmbiguousAnnotation(line: line, text: text, substring: substring)
        }
    }

    private static func parseMainResponse(_ response: String) -> String? {
        guard let start = response.range(of: "<response>")?.upperBound,
              let end = response.range(of: "</response>")?.lowerBound else {
            return nil
        }
        let escaped = String(response[start..<end])
        return unescapeHTML(escaped)
    }

    private static func unescapeHTML(_ string: String) -> String {
        return CFXMLCreateStringByUnescapingEntities(nil, string as CFString, nil) as String? ?? string
    }

    static func parse(_ response: String?, request: AIExplanationRequest) -> ([Annotation], String?) {
        guard let response else {
            return ([], nil)
        }
        let inputLines = request.originalString.string.components(separatedBy: "\n")
        let ambiguousAnnotations: [AmbiguousAnnotation] = parseAmbiguous(response)
        let annotations = ambiguousAnnotations.compactMap { annotation -> Annotation? in
            guard let line = inputLines[safe: annotation.line] else {
                return nil
            }
            guard let range = line.range(of: annotation.substring) else {
                return nil
            }
            return Annotation(line: annotation.line,
                              utf16OffsetInLine: line.utf16.distance(from: line.startIndex,
                                                                     to: range.lowerBound),
                              utf16Length: annotation.substring.utf16.count,
                              note: annotation.text,
                              annotatedText: annotation.substring)
        }
        let mainResponse = parseMainResponse(response)
        return (annotations, mainResponse)
    }
}

class AITermAnnotation: NSObject, Codable {
    let run: VT100GridRun
    let note: String
    let annotatedText: String

    @nonobjc
    init?(annotation: Annotation, locatedString: iTermLocatedString) {
        guard annotation.utf16Length > 0 else {
            return nil
        }
        guard locatedString.gridCoords.count > 0 else {
            return nil
        }

        note = annotation.note
        annotatedText = annotation.annotatedText

        let offsetOfLine = locatedString.offset(ofLineNumber: Int32(clamping: annotation.line))
        guard offsetOfLine != NSNotFound else {
            return nil
        }
        let end = offsetOfLine + annotation.utf16OffsetInLine
        let coord = if end < locatedString.gridCoords.count {
            locatedString.gridCoords.coord(at: end)
        } else {
            locatedString.gridCoords.coord(at: locatedString.gridCoords.count - 1).coordByIncrementingX
        }
        run = VT100GridRun(origin: coord,
                           length: Int32(clamping: annotation.utf16Length))
    }

    private enum CodingKeys: String, CodingKey {
        case run, note, annotatedText
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decode(String.self, forKey: .note)
        annotatedText = try container.decode(String.self, forKey: .annotatedText)
        run = try container.decode(VT100GridRun.self, forKey: .run)
        super.init()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(note, forKey: .note)
        try container.encode(annotatedText, forKey: .annotatedText)
        try container.encode(run, forKey: .run)
    }

}

extension VT100GridCoord {
    var coordByIncrementingX: VT100GridCoord {
        var temp = self
        temp.x += 1
        return temp
    }
}

extension VT100GridRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case origin, length
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try container.decode(VT100GridCoord.self, forKey: .origin)
        let length = try container.decode(Int32.self, forKey: .length)
        self.init(origin: origin, length: length)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(length, forKey: .length)
    }
}

public class iTermCodableLocatedString: iTermLocatedString, Codable {
    private enum CodingKeys: String, CodingKey {
        case string, gridCoords
    }

    init(_ locatedString: iTermLocatedString) {
        super.init(string: locatedString.string, gridCoords: locatedString.gridCoords)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedString = try container.decode(String.self, forKey: .string)
        let decodedGridCoords = try container.decode(GridCoordArray.self, forKey: .gridCoords)
        super.init(string: decodedString, gridCoords: decodedGridCoords)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.string, forKey: .string)
        try container.encode(self.gridCoords, forKey: .gridCoords)
    }
}
