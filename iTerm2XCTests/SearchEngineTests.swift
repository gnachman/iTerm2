//
//  SearchEngineTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

// Tests are pretty broken but these will work if you run them from applicationDidFinishLaunching.
@objc
extension iTermSearchEngine {
    private static func sca(_ string: String) -> ScreenCharArray {
        let size = string.utf16.count * 2
        var buffer = Array<screen_char_t>(repeating: screen_char_t(), count: size)
        var length = Int32(size)
        StringToScreenChars(string,
                            &buffer,
                            screen_char_t(),
                            screen_char_t(),
                            &length,
                            false,
                            nil,
                            nil,
                            .none,
                            9,
                            false)
        var eol = screen_char_t()
        eol.code = unichar(EOL_HARD)
        let sca = ScreenCharArray(line: buffer,
                                  length: length,
                                  continuation: eol)
        sca.makeSafe()
        return sca
    }


    fileprivate class Screen: NSObject, iTermSearchEngineDataSource {
        var syncDistributor: SyncDistributor? = SyncDistributor()

        var _totalScrollbackOverflow = Int64(0)
        var unlimitedScrollback = true

        func totalScrollbackOverflow() -> Int64 {
            return _totalScrollbackOverflow
        }


        func snapshot(forcingPrimaryGrid: Bool) -> TerminalContentSnapshot {
            return TerminalContentSnapshot(lineBuffer: buffer,
                                           grid: grid,
                                           cumulativeOverflow: totalScrollbackOverflow())
        }

        lazy var searchEngine = {
            iTermSearchEngine(dataSource: self, syncDistributor: syncDistributor)
        }()
        let buffer = LineBuffer()
        let grid = VT100Grid(size: VT100GridSize(width: 80, height: 1),
                             delegate: nil)!

        override init() {
            super.init()
            searchEngine.dataSource = self
        }

        func content(for range: SearchResult) -> String {
            let extractor = iTermTextExtractor(dataSource: self)
            let overflow = totalScrollbackOverflow()
            return extractor.content(in: VT100GridWindowedRange(
                coordRange: VT100GridCoordRange(
                    start: VT100GridCoord(
                        x: range.internalStartX,
                        y: Int32(clamping: range.internalAbsStartY - overflow)),
                    end: VT100GridCoord(
                        x: range.internalEndX + 1,
                        y: Int32(clamping: range.internalAbsEndY - overflow))),
                columnWindow: VT100GridRange(location: 0, length: 0)),
                                     attributeProvider: nil,
                                     nullPolicy: .kiTermTextExtractorNullPolicyFromLastToEnd,
                                     pad: false,
                                     includeLastNewline: false,
                                     trimTrailingWhitespace: false,
                                     cappedAtSize: Int32.max,
                                     truncateTail: false,
                                     continuationChars: nil,
                                     coords: nil) as! String
        }

        func moveCursor(to coord: VT100GridCoord) {
            grid.cursor = coord
        }

        func appendLn(_ string: String) {
            let sca = sca(string)
            var dropped = grid.appendChars(atCursor: sca.line,
                                           length: sca.length,
                                           scrollingInto: buffer,
                                           unlimitedScrollback: unlimitedScrollback,
                                           useScrollbackWithRegion: false,
                                           wraparound: true,
                                           ansi: false,
                                           insert: false,
                                           externalAttributeIndex: iTermExternalAttributeIndex())
            _totalScrollbackOverflow += Int64(dropped)

            grid.moveCursorToLeftMargin()
            dropped = grid.moveCursorDownOneLineScrolling(into: buffer,
                                                          unlimitedScrollback: unlimitedScrollback,
                                                          useScrollbackWithRegion: false,
                                                          willScroll: nil,
                                                          sentToLineBuffer: nil)
            _totalScrollbackOverflow += Int64(dropped)
        }
    }


