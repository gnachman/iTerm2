//
//  TriggerInterpolatedParameter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/26.
//

import Foundation

// Classifies a trigger parameter written as an interpolated string, so that the common case
// can be evaluated without the session's variable scope.
//
// Evaluating an interpolated string in general requires the session's variable scope, which
// lives on the main queue. Getting it costs a paused side effect: token execution stops until
// the main queue runs it, so that later tokens cannot change a variable before the trigger
// reads it. For a session that is not visible that can take up to a second, and because tmux
// panes share one reader thread, one stalled pane can freeze output in every session.
// Issue 13160.
//
// Many parameters refer only to values the trigger itself supplies, like
// https://example.com/\(matches[1]). Nothing later in the token stream can change those, so
// they are compiled once into a template that can be filled in on any queue.
//
// Only the simplest forms are recognized: \(matches[N]) and \(line). Anything else, including
// operators, function calls, and optional chaining, is evaluated the general way. Results are
// cached by parameter string because classifying requires scanning the string, and triggers
// are checked on every line of output.
@objc(iTermTriggerInterpolatedParameter)
class TriggerInterpolatedParameter: NSObject {
    @objc(iTermTriggerInterpolatedParameterKind)
    enum Kind: Int {
        // Contains no interpolated expressions.
        case literal
        // Every interpolated expression refers only to trigger-local values.
        case triggerLocal
        // Needs the session's variable scope to evaluate.
        case requiresScope
    }

    private enum Part: Equatable {
        case literal(String)
        case match(Int)
        case line
    }

    @objc let kind: Kind
    // Only nonempty when kind is triggerLocal.
    private let parts: [Part]

    private static let cache = NSCache<NSString, TriggerInterpolatedParameter>()
    private static let matchRegex = try! NSRegularExpression(pattern: #"^\s*matches\s*\[\s*([0-9]+)\s*\]\s*$"#)
    private static let lineRegex = try! NSRegularExpression(pattern: #"^\s*line\s*$"#)

    // Safe to call on any queue.
    @objc(parameterWithString:)
    static func parameter(_ string: String) -> TriggerInterpolatedParameter {
        let key = string as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let parameter = TriggerInterpolatedParameter(string)
        cache.setObject(parameter, forKey: key)
        return parameter
    }

    private init(_ string: String) {
        var parts = [Part]()
        var sawExpression = false
        var requiresScope = false
        // Use the same scanner as the expression parser so literals are split identically.
        (string as NSString).enumerateSwiftySubstrings { _, substring, isLiteral, stop in
            if isLiteral {
                // The expression parser expands escapes in each literal piece the same way.
                parts.append(.literal((substring as NSString).it_stringByExpandingBackslashEscapedCharacters()))
                return
            }
            sawExpression = true
            if let part = Self.triggerLocalPart(substring) {
                parts.append(part)
            } else {
                requiresScope = true
                stop.pointee = true
            }
        }
        if !sawExpression {
            kind = .literal
            self.parts = []
        } else if requiresScope {
            kind = .requiresScope
            self.parts = []
        } else {
            kind = .triggerLocal
            self.parts = parts
        }
        super.init()
    }

    private static func triggerLocalPart(_ expression: String) -> Part? {
        let range = NSRange(location: 0, length: (expression as NSString).length)
        if lineRegex.firstMatch(in: expression, range: range) != nil {
            return .line
        }
        guard let match = matchRegex.firstMatch(in: expression, range: range),
              let index = Int((expression as NSString).substring(with: match.range(at: 1))) else {
            return nil
        }
        return .match(index)
    }

    // Fills in a triggerLocal template. Returns nil if a referenced value is unavailable (an
    // index out of range, or no line number, signaled by a negative absLine). The caller then
    // evaluates the general way so the error is reported exactly as before.
    @objc(valueWithMatches:absLine:)
    func value(matches: [String], absLine: Int64) -> String? {
        it_assert(kind == .triggerLocal)
        var result = ""
        for part in parts {
            switch part {
            case .literal(let string):
                result += string
            case .match(let index):
                guard index < matches.count else {
                    return nil
                }
                result += matches[index]
            case .line:
                guard absLine >= 0 else {
                    return nil
                }
                result += String(absLine)
            }
        }
        return result
    }
}
