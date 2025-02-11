//
//  ExplainWithAI.swift
//  iTerm2
//
//  Created by George Nachman on 2/9/25.
//

fileprivate struct Annotation {
    var line: Int  // line number
    var utf16OffsetInLine: Int  // count from the start of `line` where the annotation begins
    var utf16Length: Int  // length of the text that is being annotated
    var note: String
}

@objc
extension AITermControllerObjC {
    @objc
    static func explain(command: String?,
                        snapshot: TerminalContentSnapshot,
                        question: String,
                        selection: iTermSelection,
                        scope: iTermVariableScope,
                        window: NSWindow,
                        completion: @escaping (iTermOr<AIAnnotationCollection, NSError>) -> ()) -> AITermControllerObjC {
        let request = AIExplanationRequest(command: command,
                                           snapshot: snapshot,
                                           selection: selection,
                                           question: question)
        let aiterm = AITermControllerObjC(query: request.prompt(),
                                          scope: scope,
                                          window: window) { or in
            handleResponse(request: request,
                           result: Result(or),
                           completion: completion)
        }
//        handleFakeResponse(request, completion: completion)
        return aiterm
    }

    @nonobjc
    private static func handleFakeResponse(_ request: AIExplanationRequest,
                                           completion: @escaping (iTermOr<AIAnnotationCollection, NSError>) -> ()) {
        let preferredChoice = """
Place fake response here
"""
        let (annotations, mainResponse) = parse(preferredChoice, request: request)
        completion(iTermOr.first(AIAnnotationCollection(mainResponse: mainResponse,
                                                        values: annotations,
                                                        locatedString: request.originalString)))
    }

    @nonobjc
    private static func handleResponse(request: AIExplanationRequest,
                                       result: Result<String, NSError>,
                                       completion: @escaping (iTermOr<AIAnnotationCollection, NSError>) -> ()) {
        result.handle { preferredChoice in
            let (annotations, mainResponse) = parse(preferredChoice, request: request)
            completion(iTermOr.first(AIAnnotationCollection(mainResponse: mainResponse,
                                                            values: annotations,
                                                            locatedString: request.originalString)))
        } failure: { error in
            completion(iTermOr.second(error))
        }
    }

    private struct AmbiguousAnnotation {
        var line: Int
        var text: String
        var substring: String
    }

    @nonobjc
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

    @nonobjc
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

    @nonobjc
    private static func parse(_ response: String?, request: AIExplanationRequest) -> ([Annotation], String?) {
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
                              note: annotation.text)
        }
        let mainResponse = parseMainResponse(response)
        return (annotations, mainResponse)
    }

}

@objc(iTermAIAnnotationCollection)
class AIAnnotationCollection: NSObject {
    @objc let values: [AITermAnnotation]
    @objc let mainResponse: String?

    @nonobjc
    fileprivate init(mainResponse: String?, values: [Annotation], locatedString: iTermLocatedString) {
        self.mainResponse = mainResponse
        self.values = values.compactMap {
            AITermAnnotation(annotation: $0, locatedString: locatedString)
        }
    }
}

@objc(iTermAIAnnotation)
class AITermAnnotation: NSObject {
    @objc let run: VT100GridRun
    @objc let note: String

    @nonobjc
    fileprivate init?(annotation: Annotation, locatedString: iTermLocatedString) {
        guard annotation.utf16Length > 0 else {
            return nil
        }
        guard locatedString.gridCoords.count > 0 else {
            return nil
        }

        note = annotation.note

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
}

extension VT100GridCoord {
    var coordByIncrementingX: VT100GridCoord {
        var temp = self
        temp.x += 1
        return temp
    }
}

struct AIExplanationRequest {
    var command: String?
    var markedUpString: String
    var originalString: iTermLocatedString
    var question: String

