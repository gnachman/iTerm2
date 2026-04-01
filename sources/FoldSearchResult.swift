//
//  FoldSearchResult.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/25/26.
//

import Foundation

/// Owner for fold search results. One per fold mark that has matches.
class FoldSearchResultOwner: NSObject, ExternalSearchResultOwner {
    var absLine: Int64
    let numLines: Int32 = 1

    init(absLine: Int64) {
        self.absLine = absLine
    }

    func select(_ result: ExternalSearchResult) {
    }

    func searchResultIsVisible(_ result: ExternalSearchResult) -> Bool {
        return true
    }

    func remove(_ result: ExternalSearchResult) {
    }
}

/// A search match found inside the content of a folded region.
@objc(iTermFoldSearchResult)
class FoldSearchResult: ExternalSearchResult {
    /// Match coordinates relative to the fold's LineBuffer.
    @objc let startX: Int32
    @objc let startY: Int32
    @objc let endX: Int32
    @objc let endY: Int32

    /// Short snippet text for the find bar.
    @objc let snippetText: String
    /// Range of the match within snippetText.
    @objc let snippetMatchRange: NSRange

    /// The fold mark this result came from. Weak because the fold mark
    /// is owned by the interval tree which may remove it.
    @objc weak var foldMark: FoldMarkReading?

    /// Width used during the search. If the terminal width changes before
    /// unfold, coordinates may be invalid.
    @objc let searchWidth: Int32

    init(startX: Int32,
         startY: Int32,
         endX: Int32,
         endY: Int32,
         snippetText: String,
         snippetMatchRange: NSRange,
         foldMark: FoldMarkReading,
         searchWidth: Int32,
         owner: FoldSearchResultOwner) {
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.snippetText = snippetText
        self.snippetMatchRange = snippetMatchRange
        self.foldMark = foldMark
        self.searchWidth = searchWidth
        super.init(owner)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FoldSearchResult else {
            return false
        }
        return owner === other.owner &&
               startX == other.startX &&
               startY == other.startY &&
               endX == other.endX &&
               endY == other.endY
    }

    override var hash: Int {
        var h = absLine.hashValue
        h = h &* 31 &+ Int(startX)
        h = h &* 31 &+ Int(startY)
        h = h &* 31 &+ Int(endX)
        h = h &* 31 &+ Int(endY)
        return h
    }

    /// Convert to an internal SearchResult after the fold has been expanded.
    /// `foldAbsLine` is the absolute line where the fold was.
    @objc(internalSearchResultWithFoldAbsLine:)
    func internalSearchResult(foldAbsLine: Int64) -> SearchResult {
        return SearchResult(
            fromX: startX,
            y: foldAbsLine + Int64(startY),
            toX: endX,
            y: foldAbsLine + Int64(endY))
    }
}