    private static func appendTestNumbers(screen: Screen) {
        for i in 0..<10 {
            screen.appendLn("Test \(i)")
            screen.buffer.forceSeal()
        }
    }

    @nonobjc
    private static func performTestSearch(screen: Screen,
                                          request: SearchRequest) -> [SearchResult] {
        let snapshot = screen.snapshot(forcingPrimaryGrid: false)
        _ = screen.searchEngine.search(request: request,
                                       snapshot: snapshot)

        var results = [SearchResult]()
        var rangeSearched = VT100GridAbsCoordRange()
        var lineRange = NSRange()
        while true {
            var finished = ObjCBool(false)
            if let partialResults = screen.searchEngine.consume(rangeSearched: &rangeSearched,
                                                                lineRange: &lineRange,
                                                                finished: &finished,
                                                                block: true) {
                results.append(contentsOf: partialResults)
            }
            if finished.boolValue {
                break
            }
        }
        return results
    }

    @nonobjc
    private static func runTest(_ name: String, closure: () throws -> ()) {
        print("Begin \(name)")
        do {
            try closure()
        } catch {
            print("Failed: \(error)")
        }
    }

    @objc static func test() {
        runTest("testForwards") { testForwards() }
        runTest("testBackwards") { testBackwards() }
        runTest("testForwardsFromCursor") { testForwardsFromCursor() }
        runTest("testBackwardsFromCursor") { testBackwardsFromCursor() }
        runTest("testForwardsWithLineRange") { testForwardsWithLineRange() }
        runTest("testBackwardsWithLineRange") { testBackwardsWithLineRange() }
        runTest("testForwardsWithCursorOutOfBoundsAndLineRange") { testForwardsWithCursorOutOfBoundsAndLineRange() }
        runTest("testRegex") { testRegex() }
        runTest("testCaseSensitive") { testCaseSensitive() }
        runTest("testCaseSensitiveRegex") { testCaseSensitiveRegex() }
        runTest("testSingleResult") { testSingleResult() }
        runTest("testOnePerRawLine") { testOnePerRawLine() }
        runTest("testEmptyQueryMatches") { testEmptyQueryMatches() }
        runTest("testSpanLines") { testSpanLines() }
        runTest("testUpdateSnapshot") { testUpdateSnapshot() }
        runTest("testUpdateSnapshot2") { testUpdateSnapshot2() }
        abort()
    }

    private static func expectEquals(_ expected: [SearchResult], _ actual: [SearchResult]) {
        if (expected.count != actual.count) {
            print("Counts differ")
            print("Actual (count=\(actual.count)):")
            print(actual)
            print("")
            print("Expected (count=\(expected.count)):")
            print(expected)
            fatalError()
        }
        for i in 0..<expected.count {
            if !expected[i].isEqual(to: actual[i]) {
                print("Failed at index \(i)")
                print("Actual:")
                print(actual)
                print("")
                print("Expected:")
                print(expected)
                fatalError()
            }
        }
    }

