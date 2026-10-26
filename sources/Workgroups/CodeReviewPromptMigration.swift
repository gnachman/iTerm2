//
//  CodeReviewPromptMigration.swift
//  iTerm2SharedARC
//
//  The code review system prompt (Settings > General > AI > Prompts) is user-editable. Someone who
//  edited it keeps text derived from the default of when they did, so they miss two later changes
//  to it:
//
//  - The default says {{it2}} where it runs it2, which iTerm2 fills in at launch with an it2 that
//    reaches it (CodeReviewIt2), so Claude Code doesn't depend on PATH. A prompt that runs it2 by
//    name finds it locally, but on a remote host only with a current shell integration install.
//  - The default passes --tmux "$TMUX" --tmux-pane "$TMUX_PANE" --session "${TERM_SESSION_ID#*:}",
//    where older ones passed --session=$TERM_SESSION_ID; inside a tmux pane, that leaves it2 to
//    work out the target itself.
//
//  Saved text is never rewritten silently. This works out what to offer; the user is shown it and
//  decides (PTYSession+CodeReviewPrompt). Only the it2 command lines change: everything else is
//  the user's, byte for byte.
//

import CryptoKit
import Foundation

enum CodeReviewPromptMigration {
    /// SHA-256 of the default 3.7.0 through 3.7.4 shipped, which is the same in each.
    static let shippedDefaultHashes: Set<String> = [
        "1998c397b460c9641153456ff15ad46ac4db0381b05cff1024f23bf83111f702",
    ]

    /// The addressing the default passes now.
    static let addressing = #"--tmux "$TMUX" --tmux-pane "$TMUX_PANE" --session "${TERM_SESSION_ID#*:}""#

    /// The commands every shipped default runs, which are what change.
    private static let subcommands = ["session archive-clippings", "session add-clipping"]

    /// The session values the old defaults passed: the variable, or in the worked example a
    /// made-up session ID.
    private static let oldSessionValues: Set<String> = [
        "$TERM_SESSION_ID", "${TERM_SESSION_ID}", "\"$TERM_SESSION_ID\"", "\"${TERM_SESSION_ID}\"",
        "1234-56789",
    ]

    /// What replaces an old --session when the line already has the tmux pair.
    private static let sessionOnly = #"--session "${TERM_SESSION_ID#*:}""#

    struct Proposal: Equatable {
        var text: String
        /// The stored prompt is an old default, so the proposal is the current default and
        /// updating stops storing a copy of it.
        var resetsToDefault: Bool
    }

    /// What to offer for `stored`, the saved prompt (nil when there is none, so the default is
    /// used), or nil to offer nothing.
    static func proposal(stored: String?, currentDefault: String) -> Proposal? {
        guard let stored, stored != currentDefault else {
            return nil
        }
        if shippedDefaultHashes.contains(sha256(stored)) {
            return Proposal(text: currentDefault, resetsToDefault: true)
        }
        return migrated(stored).map { Proposal(text: $0, resetsToDefault: false) }
    }

    /// `text` with its it2 command lines brought up to date, or nil if none needs it. Lines are
    /// split on \n only, so \r\n endings survive unchanged.
    static func migrated(_ text: String) -> String? {
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let updated = migratedLine(line) else {
                return line
            }
            changed = true
            return updated
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    /// One command line brought up to date, or nil if it is not a command line or needs nothing.
    private static func migratedLine(_ line: String) -> String? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        var rest = String(line.dropFirst(indentation.count))
        var changed = false
        if commandArguments(rest, command: "it2") != nil {
            rest = CodeReviewIt2.placeholder + rest.dropFirst(3)
            changed = true
        }
        guard let arguments = commandArguments(rest, command: CodeReviewIt2.placeholder) else {
            return nil
        }
        if let readdressed = readdressed(arguments) {
            rest = String(rest.prefix(rest.count - arguments.count)) + readdressed
            changed = true
        }
        return changed ? indentation + rest : nil
    }

    /// What follows `command` and one of the subcommands on `line`, or nil if the line doesn't
    /// run one.
    private static func commandArguments(_ line: String, command: String) -> String? {
        guard line.hasPrefix(command) else {
            return nil
        }
        let afterCommand = line.dropFirst(command.count)
        guard let first = afterCommand.first, first == " " || first == "\t" else {
            return nil
        }
        let words = afterCommand.drop { $0 == " " || $0 == "\t" }
        for subcommand in subcommands where words.hasPrefix(subcommand) {
            let after = words.dropFirst(subcommand.count)
            if after.isEmpty || after.first == " " || after.first == "\t" {
                return String(after)
            }
        }
        return nil
    }

