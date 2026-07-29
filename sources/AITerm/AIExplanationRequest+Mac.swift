//
//  AIExplanationRequest+Mac.swift
//  iTerm2
//
//  Mac-only construction of AIExplanationRequest from terminal content. Split
//  from AIExplanationRequest.swift, which is shared with the iOS companion app.
//

import Foundation

extension AIExplanationRequest {
    private static func content(snapshot: TerminalContentSnapshot,
                                selection: iTermSelection) -> iTermLocatedString {
        let extractor = LocatedStringSelectionExtractor(selection: selection,
                                                        snapshot: snapshot,
                                                        options: .trimWhitespace,
                                                        maxBytes: 0,
                                                        minimumLineNumber: 0)!
        return extractor.extract()
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
