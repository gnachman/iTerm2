//
//  AIExplanationResponse.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); the Mac-only streaming parser and the
//  AppKit annotation bridge live in AIExplanationResponse+Mac.swift.
//

import Foundation

struct Annotation: Codable {
    var line: Int  // line number
    var utf16OffsetInLine: Int  // count from the start of `line` where the annotation begins
    var utf16Length: Int  // length of the text that is being annotated
    var note: String
    var annotatedText: String
}

struct ExplanationResponse: Codable {
    var rawResponse = ""
    // Internal (not private): the streaming parser lives in
    // AIExplanationResponse+Mac.swift.
    var unparsed = ""
    var annotations = [Annotation]()
    var mainResponse: String?
    var request: AIExplanationRequest
    lazy var inputLines: [String] = {
        request.originalString.string.components(separatedBy: "\n")
    }()

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

}
