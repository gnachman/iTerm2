//
//  CCStatusHookCommand.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/3/26.
//

import Foundation

/// Finds and resolves references to cc-status in a Claude Code hook command.
///
/// Claude Code does not inspect a hook’s `command`: it runs it with `/bin/sh -c`, so users may
/// write `$HOME/.config/iterm2/cc-status`, `~/…/cc-status`, or a wrapper such as
/// `[ -x "$HOME/…/cc-status" ] || exit 0; exec "$HOME/…/cc-status"` (issue 13099). This splits
/// the command into words roughly the way sh does and reports each word whose last path
/// component is `cc-status`. Install, uninstall and the health check all use it so they agree on
/// which entries are ours.
///
/// Resolution expands `~`, `$NAME` and `${NAME}` from a supplied environment, which should be the
/// user’s shell environment since Claude Code passes its own environment to hooks. Anything that
/// would require running code, such as `$(…)` or backticks, is never evaluated; a word using it
/// is reported as unresolvable.
enum CCStatusHookCommand {
    enum Resolution: Equatable {
        /// The word expands to this path and it is executable.
        case executable(String)
        /// The word expands to this absolute path and it is not executable, so the hook would
        /// fail.
        case notExecutable(String)
        /// The word depends on something that can’t be determined without running the shell:
        /// command substitution, an unset variable, a relative path, and so on.
        case unresolvable
    }

    /// True if any word of `command` names cc-status.
    static func refersToCCStatus(_ command: String) -> Bool {
        return !ccStatusWords(in: command).isEmpty
    }

    /// The resolution of every word in `command` that names cc-status, in order. Empty if the
    /// command does not refer to cc-status.
    static func resolutions(of command: String,
                            environment: [String: String],
                            isExecutable: (String) -> Bool) -> [Resolution] {
        return ccStatusWords(in: command).map {
            resolve($0, environment: environment, isExecutable: isExecutable)
        }
    }

    /// True if resolving a cc-status reference in `command` depends on the environment: it uses
    /// `~` or a variable, or is a bare name looked up through PATH. Callers use this to avoid
    /// launching the user’s shell when no hook command needs its environment.
    static func needsEnvironment(_ command: String) -> Bool {
        return ccStatusWords(in: command).contains { word in
            if word.parts == [.literal(name)] {
                return true
            }
            return word.parts.contains { part in
                switch part {
                case .variable, .home:
                    return true
                case .literal, .unsupported:
                    return false
                }
            }
        }
    }

    /// True if `command` is exactly one unquoted absolute path, the form the installer writes.
    static func isPlainAbsolutePath(_ command: String) -> Bool {
        let words = Lexer.words(in: command)
        guard words.count == 1, words[0].parts.count == 1,
              case .literal(let text) = words[0].parts[0] else {
            return false
        }
        return text == command && text.hasPrefix("/")
    }

