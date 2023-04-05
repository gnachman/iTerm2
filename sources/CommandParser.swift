//
//  CommandParser.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/23.
//

import Foundation

class CommandParser {
    private let command: String
    private let escapes: [unichar: String]
    private(set) var expandedComponents = [String]()
    let attributedString = NSMutableAttributedString()

    @objc
    convenience init(command: NSString, escapes: [NSNumber: NSString]) {
        let swiftEscapes = Dictionary(uniqueKeysWithValues: escapes.map { (key, value) in
            let unicharKey = key.uint16Value
            let unicharValue = String(value)
            return (unicharKey, unicharValue)
        })
        self.init(command: command, escapes: swiftEscapes)
    }

    init(command: NSString, escapes: [unichar: String]) {
        self.command = String(command)
        self.escapes = escapes
        parse()
    }

    private var singleQuoteIndex: Int?
    private var doubleQuoteIndex: Int?
    private var escape = false
    private var isFirstCharacterOfWord = true
    private var firstCharacterOfThisWordWasQuoted = true
    private var currentValue = NSMutableString()

    private func append(_ i: Int, _ c: unichar, hidden: Bool = false) {
        if !hidden {
            currentValue.appendCharacter(c)
        }
        extendAttributedString(to: i)
        attributedString.appendCharacter(c, withAttributes: attributes(c))
    }

    private func extendAttributedString(to count: Int) {
        while count > attributedString.string.utf16.count {
            attributedString.appendCharacter(0,
                                             withAttributes: [NSAttributedString.Key.commandParserRole: Role.placeholder.rawValue])
        }
    }

    private func parse() {
        let length = command.utf16.count
        for j in 0...length {
            let i = command.utf16.index(command.utf16.startIndex, offsetBy: j)
            var c: unichar
            if j < length {
                c = command.utf16[i]
                if c == 0 {
                    // Pretty sure this can't happen, but better to be safe.
                    c = unichar(Character(" "))
                }
            } else {
                // Signifies end-of-string.
                c = 0
                escape = false
            }
            handle(character: c, at: j)
        }
    }

    enum Role: Int {
        case command
        case whitespace
        case quoted
        case other
        case placeholder
        case quotationMark
        case unbalancedQuotationMark
        case unbalancedParen
        case paren
        case subshell
    }

    private func role(_ c: unichar) -> Role {
        if expandedComponents.isEmpty {
            return .command
        }
        if iswspace(Int32(c)) != 0 {
            return .whitespace
        }
        if c == singleQuote {
            if singleQuoteIndex == nil {
                return .unbalancedQuotationMark
            } else {
                return .quotationMark
            }
        }
        if c == doubleQuote {
            if doubleQuoteIndex == nil && singleQuoteIndex == nil {
                return .unbalancedQuotationMark
            } else {
                return .quotationMark
            }
        }
        if singleQuoteIndex != nil || doubleQuoteIndex != nil {
            return .quoted
        }
        if c == openParen {
            return .unbalancedParen
        }
        if c == closeParen {
            if parenIndexes.isEmpty {
                return .unbalancedParen
            } else {
                return .paren
            }
        }
        if !parenIndexes.isEmpty {
            return .subshell
        }
        return .other
    }

    private func attributes(_ c: unichar) -> [NSAttributedString.Key: Any] {
        return [NSAttributedString.Key.commandParserRole: role(c).rawValue]
    }

    private let backslash = unichar(Character("\\"))
    private let doubleQuote = unichar(Character("\""))
    private let singleQuote = unichar(Character("'"))
    private let openParen = unichar(Character("("))
    private let closeParen = unichar(Character(")"))
    private var parenIndexes = [Int]()

    private func handle(character c: unichar, at j: Int) {
        if c == backslash && !escape {
            append(j, c, hidden: true)
            escape = true
            return
        }

        if escape {
            handleEscaped(character: c, at: j)
            return;
        }

        handleUnescaped(character: c, at: j)
    }

