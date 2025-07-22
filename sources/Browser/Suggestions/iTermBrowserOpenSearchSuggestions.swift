//
//  iTermBrowserOpenSearchSuggestions.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/25.
//

import Foundation

@available(macOS 11.0, *)
@MainActor
class iTermBrowserOpenSearchSuggestions {
    private let attributes: [NSAttributedString.Key: Any]
    private let maxResults: Int
    private var cache: [String: [iTermBrowserSuggestionsController.ScoredSuggestion]] = [:]
    private var currentTask: Task<[iTermBrowserSuggestionsController.ScoredSuggestion], Never>?

    init(attributes: [NSAttributedString.Key: Any],
         maxResults: Int) {
        self.attributes = attributes
        self.maxResults = maxResults
    }
    
    func getSuggestions(for query: String) async -> [iTermBrowserSuggestionsController.ScoredSuggestion] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.hasPrefix("https://") {
            return []
        }
        
        guard let escapedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        
        let templateURL = iTermAdvancedSettingsModel.searchSuggestURL()!
        let requestURL = templateURL.replacingOccurrences(of: "%@", with: escapedQuery)
        
        guard let url = URL(string: requestURL) else {
            return []
        }
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Start background task that will continue even if we timeout
        currentTask = Task<[iTermBrowserSuggestionsController.ScoredSuggestion], Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let suggestions = await parseSuggestions(data: data, originalQuery: trimmedQuery)
                cache[trimmedQuery] = suggestions
                return suggestions
            } catch {
                return []
            }
        }
        
        // Race the network request against timeout
        do {
            let result = try await withTimeout(seconds: 0.05) {
                try await URLSession.shared.data(from: url)
            }
            let suggestions = await parseSuggestions(data: result.0, originalQuery: trimmedQuery)
            cache[trimmedQuery] = suggestions
            return suggestions
        } catch {
            // Timeout occurred - return cached results if available, but let background task continue
            if let prefixResults = findCachedPrefix(for: trimmedQuery).flatMap({ cache[$0] }) {
                return filterAndRescoreSuggestions(prefixResults, for: trimmedQuery)
            }
            return []
        }
    }
    
    private func parseSuggestions(data: Data, originalQuery: String) async -> [iTermBrowserSuggestionsController.ScoredSuggestion] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              jsonArray.count >= 2,
              let query = jsonArray[0] as? String,
              let suggestions = jsonArray[1] as? [String] else {
            return []
        }
        
        // Verify the query matches what we sent
        guard query == originalQuery else {
            return []
        }
        
        var results: [iTermBrowserSuggestionsController.ScoredSuggestion] = []
        
        for (index, suggestion) in suggestions.enumerated() {
            guard !suggestion.isEmpty else { continue }
            
            // Escape the suggestion for use in search URL
            let escapedSuggestion = suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? suggestion
            let searchURL = iTermAdvancedSettingsModel.searchCommand().replacingOccurrences(of: "%@", with: escapedSuggestion)
            
            let displayText = NSAttributedString(string: suggestion, attributes: attributes)
            
            let urlSuggestion = URLSuggestion(
                url: searchURL,
                displayText: displayText,
                detail: "Search Suggestion",
                type: .webSearch
            )
            
            // Score decreases with position in the list
            let score = iTermBrowserSuggestionsController.Score.openSearch.rawValue - index
            
            results.append(iTermBrowserSuggestionsController.ScoredSuggestion(
                suggestion: urlSuggestion,
                score: score
            ))
            if results.count == maxResults {
                break
            }
        }
        
        return results
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func findCachedPrefix(for query: String) -> String? {
        var bestMatch: String?
        var bestLength = 0
        
        for cachedQuery in cache.keys {
            if query.hasPrefix(cachedQuery) && cachedQuery.count > bestLength {
                bestMatch = cachedQuery
                bestLength = cachedQuery.count
            }
        }
        
        return bestMatch
    }
    
    private func filterAndRescoreSuggestions(_ suggestions: [iTermBrowserSuggestionsController.ScoredSuggestion], for query: String) -> [iTermBrowserSuggestionsController.ScoredSuggestion] {
        let filtered = suggestions.filter { suggestion in
            let urlSuggestion = suggestion.suggestion
            return urlSuggestion.displayText.string.localizedCaseInsensitiveHasPrefix(query)
        }
        
        // Re-score based on relevance to the new query
        return filtered.enumerated().map { index, suggestion in
            let newScore = iTermBrowserSuggestionsController.Score.openSearch.rawValue - index - 10 // Lower score for cached results
            return iTermBrowserSuggestionsController.ScoredSuggestion(
                suggestion: suggestion.suggestion,
                score: newScore
            )
        }
    }
}
