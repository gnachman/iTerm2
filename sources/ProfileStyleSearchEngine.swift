//
//  ProfileStyleSearchEngine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/13/24.
//

import Foundation

extension NSAttributedString {
    @objc(highlightMatchesForQuery:phraseIdentifier:)
    func highlight(query: String, phraseIdentifier: String) -> NSAttributedString {
        if query.isEmpty {
            return self
        }
        var tags = [String]()
        var phrases = [String: String]()
        if phraseIdentifier == kTagRestrictionOperator {
            tags.append(string)
        } else {
            phrases[phraseIdentifier] = string
        }
        let doc = ProfileStyleSearchEngineDocument(phrases: phrases, tags: tags)
        let query = ProfileStyleSearchEngineQuery(query: query, operators: [phraseIdentifier])
        let engine = ProfileStyleSearchEngine(query: query)
        if let result = engine.search(document: doc, sloppy: true), let indexes = result.phraseIndexes[phraseIdentifier] {
            return highlight(indexes: indexes)
        }
        return self
    }

    func highlight(indexes: IndexSet) -> NSAttributedString {
        let result = mutableCopy() as! NSMutableAttributedString
        for range in indexes.rangeView {
            result.highlight(range: NSRange(range))
        }

        return result
    }
}

extension NSMutableAttributedString {
    func highlight(range: NSRange) {
        let fontManager = NSFontManager.shared
        enumerateAttributes(in: range, options: []) { attrs, range, stopPtr in
            var modifiedAttrs = attrs
            modifiedAttrs[.backgroundColor] = NSColor.yellow
            modifiedAttrs[.foregroundColor] = NSColor.black
            if let obj = attrs[.font], let font = obj as? NSFont {
                let bold = fontManager.convert(font, toHaveTrait: .boldFontMask)
                modifiedAttrs[.font] = bold
            }
            setAttributes(modifiedAttrs, range: range)
        }
    }
}

@objc(iTermProfileStyleSearchEngineResult)
class ProfileStyleSearchEngineResult: NSObject {
    // Maps a phrase identifier to an indexset of matches in the corresponding phrase.
    // For tags, the phrase identifier is "tag:"+tagname.
    // For other parts, the phrase identifier equals the operator name (e.g., "text:").
    fileprivate(set) var phraseIndexes = [String: IndexSet]()

    @objc func highlight(attributedString: NSAttributedString,
                         operator op: String) -> NSAttributedString {
        if let indexSet = phraseIndexes[op] {
            return attributedString.highlight(indexes: indexSet)
        }
        return attributedString
    }
}

@objc(iTermProfileStyleSearchEngineQuery)
class ProfileStyleSearchEngineQuery: NSObject {
    private(set) var tokens: [iTermProfileSearchToken]

    @objc var hasTags: Bool {
        return tokens.anySatisfies { token in
            token.isTag
        }
    }
    
    @objc
    init(query: String, operators: [String]) {
        let phrases = (query as NSString).componentsBySplittingProfileListQuery() ?? []
        tokens = phrases.map {
            iTermProfileSearchToken(phrase: $0, operators: operators)
        }
    }

    @objc(addTag:)
    func add(tag: String) {
        tokens.append(iTermProfileSearchToken(tag: tag))
    }
}

@objc(iTermProfileStyleSearchEngineDocument)
class ProfileStyleSearchEngineDocument: NSObject {
    let phrases: [String: String]
    let tags: [String]

    // Phrases map operator (e.g., "text:") to value (e.g., the content of a document)
    @objc(initWithPhrases:tags:)
    init(phrases: [String: String], tags: [String]) {
        self.phrases = phrases
        self.tags = tags
    }
}

@objc(iTermProfileStyleSearchEngine)
class ProfileStyleSearchEngine: NSObject {
    let query: ProfileStyleSearchEngineQuery

    @objc
    init(query: ProfileStyleSearchEngineQuery) {
        self.query = query
    }

