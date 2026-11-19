//
//  EscapeHTMLBuiltInFunction.swift
//  iTerm2SharedARC
//
//  iterm2.escape_html(string:) replaces the characters that have a meaning in
//  HTML with entities, so a value can go in lightweight HTML without being read
//  as markup. For example, a rich tab content line in HTML:
//
//    \(iterm2.escape_html(string: jobName?)) <b>\(iterm2.escape_html(string: status?))</b>
//
//  With name?, a value that isn't set is passed as null, which gives an empty
//  string, as \(name) would.

import Foundation

@objc(iTermEscapeHTMLBuiltInFunction)
class EscapeHTMLBuiltInFunction: NSObject {
    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf16.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    // Undoes escape(_:).
    static func unescape(_ string: String) -> String {
        guard string.contains("&") else {
            return string
        }
        return string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            // Last, so "&amp;lt;" becomes "&lt;" rather than "<".
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension EscapeHTMLBuiltInFunction: iTermBuiltInFunctionProtocol {
    static func register() {
        let stringArg = "string"
        let function = iTermBuiltInFunction(
            name: "escape_html",
            // Any value, shown as text the way plain interpolation shows it.
            arguments: [stringArg: NSObject.self],
            optionalArguments: [stringArg],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil) { parameters, completion in
                completion(escape(iTermExpressionEvaluator.string(fromJSONObject: parameters[stringArg])), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(function, namespace: "iterm2")
    }
}
