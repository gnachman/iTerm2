//
//  ICURegexToRailroadConverter.swift
//  iTerm2
//
//  Created by George Nachman on 5/25/25.
//

import Foundation
import WebKit

/// Converts ICU style regular expressions into railroad DSL for visualization
class ICURegexToRailroadConverter {

    // MARK: - Types

    enum Token {
        case literal(String)
        case metachar(String)
        case charClass(String)
        case group(String)
        case quantifier(String)
        case anchor(String)
        case alternation
        case escaped(String)
    }

    // MARK: - Properties

    private var input: String
    private var position: String.Index

    // MARK: - Initialization

    init() {
        self.input = ""
        self.position = self.input.startIndex
    }

    // MARK: - Public Methods

    /// Converts an ICU regex pattern to railroad DSL
    func convert(_ pattern: String) -> String {
        self.input = pattern
        self.position = pattern.startIndex

        let result = parseAlternation()
        return result
    }

    // MARK: - Parsing Methods

    private func parseAlternation() -> String {
        var alternatives: [String] = []
        var current = parseSequence()

        while hasMore() && peek() == "|" {
            alternatives.append(current)
            advance() // consume |
            current = parseSequence()
        }

        if alternatives.isEmpty {
            return current
        } else {
            alternatives.append(current)
            // <...> is for choices/alternatives and uses commas
            return "<\(alternatives.joined(separator: ", "))>"
        }
    }

    private func parseSequence() -> String {
        var elements: [String] = []
        var currentLiteral = ""

        while hasMore() && peek() != "|" && peek() != ")" {
            let element = parseElement()

            if let elem = element {
                // Check if this element is a single unquoted character
                // (returned by parseElement when it's a literal without quantifier)
                if elem.count == 1 && !elem.contains("\"") && !elem.contains("'") && !elem.contains("`") {
                    // This is a raw character - accumulate it
                    currentLiteral.append(elem)
                } else if elem.count == 1 {
                    // This is a single character that needs escaping (like a quote)
                    // Flush any accumulated literals first
                    if !currentLiteral.isEmpty {
                        elements.append("\"\(escapeForTerminal(currentLiteral))\"")
                        currentLiteral = ""
                    }
                    // Add the single character as a properly escaped element
                    elements.append("\"\(escapeForTerminal(elem))\"")
                } else {
                    // This is a complete element (quoted, quantified, etc.)
                    // Flush any accumulated literals first
                    if !currentLiteral.isEmpty {
                        elements.append("\"\(escapeForTerminal(currentLiteral))\"")
                        currentLiteral = ""
                    }
                    elements.append(elem)
                }
            }
        }

        // Flush any remaining literals
        if !currentLiteral.isEmpty {
            elements.append("\"\(escapeForTerminal(currentLiteral))\"")
        }

        if elements.isEmpty {
            return "!"
        } else if elements.count == 1 {
            return elements[0]
        } else {
            return "{\(elements.joined(separator: ", "))}"
        }
    }

    private func parseElement() -> String? {
        guard hasMore() else { return nil }

        let char = peek()

        switch char {
        case "(":
            return parseGroup()
        case "[":
            return parseCharacterClass()
        case "\\":
            return parseEscape()
        case ".":
            advance()
            return applyQuantifier("\"[any character]\"")
        case "^":
            advance()
            return "`start of line`"
        case "$":
            advance()
            return "`end of line`"
        case "*", "+", "?", "{":
            // Quantifier without preceding element - invalid regex
            advance()
            return nil
        case ")":
            // End of group - let parent handle
            return nil
        default:
            // Literal character - return it without quotes for now
            // The sequence parser will handle grouping literals together
            advance()

            // Check if there's a quantifier following this literal
            if hasMore() && isQuantifier(peek()) {
                return applyQuantifier("\"\(escapeForTerminal(String(char)))\"")
            }

            // Return the literal - parseSequence will handle grouping
            return String(char)
        }
    }

