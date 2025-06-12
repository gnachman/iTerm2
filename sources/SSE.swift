//
//  SSE.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

func SplitServerSentEvents(from rawInput: String) -> (json: String?, remainder: String) {
    let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
    guard let newlineRange = input.range(of: "\r\n") ?? input.range(of: "\n") else {
        return (nil, String(input))
    }

    // Extract the first line (up to, but not including, the newline)
    let firstLine = input[..<newlineRange.lowerBound]
    // Everything after the newline is the remainder.
    let remainder = input[newlineRange.upperBound...]

    // Skip all SSE control lines that aren't data
    if firstLine.hasPrefix("event:") ||
       firstLine.hasPrefix("id:") ||
       firstLine.hasPrefix("retry:") ||
       firstLine.hasPrefix(":") ||  // Comments
       firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
        return SplitServerSentEvents(from: String(remainder))
    }
    // Ensure the line starts with "data:".
    let prefix = "data:"
    guard firstLine.hasPrefix(prefix) else {
        // If not, we can't extract a valid JSON object.
        return (nil, String(input))
    }

    // Remove the prefix and trim whitespace to get the JSON object.
    let jsonPart = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

    return (String(jsonPart), String(remainder))
}