    /// The arguments with an old --session among the leading options replaced, or nil if there is
    /// none. Only the options before the first other argument are read, so text in a title or
    /// detail that happens to say --session is left alone.
    private static func readdressed(_ arguments: String) -> String? {
        let tokens = shellWords(arguments)
        var hasTmux = false
        var old: Range<String.Index>?
        var i = 0
        while i < tokens.count {
            let word = String(arguments[tokens[i]])
            guard word.hasPrefix("--") else {
                break
            }
            let name = word.split(separator: "=", maxSplits: 1).first.map(String.init) ?? word
            let takesValue = ["--tmux", "--tmux-pane", "--session"].contains(name) && !word.contains("=")
            if name == "--tmux" || name == "--tmux-pane" {
                hasTmux = true
            }
            if name == "--session" {
                if word.contains("=") {
                    if oldSessionValues.contains(String(word.dropFirst("--session=".count))) {
                        old = tokens[i]
                    }
                } else if i + 1 < tokens.count, oldSessionValues.contains(String(arguments[tokens[i + 1]])) {
                    old = tokens[i].lowerBound..<tokens[i + 1].upperBound
                }
            }
            i += takesValue ? 2 : 1
        }
        guard let old else {
            return nil
        }
        var result = arguments
        result.replaceSubrange(old, with: hasTmux ? sessionOnly : addressing)
        return result
    }

    /// The ranges of the words in `text` as sh splits them: at unquoted spaces and tabs, with
    /// quotes and backslashes kept in the word.
    private static func shellWords(_ text: String) -> [Range<String.Index>] {
        var words = [Range<String.Index>]()
        var start: String.Index?
        var quote: Character?
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if escaped {
                escaped = false
            } else if c == "\\" && quote != "'" {
                escaped = true
                start = start ?? index
            } else if let open = quote {
                if c == open {
                    quote = nil
                }
            } else if c == "'" || c == "\"" {
                quote = c
                start = start ?? index
            } else if c == " " || c == "\t" || c == "\r" {
                if let begin = start {
                    words.append(begin..<index)
                    start = nil
                }
            } else {
                start = start ?? index
            }
            index = text.index(after: index)
        }
        if let begin = start {
            words.append(begin..<text.endIndex)
        }
        return words
    }

    static func sha256(_ text: String) -> String {
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum Answer {
        case update
        case keep
        /// The offer was closed: ask again next time.
        case undecided
    }

    /// What to store, after asking if there is something to offer that the user hasn't kept.
    struct Outcome: Equatable {
        /// The prompt to store, nil to store none (the default applies); absent to leave it.
        var prompt: String??
        /// The hash to remember as kept; absent to leave it.
        var keptHash: String?
        var asked: Bool
    }

    /// Whether to ask, and what the answer means, for the stored prompt `stored` (nil when none is
    /// stored), given the hash of a prompt the user kept.
    static func decide(stored: String?,
                       currentDefault: String,
                       keptHash: String?,
                       ask: (_ stored: String, _ proposal: Proposal) -> Answer) -> Outcome {
        guard let stored, let proposal = proposal(stored: stored, currentDefault: currentDefault) else {
            return Outcome(prompt: .none, keptHash: nil, asked: false)
        }
        var memory = KeepMemory(storedHash: keptHash)
        guard !memory.kept(stored) else {
            return Outcome(prompt: .none, keptHash: nil, asked: false)
        }
        switch ask(stored, proposal) {
        case .update:
            return Outcome(prompt: .some(proposal.resetsToDefault ? nil : proposal.text), keptHash: nil, asked: true)
        case .keep:
            memory.keep(stored)
            return Outcome(prompt: .none, keptHash: memory.storedHash, asked: true)
        case .undecided:
            return Outcome(prompt: .none, keptHash: nil, asked: true)
        }
    }

    /// The prompt the user chose to keep, by hash, so the same text isn't offered again and an
    /// edited one is.
    struct KeepMemory {
        private(set) var storedHash: String?

        init(storedHash: String?) {
            self.storedHash = storedHash
        }

        func kept(_ text: String) -> Bool {
            return storedHash == CodeReviewPromptMigration.sha256(text)
        }

        mutating func keep(_ text: String) {
            storedHash = CodeReviewPromptMigration.sha256(text)
        }
    }
}
