//
//  iTermBrowserOpenSearchSuggestions.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/25.
//

import Foundation

@available(macOS 11.0, *)
class iTermBrowserOpenSearchSuggestions {
    private let attributes: [NSAttributedString.Key: Any]
    private let maxResults: Int

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
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return await parseSuggestions(data: data, originalQuery: trimmedQuery)
        } catch {
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
}
