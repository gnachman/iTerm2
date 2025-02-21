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

struct ExplanationResponse: Codable {
    var rawResponse = ""
    private var unparsed = ""
    var annotations = [Annotation]()
    var mainResponse: String?
    var request: AIExplanationRequest
    private lazy var inputLines: [String] = {
        request.originalString.string.components(separatedBy: "\n")
    }()

    init(text: String, request: AIExplanationRequest, final: Bool) {
        self.request = request
        _ = append(text, final: final)
    }

    mutating func append(_ string: String, final: Bool) -> Update {
        rawResponse += string
        unparsed += string
        return parse(final: final)
    }

    private struct AmbiguousAnnotation {
        var line: Int
        var text: String
        var substring: String
    }

    mutating func append(_ other: ExplanationResponse) {
        annotations += other.annotations
        if let main = other.mainResponse {
            mainResponse = (mainResponse ?? "") + main
        }
    }

    struct Update: Codable {
        var annotations = [Annotation]()
        var mainResponse: String?
        var messageID: UUID?
        var final: Bool

        init(final: Bool, messageID: UUID?) {
            self.final = final
            self.messageID = messageID
        }

        init(_ full: ExplanationResponse) {
            self.annotations = full.annotations
            self.mainResponse = full.mainResponse
            final = true
        }
    }

    private mutating func parse(final: Bool) -> Update {
        var result = Update(final: final, messageID: nil)
        result.annotations = disambiguate(parseAmbiguous())
        annotations += result.annotations
        if let mainResponse = parseMainResponse() {
            result.mainResponse = mainResponse
            self.mainResponse = (self.mainResponse ?? "") + mainResponse
        }
        return result
    }

    private mutating func parseAmbiguous() -> [AmbiguousAnnotation] {
        var result = [AmbiguousAnnotation]()
        let pattern = #"<annotation line="(\d+)" text="(.*?)" substring="(.*?)" */>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let nsResponse = NSMutableString(string: unparsed)
        let matches = regex.matches(in: unparsed,
                                    options: [],
                                    range: NSRange(location: 0, length: nsResponse.length))
        var ranges = [NSRange]()
        for match in matches {
            guard match.numberOfRanges == 4 else {
                continue
            }

            let lineStr = nsResponse.substring(with: match.range(at: 1))
            let text = unescapeHTML(nsResponse.substring(with: match.range(at: 2)))
            let substring = unescapeHTML(nsResponse.substring(with: match.range(at: 3)))

            guard let line = Int(lineStr) else {
                continue
            }

            result.append(AmbiguousAnnotation(line: line,
                                              text: text,
                                              substring: substring))
            ranges.append(match.range)
        }
        for range in ranges.reversed() {
            nsResponse.replaceCharacters(in: range, with: "")
        }
        unparsed = nsResponse as String
        return result
    }

    private func unescapeHTML(_ string: String) -> String {
        return CFXMLCreateStringByUnescapingEntities(nil, string as CFString, nil) as String? ?? string
    }

    private mutating func disambiguate(_ ambiguousAnnotations: [AmbiguousAnnotation]) -> [Annotation] {
        return ambiguousAnnotations.compactMap { annotation in
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
    }

    private mutating func parseMainResponse() -> String? {
        guard let startRange = unparsed.range(of: "<response>"),
              let endRange = unparsed.range(of: "</response>") else {
            return nil
        }
        let start = startRange.upperBound
        let end = endRange.lowerBound
        unparsed = unparsed
            .replacingCharacters(in: startRange.lowerBound..<endRange.upperBound,
                                 with: "")
        let escaped = String(unparsed[start..<end])
        return unescapeHTML(escaped)
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