    private func isQuantifier(_ char: Character) -> Bool {
        return char == "*" || char == "+" || char == "?" || char == "{"
    }

    private func parseGroup() -> String {
        advance() // consume (

        var groupType = "capture"
        var groupName = ""
        var content = ""

        if hasMore() && peek() == "?" {
            advance() // consume ?
            if hasMore() {
                let next = peek()
                switch next {
                case ":":
                    advance()
                    groupType = "non-capture"
                case ">":
                    advance()
                    groupType = "atomic"
                case "=":
                    advance()
                    groupType = "lookahead"
                case "!":
                    advance()
                    groupType = "negative-lookahead"
                case "#":
                    // Comment group
                    advance()
                    while hasMore() && peek() != ")" {
                        advance()
                    }
                    if hasMore() { advance() } // consume )
                    return "`comment`"
                case "<":
                    advance()
                    if hasMore() {
                        let lookBehindType = peek()
                        if lookBehindType == "=" {
                            advance()
                            groupType = "lookbehind"
                        } else if lookBehindType == "!" {
                            advance()
                            groupType = "negative-lookbehind"
                        } else {
                            // Named capture group
                            var name = ""
                            while hasMore() && peek() != ">" {
                                name.append(peek())
                                advance()
                            }
                            if hasMore() { advance() } // consume >
                            groupType = "named"
                            groupName = name
                        }
                    }
                default:
                    // Flag settings
                    if isFlag(next) || next == "-" {
                        var flags = ""
                        while hasMore() && peek() != ":" && peek() != ")" {
                            flags.append(peek())
                            advance()
                        }
                        if hasMore() && peek() == ":" {
                            advance()
                            groupType = "flags"
                            groupName = flags
                        } else {
                            // Flag change without group
                            if hasMore() { advance() } // consume )
                            return "`flags: \(flags)`"
                        }
                    }
                }
            }
        }

        // Parse group content
        content = parseAlternation()

        if hasMore() && peek() == ")" {
            advance() // consume )
        }

        // Apply annotations based on group type
        var result = content

        switch groupType {
        case "capture":
            // Regular capture group - add annotation for group number if needed
            // For now, just return the content
            break
        case "non-capture":
            // Non-capturing group - no annotation needed
            break
        case "named":
            // Named capture group - add the name as annotation
            result = "\(content)#`\(groupName)`"
        case "atomic":
            result = "\(content)#`atomic`"
        case "lookahead":
            result = "\(content)#`lookahead`"
        case "negative-lookahead":
            result = "\(content)#`negative lookahead`"
        case "lookbehind":
            result = "\(content)#`lookbehind`"
        case "negative-lookbehind":
            result = "\(content)#`negative lookbehind`"
        case "flags":
            result = "\(content)#`flags: \(groupName)`"
        default:
            break
        }

        return applyQuantifier(result)
    }

    private func parseCharacterClass() -> String {
        advance() // consume [

        var isNegated = false
        var elements: [String] = []

        if hasMore() && peek() == "^" {
            isNegated = true
            advance()
        }

        while hasMore() && peek() != "]" {
            if peek() == "\\" {
                advance()
                if hasMore() {
                    let escaped = peek()
                    advance()
                    elements.append(handleEscapeInClass(escaped))
                }
            } else if peek() == "[" && peekAhead() == ":" {
                // POSIX-style property
                var posixClass = ""
                advance() // [
                advance() // :
                while hasMore() && !(peek() == ":" && peekAhead() == "]") {
                    posixClass.append(peek())
                    advance()
                }
                if hasMore() { advance() } // :
                if hasMore() { advance() } // ]
                elements.append("\"[\(posixClass)]\"")
            } else {
                let char = peek()
                advance()

                // Check for range
                if hasMore() && peek() == "-" && peekAhead() != "]" {
                    advance() // consume -
                    if hasMore() {
                        let endChar = peek()
                        advance()
                        elements.append("\"[\(char)-\(endChar)]\"")
                    }
                } else {
                    elements.append("\"\(escapeForTerminal(String(char)))\"")
                }
            }
        }

        if hasMore() && peek() == "]" {
            advance() // consume ]
        }

        // Character classes are choices, so use <...> with commas
        let classContent = elements.isEmpty ? "!" : "<\(elements.joined(separator: ", "))>"
        let result = isNegated ? "{`not`, \(classContent)}" : classContent
        return applyQuantifier(result)
    }

