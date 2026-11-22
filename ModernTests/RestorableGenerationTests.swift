//
//  RestorableGenerationTests.swift
//  ModernTests
//
//  The delta encoder reuses a saved record whenever an object reports the same generation as the
//  record. These tests cover the shared generation counter and the generations that let an
//  unchanged VT100ScreenMark skip re-encoding on every save while still catching every change.
//

import XCTest
@testable import iTerm2SharedARC

final class RestorableGenerationTests: XCTestCase {
    private var session = FakeSession()
    private var nextRowID = 0

    // MARK: - Shared counter

    func testNextIsStrictlyIncreasing() {
        let a = iTermGenerationNext()
        let b = iTermGenerationNext()
        XCTAssertGreaterThan(b, a)
    }

    func testRaiseFloorAbove() {
        let floor = iTermGenerationNext() + 1_000_000
        iTermGenerationRaiseFloorAbove(floor)
        XCTAssertGreaterThan(iTermGenerationNext(), floor)
    }

    func testRaiseFloorNeverLowers() {
        let current = iTermGenerationNext()
        iTermGenerationRaiseFloorAbove(1)
        XCTAssertGreaterThan(iTermGenerationNext(), current)
    }

    func testAddingBaselineMovesEveryLaterValuePastIt() {
        let before = iTermGenerationNext()
        iTermGenerationAddBaseline(1_000_000)
        XCTAssertGreaterThan(iTermGenerationNext(), before + 1_000_000)
    }

    func testAlwaysEncodeDoesNotRaiseFloor() {
        iTermGenerationRaiseFloorAbove(iTermGenerationAlwaysEncode)
        XCTAssertLessThan(iTermGenerationNext(), iTermGenerationAlwaysEncode)
    }

    // A saved generation written by an earlier run must never be handed out again, even though
    // this run's counter started at zero.
    func testLoadingDatabaseRaisesFloorAboveSavedGenerations() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("restorable-generation-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm", ".wal", ".shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let saved = iTermGenerationNext() + 10_000_000

        do {
            let sqlite = iTermSqliteDatabaseImpl(url: url)
            let db = try XCTUnwrap(iTermGraphDatabase(database: sqlite))
            db.waitUntilReady()
            db.updateSynchronously(true, block: { encoder in
                _ = encoder.encodeChild(withKey: "leaf", identifier: "", generation: saved) { sub in
                    sub.encode("value", forKey: "k")
                    return true
                }
            }, completion: nil)
            sqlite.unlock()
        }

        XCTAssertLessThan(iTermGenerationNext(), saved)

        let sqlite = iTermSqliteDatabaseImpl(url: url)
        let db = try XCTUnwrap(iTermGraphDatabase(database: sqlite))
        db.waitUntilReady()
        defer {
            sqlite.unlock()
        }
        XCTAssertEqual(db.record.childRecord(withKey: "leaf", identifier: "")?.generation, saved)
        XCTAssertGreaterThan(iTermGenerationNext(), saved)
    }

    // MARK: - Objects that merge saved state into what they already hold

    // App-wide objects can change before the saved state loads, and then merge it in. They adopt
    // the saved generation only if they hadn't changed: otherwise the merged content differs from
    // the saved record and must not share its generation.