    private static func content(snapshot: TerminalContentSnapshot,
                                selection: iTermSelection) -> iTermLocatedString {
        let extractor = LocatedStringSelectionExtractor(selection: selection,
                                                        snapshot: snapshot,
                                                        options: .trimWhitespace,
                                                        maxBytes: 0,
                                                        minimumLineNumber: 0)!
        return extractor.extract()
    }

    private static func escapedContent(_ original: String) -> String {
        return original
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .components(separatedBy: "\n")
            .enumerated()
            .map { (i, line) in
                "<line n=\"\(i)\">\(line)</line>\n"
            }
            .joined(separator: "\n")
    }

    private static func prompt(_ command: String?,
                               text: String,
                               question: String) -> String {
        if question.isEmpty {
            var instructions = [String]()
            if let command {
                instructions.append("After this line I will attach the output of \(command), which the user needs help understanding.")
            } else {
                instructions.append("After this line I will attach some text from a terminal emulator that the user needs help understanding.")
            }
            instructions += [
                "Respond with a sequence of annotations.",
                "Annotations should explain parts of the output that the user likely wants to know more about, such as error messages, abstruse terms of art, tersely formatted messages, or anything non-obvious.",
                "Don't annotate anything obvious, like self-explanatory comments in code.",
                "An example of a good annotation: `Error: text file busy` might be annotated as `This usually happens when you try to modify or delete an executable that is currently running`.",
                #"Each annotation you write should look like this: <annotation line="N" text="This is the text of the annotation" substring="text that occurs on line N that you wish to annotate"/>."#,
                "Use ampersand escaping like HTML if you need to use a quotation mark or an ampersand.",
                "Since the user asked for this to be explained, you should always add at least one annotation.",
                "You may provide more than one annotation per line of input if needed.",
                "Avoid overlapping annotations because they lead to a confusing user interface.",
                "I have added markup to help identify line numbers.",
                "Each line is wrapped in <line n=\"number\">…</line>.",
            ]
            return instructions.joined(separator: " ") + "\n" + text
        }

        var instructions = [String]()
        if let command {
            instructions.append("After this line I will attach the output of \(command).")
        } else {
            instructions.append("After this line I will attach some text from a terminal emulator that the user needs help understanding.")
        }
        instructions += [
            "The user has asked this question about it: “\(question)”",
            "You should respond to their question with a main response and, if needed, annotations of the text provided below.",
            "The entirety of the main response should be wrapped in <response>…</response> tags.",
            "The main response should be markdown. < and & must be ampersand encoded.",
            "You may also choose to include annotations that are relevant to the question.",
            "Annotations will be displayed to the user next to the parts of the terminal emulator's content that are annotated.",
            "Don't annotate anything obvious, like self-explanatory comments in code.",
            "An example of a good annotation: `Error: text file busy` might be annotated as `This usually happens when you try to modify or delete an executable that is currently running`.",
            #"Each annotation you write should look like this: <annotation line="N" text="This is the text of the annotation" substring="text that occurs on line N that you wish to annotate"/>."#,
            "Use ampersand escaping like HTML if you need to use a quotation mark or an ampersand.",
            "You may provide more than one annotation per line of input if needed.",
            "Avoid overlapping annotations because they lead to a confusing user interface.",
            "I have added markup to help identify line numbers.",
            "Each line is wrapped in <line n=\"number\">…</line>.",
        ]
        return instructions.joined(separator: " ") + "\n" + text

    }

    func prompt() -> String {
        return Self.prompt(command, text: markedUpString, question: question)
    }

    init(command: String?,
         snapshot: TerminalContentSnapshot,
         selection: iTermSelection,
         question: String) {
        self.command = command
        self.question = question
        originalString = Self.content(snapshot: snapshot, selection: selection)
        markedUpString = Self.escapedContent(originalString.string)
    }
}

extension Result {
    init<T, U>(_ or: iTermOr<T, U>) {
        var actual: Result<Success, Failure>!
        or.whenFirst { value in
            actual = .success(value as! Success)
        } second: { value in
            actual = .failure(value as! Failure)
        }
        self = actual
    }
}