    private func parseEscape() -> String {
        advance() // consume \

        guard hasMore() else { return "\"\\\\\"" }

        let escaped = peek()
        advance()

        switch escaped {
            // Special sequences
        case "a": return applyQuantifier("\"[bell]\"")
        case "A": return "`start of input`"
        case "b": return "`word boundary`"
        case "B": return "`non-word boundary`"
        case "d": return applyQuantifier("\"[digit]\"")
        case "D": return applyQuantifier("\"[non-digit]\"")
        case "e": return applyQuantifier("\"[escape]\"")
        case "f": return applyQuantifier("\"[form feed]\"")
        case "G": return "`end of previous match`"
        case "h": return applyQuantifier("\"[horizontal whitespace]\"")
        case "H": return applyQuantifier("\"[non-horizontal whitespace]\"")
        case "n": return applyQuantifier("\"[line feed]\"")
        case "r": return applyQuantifier("\"[carriage return]\"")
        case "R": return applyQuantifier("\"[newline]\"")
        case "s": return applyQuantifier("\"[whitespace]\"")
        case "S": return applyQuantifier("\"[non-whitespace]\"")
        case "t": return applyQuantifier("\"[tab]\"")
        case "v": return applyQuantifier("\"[vertical whitespace]\"")
        case "V": return applyQuantifier("\"[non-vertical whitespace]\"")
        case "w": return applyQuantifier("\"[word character]\"")
        case "W": return applyQuantifier("\"[non-word character]\"")
        case "X": return applyQuantifier("\"[grapheme cluster]\"")
        case "Z": return "`end of input (before final newline)`"
        case "z": return "`end of input`"

            // Unicode escapes
        case "u":
            var hex = ""
            for _ in 0..<4 {
                if hasMore() && isHexDigit(peek()) {
                    hex.append(peek())
                    advance()
                }
            }
            return applyQuantifier("\"[U+\(hex)]\"")

        case "U":
            var hex = ""
            for _ in 0..<8 {
                if hasMore() && isHexDigit(peek()) {
                    hex.append(peek())
                    advance()
                }
            }
            return applyQuantifier("\"[U+\(hex)]\"")

        case "x":
            if hasMore() && peek() == "{" {
                advance() // consume {
                var hex = ""
                while hasMore() && peek() != "}" {
                    hex.append(peek())
                    advance()
                }
                if hasMore() { advance() } // consume }
                return applyQuantifier("\"[U+\(hex)]\"")
            } else {
                var hex = ""
                for _ in 0..<2 {
                    if hasMore() && isHexDigit(peek()) {
                        hex.append(peek())
                        advance()
                    }
                }
                return applyQuantifier("\"[U+\(hex)]\"")
            }

            // Named character
        case "N":
            if hasMore() && peek() == "{" {
                advance() // consume {
                var name = ""
                while hasMore() && peek() != "}" {
                    name.append(peek())
                    advance()
                }
                if hasMore() { advance() } // consume }
                return applyQuantifier("\"[\(name)]\"")
            }
            return applyQuantifier("\"N\"")

            // Properties
        case "p", "P":
            let isNegated = escaped == "P"
            if hasMore() && peek() == "{" {
                advance() // consume {
                var property = ""
                while hasMore() && peek() != "}" {
                    property.append(peek())
                    advance()
                }
                if hasMore() { advance() } // consume }
                let propDesc = isNegated ? "not \(property)" : property
                return applyQuantifier("\"[\(propDesc)]\"")
            }
            return applyQuantifier("\"\(escaped)\"")

            // Back reference
        case "k":
            if hasMore() && peek() == "<" {
                advance() // consume <
                var name = ""
                while hasMore() && peek() != ">" {
                    name.append(peek())
                    advance()
                }
                if hasMore() { advance() } // consume >
                return applyQuantifier("'\(name)'")
            }
            return applyQuantifier("\"k\"")

            // Numeric back reference
        case "1"..."9":
            return applyQuantifier("'group \(escaped)'")

            // Octal
        case "0":
            var octal = "0"
            for _ in 0..<3 {
                if hasMore() && isOctalDigit(peek()) {
                    octal.append(peek())
                    advance()
                }
            }
            return applyQuantifier("\"[\\\\o\(octal)]\"")

            // Control character
        case "c":
            if hasMore() {
                let control = peek()
                advance()
                return applyQuantifier("\"[control-\(control)]\"")
            }
            return applyQuantifier("\"c\"")

            // Quote sequences
        case "Q":
            var quoted = ""
            while hasMore() {
                if peek() == "\\" && peekAhead() == "E" {
                    advance() // consume \
                    advance() // consume E
                    break
                }
                quoted.append(peek())
                advance()
            }
            return applyQuantifier("\"\(escapeForTerminal(quoted))\"")

        case "E":
            return "" // End of quote - handled by \Q

            // Literal escaped characters
        default:
            return applyQuantifier("\"\(escapeForTerminal(String(escaped)))\"")
        }
    }

