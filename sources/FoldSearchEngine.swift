//
//  FoldSearchEngine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/25/26.
//

import Foundation

/// Searches fold mark contents asynchronously on a background queue.
/// Results are delivered to the main thread via a completion closure.
@objc(iTermFoldSearchEngine)
class FoldSearchEngine: NSObject {
    private let queue = DispatchQueue(label: "com.iterm2.fold-search",
                                      qos: .userInitiated)
    private let generation = MutableAtomicObject<Int>(0)

    @objc func cancel() {
        generation.mutate { $0 + 1 }
    }

    /// Search fold marks for a query. `results` is called on the main thread
    /// once per fold that has matches. `finished` is called on the main thread
    /// when all folds have been searched (or the search was cancelled).
    /// Call cancel() before starting a new search.
    @objc(searchForQuery:mode:foldMarks:absLines:width:results:finished:)
    func search(query: String,
                mode: iTermFindMode,
                foldMarks: [FoldMarkReading],
                absLines: [NSNumber],
                width: Int32,
                results resultsCallback: @escaping ([ExternalSearchResult]) -> Void,
                finished finishedCallback: @escaping () -> Void) {
        let myGeneration = generation.mutate { $0 + 1 }
        let gen = self.generation

        // Pair up marks with their abs lines.
        let folds: [(mark: FoldMarkReading, absLine: Int64)] = zip(foldMarks, absLines).map {
            ($0.0, $0.1.int64Value)
        }

        queue.async { [weak self] in
            guard self != nil else { return }

            for (mark, absLine) in folds {
                guard gen.value == myGeneration else { return }

                guard let savedLines = mark.savedLines, !savedLines.isEmpty else {
                    continue
                }

                let lineBuffer = LineBuffer()
                for sca in savedLines {
                    lineBuffer.append(sca, width: width)
                }

                guard gen.value == myGeneration else { return }

                let xyRanges = Self.searchLineBuffer(lineBuffer,
                                                     width: width,
                                                     query: query,
                                                     mode: mode)
                guard gen.value == myGeneration else { return }
                guard !xyRanges.isEmpty else { continue }

                let owner = FoldSearchResultOwner(absLine: absLine)
                let results: [ExternalSearchResult] = xyRanges.map { xyRange in
                    let snippet = Self.extractSnippet(
                        from: lineBuffer,
                        xyRange: xyRange,
                        width: width)
                    return FoldSearchResult(
                        startX: xyRange.coordRange.start.x,
                        startY: xyRange.coordRange.start.y,
                        endX: xyRange.coordRange.end.x,
                        endY: xyRange.coordRange.end.y,
                        snippetText: snippet.text,
                        snippetMatchRange: snippet.matchRange,
                        foldMark: mark,
                        searchWidth: width,
                        owner: owner)
                }

                DispatchQueue.main.async {
                    guard gen.value == myGeneration else { return }
                    resultsCallback(results)
                }
            }

            DispatchQueue.main.async {
                guard gen.value == myGeneration else { return }
                finishedCallback()
            }
        }
    }

    // MARK: - Private

    /// Search a LineBuffer for all matches of a query.
    private static func searchLineBuffer(
        _ lineBuffer: LineBuffer,
        width: Int32,
        query: String,
        mode: iTermFindMode
    ) -> [XYRange] {
        let context = FindContext()
        let startPosition = lineBuffer.firstPosition()
        let stopPosition = lineBuffer.lastPosition()
        let options: FindOptions = [.multipleResults]

        lineBuffer.prepareToSearch(
            for: query,
            startingAt: startPosition,
            options: options,
            mode: mode,
            with: context)

        var allXYRanges = [XYRange]()

        while true {
            lineBuffer.findSubstring(context, stopAt: stopPosition)

            switch context.status {
            case .Matched:
                if let resultRanges = context.results as? [ResultRange],
                   let xyRanges = lineBuffer.convertPositions(resultRanges,
                                                              withWidth: width) {
                    allXYRanges.append(contentsOf: xyRanges)
                }
                context.results?.removeAllObjects()

            case .Searching:
                continue

            case .NotFound:
                return allXYRanges

            @unknown default:
                return allXYRanges
            }
        }
    }

    /// Extract a short snippet of text around a match for display in the find bar.
    /// Uses `iTermLocatedString` to correctly map grid coordinates to string
    /// indices so that double-width, image, and PUA characters are handled.
    private static func extractSnippet(
        from lineBuffer: LineBuffer,
        xyRange: XYRange,
        width: Int32
    ) -> (text: String, matchRange: NSRange) {
        let matchStartX = xyRange.coordRange.start.x
        let matchStartY = xyRange.coordRange.start.y
        let matchEndX = xyRange.coordRange.end.x
        let matchEndY = xyRange.coordRange.end.y

        // Get the line containing the match start.
        let sca = lineBuffer.wrappedLine(at: matchStartY, width: width)
        let located = iTermLocatedString(screenCharArray: sca)
        let nsString = located.string as NSString

        guard nsString.length > 0 else {
            return ("", NSRange(location: 0, length: 0))
        }

        // For single-line matches, extract context around the match.
        if matchStartY == matchEndY {
            // Map grid x range [matchStartX, matchEndX] to string indices.
            // matchEndX is inclusive, so pass matchEndX + 1 as the exclusive upper bound.
            let matchStringRange = located.gridCoords.rangeOfIndices(
                xFrom: matchStartX, to: matchEndX + 1)

            if matchStringRange.location == NSNotFound {
                return (located.string, NSRange(location: 0, length: 0))
            }

            // Add context: up to 20 characters before, 40 after.
            let contextStart = max(0, matchStringRange.location - 20)
            let contextEnd = min(Int(nsString.length),
                                 NSMaxRange(matchStringRange) + 40)
            let snippetRange = NSRange(location: contextStart,
                                       length: contextEnd - contextStart)
            let snippet = nsString.substring(with: snippetRange)
            let matchInSnippet = NSRange(
                location: matchStringRange.location - contextStart,
                length: matchStringRange.length)
            return (snippet, matchInSnippet)
        }

        // Multi-line match: show from match start to end of line.
        let startStringIdx = located.gridCoords.indexOfFirstCoord(
            xGreaterOrEqual: matchStartX)
        if startStringIdx != NSNotFound && startStringIdx < nsString.length {
            let snippet = nsString.substring(from: startStringIdx)
            return (snippet, NSRange(location: 0,
                                     length: min((snippet as NSString).length, 80)))
        }
        return (located.string, NSRange(location: 0,
                                         length: min(nsString.length, 80)))
    }
}