    /// Parses `/usr/bin/env` output (newline-separated KEY=VALUE lines) into a dictionary. A
    /// value containing a newline splits incorrectly, as in parseCLAUDE_CONFIG_DIR.
    static func parseEnvironment(_ output: String) -> [String: String] {
        var result = [String: String]()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let equals = line.firstIndex(of: "="), equals != line.startIndex else {
                continue
            }
            let key = String(line[line.startIndex..<equals])
            if result[key] == nil {
                result[key] = String(line[line.index(after: equals)...])
            }
        }
        return result
    }

    // MARK: - Private

    fileprivate enum Part: Equatable {
        case literal(String)
        /// `$NAME` or `${NAME}`.
        case variable(String)
        /// An unquoted `~` at the start of a word, followed by `/` or the end of the word.
        case home
        /// Anything that needs the shell to evaluate: `$(…)`, backticks, `${…}` with operators,
        /// special parameters, `~user`.
        case unsupported
    }

    fileprivate struct Word: Equatable {
        var parts = [Part]()
        /// True if the word is in command position: the name of the program a simple command
        /// runs, as opposed to one of its arguments or a redirection target.
        var isCommand = false

        mutating func append(_ text: String) {
            if case .literal(let existing) = parts.last {
                parts[parts.count - 1] = .literal(existing + text)
            } else {
                parts.append(.literal(text))
            }
        }

        // The literal text after the last non-literal part.
        var literalTail: String {
            if case .literal(let text) = parts.last {
                return text
            }
            return ""
        }
    }

    private static let name = "cc-status"

    private static func ccStatusWords(in command: String) -> [Word] {
        return Lexer.words(in: command).filter { word in
            let tail = word.literalTail
            if tail == name && word.parts.count == 1 {
                // A bare name, found through PATH. Only in command position: as an argument
                // (`notify cc-status`) it is just text.
                return word.isCommand
            }
            return tail.hasSuffix("/" + name)
        }
    }

    private static func resolve(_ word: Word,
                                environment: [String: String],
                                isExecutable: (String) -> Bool) -> Resolution {
        var path = ""
        for part in word.parts {
            switch part {
            case .literal(let text):
                path += text
            case .variable(let variable):
                guard let value = environment[variable] else {
                    return .unresolvable
                }
                path += value
            case .home:
                guard let home = environment["HOME"], !home.isEmpty else {
                    return .unresolvable
                }
                path += home
            case .unsupported:
                return .unresolvable
            }
        }
        if path == name {
            // sh searches PATH for a name without a slash. A miss is not proof the hook fails:
            // Claude Code’s PATH may differ from the one supplied (it may have been launched from
            // an IDE, or the environment came from a shell that skipped the login files), and an
            // empty or relative entry, or an unset PATH, makes sh search places we can’t check.
            let directories = (environment["PATH"] ?? "").components(separatedBy: ":")
            for directory in directories where directory.hasPrefix("/") {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if isExecutable(candidate) {
                    return .executable(candidate)
                }
            }
            return .unresolvable
        }
        guard path.hasPrefix("/") else {
            // Relative to the hook’s working directory, which is Claude Code’s project directory.
            return .unresolvable
        }
        return isExecutable(path) ? .executable(path) : .notExecutable(path)
    }

    /// Splits a command into words following sh’s quoting rules closely enough to find paths.
    /// Operators (`;`, `|`, `&`, parentheses, redirections) and newlines separate words; `#` at
    /// the start of a word begins a comment. Words are marked as being in command position: the
    /// first word of the command or after `;`, `|`, `&`, `(` or a newline, skipping variable
    /// assignments, redirections, and the `exec` and `command` builtins.
    private struct Lexer {
        private let chars: [Character]
        private var i = 0
        private var result = [Word]()
        private var current: Word?
        /// Whether the next word to start would be in command position.
        private var expectingCommand = true
        /// Whether the next word to start is the target of a redirection.
        private var expectingRedirectTarget = false

        static func words(in command: String) -> [Word] {
            var lexer = Lexer(command)
            return lexer.lex()
        }

        private init(_ command: String) {
            chars = Array(command)
        }

        private mutating func lex() -> [Word] {
            while i < chars.count {
                let c = chars[i]
                switch c {
                case " ", "\t":
                    finishWord()
                    i += 1
                case "\n", ";", "|", "&", "(":
                    finishWord()
                    i += 1
                    expectingCommand = true
                    expectingRedirectTarget = false
                case ")":
                    finishWord()
                    i += 1
                    expectingCommand = false
                case "<", ">":
                    // A file descriptor written before the operator (2>) is not a command.
                    if var word = current, word.parts.allSatisfy(Self.isDigits) {
                        word.isCommand = false
                        current = word
                    }
                    finishWord()
                    // Consume the rest of the operator: >>, >&, <&, >|, <>.
                    i += 1
                    while i < chars.count && "<>&|".contains(chars[i]) {
                        i += 1
                    }
                    expectingRedirectTarget = true
                case "#" where current == nil:
                    while i < chars.count && chars[i] != "\n" {
                        i += 1
                    }
                case "'":
                    i += 1
                    var text = ""
                    while i < chars.count && chars[i] != "'" {
                        text.append(chars[i])
                        i += 1
                    }
                    i += 1
                    appendLiteral(text)
                case "\"":
                    i += 1
                    lexDoubleQuoted()
                case "\\":
                    if i + 1 < chars.count {
                        if chars[i + 1] != "\n" {
                            appendLiteral(String(chars[i + 1]))
                        }
                        i += 2
                    } else {
                        appendLiteral("\\")
                        i += 1
                    }
                case "~" where current == nil:
                    i += 1
                    if i == chars.count || chars[i] == "/" || Self.endsWord(chars[i]) {
                        appendPart(.home)
                    } else {
                        appendPart(.unsupported)
                    }
                case "$":
                    lexDollar()
                case "`":
                    skipBackticks()
                    appendPart(.unsupported)
                default:
                    appendLiteral(String(c))
                    i += 1
                }
            }
            finishWord()
            return result
        }

        private static func endsWord(_ c: Character) -> Bool {
            return " \t\n;|&()<>".contains(c)
        }

        private mutating func lexDoubleQuoted() {
            var text = ""
            while i < chars.count && chars[i] != "\"" {
                let c = chars[i]
                if c == "\\", i + 1 < chars.count, "$`\"\\\n".contains(chars[i + 1]) {
                    if chars[i + 1] != "\n" {
                        text.append(chars[i + 1])
                    }
                    i += 2
                } else if c == "$" || c == "`" {
                    appendLiteral(text)
                    text = ""
                    if c == "$" {
                        lexDollar()
                    } else {
                        skipBackticks()
                        appendPart(.unsupported)
                    }
                } else {
                    text.append(c)
                    i += 1
                }
            }
            i += 1
            // Always append, so that "" still produces an (empty) word.
            appendLiteral(text)
        }

        // On entry chars[i] is "$".
        private mutating func lexDollar() {
            i += 1
            guard i < chars.count else {
                appendLiteral("$")
                return
            }
            let c = chars[i]
            if c == "{" {
                i += 1
                var body = ""
                while i < chars.count && chars[i] != "}" {
                    body.append(chars[i])
                    i += 1
                }
                i += 1
                appendPart(Self.isName(body) ? .variable(body) : .unsupported)
            } else if c == "(" {
                var depth = 0
                while i < chars.count {
                    if chars[i] == "(" {
                        depth += 1
                    } else if chars[i] == ")" {
                        depth -= 1
                        if depth == 0 {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                appendPart(.unsupported)
            } else if c == "_" || c.isASCIILetter {
                var variable = ""
                while i < chars.count && (chars[i] == "_" || chars[i].isASCIILetter || chars[i].isASCIIDigit) {
                    variable.append(chars[i])
                    i += 1
                }
                appendPart(.variable(variable))
            } else if c.isASCIIDigit || "?$!#*@-".contains(c) {
                i += 1
                appendPart(.unsupported)
            } else {
                appendLiteral("$")
            }
        }

        // On entry chars[i] is "`". Consumes through the closing backtick.
        private mutating func skipBackticks() {
            i += 1
            while i < chars.count && chars[i] != "`" {
                i += chars[i] == "\\" ? 2 : 1
            }
            i += 1
        }

        private static func keepsCommandPosition(_ word: Word) -> Bool {
            guard case .literal(let text) = word.parts.first else {
                return false
            }
            if word.parts.count == 1 && (text == "exec" || text == "command") {
                return true
            }
            guard let equals = text.firstIndex(of: "=") else {
                return false
            }
            return isName(String(text[text.startIndex..<equals]))
        }

        private static func isName(_ s: String) -> Bool {
            guard let first = s.first, first == "_" || first.isASCIILetter else {
                return false
            }
            return s.allSatisfy { $0 == "_" || $0.isASCIILetter || $0.isASCIIDigit }
        }

        private static func isDigits(_ part: Part) -> Bool {
            guard case .literal(let text) = part else {
                return false
            }
            return !text.isEmpty && text.allSatisfy(\.isASCIIDigit)
        }

        private func startWord() -> Word {
            if let current {
                return current
            }
            return Word(parts: [], isCommand: expectingCommand && !expectingRedirectTarget)
        }

        private mutating func appendLiteral(_ text: String) {
            var word = startWord()
            word.append(text)
            current = word
        }

        private mutating func appendPart(_ part: Part) {
            var word = startWord()
            word.parts.append(part)
            current = word
        }

        private mutating func finishWord() {
            if let current {
                if expectingRedirectTarget {
                    // The target doesn't change whether a command is still expected.
                    expectingRedirectTarget = false
                } else if current.isCommand {
                    // After an assignment (FOO=bar cmd) or exec/command, the next word is
                    // still the command.
                    expectingCommand = Self.keepsCommandPosition(current)
                }
                result.append(current)
            }
            current = nil
        }
    }
}

private extension Character {
    var isASCIILetter: Bool {
        return isASCII && isLetter
    }

    var isASCIIDigit: Bool {
        return isASCII && isNumber
    }
}
