//
//  iTermBrowserHistoryController.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit

@available(macOS 11.0, *)
class iTermBrowserHistoryController {
    private let sessionGuid: String
    private let navigationState: iTermBrowserNavigationState
    private let user: iTermBrowserUser

    init(user: iTermBrowserUser,
         sessionGuid: String,
         navigationState: iTermBrowserNavigationState) {
        self.user = user
        self.sessionGuid = sessionGuid
        self.navigationState = navigationState
    }

    func getHistorySuggestions(for query: String,
                                       attributes: [NSAttributedString.Key: Any]) async -> [iTermBrowserSuggestionsController.ScoredSuggestion] {
        guard let database = await BrowserDatabase.instance(for: user) else {
            return []
        }

        let visits = await database.getVisitSuggestions(forPrefix: query, limit: 10)
        var suggestions = [iTermBrowserSuggestionsController.ScoredSuggestion]()

        for visit in visits {
            // Reconstruct full URL for display (add https:// if needed)
            let displayUrl = visit.fullUrl.hasPrefix("http") ? visit.fullUrl : "https://\(visit.fullUrl)"

            let suggestion = if let title = visit.title, !title.isEmpty {
                URLSuggestion(
                    url: displayUrl,
                    displayText: NSAttributedString(string: title, attributes: attributes),
                    detail: displayUrl,
                    type: .history)
            } else {
                URLSuggestion(
                    url: displayUrl,
                    displayText: NSAttributedString(string: displayUrl, attributes: attributes),
                    detail: "Visited \(visit.visitCount) time\(visit.visitCount == 1 ? "" : "s")",
                    type: .history)
            }

            suggestions.append(.init(suggestion: suggestion,
                                     score: iTermBrowserSuggestionsController.Score.history.rawValue + visit.visitCount))
        }

        return suggestions
    }

    func recordVisit(for url: URL?, title: String?) async {
        // Record visit in browser history
        if let url, !url.absoluteString.hasPrefix(iTermBrowserSchemes.about + ":") {
            Task {
                await BrowserDatabase.instance(for: user)?.recordVisit(
                    url: url.absoluteString,
                    title: title,
                    sessionGuid: sessionGuid,
                    referrerUrl: nil,
                    transitionType: navigationState.lastTransitionType
                )
            }
        }
    }

    func titleDidChange(for url: URL?, title: String?) {
        if let url = url?.absoluteString,
           let title,
           !url.hasPrefix(iTermBrowserSchemes.about + ":"),
           !title.isEmpty {
            Task {
                await BrowserDatabase.instance(for: user)?.updateTitle(title, forUrl: url)
            }
        }
    }
}
