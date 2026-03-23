import Foundation

/// Extends search results across soft boundaries (like tmux pane dividers).
///
/// When a URL is split across visual lines due to a soft boundary, the search only finds
/// the first part. This detects such cases and extends the result to include the
/// continuation on subsequent lines by re-running the URL regex on concatenated text.
class SearchResultSoftBoundaryExtender {
    static func extend(result: SearchResult,
                       dataSource: iTermTextDataSource,
                       regex: NSRegularExpression) {
        if result.isExternal {
            return
        }

        let overflow = dataSource.totalScrollbackOverflow()
        let numberOfLines = dataSource.numberOfLines()

        let startY = Int32(clamping: result.internalAbsStartY - overflow)
        let endY = Int32(clamping: result.internalAbsEndY - overflow)

        if startY < 0 || startY >= numberOfLines || endY < 0 || endY >= numberOfLines {
            return
        }

        let startCoord = VT100GridCoord(x: result.internalStartX, y: startY)

        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.restrictToLogicalWindow(including: startCoord)

        guard extractor.hasLogicalWindow else {
            return
        }

        let logicalWindow = extractor.logicalWindow
        let rightEdge = logicalWindow.location + logicalWindow.length - 1

        // Only extend if result ends at the right edge of the logical window
        if result.internalEndX < rightEdge {
            return
        }

        // The loop already stops when dividers disappear, so numberOfLines is a safe upper bound.
        let maxY = numberOfLines
        guard let (newEndX, newEndY) = findExtendedEnd(
            result: result,
            startY: startY,
            endY: endY,
            logicalWindow: logicalWindow,
            extractor: extractor,
            maxY: maxY,
            overflow: overflow,
            regex: regex
        ) else {
            return
        }

        result.internalEndX = newEndX
        result.internalAbsEndY = newEndY
        result.logicalWindow = logicalWindow
    }

    private static func findExtendedEnd(
        result: SearchResult,
        startY: Int32,
        endY: Int32,
        logicalWindow: VT100GridRange,
        extractor: iTermTextExtractor,
        maxY: Int32,
        overflow: Int64,
        regex: NSRegularExpression
    ) -> (Int32, Int64)? {
        let rightEdge = logicalWindow.location + logicalWindow.length - 1
        let dividerColumn = logicalWindow.location + logicalWindow.length

        let locatedString = iTermLocatedString()

        appendLineContent(
            to: locatedString,
            extractor: extractor,
            y: startY,
            startX: result.internalStartX,
            endX: rightEdge
        )

        var currentY = endY + 1
        while currentY < maxY {
            let dividerCoord = VT100GridCoord(x: dividerColumn, y: currentY)
            if !extractor.character(atCoordIsColumnDivider: dividerCoord) {
                break
            }

            appendLineContent(
                to: locatedString,
                extractor: extractor,
                y: currentY,
                startX: logicalWindow.location,
                endX: rightEdge
            )
            currentY += 1
        }

        let string = locatedString.string
        guard !string.isEmpty else { return nil }

        let range = NSRange(location: 0, length: string.utf16.count)
        guard let match = regex.firstMatch(in: string, options: [], range: range) else {
            return nil
        }

        guard match.range.location == 0 else { return nil }

        let matchEndIndex = match.range.location + match.range.length - 1
        guard matchEndIndex < locatedString.gridCoords.count else { return nil }

        let endCoord = locatedString.gridCoords.coord(at: matchEndIndex)
        let newEndY = Int64(endCoord.y) + overflow

        if newEndY > result.internalAbsEndY ||
            (newEndY == result.internalAbsEndY && endCoord.x > result.internalEndX) {
            return (endCoord.x, newEndY)
        }

        return nil
    }

    private static func appendLineContent(
        to locatedString: iTermLocatedString,
        extractor: iTermTextExtractor,
        y: Int32,
        startX: Int32,
        endX: Int32
    ) {
        for x in startX...endX {
            let coord = VT100GridCoord(x: x, y: y)
            var char = extractor.character(at: coord)

            if char.code == 0 {
                break
            }

            if let str = ScreenCharToStr(&char) {
                locatedString.appendString(str, at: coord)
            }
        }
    }
}