    private func handleUnescaped(character c: unichar, at j: Int) {
        if c == doubleQuote && singleQuoteIndex == nil {
            append(j, c, hidden: true)
            toggleDoubleQuote(j)
            return
        }
        if c == singleQuote && doubleQuoteIndex == nil {
            append(j, c, hidden: true)
            toggleSingleQuote(j)
            return
        }
        if c == 0 {
            singleQuoteIndex = nil
            doubleQuoteIndex = nil
        }

        // Treat end-of-string like whitespace.
        let isWhitespace = (c == 0 || iswspace(Int32(c)) != 0)

        if singleQuoteIndex == nil && doubleQuoteIndex == nil && isWhitespace {
            if c != 0 {
                append(j, c, hidden: true)
            }
            handleUnquotedWhitespace()
            return
        }

        if isFirstCharacterOfWord {
            firstCharacterOfThisWordWasQuoted = doubleQuoteIndex != nil || singleQuoteIndex != nil
            isFirstCharacterOfWord = false
        }
        if c == openParen {
            parenIndexes.append(j)
            append(j, c)
        } else if c == closeParen {
            append(j, c)
            if let balancingIndex = parenIndexes.popLast() {
                balanceParen(at: balancingIndex)
            }
        } else {
            append(j, c)
        }
    }

    private func handleEscaped(character c: unichar, at j: Int) {
        isFirstCharacterOfWord = false
        escape = false
        if let e = escapes[c] {
            for ec in e.utf16 {
                append(j, ec)
            }
        } else if doubleQuoteIndex != nil {
            // Determined by testing with bash.
            if c == doubleQuote {
                append(j, doubleQuote)
            } else if c == backslash {
                append(j, c)
            } else {
                append(j, backslash)
                append(j, c)
            }
        } else if singleQuoteIndex != nil {
            // Determined by testing with bash.
            if c == singleQuote {
                append(j, backslash)
            } else {
                append(j, backslash)
                append(j, unichar(c))
            }
        } else {
            append(j, c);
        }
    }

    private func balanceQuote(at index: Int) {
        replace(role: .unbalancedQuotationMark, with: .quotationMark, at: index)
    }

    private func balanceParen(at index: Int) {
        replace(role: .unbalancedParen, with: .paren, at: index)
    }

    private func replace(role original: Role, with replacement: Role, at index: Int) {
        let attributes = attributedString.attributes(at: index, effectiveRange: nil)
        if let role = attributes[NSAttributedString.Key.commandParserRole],
           role as? Int == original.rawValue {
            let replacement = [NSAttributedString.Key.commandParserRole: replacement.rawValue]
            attributedString.addAttributes(replacement,
                                           range: NSRange(location: index, length: 1))
        }
    }

    private func toggleDoubleQuote(_ index: Int) {
        if let doubleQuoteIndex {
            balanceQuote(at: doubleQuoteIndex)
            self.doubleQuoteIndex = nil
        } else {
            doubleQuoteIndex = index
        }
        isFirstCharacterOfWord = false
    }

    private func toggleSingleQuote(_ index: Int) {
        if let singleQuoteIndex {
            balanceQuote(at: singleQuoteIndex)
            self.singleQuoteIndex = nil
        } else {
            singleQuoteIndex = index
        }
        isFirstCharacterOfWord = false
    }

    private func handleUnquotedWhitespace() {
        if isFirstCharacterOfWord {
            // Ignore whitespace not in quotes or escaped.
            return
        }
        if !firstCharacterOfThisWordWasQuoted {
            expandedComponents.append((currentValue).expandingTildeInPathPreservingSlash())
        } else {
            expandedComponents.append(currentValue as String)
        }
        currentValue = NSMutableString()
        firstCharacterOfThisWordWasQuoted = true
        isFirstCharacterOfWord = true
    }
}

extension unichar {
    init(_ character: Character) {
        self = UInt16(character.unicodeScalars.first!.value)
    }
}

extension NSAttributedString.Key {
    static let commandParserRole: NSAttributedString.Key = .init("commandParserRole")
}

extension NSAttributedString {
    func enumerateRoles(closure: (CommandParser.Role, NSRange) -> ()) {
        let range = NSRange(location: 0, length: self.length)
        enumerateAttribute(.commandParserRole, in: range, options: []) { value, range, stop in
            guard let rawValue = value as? Int, let role = CommandParser.Role(rawValue: rawValue) else {
                return
            }
            closure(role, range)
        }
    }
}
