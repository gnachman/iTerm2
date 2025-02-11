//
//  ExplainWithAI.swift
//  iTerm2
//
//  Created by George Nachman on 2/9/25.
//


struct AIExplanationRequest: Codable {
    struct Context: Codable {
        var sessionID: String
        var baseOffset: Int64
    }
    var command: String?
    var truncated: Bool
    var originalString: iTermCodableLocatedString
    var question: String
    var subjectMatter: String
    var url: URL?
    var context: Context
    private var _boxedUserInfo: NSDictionaryCodableBox?
    var userInfo: NSDictionary? {
        get { _boxedUserInfo?.dictionary }
        set { _boxedUserInfo = newValue.map { NSDictionaryCodableBox(dictionary: $0) } }
    }
    var snippetText: String {
        if let command {
            return "Explain \(command)"
        }
        if !question.isEmpty {
            return question
        }
        return "Explain \(subjectMatter)"
    }
    
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
                               truncated: Bool,
                               question: String) -> String {
        var instructions = [String]()
        if let command {
            instructions.append("After this paragraph I will attach the output of \(command), which the user needs help understanding.")
        } else {
            instructions.append("After this paragraph I will attach some text from a terminal emulator that the user needs help understanding.")
        }
        if truncated {
            instructions.append("The beginning of the command output is not included because it was extremely long. What you see is just the latter part of it.")
        }
        let annotationsPurpose = "Annotations should explain parts of the output that the user likely wants to know more about, such as error messages, abstruse terms of art, tersely formatted messages, or anything non-obvious."

        if question.isEmpty {
            instructions += [
                "Respond with a sequence of annotations.",
                annotationsPurpose,
                "Since the user asked for this to be explained, you should always add at least one annotation.",
            ]
        } else {
            instructions += [
                "The user has asked this question about it: “\(question)”",
                "You should respond to their question with a main response and, if needed, annotations of the text provided below.",
                "The entirety of the main response should be wrapped in <response>…</response> tags.",
                "The main response should be markdown. < and & must be ampersand encoded.",
                "You may also choose to include annotations that are relevant to the question.",
                annotationsPurpose
            ]
        }
        instructions += [
            "Annotations will be displayed to the user next to the parts of the terminal emulator's content.",
            "Don't annotate anything obvious, like self-explanatory comments in code.",
            "Never use a substring as its own annotation.",
            "An example of a good annotation: `Error: text file busy` might be annotated as `This usually happens when you try to modify or delete an executable that is currently running`.",
            #"Each annotation you write should look like this: <annotation line="N" text="A useful explanation of the annotated substring" substring="text that occurs on line N that you wish to annotate"/>."#,
            "Use ampersand escaping like HTML if you need to use a quotation mark or an ampersand.",
            "You may provide more than one annotation per line of input if needed.",
            "Avoid overlapping annotations because they lead to a confusing user interface.",
            "I have added markup to help identify line numbers.",
            "Each line is wrapped in <line n=\"number\">…</line>.",
            "The text to annotate follows:",
        ]
        return instructions.joined(separator: " ") + "\n" + text

    }

    func prompt() -> String {
        let markedUpString = Self.escapedContent(originalString.string)
        return Self.prompt(command,
                           text: markedUpString,
                           truncated: truncated,
                           question: question)
    }

    static func conversationalPrompt(userPrompt: String) -> String {
        return "Stop using <annotation> and <response>. I am no longer parsing them. What follows will be a regular conversation. Here is the next prompt from the user: \(userPrompt)"
    }

    init(command: String?,
         snapshot: TerminalContentSnapshot,
         selection: iTermSelection,
         truncated: Bool,
         question: String,
         subjectMatter: String,
         url: URL?,
         context: Context) {
        self.command = command
        self.question = question
        self.subjectMatter = subjectMatter
        self.url = url
        self.truncated = truncated
        self.context = context
        originalString = iTermCodableLocatedString(Self.content(snapshot: snapshot, selection: selection))
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