    // Returns nil if the document does not match the query.
    // Sloppy search doesn't quit when a token fails to match. It's used when you want to know which
    // ranges matched (perhaps when only part of the document is available so match failures are expected).
    @objc
    func search(document: ProfileStyleSearchEngineDocument,
                sloppy: Bool = false) -> ProfileStyleSearchEngineResult? {
        let result = ProfileStyleSearchEngineResult()
        if query.tokens.isEmpty {
            return result
        }
        // First iterate over query tokens because all must be satisfied.
        for queryToken in query.tokens {
            let status = search(queryToken: queryToken, document: document, result: result)
            if sloppy {
                continue
            }
            switch status {
            case .excluded:
                return nil
            case .matched:
                break
            case .none:
                if !queryToken.negated {
                    return nil
                }
            }
        }
        return result
    }

    private enum SearchStatus {
        case none
        case matched
        case excluded
    }

    private func search(queryToken: iTermProfileSearchToken,
                        document: ProfileStyleSearchEngineDocument,
                        result: ProfileStyleSearchEngineResult) -> SearchStatus {
        var foundAnyMatches = false

        switch searchPhrases(queryToken: queryToken, phrases: document.phrases, result: result) {
        case .none:
            break
        case .matched:
            foundAnyMatches = true
        case .excluded:
            return .excluded
        }

        switch searchTags(queryToken: queryToken, tags: document.tags, result: result) {
        case .none:
            break
        case .matched:
            foundAnyMatches = true
        case .excluded:
            return .excluded
        }

        return foundAnyMatches ? .matched : .none
    }

    private func searchPhrases(queryToken: iTermProfileSearchToken,
                               phrases: [String: String],
                               result: ProfileStyleSearchEngineResult) -> SearchStatus {
        var status = SearchStatus.none
        for kvp in phrases {
            let (op, content) = (kvp.key, kvp.value)
            guard let matchingIndexes = search(queryToken: queryToken, phrase: content, operator: op) else {
                return .excluded
            }
            if matchingIndexes.count > 0 {
                status = .matched
                result.phraseIndexes[op, default: IndexSet()].insert(integersIn: matchingIndexes)
            }
        }
        return status

    }

    private func searchTags(queryToken: iTermProfileSearchToken,
                            tags: [String],
                            result: ProfileStyleSearchEngineResult) -> SearchStatus {
        var status = SearchStatus.none
        for tag in tags {
            let tagWords = tag.components(separatedBy: .whitespaces)
            let found = queryToken.matchesAnyWord(inTagWords: tagWords)
            if found {
                if queryToken.negated {
                    return .excluded
                }
                if let range = Range(queryToken.range) {
                    result.phraseIndexes[kTagRestrictionOperator + tag, default: IndexSet()].insert(integersIn: range)
                    status = .matched
                }
            }
        }
        return status
    }

    // Returns nil if the phrase includes a negated token.
    // Returns an empty range if no match was found.
    // Otherwise, returns the range that matched.
    private func search(queryToken: iTermProfileSearchToken, phrase: String, operator op: String) -> Range<Int>? {
        let phraseWords = phrase.components(separatedBy: .whitespacesAndNewlines)
        let found = queryToken.matchesAnyWord(in: phraseWords, operator: op)
        guard found else {
            return 0..<0
        }
        if queryToken.negated {
            return nil
        }
        return Range(queryToken.range)
    }

    private func search(phrase: String) -> IndexSet? {
        let documentTokens = phrase.components(separatedBy: .whitespacesAndNewlines)
        var result = IndexSet()
        for queryToken in query.tokens {
            let found = queryToken.matchesAnyWord(inNameWords: documentTokens)
            if found {
                if queryToken.negated {
                    return nil
                }
                if let range = Range(queryToken.range) {
                    result.insert(integersIn: range)
                }
            }
        }
        return result
    }
}
