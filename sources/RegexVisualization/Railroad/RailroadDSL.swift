//
//  RailroadDSL.swift
//  iTerm2
//
//  Swift port of railroad_dsl (https://github.com/lukaslueg/railroad_dsl),
//  Copyright (c) 2018 Lukas Lueg, MIT License.
//
//  Grammar (parser.pest in the Rust crate):
//
//    term        = "\"" ( "\\" ANY | !"\"" ANY )* "\""
//    nonterm     = "'"  ( "\\" ANY | !"'"  ANY )* "'"
//    comment     = "`"  ( "\\" ANY | !"`"  ANY )* "`"
//    empty       = "!"
//    sequence    = "[" lbox_expr* "]"
//    stack       = "{" lbox_expr ("," lbox_expr)* "}"
//    choice      = "<" lbox_expr ("," lbox_expr)* ">"
//    opt_expr    = simple_expr "?"?
//    rpt_expr    = opt_expr ("*" opt_expr)?
//    lbox_expr   = rpt_expr ("#" rpt_expr)?
//    root_expr   = lbox_expr+
//
//  Whitespace (space, tab, newline) is allowed between tokens.
//

import Foundation

enum RailroadDSL {
    struct ParseError: Error, Equatable {
        var offset: Int
        var message: String
    }

    static func isValid(_ source: String) -> Bool {
        (try? parse(source)) != nil
    }

    /// One tree per top-level expression, not yet wrapped in start and end markers.
    static func parse(_ source: String) throws -> [any RailroadNode] {
        var parser = Parser(Array(source.unicodeScalars))
        return try parser.root()
    }

    /// The diagram railroad_dsl's `compile` builds: each top-level expression
    /// gets start and end markers, and several are stacked in a vertical grid.
    static func diagram(_ source: String, css: String?) throws -> RailroadDiagram {
        var trees: [any RailroadNode] = try parse(source).map { tree in
            RailroadSequence(children: [RailroadSimpleStart(), tree, RailroadSimpleEnd()])
        }
        let root: any RailroadNode = trees.count == 1 ? trees.removeFirst() : RailroadVerticalGrid(children: trees)
        return RailroadDiagram(root: root, css: css)
    }

    static func svg(_ source: String, css: String?) throws -> String {
        try diagram(source, css: css).svg
    }

    private struct Parser {
        let chars: [Unicode.Scalar]
        var pos = 0

        init(_ chars: [Unicode.Scalar]) {
            self.chars = chars
        }

        mutating func root() throws -> [any RailroadNode] {
            var result = [try lboxExpr()]
            while true {
                skipWhitespace()
                if pos == chars.count {
                    return result
                }
                result.append(try lboxExpr())
            }
        }

        private mutating func lboxExpr() throws -> any RailroadNode {
            let first = try rptExpr()
            if consume("#") {
                return RailroadLabeledBox(inner: first, label: try rptExpr())
            }
            return first
        }

        private mutating func rptExpr() throws -> any RailroadNode {
            let first = try optExpr()
            if consume("*") {
                return RailroadRepeat(inner: first, repeat: try optExpr())
            }
            return first
        }

        private mutating func optExpr() throws -> any RailroadNode {
            let node = try simpleExpr()
            if consume("?") {
                return RailroadOptional(inner: node)
            }
            return node
        }

        private mutating func simpleExpr() throws -> any RailroadNode {
            skipWhitespace()
            guard pos < chars.count else {
                throw ParseError(offset: pos, message: "expected an expression")
            }
            switch chars[pos] {
            case "\"":
                return RailroadTerminal(label: try quoted("\""))
            case "'":
                return RailroadNonTerminal(label: try quoted("'"))
            case "`":
                return RailroadComment(text: try quoted("`"))
            case "!":
                pos += 1
                return RailroadEmpty()
            case "[":
                pos += 1
                var children: [any RailroadNode] = []
                while !consume("]") {
                    children.append(try lboxExpr())
                }
                return RailroadSequence(children: children)
            case "{":
                pos += 1
                return RailroadStack(children: try commaList(closing: "}"))
            case "<":
                pos += 1
                return RailroadChoice(children: try commaList(closing: ">"))
            default:
                throw ParseError(offset: pos, message: "unexpected character")
            }
        }

        private mutating func commaList(closing: Unicode.Scalar) throws -> [any RailroadNode] {
            var result = [try lboxExpr()]
            while consume(",") {
                result.append(try lboxExpr())
            }
            if !consume(closing) {
                throw ParseError(offset: pos, message: "expected \(closing)")
            }
            return result
        }

        /// A quoted literal with backslash escapes removed.
        private mutating func quoted(_ quote: Unicode.Scalar) throws -> String {
            let start = pos
            pos += 1
            var result = String.UnicodeScalarView()
            while pos < chars.count {
                let c = chars[pos]
                if c == "\\" {
                    guard pos + 1 < chars.count else {
                        break
                    }
                    result.append(chars[pos + 1])
                    pos += 2
                } else if c == quote {
                    pos += 1
                    return String(result)
                } else {
                    result.append(c)
                    pos += 1
                }
            }
            throw ParseError(offset: start, message: "unterminated literal")
        }

        private mutating func consume(_ c: Unicode.Scalar) -> Bool {
            skipWhitespace()
            if pos < chars.count && chars[pos] == c {
                pos += 1
                return true
            }
            return false
        }

        private mutating func skipWhitespace() {
            while pos < chars.count, chars[pos] == " " || chars[pos] == "\t" || chars[pos] == "\n" {
                pos += 1
            }
        }
    }
}