    private func applyQuantifier(_ base: String) -> String {
        guard hasMore() else { return base }

        let quantChar = peek()

        switch quantChar {
        case "*":
            advance()
            if hasMore() && peek() == "?" {
                advance()
                // Lazy zero-or-more: choice between empty and one-or-more
                return "<!, {\(base)*!, `*? (lazy)`}>"
            } else if hasMore() && peek() == "+" {
                advance()
                // Possessive zero-or-more: choice between empty and one-or-more
                return "<!, {\(base)*!, `*+ (possessive)`}>"
            }
            // Zero or more: choice between empty and one-or-more
            return "<!, {\(base)*!}>"

        case "+":
            advance()
            if hasMore() && peek() == "?" {
                advance()
                // Lazy one-or-more
                return "{\(base)*!, `+? (lazy)`}"
            } else if hasMore() && peek() == "+" {
                advance()
                // Possessive one-or-more
                return "{\(base)*!, `++ (possessive)`}"
            }
            // One or more
            return "{\(base)*!}"

        case "?":
            advance()
            if hasMore() && peek() == "?" {
                advance()
                // Lazy optional: prefer empty
                return "<!, \(base), `?? (lazy)`>"
            } else if hasMore() && peek() == "+" {
                advance()
                // Possessive optional
                return "<!, \(base), `?+ (possessive)`>"
            }
            // Optional: choice between empty and the element
            return "<!, \(base)>"

        case "{":
            advance()
            var quantifier = ""
            while hasMore() && peek() != "}" {
                quantifier.append(peek())
                advance()
            }
            if hasMore() { advance() } // consume }

            var suffix = ""
            if hasMore() {
                if peek() == "?" {
                    advance()
                    suffix = " (lazy)"
                } else if peek() == "+" {
                    advance()
                    suffix = " (possessive)"
                }
            }

            // Parse quantifier
            let parts = quantifier.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            if parts.count == 1 {
                // Exactly n times
                if let n = Int(parts[0]) {
                    if n == 0 {
                        // {0} means empty
                        return "!"
                    } else if n == 1 {
                        // {1} means exactly once
                        return suffix.isEmpty ? base : "{\(base), `{\(n)}\(suffix)`}"
                    } else {
                        // {n} means exactly n times - need n-1 in sequence then base
                        var result = [base]
                        for _ in 1..<n {
                            result.append(base)
                        }
                        let repeated = "{\(result.joined(separator: ", "))}"
                        return suffix.isEmpty ? repeated : "{\(repeated), `{\(n)}\(suffix)`}"
                    }
                }
            } else if parts.count == 2 {
                if parts[1].isEmpty {
                    // At least n times {n,}
                    if let n = Int(parts[0]) {
                        if n == 0 {
                            // {0,} is same as *
                            return suffix.isEmpty ? "<!, {\(base)*!}>" : "<!, {\(base)*!, `{0,}\(suffix)`}>"
                        } else if n == 1 {
                            // {1,} is same as +
                            return suffix.isEmpty ? "{\(base)*!}" : "{\(base)*!, `{1,}\(suffix)`}"
                        } else {
                            // {n,} means n required followed by zero or more
                            var required = [base]
                            for _ in 1..<n {
                                required.append(base)
                            }
                            let result = "{\(required.joined(separator: ", ")), {\(base)*!}?}"
                            return suffix.isEmpty ? result : "{\(result), `{\(n),}\(suffix)`}"
                        }
                    }
                } else {
                    // Between n and m times {n,m}
                    if let n = Int(parts[0]), let m = Int(parts[1]) {
                        if n == 0 && m == 1 {
                            // {0,1} is same as ?
                            return suffix.isEmpty ? "<!, \(base)>" : "<!, \(base), `{0,1}\(suffix)`>"
                        } else if n == 0 {
                            // {0,m} - all optional
                            var elements: [String] = []
                            for i in 0..<m {
                                if i == 0 {
                                    elements.append(base)
                                } else {
                                    elements.append("<!, \(base)>")
                                }
                            }
                            let result = "<!, {\(elements.joined(separator: ", "))}>"
                            return suffix.isEmpty ? result : "{\(result), `{\(n),\(m)}\(suffix)`}"
                        } else {
                            // {n,m} - n required, m-n optional
                            var elements: [String] = []
                            // Required elements
                            for _ in 0..<n {
                                elements.append(base)
                            }
                            // Optional elements
                            for _ in n..<m {
                                elements.append("<!, \(base)>")
                            }
                            let result = "{\(elements.joined(separator: ", "))}"
                            return suffix.isEmpty ? result : "{\(result), `{\(n),\(m)}\(suffix)`}"
                        }
                    }
                }
            }

            return "{\(base), `{\(quantifier)}\(suffix)`}"

        default:
            return base
        }
    }

