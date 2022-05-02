//
//  ExternalSearchResult.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/1/22.
//

import Foundation

// External search results are those vended by subviews of PTYTextView               
// (currently just Portholes) that try to blend in with the internal search          
// results from terminal contents.                                                   
//                                                                                   
// These classes and protocols define the interface for external search results      
// which are used primarily by the find-on-page helper.                              
protocol ExternalSearchResultOwner: AnyObject {
    func select(_ result: ExternalSearchResult)
    var absLine: Int64 { get }
    var numLines: Int32 { get }
    func searchResultIsVisible(_ result: ExternalSearchResult) -> Bool
}

@objc protocol ExternalSearchResultsController {
    @objc(snippetFromExternalSearchResult:matchAttributes:regularAttributes:)
    func snippet(from result: ExternalSearchResult,
                 matchAttributes: [NSAttributedString.Key: Any],
                 regularAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString?

    @objc(selectExternalSearchResult:multiple:scroll:)
    @discardableResult
    func select(externalSearchResult result: ExternalSearchResult,
                multiple: Bool,
                scroll: Bool) -> VT100GridCoordRange

    @objc(externalSearchResultsForQuery:mode:)
    func externalSearchResults(for query: String, mode: iTermFindMode) -> [ExternalSearchResult]
}

@objc(iTermExternalSearchResult)
class ExternalSearchResult: NSObject {
    weak var owner: ExternalSearchResultOwner?
    // Line number associated with the container for this result.
    // For a porthole, this is the line number of the top of the porthole.
    @objc var absLine: Int64

    // Number of lines from absLine that are associated with the container.
    @objc var numLines: Int32

    // Is this result actually visible? Containers may get truncated
    // causing some results to be hidden and we don't want to highlight those.
    @objc var isVisible: Bool {
        return owner?.searchResultIsVisible(self) ?? false
    }
    init(_ owner: ExternalSearchResultOwner) {
        self.owner = owner
        self.absLine = owner.absLine
        self.numLines = owner.numLines
    }

    @objc override func isEqual(_ object: Any?) -> Bool {
        fatalError("Subclasses must override")
    }
}
