//
//  iTermBrowserSuggestionsController.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

@available(macOS 11.0, *)
class iTermBrowserSuggestionsController {
    private let tailTruncatingAttributes: [NSAttributedString.Key: Any]
    private let midTruncatingAttributes: [NSAttributedString.Key: Any]
    let historyController: iTermBrowserHistoryController
    struct ScoredSuggestion {
        let suggestion: URLSuggestion
        let score: Int
    }

    enum Score: Int {
        case strongSearch = 1_000_001
        case strongURL = 1_000_000
        case weakSearch = 999_999
        case weakURL = 999_998
        case bookmarks = 500_000  // visit count gets added to this, and bookmarks take priority over history
        case history = 0  // visit count gets added to this.
    }

    init(historyController: iTermBrowserHistoryController,
         attributes: [NSAttributedString.Key: Any]) {
        tailTruncatingAttributes = attributes.modifyingParagraphStyle {
            $0.lineBreakMode = .byTruncatingTail
        }
        midTruncatingAttributes = attributes.modifyingParagraphStyle {
            $0.lineBreakMode = .byTruncatingMiddle
        }
        self.historyController = historyController
    }

    func suggestions(forQuery query: String) async -> [URLSuggestion] {
        var scoredResults = [ScoredSuggestion]()
        var seenURLs = Set<String>()

        // Get bookmark suggestions first (they have higher priority)
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let bookmarkSuggestions = await getBookmarkSuggestions(for: query)
            for suggestion in bookmarkSuggestions {
                scoredResults.append(suggestion)
                seenURLs.insert(suggestion.suggestion.url)
            }
        }

        // Get history suggestions, excluding URLs already covered by bookmarks
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let historySuggestions = await historyController.getHistorySuggestions(for: query,
                                                                                   attributes: tailTruncatingAttributes)
            for suggestion in historySuggestions {
                if !seenURLs.contains(suggestion.suggestion.url) {
                    scoredResults.append(suggestion)
                }
            }
        }

        var searchScore: Score

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let actualQuery: String
            if let search = searchQueryFromURL(query) {
                searchScore = .strongSearch
                actualQuery = search
            } else {
                searchScore = .weakSearch
                actualQuery = query
            }
            let trimmed = actualQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryParameterValue = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let url = iTermAdvancedSettingsModel.searchCommand().replacingOccurrences(of: "%@", with: queryParameterValue)

            let searchSuggestion = URLSuggestion(
                url: url,
                displayText: NSAttributedString(string: "Search for \"\(actualQuery)\"", attributes: midTruncatingAttributes),
                detail: "Web Search",
                type: .webSearch
            )

            scoredResults.append(.init(suggestion: searchSuggestion, score: searchScore.rawValue))
        }

        if let normal = normalizeURL(query) {
            let suggestion = URLSuggestion(
                url: normal.absoluteString,
                displayText: NSAttributedString(string: "Navigate to \"\(normal.absoluteString)\"",
                                                attributes: midTruncatingAttributes),
                detail: "URL",
                type: .navigation
            )
            let urlScore: iTermBrowserSuggestionsController.Score
            if stringIsStronglyURLLike(query) {
                urlScore = .strongURL
            } else {
                urlScore = .weakURL
            }

            scoredResults.append(.init(suggestion: suggestion, score: urlScore.rawValue))
        }

        // Sort by score (highest first) and return suggestions
        return scoredResults
            .sorted { $0.score > $1.score }
            .map { $0.suggestion }
    }


    func searchQueryFromURL(_ url: String) -> String? {
        guard let actualComponents = URLComponents(string: url),
              let searchEngineComponents = URLComponents(string: iTermAdvancedSettingsModel.searchCommand()) else {
            return nil
        }

        // Helper function to normalize host by removing common prefixes
        func normalizeHost(_ host: String?) -> String? {
            guard let host = host?.lowercased() else { return nil }
            let prefixesToRemove = ["www.", "m.", "mobile."]
            for prefix in prefixesToRemove {
                if host.hasPrefix(prefix) {
                    return String(host.dropFirst(prefix.count))
                }
            }
            return host
        }

        // Check if hosts match (ignoring common prefixes)
        let normalizedActualHost = normalizeHost(actualComponents.host)
        let normalizedSearchHost = normalizeHost(searchEngineComponents.host)
        guard normalizedActualHost == normalizedSearchHost else {
            return nil
        }

        // Check if paths match
        guard actualComponents.path == searchEngineComponents.path else {
            return nil
        }

        // Extract query parameters from both URLs
        guard let actualQueryItems = actualComponents.queryItems,
              let searchQueryItems = searchEngineComponents.queryItems else {
            return nil
        }

        // Find the query parameter that contains "%@" in the search template
        var targetQueryParam: String?
        for item in searchQueryItems {
            if let value = item.value, value.contains("%@") {
                targetQueryParam = item.name
                break
            }
        }

        guard let queryParamName = targetQueryParam else {
            return nil
        }

        // Find the corresponding parameter in the actual URL
        for item in actualQueryItems {
            if item.name == queryParamName, let value = item.value {
                // Return the decoded query value
                return value.removingPercentEncoding ?? value
            }
        }

        return nil
    }

    private func getBookmarkSuggestions(for query: String) async -> [ScoredSuggestion] {
        guard let database = await BrowserDatabase.instance else {
            return []
        }
        
        let bookmarks = await database.getBookmarkSuggestions(forPrefix: query, limit: 10)
        var suggestions: [ScoredSuggestion] = []
        
        for bookmark in bookmarks {
            // Get exact visit count for this URL
            let visitCount = await getVisitCount(for: bookmark.url, database: database)
            
            let title = bookmark.title?.isEmpty == false ? bookmark.title! : bookmark.url
            let displayText = NSAttributedString(string: title, attributes: tailTruncatingAttributes)

            let suggestion = URLSuggestion(
                url: bookmark.url,
                displayText: displayText,
                detail: "Bookmark",
                type: .bookmark
            )
            
            let score = Score.bookmarks.rawValue + visitCount
            suggestions.append(ScoredSuggestion(suggestion: suggestion, score: score))
        }
        
        return suggestions
    }
    
    private func getVisitCount(for url: String, database: BrowserDatabase) async -> Int {
        return await database.getVisitCount(for: url)
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    func modifyingParagraphStyle(_ closure: (NSMutableParagraphStyle) -> ()) -> Self {
        var result = self

        let mps = if let existing = self[.paragraphStyle] as? NSParagraphStyle {
            existing.mutableCopy() as! NSMutableParagraphStyle
        } else {
            NSMutableParagraphStyle()
        }
        closure(mps)
        result[.paragraphStyle] = mps
        return result
    }
}