    private func savedRecord(key: String = "", generation: Int,
                             children: [iTermEncoderGraphRecord] = []) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs([:], graphs: children, generation: generation,
                                                key: key, identifier: "", rowid: nil)
    }

    func testAdoptKeepsSavedGenerationWhenUnchanged() {
        let saved = iTermGenerationNext()
        XCTAssertEqual(iTermGenerationAdopt(0, saved), saved)
    }

    func testAdoptTakesFreshGenerationWhenChanged() {
        let changed = iTermGenerationNext()
        let saved = changed + 1_000_000
        let adopted = iTermGenerationAdopt(changed, saved)
        XCTAssertGreaterThan(adopted, saved)
    }

    func testURLStoreAdoptsSavedGenerationOnlyWhenUnchanged() {
        let saved = iTermGenerationNext() + 1_000_000

        let unchanged = iTermURLStore()
        unchanged.load(from: savedRecord(generation: saved))
        XCTAssertEqual(unchanged.generation, saved)

        let changed = iTermURLStore()
        changed.retainCode(1)
        changed.load(from: savedRecord(generation: saved))
        XCTAssertNotEqual(changed.generation, saved)
        XCTAssertGreaterThan(changed.generation, saved)
    }

    func testChangeTrackingDictionaryAdoptsSavedGenerationOnlyWhenUnchanged() {
        let saved = iTermGenerationNext() + 1_000_000
        func encodedGeneration(_ dict: iTermChangeTrackingDictionary<NSString, NSNumber>) -> Int? {
            let encoder = iTermGraphEncoder(key: "", identifier: "", generation: 1)
            _ = dict.encodeGraph(with: encoder)
            return encoder.record?.childRecord(withKey: "changeTrackingDictionary", identifier: "")?.generation
        }
        let record = savedRecord(generation: 1, children: [
            savedRecord(key: "changeTrackingDictionary", generation: saved)])

        let unchanged = iTermChangeTrackingDictionary<NSString, NSNumber>()
        unchanged.load(from: record, keyClass: NSString.self, valueClass: NSNumber.self)
        XCTAssertEqual(encodedGeneration(unchanged), saved)

        let changed = iTermChangeTrackingDictionary<NSString, NSNumber>()
        changed.setObject(1, forKey: "new" as NSString)
        changed.load(from: record, keyClass: NSString.self, valueClass: NSNumber.self)
        XCTAssertNotEqual(encodedGeneration(changed), saved)
    }

    func testPortholeRegistryAdoptsSavedGenerationOnlyWhenUnchanged() {
        let saved = iTermGenerationNext() + 1_000_000
        let dictionary: [String: AnyObject] = ["Pending": NSDictionary(),
                                               "Generation": NSNumber(value: saved),
                                               "Portholes": NSDictionary()]

        let unchangedRecord = PortholeRegistry()
        unchangedRecord.decode(record: savedRecord(generation: saved))
        XCTAssertEqual(unchangedRecord.generation, saved)

        let changedRecord = PortholeRegistry()
        changedRecord.incrementGeneration()
        changedRecord.decode(record: savedRecord(generation: saved))
        XCTAssertGreaterThan(changedRecord.generation, saved)

        let unchangedDictionary = PortholeRegistry()
        unchangedDictionary.load(dictionary)
        XCTAssertEqual(unchangedDictionary.generation, saved)

        let changedDictionary = PortholeRegistry()
        changedDictionary.incrementGeneration()
        changedDictionary.load(dictionary)
        XCTAssertGreaterThan(changedDictionary.generation, saved)
    }

    func testSharedCounterAdoptsSavedGenerationOnlyWhenUnchanged() {
        let saved = iTermGenerationNext() + 1_000_000

        let unchanged = MonotonicCounter(dataSource: SharedGenerationDataSource())
        unchanged.setMinimum(saved)
        XCTAssertEqual(unchanged.value, saved)

        let changed = MonotonicCounter(dataSource: SharedGenerationDataSource())
        changed.advance()
        changed.setMinimum(saved)
        XCTAssertGreaterThan(changed.value, saved)
    }

    func testLocalCounterStillRatchets() {
        let counter = MonotonicCounter()
        counter.advance()
        counter.setMinimum(100)
        XCTAssertEqual(counter.value, 100)
        XCTAssertEqual(counter.next, 101)
    }

    // MARK: - Database writes

    private func storedRow(url: URL, key: String) -> (generation: Int64, data: Data?)? {
        // A second, read-only connection. It must not take the advisory lock, which the database
        // under test holds.
        let reader = iTermSqliteDatabaseImpl(url: url, lockName: nil)
        guard reader.open() else {
            return nil
        }
        defer {
            reader.close()
        }
        guard let rs = try? reader.executeQuery("select generation, data from Node where key=?",
                                                withNonOptionalArguments: [key]),
              rs.next() else {
            return nil
        }
        defer {
            rs.close()
        }
        return (rs.longLongInt(forColumn: "generation"), rs.data(forColumn: "data"))
    }

    // Overwrites a row's data behind the database's back, so a later rewrite is detectable.
    private func plantMarker(url: URL, key: String) throws -> Data {
        let marker = Data("marker".utf8)
        let writer = iTermSqliteDatabaseImpl(url: url, lockName: nil)
        XCTAssertTrue(writer.open())
        defer {
            writer.close()
        }
        try writer.executeUpdate("update Node set data=? where key=?",
                                 withNonOptionalArguments: [marker, key])
        return marker
    }

    // A node re-encoded on every save keeps its generation. When its data is also the same, the
    // row should not be rewritten.
    func testUnchangedAlwaysEncodedNodeIsNotRewritten() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("restorable-unchanged-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let sqlite = iTermSqliteDatabaseImpl(url: url)
        let db = try XCTUnwrap(iTermGraphDatabase(database: sqlite))
        defer {
            sqlite.unlock()
        }
        db.waitUntilReady()
        func save(_ value: String) {
            db.updateSynchronously(true, block: { encoder in
                _ = encoder.encodeChild(withKey: "leaf", identifier: "", generation: iTermGenerationAlwaysEncode) { sub in
                    sub.encode(value, forKey: "k")
                    return true
                }
            }, completion: nil)
        }

        save("same")
        save("same")
        let marker = try plantMarker(url: url, key: "leaf")
        save("same")
        XCTAssertEqual(try XCTUnwrap(storedRow(url: url, key: "leaf")).data, marker,
                       "Unchanged row was rewritten")

        save("different")
        XCTAssertNotEqual(try XCTUnwrap(storedRow(url: url, key: "leaf")).data, marker)
        XCTAssertEqual(db.record.childRecord(withKey: "leaf", identifier: "")?.pod["k"] as? String, "different")
    }

    // The encoder stores some values by reference. A container mutated in place after a save must
    // still be written on the next save, even though the previous save's record sees the mutation.
    func testContainerMutatedInPlaceIsRewritten() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("restorable-aliased-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let sqlite = iTermSqliteDatabaseImpl(url: url)
        let db = try XCTUnwrap(iTermGraphDatabase(database: sqlite))
        defer {
            sqlite.unlock()
        }
        db.waitUntilReady()
        let live = NSMutableDictionary(dictionary: ["k": "old"])
        func save() {
            db.updateSynchronously(true, block: { encoder in
                _ = encoder.encodeChild(withKey: "leaf", identifier: "", generation: iTermGenerationAlwaysEncode) { sub in
                    sub.encode(live, key: "d")
                    return true
                }
            }, completion: nil)
        }

        save()
        save()
        let before = try XCTUnwrap(storedRow(url: url, key: "leaf")).data
        live["k"] = "new"
        save()
        XCTAssertNotEqual(try XCTUnwrap(storedRow(url: url, key: "leaf")).data, before,
                          "In-place mutation was not written")
    }

    // MARK: - VT100ScreenMark setters

    private func assertChangesGeneration(_ name: String,
                                         file: StaticString = #filePath,
                                         line: UInt = #line,
                                         _ mutate: (VT100ScreenMark) -> Void) {
        let mark = VT100ScreenMark()
        let before = mark.generation
        XCTAssertEqual(mark.generation, before, "\(name): reading changed the generation", file: file, line: line)
        mutate(mark)
        XCTAssertNotEqual(mark.generation, before, "\(name) did not change the generation", file: file, line: line)
    }

    func testEverySetterOfEncodedStateChangesGeneration() {
        assertChangesGeneration("isPrompt") { $0.isPrompt = true }
        assertChangesGeneration("code") { $0.code = 3 }
        assertChangesGeneration("promptDetectedByTrigger") { $0.promptDetectedByTrigger = true }
        assertChangesGeneration("lineStyle") { $0.lineStyle = true }
        assertChangesGeneration("firstLineOfCommand") { $0.firstLineOfCommand = "ls" }
        assertChangesGeneration("fullCommand") { $0.fullCommand = "ls -l" }
        assertChangesGeneration("startDate") { $0.startDate = Date() }
        assertChangesGeneration("endDate") { $0.endDate = Date() }
        assertChangesGeneration("sessionGuid") { $0.sessionGuid = "guid" }
        assertChangesGeneration("name") { $0.name = "name" }
        assertChangesGeneration("promptText") { $0.promptText = [ScreenCharArray()] }
        assertChangesGeneration("promptRange") {
            $0.promptRange = VT100GridAbsCoordRangeMake(0, 1, 2, 1)
        }
        assertChangesGeneration("commandRange") {
            $0.commandRange = VT100GridAbsCoordRangeMake(2, 1, 5, 1)
        }
        assertChangesGeneration("outputStart") {
            $0.outputStart = VT100GridAbsCoordMake(0, 2)
        }
        assertChangesGeneration("kind") { $0.kind = .initial }
        assertChangesGeneration("aid") { $0.aid = "aid" }
        assertChangesGeneration("parentAid") { $0.parentAid = "parent" }
        assertChangesGeneration("ancestorAids") { $0.ancestorAids = ["a"] }
        assertChangesGeneration("excludedSubranges") {
            $0.excludedSubranges = [ResilientCoordinateRange(unboundAbsRange: VT100GridAbsCoordRangeMake(0, 0, 1, 0))]
        }
        assertChangesGeneration("appendExcludedSubrange") {
            $0.appendExcludedSubrange(ResilientCoordinateRange(unboundAbsRange: VT100GridAbsCoordRangeMake(0, 0, 1, 0)))
        }
        assertChangesGeneration("addCapturedOutput") {
            let capturedOutput = CapturedOutput()
            capturedOutput.line = "x"
            $0.add(capturedOutput)
        }
    }

    func testMergingCapturedOutputChangesGeneration() {
        let mark = VT100ScreenMark()
        let first = CapturedOutput()
        first.line = "abc"
        first.absoluteLineNumber = 3
        mark.add(first)
        let before = mark.generation

        let second = CapturedOutput()
        second.line = "abcdef"
        second.absoluteLineNumber = 3
        mark.add(second)

        XCTAssertEqual(mark.capturedOutput?.count, 1, "Expected the second captured output to merge into the first")
        XCTAssertNotEqual(mark.generation, before)
    }

    // The toolbelt toggles a captured output's checkmark directly, without going through the mark.
    func testChangingCapturedOutputDirectlyChangesMarkGeneration() {
        let mark = VT100ScreenMark()
        let capturedOutput = CapturedOutput()
        capturedOutput.line = "x"
        mark.add(capturedOutput)
        let before = mark.generation

        capturedOutput.state = !capturedOutput.state

        XCTAssertNotEqual(mark.generation, before)
    }

    // A captured output's encoded command comes from a promise, which can resolve after it was
    // last saved with no mutation at all.
    func testResolvingCapturedOutputCommandChangesMarkGeneration() {
        var resolve: ((String) -> Void)?
        let capturedOutput = CapturedOutput()
        capturedOutput.line = "x"
        capturedOutput.promisedCommand = iTermPromise<NSString> { seal in
            resolve = { seal.fulfill($0 as NSString) }
        }
        let mark = VT100ScreenMark()
        mark.add(capturedOutput)
        let before = mark.generation
        XCTAssertEqual(mark.generation, before)

        resolve?("make")

        XCTAssertNotEqual(mark.generation, before)
        let after = mark.generation
        XCTAssertEqual(mark.generation, after)
    }

    // The Captured Output tool shows the main-thread copy, and double-clicking a line runs the
    // copy's command. A command that arrives after the copy was made must reach it.
    func testMainThreadCopyOfCapturedOutputGetsCommandThatArrivesLater() {
        var resolve: ((String) -> Void)?
        let capturedOutput = CapturedOutput()
        capturedOutput.line = "x"
        capturedOutput.promisedCommand = iTermPromise<NSString> { seal in
            resolve = { seal.fulfill($0 as NSString) }
        }
        let copy = capturedOutput.doppelganger()!
        XCTAssertNil(copy.promisedCommand.maybeValue)

        resolve?("make")

        XCTAssertEqual(copy.promisedCommand.maybeValue as String?, "make")
    }

    func testCopyOfMarkHasSameEncodedState() {
        let mark = VT100ScreenMark()
        mark.name = "n"
        let copy = mark.copy() as! VT100ScreenMark
        XCTAssertEqual(copy.dictionaryValue() as NSDictionary, mark.dictionaryValue() as NSDictionary)
    }

    // MARK: - Screen integration

    private func makeScreen(maxScrollback: UInt32? = nil) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
            if let maxScrollback {
                mutableState.maxScrollbackLines = maxScrollback
                mutableState.linebuffer.setMaxLines(Int32(maxScrollback))
            }
        })
        for i in 0..<5 {
            feed(screen, "\u{1b}]133;A\u{07}$ \u{1b}]133;B\u{07}command \(i)\r\n\u{1b}]133;C\u{07}output \(i)\r\n\u{1b}]133;D;0\u{07}")
        }
        return screen
    }

    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(string.data(using: .utf8)!)
        screen.waitForQueuedTokensForTesting()
    }

    private func assignRowIDs(_ record: iTermEncoderGraphRecord) {
        if record.rowid == nil {
            nextRowID += 1
            record.rowid = NSNumber(value: nextRowID)
        }
        for child in record.graphRecords {
            assignRowIDs(child)
        }
    }

    private func encode(_ screen: VT100Screen, previous: iTermEncoderGraphRecord?) -> iTermEncoderGraphRecord {
        let encoder = iTermGraphDeltaEncoder(previousRevision: previous)
        _ = encoder.encodeChild(withKey: "screen", identifier: "", generation: iTermGenerationAlwaysEncode) { subencoder in
            let adapter = iTermGraphEncoderAdapter(graphEncoder: subencoder)
            var linesDropped = Int32(0)
            return screen.encodeContents(adapter, linesDropped: &linesDropped, unlimited: false)
        }
        let record = encoder.record!
        assignRowIDs(record)
        return record
    }

    /// The content record of every screen mark in the main interval tree, keyed by mark guid.
    private func screenMarkContentRecords(_ root: iTermEncoderGraphRecord,
                                          screen: VT100Screen) -> [String: iTermEncoderGraphRecord] {
        var guids = Set<String>()
        screen.enumerateObservableMarks { _, _, mark in
            if let screenMark = mark as? VT100ScreenMarkReading {
                guids.insert(screenMark.guid)
            }
        }
        var result = [String: iTermEncoderGraphRecord]()
        var stack = [root]
        while let record = stack.popLast() {
            if record.key == "content",
               let parent = record.parent,
               guids.contains(parent.identifier) {
                result[parent.identifier] = record
            }
            stack.append(contentsOf: record.graphRecords)
        }
        return result
    }

    private func lastCommandMark(_ screen: VT100Screen) -> VT100ScreenMark {
        var result: VT100ScreenMark?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.lastCommandMark as? VT100ScreenMark
        })
        return result!
    }

    func testIdleSaveReusesEveryScreenMarkContentRecord() {
        let screen = makeScreen()
        let first = encode(screen, previous: nil)
        let second = encode(screen, previous: first)

        let before = screenMarkContentRecords(first, screen: screen)
        let after = screenMarkContentRecords(second, screen: screen)
        XCTAssertGreaterThanOrEqual(before.count, 5)
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        for (guid, record) in after {
            XCTAssertTrue(record === before[guid], "Mark \(guid) was re-encoded although nothing changed")
        }
    }

    func testChangingOneMarkReencodesOnlyThatMark() {
        let screen = makeScreen()
        let first = encode(screen, previous: nil)
        let changed = lastCommandMark(screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.mutableIntervalTree().mutate(changed) { obj in
                (obj as! VT100ScreenMark).name = "renamed"
            }
        })
        let second = encode(screen, previous: first)

        let before = screenMarkContentRecords(first, screen: screen)
        let after = screenMarkContentRecords(second, screen: screen)
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        for (guid, record) in after {
            if guid == changed.guid {
                XCTAssertFalse(record === before[guid])
                XCTAssertEqual(record.pod["Name"] as? String, "renamed")
            } else {
                XCTAssertTrue(record === before[guid], "Mark \(guid) was re-encoded although it did not change")
            }
        }
    }

    // A resize moves a mark's coordinates through notifications, without calling any of its setters.
    func testResizeReencodesMarksWhoseCoordinatesMoved() {
        let screen = makeScreen()
        let first = encode(screen, previous: nil)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(7, 24), delegate: screen.delegate!)
        })
        let second = encode(screen, previous: first)

        let before = screenMarkContentRecords(first, screen: screen)
        let after = screenMarkContentRecords(second, screen: screen)
        var changed = 0
        for (guid, record) in after where !(record === before[guid]) {
            changed += 1
            XCTAssertNotEqual(record.pod as NSDictionary, before[guid]?.pod as NSDictionary?)
        }
        XCTAssertGreaterThan(changed, 0)
    }

    // MARK: - Interval tree generation

    // An interval tree's generation lets a save reuse the tree's whole record without visiting its
    // objects. It must change whenever what the tree encodes may have changed.

    func testIntervalTreeGenerationChangesOnlyWhenContentsChange() {
        let tree = IntervalTree()
        var generation = tree.generation
        func assertChanged(_ what: String) {
            XCTAssertNotEqual(tree.generation, generation, what)
            generation = tree.generation
        }

        let mark = VT100ScreenMark()
        tree.add(mark, with: Interval(location: 0, length: 1))
        assertChanged("add")
        _ = tree.allObjects()
        XCTAssertEqual(tree.generation, generation, "reading")
        tree.remove(mark)
        assertChanged("remove")
        tree.add(VT100ScreenMark(), with: Interval(location: 0, length: 1))
        generation = tree.generation
        tree.removeAllObjects()
        assertChanged("removeAllObjects")
        tree.noteContentsChanged()
        assertChanged("noteContentsChanged")
    }

    private final class IgnoredSideEffects: NSObject, EventuallyConsistentIntervalTreeSideEffectPerformer {
        func addSideEffect(_ closure: @escaping () -> (), name: String) {
        }
    }

    // mutate and bulkMutate change objects in place, which the tree can't see on its own.
    func testMutatingThroughTheTreeChangesItsGeneration() {
        let sideEffects = IgnoredSideEffects()
        let tree = EventuallyConsistentIntervalTree(sideEffects, derivative: IntervalTree())
        let mark = VT100ScreenMark()
        tree.add(mark, with: Interval(location: 0, length: 1))

        var generation = tree.generation
        func assertChanged(_ what: String) {
            XCTAssertNotEqual(tree.generation, generation, what)
            generation = tree.generation
        }
        tree.mutate(mark) { ($0 as! VT100ScreenMark).name = "a" }
        assertChanged("mutate")
        tree.bulkMutate([mark]) { ($0 as! VT100ScreenMark).name = "b" }
        assertChanged("bulkMutate")
    }

    private func intervalTreeRecord(_ root: iTermEncoderGraphRecord) -> iTermEncoderGraphRecord? {
        var stack = [root]
        while let record = stack.popLast() {
            if record.key == "Interval Tree" {
                return record
            }
            stack.append(contentsOf: record.graphRecords)
        }
        return nil
    }

    private func scrollbackOverflow(_ screen: VT100Screen) -> Int64 {
        var result = Int64(0)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.cumulativeScrollbackOverflow
        })
        return result
    }

    // Saving encodes the mutation thread's tree.
    private func treeGeneration(_ screen: VT100Screen) -> Int {
        var result = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.mutableIntervalTree().generation
        })
        return result
    }

    func testIdleSaveReusesIntervalTreeRecord() {
        let screen = makeScreen()
        let first = encode(screen, previous: nil)
        let second = encode(screen, previous: first)
        XCTAssertNotNil(intervalTreeRecord(first))
        XCTAssertTrue(intervalTreeRecord(second) === intervalTreeRecord(first))
    }

    func testOutputWithoutScrollbackOverflowReusesIntervalTreeRecord() {
        let screen = makeScreen(maxScrollback: 1000)
        let first = encode(screen, previous: nil)
        feed(screen, "plain output\r\nmore output\r\n")
        let second = encode(screen, previous: first)
        XCTAssertTrue(intervalTreeRecord(second) === intervalTreeRecord(first))
    }

    func testMutatingAMarkReencodesIntervalTree() {
        let screen = makeScreen()
        let first = encode(screen, previous: nil)
        let changed = lastCommandMark(screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.mutableIntervalTree().mutate(changed) { obj in
                (obj as! VT100ScreenMark).name = "renamed"
            }
        })
        let second = encode(screen, previous: first)
        XCTAssertFalse(intervalTreeRecord(second) === intervalTreeRecord(first))
        XCTAssertEqual(screenMarkContentRecords(second, screen: screen)[changed.guid]?.pod["Name"] as? String,
                       "renamed")
    }

    // Saved intervals are relative to the oldest line kept, which moves when scrollback overflows.
    func testScrollbackOverflowReencodesIntervalTree() {
        let screen = makeScreen(maxScrollback: 5)
        let first = encode(screen, previous: nil)
        let overflowBefore = scrollbackOverflow(screen)
        feed(screen, String(repeating: "overflow\r\n", count: 30))
        XCTAssertGreaterThan(scrollbackOverflow(screen), overflowBefore)
        let second = encode(screen, previous: first)
        XCTAssertFalse(intervalTreeRecord(second) === intervalTreeRecord(first))
    }

    // Coordinates move through notifications rather than through the tree, so whoever posts them
    // must tell the tree. Clearing below every mark removes nothing, so only the notification can
    // account for the change.
    func testClearingToEndChangesTreeGeneration() {
        let screen = makeScreen()
        let before = treeGeneration(screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearFromAbsoluteLine(toEnd: mutableState.cumulativeScrollbackOverflow +
                               Int64(mutableState.numberOfScrollbackLines) +
                               Int64(mutableState.height()) - 1)
        })
        XCTAssertNotEqual(treeGeneration(screen), before)
    }

    func testResizeChangesTreeGeneration() {
        let screen = makeScreen()
        let before = treeGeneration(screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(7, 24), delegate: screen.delegate!)
        })
        XCTAssertNotEqual(treeGeneration(screen), before)
    }

    // The toolbelt's checkmark used to change the main-thread copy only. Saving encodes the
    // mutation thread's copy, so the change was never saved.
    func testSettingCapturedOutputStateReencodesIntervalTree() {
        let screen = makeScreen()
        let capturedOutput = CapturedOutput()
        capturedOutput.line = "captured"
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let mark = mutableState.lastCommandMark!
            mutableState.mutableIntervalTree().mutate(mark) { obj in
                let mutableMark = obj as! VT100ScreenMark
                mutableMark.add(mutableMark.isDoppelganger ?
                                              capturedOutput.doppelganger() as! CapturedOutput :
                                              capturedOutput)
            }
        })
        let first = encode(screen, previous: nil)

        let mainThreadMark = screen.lastCommandMark()!
        let mainThreadCapturedOutput = mainThreadMark.capturedOutput!.first!
        screen.setState(true, ofCapturedOutput: mainThreadCapturedOutput, inMark: mainThreadMark)
        screen.waitForQueuedTokensForTesting()
        let second = encode(screen, previous: first)

        XCTAssertTrue(mainThreadCapturedOutput.state)
        XCTAssertTrue(capturedOutput.state, "The mutation thread's copy should match")
        XCTAssertFalse(intervalTreeRecord(second) === intervalTreeRecord(first))
    }

    // A capture trigger's command can be computed after the output was captured, which changes
    // what the mark encodes without going through the tree.
    func testCapturedCommandArrivingLaterReencodesIntervalTree() {
        let screen = makeScreen()
        var resolve: ((String) -> Void)?
        let capturedOutput = CapturedOutput()
        capturedOutput.line = "captured"
        capturedOutput.promisedCommand = iTermPromise<NSString> { seal in
            resolve = { seal.fulfill($0 as NSString) }
        }
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let triggerSession = mutableState as AnyObject as! iTermTriggerSession
            triggerSession.triggerSession(Trigger(), didCapture: capturedOutput)
        })
        let first = encode(screen, previous: nil)

        // No waiting: a save right after the command arrives must already see the change.
        resolve?("make")
        let second = encode(screen, previous: first)

        XCTAssertFalse(intervalTreeRecord(second) === intervalTreeRecord(first))
    }
}