    private static func testUpdateSnapshot2() {
        let screen = Screen()
        screen.unlimitedScrollback = false
        screen.buffer.setMaxLines(10)
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let op = SearchOperation(snapshot: screen.snapshot(forcingPrimaryGrid: false),
                                 request: request,
                                 queue: DispatchQueue.global())!
        var results = [SearchResult]()
        op.searchOnce()
        results.append(contentsOf: op.blockingConsume().results)

        let popped = screen.buffer.popLastLine(withWidth: screen.width())
        SELog("Popped: \(String(describing: popped))")

        let unpauser = screen.syncDistributor?.pause()
        screen.moveCursor(to: VT100GridCoord(x: 0, y: 0))
        screen.appendLn("test a")
        screen.appendLn("test b")
        screen.appendLn("test c")
        unpauser?.unpause()

        while op.state == .searching {
            op.searchOnce()
        }

        while true {
            let next = op.blockingConsume()
            results.append(contentsOf: next.results)
            if next.finished {
                break
            }
        }

        let expected = [9, 7, 6, 5, 4, 3, 2, 11, 10].map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testUpdateSnapshot() {
        let screen = Screen()
        screen.unlimitedScrollback = false
        screen.buffer.setMaxLines(10)
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let op = SearchOperation(snapshot: screen.snapshot(forcingPrimaryGrid: false),
                                 request: request,
                                 queue: DispatchQueue.global())!
        op.searchOnce()
        expectEquals([SearchResult(fromX: 0, y: 9, toX: 3, y: 9)],
                     op.blockingConsume().results)

        // Cause the first lines to be dropped
        let unpauser = screen.syncDistributor?.pause()
        for _ in 0..<5 {
            screen.appendLn("no match here")
        }
        unpauser?.unpause()

        SELog("Subsequent searches are on up-to-date snapshot")
        while op.state == .searching {
            op.searchOnce()
        }

        var results = [SearchResult]()
        while true {
            let next = op.blockingConsume()
            results.append(contentsOf: next.results)
            if next.finished {
                break
            }
        }

        let expected = (5...8).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testSpanLines() {
        let screen = Screen()
        // Multiline search can't span blocks currently
        for i in 0..<10 {
            screen.appendLn("Test \(i)")
        }
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test 2\ntest 3",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: true,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = [SearchResult(fromX: 0, y: 2, toX: 5, y: 3)!]
        expectEquals(expected, results)
    }

    // Note that emptyQueryMatches only akes sense when limitResultsToOnePerRawLine
    // is also set.
    private static func testEmptyQueryMatches() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: true,
                                    emptyQueryMatches: true,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0..<10).map { y in
            SearchResult(fromX: 0, y: y, toX: 5, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testOnePerRawLine() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: true,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0..<10).map { y in
            SearchResult(fromX: 0, y: y, toX: 0, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testSingleResult() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: false,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = [0].map { y in
            SearchResult(fromX: 0, y: y, toX: 0, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testCaseSensitiveRegex() {
        let screen = Screen()
        for i in 0..<10 {
            if i == 5 || i == 6 {
                screen.appendLn("test \(i)")
            } else {
                screen.appendLn("Test \(i)")
            }
            screen.buffer.forceSeal()
        }

        let request = SearchRequest(direction: .forwards,
                                    regex: true,
                                    query: "[te][es][es]t",
                                    caseSensitivity: .sensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (5...6).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testCaseSensitive() {
        let screen = Screen()
        for i in 0..<10 {
            if i == 5 || i == 6 {
                screen.appendLn("test \(i)")
            } else {
                screen.appendLn("Test \(i)")
            }
            screen.buffer.forceSeal()
        }

        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .sensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (5...6).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testRegex() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: true,
                                    query: "t[es][es]t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0...9).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsWithCursorOutOfBoundsAndLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (3..<8).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwardsWithLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = ([5, 4, 3, 7, 6]).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsWithLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(5...7)+Array(3...4)).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsFromCursor() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(5...9)+Array(0...4)).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwardsFromCursor() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(6...9)+Array(0...5)).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwards() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0...9).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwards() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let results = performTestSearch(screen: screen, request: request)
        let expected = Array(0...9).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }
}

extension iTermSearchEngine.Screen: iTermTextDataSource {
    func width() -> Int32 {
        return grid.size.width
    }

    func numberOfLines() -> Int32 {
        return buffer.numLines(withWidth: width()) + grid.size.height
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        let historyCount = buffer.numLines(withWidth: width())
        if line < historyCount {
            return buffer.screenCharArray(forLine: line, width: width(), paddedTo: width(), eligibleForDWC: false)
        }
        return screenCharArray(atScreenIndex: line - historyCount)
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        let chars = grid.screenChars(atLineNumber: index)!
        return ScreenCharArray(line: chars,
                               length: width(),
                               continuation: chars[Int(width())])
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        return nil
    }

    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? {
        return nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
    }
}