    // MARK: - Helper Methods

    private func hasMore() -> Bool {
        return position < input.endIndex
    }

    private func peek() -> Character {
        guard hasMore() else { return "\0" }
        return input[position]
    }

    private func peekAhead() -> Character {
        let nextIndex = input.index(after: position)
        guard nextIndex < input.endIndex else { return "\0" }
        return input[nextIndex]
    }

    private func advance() {
        if hasMore() {
            position = input.index(after: position)
        }
    }

    private func isHexDigit(_ char: Character) -> Bool {
        return char.isHexDigit
    }

    private func isOctalDigit(_ char: Character) -> Bool {
        return char >= "0" && char <= "7"
    }

    private func isFlag(_ char: Character) -> Bool {
        return "ismwx".contains(char)
    }

    private func escapeForTerminal(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func handleEscapeInClass(_ char: Character) -> String {
        switch char {
        case "d": return "\"[digit]\""
        case "D": return "\"[non-digit]\""
        case "s": return "\"[whitespace]\""
        case "S": return "\"[non-whitespace]\""
        case "w": return "\"[word character]\""
        case "W": return "\"[non-word character]\""
        case "h": return "\"[horizontal whitespace]\""
        case "H": return "\"[non-horizontal whitespace]\""
        case "v": return "\"[vertical whitespace]\""
        case "V": return "\"[non-vertical whitespace]\""
        case "n": return "\"[line feed]\""
        case "r": return "\"[carriage return]\""
        case "t": return "\"[tab]\""
        case "f": return "\"[form feed]\""
        case "a": return "\"[bell]\""
        case "e": return "\"[escape]\""
        default: return "\"\(escapeForTerminal(String(char)))\""
        }
    }
}
