//
//  iTermAdblockParser.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Foundation

@available(macOS 11.0, *)
class iTermAdblockParser {
    
    // MARK: - Public Interface
    
    static func parseAdblockList(_ content: String) -> String? {
        let parser = iTermAdblockParser()
        return parser.convertToWebKitJSON(content)
    }
    
    // MARK: - Private Implementation
    
    private func convertToWebKitJSON(_ content: String) -> String? {
        let rules = parseRules(content)
        let webkitRules = convertToWebKitRules(rules)
        
        guard !webkitRules.isEmpty else {
            return nil
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(webkitRules)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("Failed to serialize WebKit rules to JSON: \(error)")
            return nil
        }
    }
    
    private func parseRules(_ content: String) -> [AdblockRule] {
        var rules: [AdblockRule] = []
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
                continue
            }
            
            if let rule = parseRule(trimmed) {
                rules.append(rule)
            }
        }
        
        return rules
    }
    
    private func parseRule(_ line: String) -> AdblockRule? {
        // Element hiding rules (cosmetic filters)
        if line.contains("##") {
            return parseElementHidingRule(line)
        }
        
        // Network blocking rules
        return parseNetworkRule(line)
    }
    
    // Updated parseElementHidingRule to strip $options and preserve selector cleanly
    private func parseElementHidingRule(_ line: String) -> AdblockRule? {
        // Split into optional domain-list and selector+options
        let parts = line.components(separatedBy: "##")
        guard parts.count == 2 else { return nil }

        let domainPart = parts[0]
        let rightPart = parts[1]

        // Extract selector and any $-options
        let selectorText: String
        var options: [String] = []
        if let dollarIndex = rightPart.firstIndex(of: "$") {
            // Text before '$' is the selector
            selectorText = String(rightPart[..<dollarIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Text after '$' are options
            let opts = String(rightPart[rightPart.index(after: dollarIndex)...])
            options = opts
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            selectorText = rightPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Skip invalid selectors
        if selectorText.isEmpty || selectorText.contains("'") || selectorText.contains("\"") {
            return nil
        }

        // Skip selectors with non-ASCII characters
        guard selectorText.allSatisfy({ $0.isASCII }) else {
            return nil
        }

        // Parse domains (if any)
        let domains: [String]
        if domainPart.isEmpty {
            domains = []
        } else {
            domains = domainPart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        return AdblockRule(
            type: .elementHiding,
            pattern: selectorText,
            domains: domains,
            options: options,
            originalString: line
        )
    }


    private func parseNetworkRule(_ line: String) -> AdblockRule? {
        // 1) Slash-delimited regex literal?
        if line.hasPrefix("/") {
            // find the true (unescaped) closing slash
            var idx = line.index(after: line.startIndex)
            var closing: String.Index?
            while idx < line.endIndex {
                if line[idx] == "/" {
                    // count backslashes before it
                    var bs = 0
                    var bidx = line.index(before: idx)
                    while bidx >= line.startIndex && line[bidx] == "\\" {
                        bs += 1
                        if bidx > line.startIndex {
                            bidx = line.index(before: bidx)
                        } else {
                            break
                        }
                    }
                    if bs % 2 == 0 {
                        closing = idx
                        break
                    }
                }
                idx = line.index(after: idx)
            }
            if let close = closing {
                let inner = String(line[line.index(after: line.startIndex)..<close])
                let remainder = String(line[line.index(after: close)...])

                // Reject unsupported regex syntax (character classes, quantifiers, grouping/alternation)
                let badTokens = ["[", "]", "{", "}", "\\w", "\\d", "\\p", "(?", "(", "|"]
                if badTokens.contains(where: inner.contains) {
                    return nil
                }
                // sanity-check
                guard (try? NSRegularExpression(pattern: inner)) != nil else {
                    return nil
                }

                // parse any $options after the literal
                var opts: [String] = []
                if remainder.hasPrefix("$") {
                    opts = remainder
                        .dropFirst()
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                let (domains, filteredOptions) = splitDomainFromOptions(opts)
                return AdblockRule(
                    type: .networkBlock,
                    pattern: inner,
                    domains: domains,
                    options: filteredOptions,
                    originalString: line
                )
            }
        }

        // 2) Fallback for Adblock-style patterns
        var ruleText = line
        var options: [String] = []

        // 2a) Extract $-options
        if let dollarIdx = ruleText.lastIndex(of: "$") {
            let opts = String(ruleText[ruleText.index(after: dollarIdx)...])
            options = opts
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ruleText = String(ruleText[..<dollarIdx])
        }

        // 2b) Exception prefix?
        let isException = ruleText.hasPrefix("@@")
        if isException {
            ruleText.removeFirst(2)
        }

        // 2c) ASCII-only
        guard ruleText.allSatisfy({ $0.isASCII }) else {
            return nil
        }

        // 2d) Split out domain=… options
        let (domains, filteredOptions) = splitDomainFromOptions(options)

        // 2e) Convert the rest to a WebKit-safe regex
        guard let pattern = convertPatternToRegex(ruleText) else {
            return nil
        }

        return AdblockRule(
            type: isException ? .exception : .networkBlock,
            pattern: pattern,
            domains: domains,
            options: filteredOptions,
            originalString: line
        )
    }


    /// Helper to split out `domain=…` options
    private func splitDomainFromOptions(_ options: [String]) -> (domains: [String], filtered: [String]) {
        var domains: [String] = []
        var filtered: [String] = []
        for opt in options {
            let lower = opt.lowercased()
            if lower.hasPrefix("domain=") {
                let list = opt
                    .dropFirst("domain=".count)
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                domains.append(contentsOf: list)
            } else {
                filtered.append(opt)
            }
        }
        return (domains, filtered)
    }

    private func convertPatternToRegex(_ pattern: String) -> String? {
        var text = pattern
        var prefix = ""
        var suffix = ""

        // 1) Strip off AdBlock anchors
        if text.hasPrefix("||") {
            text.removeFirst(2)
            prefix = #"^[^:/?#]*://(([^./]+\.)*)"#
            suffix = "$"                    // enforce end-of-string
        }
        else if text.hasPrefix("|") {
            text.removeFirst(1)
            prefix = "^"
        }
        if text.hasSuffix("|") {
            text.removeLast(1)
            suffix = "$"
        }

        // 2) Replace literal '^' and '*' with placeholders
        let sepPlaceholder  = "__SEP__"
        let starPlaceholder = "__STAR__"
        text = text
            .replacingOccurrences(of: "^", with: sepPlaceholder)
            .replacingOccurrences(of: "*", with: starPlaceholder)

        // 3) Escape everything else
        let escaped = NSRegularExpression.escapedPattern(for: text)

        // 4) Restore wildcards and separator **without** any grouping
        //    - "__STAR__" → ".*"
        //    - "__SEP__"  → "[/?#]?"  (zero or one of /, ? or #)
        let withStars = escaped.replacingOccurrences(of: starPlaceholder, with: ".*")
        let body      = withStars.replacingOccurrences(of: sepPlaceholder,  with: "[/?#]?")

        // 5) Assemble final regex
        let regex = prefix + body + suffix

        // 6) Sanity-check
        if (try? NSRegularExpression(pattern: regex)) != nil {
            return regex
        }
        return nil
    }

    private func escapeForRegex(_ pattern: String) -> String {
        return pattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "^", with: "([/?#]|$)")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "+", with: "\\+")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "|", with: "\\|")
    }
    
    private func convertToWebKitRules(_ rules: [AdblockRule]) -> [WebKitContentRule] {
        var webkitRules: [WebKitContentRule] = []

        // 1) Cosmetic exceptions (#@#...)
        for rule in rules where rule.originalString.contains("#@#") {
            let trigger = WebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: rule.domains.isEmpty ? nil : rule.domains
            )
            let action = WebKitAction(
                type: "ignore-previous-rules",
                selector: nil
            )
            webkitRules.append(WebKitContentRule(trigger: trigger, action: action))
        }

        // 2) True element-hiding rules (##...)
        var selectorsByDomain: [String: [String]] = [:]
        for rule in rules where rule.type == .elementHiding {
            let key = rule.domains.joined(separator: ",")
            selectorsByDomain[key, default: []].append(rule.pattern)
        }
        for (key, selectors) in selectorsByDomain {
            let domains = key.isEmpty ? [] : key.components(separatedBy: ",")
            let trigger = WebKitTrigger(
                urlFilter: ".*",
                resourceType: nil,
                ifDomain: domains.isEmpty ? nil : domains
            )
            let action = WebKitAction(
                type: "css-display-none",
                selector: selectors.joined(separator: ", ")
            )
            webkitRules.append(WebKitContentRule(trigger: trigger, action: action))
        }

        // 3) Network blocks & whitelist exceptions
        let defaultTypes = [
            "document",
            "image",
            "style-sheet",
            "script",
            "font",
            "raw",
            "svg-document"
        ]
        for rule in rules where rule.type == .networkBlock || rule.type == .exception {
            // skip cosmetic exceptions
            if rule.originalString.contains("#@#") {
                continue
            }

            // Determine if this is a raw-regex literal
            let isRawRegex = rule.originalString.hasPrefix("/") &&
            rule.originalString.dropFirst().contains("/")

            // Filter out auxiliary options
            let userOptions = rule.options.filter { opt in
                let lower = opt.lowercased()
                return lower != "third-party" && lower != "~third-party" && lower != "match-case"
            }
            let explicitTypes = getResourceTypes(from: userOptions)

            let resourceTypes: [String]?
            if isRawRegex {
                // raw regex: no options => default, any options => all resources
                resourceTypes = rule.options.isEmpty ? defaultTypes : nil
            } else {
                if rule.options.isEmpty {
                    // no options at all => default
                    resourceTypes = defaultTypes
                } else if userOptions.isEmpty {
                    // had only auxiliary options => default
                    resourceTypes = defaultTypes
                } else if explicitTypes.isEmpty {
                    // options but none map to types => all resources
                    resourceTypes = nil
                } else {
                    // explicit resource-type filters
                    resourceTypes = explicitTypes
                }
            }

            let trigger = WebKitTrigger(
                urlFilter: rule.pattern,
                resourceType: resourceTypes,
                ifDomain: rule.domains.isEmpty ? nil : rule.domains
            )
            let action = WebKitAction(
                type: rule.type == .exception ? "ignore-previous-rules" : "block",
                selector: nil
            )
            webkitRules.append(WebKitContentRule(trigger: trigger, action: action))
        }

        return webkitRules
    }




    private func getResourceTypes(from options: [String]) -> [String] {
        var types: [String] = []
        
        for option in options {
            switch option.lowercased() {
            case "script":
                types.append("script")
            case "stylesheet", "style":
                types.append("style-sheet")
            case "image":
                types.append("image")
            case "font":
                types.append("font")
            case "document":
                types.append("document")
            case "xmlhttprequest", "xhr":
                types.append("raw")
            default:
                break
            }
        }
        
        return types
    }
}

// MARK: - Supporting Types

@available(macOS 11.0, *)
private struct AdblockRule {
    enum RuleType {
        case networkBlock
        case exception
        case elementHiding
    }
    
    let type: RuleType
    let pattern: String
    let domains: [String]
    let options: [String]

    let originalString: String
}

@available(macOS 11.0, *)
private struct WebKitContentRule: Codable {
    let trigger: WebKitTrigger
    let action: WebKitAction
}

@available(macOS 11.0, *)
private struct WebKitTrigger: Codable {
    let urlFilter: String
    let resourceType: [String]?
    let ifDomain: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case resourceType = "resource-type"
        case ifDomain = "if-domain"
    }
}

@available(macOS 11.0, *)
private struct WebKitAction: Codable {
    let type: String
    let selector: String?
}
