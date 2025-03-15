//
//  JSONSerialization+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 3/14/25.
//

enum JSONParseError: Error {
    case incompleteData
}

extension JSONSerialization {
    private static func completeJSON(_ json: String) -> String {
        var stack = [Character]()
        var inString = false
        var escaped = false

        // Process each character, keeping track of quotes and brackets/braces.
        for char in json {
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            // Characters inside a string do not affect the stack.
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" || char == "[" {
                    stack.append(char)
                } else if char == "}" {
                    if let last = stack.last, last == "{" {
                        stack.removeLast()
                    }
                } else if char == "]" {
                    if let last = stack.last, last == "[" {
                        stack.removeLast()
                    }
                }
            }
        }

        // If we ended while inside a string, close it.
        var completed = json
        if inString {
            completed.append("\"")
        }

        // Append missing closing tokens in the reverse order.
        while let last = stack.popLast() {
            if last == "{" {
                completed.append("}")
            } else if last == "[" {
                completed.append("]")
            }
                }

        return completed
    }

    @objc
    static func parseTruncatedJSON(_ jsonString: String) throws -> Any {
        // First attempt a direct parse.
        if let data = jsonString.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                // If it fails, attempt to complete the JSON.
                let completedString = completeJSON(jsonString)
                if let completedData = completedString.data(using: .utf8) {
                    return try JSONSerialization.jsonObject(with: completedData, options: [.fragmentsAllowed])
                }
            }
        }
        throw JSONParseError.incompleteData
    }

    static func parseTruncatedJSON<T: Decodable>(_ jsonString: String,
                                                 as type: T.Type) throws -> T {
        let decoder = JSONDecoder()

        // Try decoding the raw JSON first.
        if let data = jsonString.data(using: .utf8),
        let result = try? decoder.decode(T.self, from: data) {
            return result
        }

        // Heuristically complete the JSON.
        let completedString = completeJSON(jsonString)
        if let data = completedString.data(using: .utf8) {
            return try decoder.decode(T.self, from: data)
        }

        throw JSONParseError.incompleteData
    }
}
