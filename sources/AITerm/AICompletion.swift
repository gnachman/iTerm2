//
//  AICompletion.swift
//  iTerm2
//
//  Created by George Nachman on 2/27/25.
//

fileprivate let filePlaceholder = "{{FILE}}"

class AICompletion {
    struct PreviouslyRunCommand {
        var command: String
        var workingDirectory: String?
        var date: Date
    }
    static func suggestionCompletions(_ request: SuggestionRequest,
                                      history: ArraySlice<PreviouslyRunCommand>,
                                      files: [CompletionItem],
                                      completion: @escaping ([CompletionItem]) -> ()) {
        DLog("Requesting AI completion")
        if !iTermAITermGatekeeper.check(silent: true) {
            DLog("Failed gatekeeper")
            completion(files)
            return
        }
        let (prompt, prefix) = request.aiPrompt(history: history,
                                                files: files.map { $0.value },
                                                prefix: request.prefix)
        let conversation =
        AIConversation(
            registrationProvider: nil,
            messages: [
                AITermController.Message(
                    role: .user,
                    content: prompt,
                    name: nil,
                    function_call: nil)])
        DLog("Completing…")
        AIConversation.completeOneShot(conversation) { result in
            DLog("Have completion")
            result.handle { updated in
                DLog("Handle success")
                guard let content = updated.messages.last?.body.content else {
                    DLog("No content")
                    completion(files)
                    return
                }
                var expandedFiles = false
                var completions = content
                    .components(separatedBy: "\n")
                    .compactMap { line -> CompletionItem? in
                        AICompletion.completionItem(fromLine: line, prefix: prefix)
                    }.flatMap { (completion: CompletionItem) -> [CompletionItem] in
                        if completion.value.contains(filePlaceholder) {
                            expandedFiles = true
                            return files
                                .sorted {
                                    $0.value < $1.value
                                }.map { (file: CompletionItem) -> CompletionItem in
                                    // Substitute the filename into the surrounding text rather than
                                    // replacing the whole value with the bare filename. For a
                                    // replacement (`rm {{FILE}}`) the verb must be preserved so the
                                    // accepted command is `rm error.log`, not just `error.log`.
                                    CompletionItem(value: completion.value.replacingOccurrences(of: filePlaceholder,
                                                                                                with: file.value),
                                                   detail: completion.detail,
                                                   kind: completion.kind)
                                }
                        } else if completion.value.contains("{{") {
                            // ChatGPT 4o likes to use {{DIRECTORY}} and {{MESSAGE}} even though I told it not to
                            let pattern = "\\{\\{([A-Z0-9_]+)\\}\\}"
                            let regex = try! NSRegularExpression(pattern: pattern)

                            let replacement = regex.stringByReplacingMatches(
                                in: completion.value,
                                options: [],
                                range: NSRange(completion.value.startIndex..., in: completion.value), withTemplate: "($1)")
                            return [CompletionItem(value: replacement,
                                                   detail: completion.detail,
                                                   kind: completion.kind)]
                        } else {
                            return [completion]
                        }
                    }
                if !files.isEmpty && !expandedFiles {
                    completions.append(contentsOf: files)
                }
                DLog("Success")
                completion(completions.withoutDuplicates { $0.value })
            } failure: { error in
                DLog("Error: \(error.localizedDescription)")
                completion(files)
            }
        }
    }

    // Parse one line of the model's response into a completion item. The model is
    // asked to emit `mode<TAB>description<TAB>suggestion` where mode is `append`
    // (finish what the user typed) or `replace` (a full command that takes the
    // place of what the user typed). A two-field line carries no mode.
    //
    // The model is unreliable about the mode. Small and local models in particular
    // mislabel it or omit it, and appending a full command after a natural-language
    // request is exactly the bug this guards against. So the declared mode is only
    // advisory: the deterministic relationship between the suggestion and what the
    // user typed is the source of truth, and we reconcile the two here.
    //
    // - If the suggestion begins with what the user typed, it continues the line:
    //   only the remainder is inserted (kind `.aiSuggestion`). This holds even when
    //   the model said `replace`, because inserting the remainder is both correct
    //   and less destructive than replacing.
    // - If the suggestion does not begin with the typed text and shares no partial
    //   overlap with it, it is a full command that takes the place of the whole line
    //   (kind `.aiReplacement`). This holds even when the model said `append`.
    // - The declared mode only breaks the tie in the genuinely ambiguous middle: a
    //   suggestion that overlaps a partially-typed word (e.g. `re` -> `reset`). There
    //   an explicit `replace` is honored; otherwise it is treated as a completion.
    static func completionItem(fromLine line: String, prefix: String) -> CompletionItem? {
        let parts = line.components(separatedBy: "\t")
        let mode: String
        let description: String
        let suggestion: String
        switch parts.count {
        case 3:
            mode = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            description = parts[1]
            suggestion = parts[2]
        case 2:
            // No mode field: infer entirely from the prefix relationship below.
            mode = ""
            description = parts[0]
            suggestion = parts[1]
        default:
            return nil
        }

        // The suggestion continues exactly what the user typed: append the remainder.
        if suggestion.hasPrefix(prefix) {
            let remainder = suggestion.removing(prefix: prefix)
            guard !remainder.isEmpty else {
                // Restates the prefix and adds nothing; not a useful suggestion.
                return nil
            }
            return CompletionItem(value: String(remainder),
                                  detail: description,
                                  kind: .aiSuggestion)
        }

        // No full-prefix match. The suggestion may still complete a partially-typed
        // trailing token (`git reba` -> `git rebase`, where the model returned only
        // `rebase`). Accept that only when the overlap covers the entire trailing
        // token AND is at least two characters. A coincidental one- or few-character
        // overlap between the tail of an English word and the start of a command
        // (e.g. `list files as a table` ending in `e`, command `exa -l`) must NOT
        // turn a full command into an append -- that is the exact garbage this
        // feature exists to prevent, and it recurs with mode-omitting local models.
        let truncated = suggestion.removingPrefixThatIsLongestSuffix(of: prefix)
        let overlapLength = suggestion.count - truncated.count
        let trailingToken = prefix.components(separatedBy: .whitespacesAndNewlines).last ?? ""
        let completesTrailingToken = overlapLength >= 2 && overlapLength == trailingToken.count
        if completesTrailingToken && mode != "replace" {
            return CompletionItem(value: String(truncated),
                                  detail: description,
                                  kind: .aiSuggestion)
        }

        // The suggestion does not continue the typed text (or the model explicitly
        // asked to replace it despite the overlap): it is a full command that takes
        // the place of the whole line.
        guard !suggestion.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return CompletionItem(value: suggestion,
                              detail: description,
                              kind: .aiReplacement)
    }
}

