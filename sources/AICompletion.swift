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
    private static var conversations = [UUID: AIConversation]()

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
        var conversation =
        AIConversation(
            registrationProvider: nil,
            messages: [
                AITermController.Message(
                    role: .user,
                    content: prompt,
                    name: nil,
                    function_call: nil)])
        let uuid = UUID()
        conversations[uuid] = conversation
        DLog("Completing…")
        conversation.complete(streaming: nil) { result in
            DLog("Have completion")
            result.handle { updated in
                DLog("Handle success")
                guard let content = updated.messages.last?.content else {
                    DLog("No content")
                    completion(files)
                    return
                }
                var expandedFiles = false
                var completions = content
                    .components(separatedBy: "\n")
                    .compactMap { line -> CompletionItem? in
                        let parts = line.components(separatedBy: "\t")
                        guard parts.count == 2 else {
                            return nil
                        }
                        let description = parts[0]
                        let suggestion = parts[1]

                        if suggestion.hasPrefix(prefix) {
                            return CompletionItem(value: String(suggestion.removing(prefix: prefix)),
                                                  detail: description,
                                                  kind: .aiSuggestion)
                        } else {
                            let truncated = suggestion.removingPrefixThatIsLongestSuffix(of: prefix)
                            if !truncated.isEmpty {
                                return CompletionItem(value: String(truncated),
                                                      detail: description,
                                                      kind: .aiSuggestion)
                            }
                        }
                        return nil
                    }.flatMap { (completion: CompletionItem) -> [CompletionItem] in
                        if completion.value.contains(filePlaceholder) {
                            expandedFiles = true
                            return files
                                .sorted {
                                    $0.value < $1.value
                                }.map { (file: CompletionItem) -> CompletionItem in
                                    CompletionItem(value: file.value,
                                                   detail: completion.detail,
                                                   kind: .aiSuggestion)
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
                                                   kind: .aiSuggestion)]
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
            conversations.removeValue(forKey: uuid)
        }
    }
}

fileprivate extension SuggestionRequest {
    func aiPrompt(history: ArraySlice<AICompletion.PreviouslyRunCommand>,
                  files: [String],
                  prefix: String) -> (String, String) {
        var lines = ["You are offering command line completion suggestions and descriptions."]
        lines.append("Respond with one description + suggestion per line.")
        lines.append("Each line should consist of a 2-5 word description, followed by a tab, followed by the suggestion.")
        lines.append("Return no more than \(4) lines. You may return fewer or none rather than poor quality suggestions.")
        lines.append("For example, if the command so far was `git re` then you might suggest `Rewrite commit history\tgit rebase`, `Rewrite commit history\tgit revert`, and `Move branch pointer\tgit reset`. ")
        lines.append("After the tab, the suggestion should begin with the literal text the user has entered so far.")
        lines.append("You can suggest more than one additional word when you can tell from context that it would be a good suggestion. For example, if the user frequently runs `grep ERROR <file> | sort | uniq` and you see that the text so far is `grep ERROR myfile.txt` your response could include `Count unique errors\tgrep ERROR myfile.txt | sort | uniq`")
        if let workingDirectory {
            lines.append("The current working directory is \(workingDirectory)")
        }
        if executable {
            lines.append("The user appears to be entering the name of a command to execute, not one of its arguments, so completions should be for executable commands likely to be present on the system.")
        }
        lines.append("The suggestion in each line you respond with is a candidate to append after what has been typed so far.")
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
        lines.append("The text the user has entered so far, which needs completion, is:")
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