fileprivate extension SuggestionRequest {
    func aiPrompt(history: ArraySlice<AICompletion.PreviouslyRunCommand>,
                  files: [String],
                  prefix: String) -> (String, String) {
        var lines = ["You are offering command line completion suggestions and descriptions."]
        lines.append("The user is editing a shell command line. For the text they have entered so far, decide whether it is the beginning of a shell command that should be completed, or a natural-language description of what they want to do that should be turned into a command.")
        lines.append("Respond with one suggestion per line.")
        lines.append("Each line must consist of a mode, a tab, a 2-5 word description, a tab, and finally the suggestion.")
        lines.append("The mode is the word `append` when the suggestion finishes the command the user has begun typing, or `replace` when the suggestion is a complete command that should take the place of what the user typed.")
        lines.append("Return no more than \(4) lines. You may return fewer or none rather than poor quality suggestions.")
        lines.append("For example, if the text so far was `git re` then you might respond with `append\tRewrite commit history\tgit rebase` and `append\tRevert a commit\tgit revert`.")
        lines.append("Use `append` when the text so far looks like the start of a valid command. For an `append` suggestion, the text after the final tab must begin with the literal text the user has entered so far, because only the portion beyond what they typed will be appended.")
        lines.append("Use `replace` when the text reads as an English request rather than a command. For example, if the text so far was `delete every .log file in this folder` you might respond with `replace\tRemove log files\trm ./*.log`. A `replace` suggestion does not need to begin with what the user typed; it will replace the entire line.")
        lines.append("You can suggest more than one additional word when you can tell from context that it would be a good suggestion. For example, if the user frequently runs `grep ERROR <file> | sort | uniq` and you see that the text so far is `grep ERROR myfile.txt` your response could include `append\tCount unique errors\tgrep ERROR myfile.txt | sort | uniq`")
        if let workingDirectory {
            lines.append("The current working directory is \(workingDirectory)")
        }
        if executable {
            lines.append("The user appears to be entering the name of a command to execute, not one of its arguments, so completions should be for executable commands likely to be present on the system.")
        }
        lines.append("Each suggestion is either appended after what has been typed (mode `append`) or replaces the whole line (mode `replace`), according to its mode.")
        if !history.isEmpty {
            lines.append("Previously run commands in chronological order are:")
            for entry in history {
                lines.append(entry.command.replacingOccurrences(of: "\n", with: " "))
            }
            lines.append("(end of command list)")
            lines.append("Your suggestions should take recently run commands into consideration: if possible, suggest a command that builds on what the user has begun.")
            lines.append("")
        }
        lines.append("Do not make up or invent file or directory names.")
        lines.append("If a suggestion would end with a filename, use \(filePlaceholder) instead.")
        lines.append("Do not invent other kinds of placeholders such as {{MESSAGE}} or {{DIRECTORY}}. Use plain English, like \"message\", instead.")
        if files.lengthOfLongestCommonPrefix > 0 {
            let lcp = String(files.longestCommonPrefix)
            lines.append("Instead, your suggestion may end with the longest common prefix of valid filename completions, which is: \(lcp)")
        }
        let sanitized = fullPrefix.replacingOccurrences(of: "\n", with: " ")
        lines.append("The text the user has entered so far is:")
        lines.append(sanitized)

        if !fullSuffix.trimmingLeadingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Additionally, there is some text after the cursor. Use this to come up with better suggestions, assuming it will be used after what you suggest or that your suggestion will replace some of it. It is:")
            lines.append(fullSuffix.replacingOccurrences(of: "\n", with: " "))
        }
        return (lines.joined(separator: "\n"), sanitized)
    }
}

@objc(iTermCompletionItem)
class CompletionItem: NSObject {
    @objc let value: String
    @objc let detail: String?
    @objc let kind: Kind

    @objc(iTermCompletionItemKind) enum Kind: Int {
        case file
        case aiSuggestion
        case history
        case command
        case folder
        case webSearch
        case navigation
        case bookmark
        // A full command that should replace everything the user typed, rather
        // than be appended to it. Used when the user typed a natural-language
        // request instead of the beginning of a command.
        case aiReplacement
    }

    @objc(initWithValue:detail:kind:)
    init(value: String, detail: String?, kind: Kind) {
        #if DEBUG
        it_assert(!(detail ?? "").contains("<iTermCompletionItem"))
        #endif
        self.value = value
        self.detail = detail
        self.kind = kind
    }

    @objc
    func mapValue(_ closure: (String) -> (String)) -> CompletionItem {
        return CompletionItem(value: closure(value), detail: detail, kind: kind)
    }
}
