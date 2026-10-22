//
//  TmuxDividerMoverPropertyTests.swift
//  iTerm2
//
//  Adversarial tests for iTermTmuxDividerMover. Random tmux layouts are generated from fixed seeds,
//  so a failure can be replayed, and every divider of every split is moved with exact, random, and
//  hostile measurements. The output is read back by a parser written here, independent of
//  iTermTmuxLayoutBuilder, and must pass the checks tmux's layout_check makes before select-layout
//  accepts a layout, as well as keep everything away from the dragged divider unchanged.
//

import XCTest
@testable import iTerm2SharedARC

// Deterministic, so a failing seed can be replayed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// A tmux layout cell as tmux would describe it, with offsets.
private indirect enum Cell: Equatable {
    case leaf(width: Int32, height: Int32, x: Int32, y: Int32, pane: Int32)
    case split(verticalDividers: Bool, width: Int32, height: Int32, x: Int32, y: Int32, children: [Cell])

    var width: Int32 {
        switch self {
        case let .leaf(width, _, _, _, _), let .split(_, width, _, _, _, _): return width
        }
    }

    var height: Int32 {
        switch self {
        case let .leaf(_, height, _, _, _), let .split(_, _, height, _, _, _): return height
        }
    }

    var x: Int32 {
        switch self {
        case let .leaf(_, _, x, _, _), let .split(_, _, _, x, _, _): return x
        }
    }

    var y: Int32 {
        switch self {
        case let .leaf(_, _, _, y, _), let .split(_, _, _, _, y, _): return y
        }
    }

    var children: [Cell] {
        if case let .split(_, _, _, _, _, children) = self {
            return children
        }
        return []
    }

    var panes: [Int32] {
        switch self {
        case let .leaf(_, _, _, _, pane): return [pane]
        case let .split(_, _, _, _, _, children): return children.flatMap { $0.panes }
        }
    }

    var leaves: [Cell] {
        switch self {
        case .leaf: return [self]
        case let .split(_, _, _, _, _, children): return children.flatMap { $0.leaves }
        }
    }

    func extent(vertical: Bool) -> Int32 {
        return vertical ? width : height
    }

    // The tree's shape: orientations, child counts, and pane order. Sizes are left out.
    var shape: String {
        switch self {
        case let .leaf(_, _, _, _, pane):
            return "\(pane)"
        case let .split(verticalDividers, _, _, _, _, children):
            let inner = children.map { $0.shape }.joined(separator: ",")
            return verticalDividers ? "{\(inner)}" : "[\(inner)]"
        }
    }

    // Serialized in tmux's v1 layout format, without the checksum.
    var body: String {
        switch self {
        case let .leaf(width, height, x, y, pane):
            return "\(width)x\(height),\(x),\(y),\(pane)"
        case let .split(verticalDividers, width, height, x, y, children):
            let inner = children.map { $0.body }.joined(separator: ",")
            return "\(width)x\(height),\(x),\(y)" + (verticalDividers ? "{\(inner)}" : "[\(inner)]")
        }
    }

    var layout: String {
        return String(format: "%04hx", Cell.checksum(body)) + "," + body
    }

    // tmux's layout_checksum.
    static func checksum(_ string: String) -> UInt16 {
        var csum: UInt16 = 0
        for byte in string.utf8 {
            csum = (csum >> 1) &+ ((csum & 1) << 15)
            csum = csum &+ UInt16(byte)
        }
        return csum
    }

    // Returns the cell with sizes kept and offsets recomputed from them.
    func placed(x: Int32, y: Int32) -> Cell {
        switch self {
        case let .leaf(width, height, _, _, pane):
            return .leaf(width: width, height: height, x: x, y: y, pane: pane)
        case let .split(verticalDividers, _, _, _, _, children):
            var newChildren = [Cell]()
            var cx = x
            var cy = y
            for child in children {
                let placedChild = child.placed(x: cx, y: cy)
                newChildren.append(placedChild)
                if verticalDividers {
                    cx += placedChild.width + 1
                } else {
                    cy += placedChild.height + 1
                }
            }
            let width = verticalDividers ? cx - x - 1 : newChildren[0].width
            let height = verticalDividers ? newChildren[0].height : cy - y - 1
            return .split(verticalDividers: verticalDividers, width: width, height: height, x: x, y: y,
                          children: newChildren)
        }
    }

    func cell(at path: [Int]) -> Cell {
        var cell = self
        for i in path {
            cell = cell.children[i]
        }
        return cell
    }

    // Paths to every split, root first.
    func splitPaths(prefix: [Int] = []) -> [[Int]] {
        guard case let .split(_, _, _, _, _, children) = self else {
            return []
        }
        var result = [prefix]
        for (i, child) in children.enumerated() {
            result += child.splitPaths(prefix: prefix + [i])
        }
        return result
    }
}

// Reads tmux's v1 layout format. It is deliberately separate from TmuxLayoutParser.
private struct LayoutReader {
    private let bytes: [UInt8]
    private var i = 0

    static func read(_ layout: String) -> (cell: Cell, checksumMatches: Bool)? {
        let parts = layout.split(separator: ",", maxSplits: 1).map(String.init)
        guard parts.count == 2, let checksum = UInt16(parts[0], radix: 16) else {
            return nil
        }
        var reader = LayoutReader(bytes: Array(parts[1].utf8))
        guard let cell = reader.cell(), reader.i == reader.bytes.count else {
            return nil
        }
        return (cell, checksum == Cell.checksum(parts[1]))
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func number() -> Int32? {
        let start = i
        while i < bytes.count, bytes[i] >= UInt8(ascii: "0"), bytes[i] <= UInt8(ascii: "9") {
            i += 1
        }
        guard i > start else {
            return nil
        }
        return Int32(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    private mutating func expect(_ c: Character) -> Bool {
        guard i < bytes.count, bytes[i] == c.asciiValue! else {
            return false
        }
        i += 1
        return true
    }

    private mutating func cell() -> Cell? {
        guard let width = number(), expect("x"), let height = number(), expect(","),
              let x = number(), expect(","), let y = number() else {
            return nil
        }
        if expect(",") {
            guard let pane = number() else {
                return nil
            }
            return .leaf(width: width, height: height, x: x, y: y, pane: pane)
        }
        let verticalDividers: Bool
        let close: Character
        if expect("{") {
            verticalDividers = true
            close = "}"
        } else if expect("[") {
            verticalDividers = false
            close = "]"
        } else {
            return nil
        }
        var children = [Cell]()
        repeat {
            guard let child = cell() else {
                return nil
            }
            children.append(child)
        } while expect(",")
        guard expect(close) else {
            return nil
        }
        return .split(verticalDividers: verticalDividers, width: width, height: height, x: x, y: y,
                      children: children)
    }
}

private struct LayoutGenerator {
    var rng: SplitMix64
    // Pane ids are drawn without replacement from a sparse range, so code that assumes ids are
    // small or contiguous is caught.
    private var paneIDs: [Int32]
    // The smallest pane height. With pane-border-status, tmux needs a row for the border.
    let minimumHeight: Int32

    init(seed: UInt64, minimumHeight: Int32) {
        rng = SplitMix64(state: seed)
        paneIDs = Array(0..<Int32(5000)).shuffled(using: &rng)
        self.minimumHeight = minimumHeight
    }

    mutating func int(_ range: ClosedRange<Int32>) -> Int32 {
        return Int32.random(in: range, using: &rng)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        return Double.random(in: range, using: &rng)
    }

    mutating func chance(_ p: Double) -> Bool {
        return Double.random(in: 0..<1, using: &rng) < p
    }

    mutating func window() -> Cell {
        let width = int(3...200)
        let height = int(minimumHeight * 2 + 1...80)
        return cell(width: width, height: height, depth: 0, parentVertical: nil).placed(x: 0, y: 0)
    }

    // Splits |total| into |count| parts, each at least its minimum.
    mutating func partition(_ total: Int32, minimums: [Int32]) -> [Int32] {
        var sizes = minimums
        let spare = total - minimums.reduce(0, +)
        precondition(spare >= 0)
        var cuts = (0..<(minimums.count - 1)).map { _ in int(0...spare) }.sorted()
        cuts.append(spare)
        var previous: Int32 = 0
        for (i, cut) in cuts.enumerated() {
            sizes[i] += cut - previous
            previous = cut
        }
        return sizes
    }

    private mutating func cell(width: Int32, height: Int32, depth: Int, parentVertical: Bool?) -> Cell {
        let verticalDividers = parentVertical.map { !$0 } ?? chance(0.5)
        let extent = verticalDividers ? width : height
        let minimumLeaf = verticalDividers ? 1 : minimumHeight
        let maximumChildren = Int((extent + 1) / (minimumLeaf + 1))
        if maximumChildren < 2 || depth >= 5 || (depth > 0 && chance(0.35)) {
            return .leaf(width: width, height: height, x: 0, y: 0, pane: paneIDs.removeLast())
        }
        let count = Int(int(2...Int32(min(5, maximumChildren))))
        let sizes = partition(extent - Int32(count - 1), minimums: Array(repeating: minimumLeaf, count: count))
        let children = sizes.map { size in
            cell(width: verticalDividers ? size : width,
                 height: verticalDividers ? height : size,
                 depth: depth + 1,
                 parentVertical: verticalDividers)
        }
        return .split(verticalDividers: verticalDividers, width: width, height: height, x: 0, y: 0,
                      children: children)
    }

    // The smallest |cell| can be across |vertical| dividers.
    func minimumExtent(_ cell: Cell, vertical: Bool) -> Int32 {
        switch cell {
        case .leaf:
            return vertical ? 1 : minimumHeight
        case let .split(verticalDividers, _, _, _, _, children):
            let minimums = children.map { minimumExtent($0, vertical: vertical) }
            if verticalDividers == vertical {
                return minimums.reduce(Int32(children.count - 1), +)
            }
            return minimums.max()!
        }
    }

    // |cell| at a new size across |vertical| dividers, shared at random among the children of
    // splits in the same direction. Offsets are left for placed(x:y:) to fix.
    mutating func resized(_ cell: Cell, to newExtent: Int32, vertical: Bool) -> Cell {
        switch cell {
        case let .leaf(width, height, x, y, pane):
            return .leaf(width: vertical ? newExtent : width, height: vertical ? height : newExtent,
                         x: x, y: y, pane: pane)
        case let .split(verticalDividers, width, height, x, y, children):
            var newChildren = [Cell]()
            if verticalDividers == vertical {
                let sizes = partition(newExtent - Int32(children.count - 1),
                                      minimums: children.map { minimumExtent($0, vertical: vertical) })
                for (child, size) in zip(children, sizes) {
                    newChildren.append(resized(child, to: size, vertical: vertical))
                }
            } else {
                for child in children {
                    newChildren.append(resized(child, to: newExtent, vertical: vertical))
                }
            }
            return .split(verticalDividers: verticalDividers,
                          width: vertical ? newExtent : width, height: vertical ? height : newExtent,
                          x: x, y: y, children: newChildren)
        }
    }
}

final class TmuxDividerMoverPropertyTests: XCTestCase {
    private let seeds: [UInt64] = Array(1...10)

    // MARK: - Running the mover

    // Parsing logs a line, so trees are kept for reuse. The mover must not change them, which
    // testParseTreeIsNotModified checks.
    private var parseTrees = [String: NSMutableDictionary]()

    private func parseTree(_ cell: Cell, paneBorderStatus: iTermTmuxPaneBorderStatus) -> NSMutableDictionary {
        let key = "\(paneBorderStatus.rawValue) \(cell.layout)"
        if let tree = parseTrees[key] {
            return tree
        }
        let parser = TmuxLayoutParser.sharedInstance()!
        let parsed = parser.parsedLayout(from: cell.layout)!
        let tree = parser.parseTree(parsed, adjustedFor: paneBorderStatus)!
        parseTrees[key] = tree
        return tree
    }

    // Each pane's size, as the window shows it: from the parse tree, so pane-border-status has
    // already taken its row.
    private func shownSizes(_ dict: NSDictionary) -> [Int32: (width: Int32, height: Int32)] {
        let type = (dict[kLayoutDictNodeType] as! NSNumber).intValue
        if type == LayoutNodeType.leafLayoutNode.rawValue {
            return [int32(dict[kLayoutDictWindowPaneKey]): (int32(dict[kLayoutDictWidthKey]),
                                                            int32(dict[kLayoutDictHeightKey]))]
        }
        var result = [Int32: (width: Int32, height: Int32)]()
        for child in dict[kLayoutDictChildrenKey] as! [NSDictionary] {
            result.merge(shownSizes(child)) { a, _ in a }
        }
        return result
    }

    private func int32(_ value: Any?) -> Int32 {
        if let number = value as? NSNumber {
            return number.int32Value
        }
        return (value as! NSString).intValue
    }

    private func exactMeasurements(_ cell: Cell,
                                   vertical: Bool,
                                   paneBorderStatus: iTermTmuxPaneBorderStatus) -> [Int32: Double] {
        return shownSizes(parseTree(cell, paneBorderStatus: paneBorderStatus)).mapValues {
            Double(vertical ? $0.width : $0.height)
        }
    }

    private func move(_ cell: Cell,
                      split path: [Int],
                      divider: Int,
                      measured: [Int32: Double],
                      paneBorderStatus: iTermTmuxPaneBorderStatus = .off,
                      panes: [Int32]? = nil) -> String? {
        let split = cell.cell(at: path)
        guard case let .split(verticalDividers, _, _, _, _, _) = split else {
            XCTFail("not a split")
            return nil
        }
        var extents = [NSNumber: NSNumber]()
        for (pane, extent) in measured {
            extents[NSNumber(value: pane)] = NSNumber(value: extent)
        }
        return TmuxDividerMover.layoutString(parseTree: parseTree(cell, paneBorderStatus: paneBorderStatus),
                                             dividerIndex: divider,
                                             panes: (panes ?? split.panes.reversed()).map { NSNumber(value: $0) },
                                             verticalDividers: verticalDividers,
                                             measuredExtents: extents,
                                             paneBorderStatus: paneBorderStatus)
    }

    // MARK: - Checking the output

    // tmux's layout_check, plus what tmux's own layouts always satisfy: offsets follow from sizes,
    // splits have at least two children and alternate direction, and every pane has its minimum.
    // With pane-border-status, a pane on the edge with the status line needs a row for it.
    private func validityProblem(_ cell: Cell,
                                 paneBorderStatus: iTermTmuxPaneBorderStatus,
                                 windowHeight: Int32? = nil,
                                 parentVertical: Bool? = nil) -> String? {
        let windowHeight = windowHeight ?? cell.height
        switch cell {
        case let .leaf(width, height, _, y, pane):
            let onStatusEdge = ((paneBorderStatus == .top && y == 0) ||
                                (paneBorderStatus == .bottom && y + height == windowHeight))
            if width < 1 || height < (onStatusEdge ? 2 : 1) {
                return "pane \(pane) is \(width)x\(height)"
            }
            return nil
        case let .split(verticalDividers, width, height, x, y, children):
            if children.count < 2 {
                return "split at \(x),\(y) has \(children.count) children"
            }
            if parentVertical == verticalDividers {
                return "split at \(x),\(y) has the same direction as its parent"
            }
            var cx = x
            var cy = y
            for child in children {
                if child.x != cx || child.y != cy {
                    return "child at \(child.x),\(child.y) should be at \(cx),\(cy)"
                }
                if verticalDividers ? child.height != height : child.width != width {
                    return "child \(child.body) doesn't span its parent \(width)x\(height)"
                }
                if let problem = validityProblem(child, paneBorderStatus: paneBorderStatus,
                                                 windowHeight: windowHeight, parentVertical: verticalDividers) {
                    return problem
                }
                if verticalDividers {
                    cx += child.width + 1
                } else {
                    cy += child.height + 1
                }
            }
            if verticalDividers ? cx - x - 1 != width : cy - y - 1 != height {
                return "children of split at \(x),\(y) don't add up to \(width)x\(height)"
            }
            return nil
        }
    }

    // Everything but the two cells beside the divider must be exactly as it was, and those two
    // may change only across the divider.
    private func unchangedProblem(_ before: Cell, _ after: Cell, path: [Int], divider: Int, vertical: Bool) -> String? {
        guard before.width == after.width, before.height == after.height,
              before.x == after.x, before.y == after.y else {
            return "\(before.body) became \(after.body)"
        }
        if path.isEmpty {
            for (i, (b, a)) in zip(before.children, after.children).enumerated() {
                if i == divider || i == divider + 1 {
                    for (bl, al) in zip(b.leaves, a.leaves) {
                        if vertical ? bl.height != al.height || bl.y != al.y : bl.width != al.width || bl.x != al.x {
                            return "pane \(bl.panes[0]) changed along the divider: \(bl.body) became \(al.body)"
                        }
                    }
                } else if b != a {
                    return "\(b.body) away from the divider became \(a.body)"
                }
            }
            return nil
        }
        for (i, (b, a)) in zip(before.children, after.children).enumerated() {
            if i == path[0] {
                if let problem = unchangedProblem(b, a, path: Array(path.dropFirst()), divider: divider,
                                                  vertical: vertical) {
                    return problem
                }
            } else if b != a {
                return "\(b.body) outside the split became \(a.body)"
            }
        }
        return nil
    }

    // Checks a result that must be a valid layout and returns it.
    @discardableResult
    private func checkedResult(_ layout: String?,
                               input: Cell,
                               path: [Int],
                               divider: Int,
                               paneBorderStatus: iTermTmuxPaneBorderStatus,
                               context: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) -> Cell? {
        guard let layout else {
            XCTFail("No layout for \(context)", file: file, line: line)
            return nil
        }
        guard let read = LayoutReader.read(layout) else {
            XCTFail("Unreadable layout \(layout) for \(context)", file: file, line: line)
            return nil
        }
        let output = read.cell
        XCTAssertTrue(read.checksumMatches, "Bad checksum in \(layout) for \(context)", file: file, line: line)
        XCTAssertEqual(output.shape, input.shape, "Shape changed for \(context)", file: file, line: line)
        if let problem = validityProblem(output, paneBorderStatus: paneBorderStatus) {
            XCTFail("tmux would reject \(layout): \(problem), for \(context)", file: file, line: line)
        }
        guard case let .split(vertical, _, _, _, _, _) = input.cell(at: path) else {
            return output
        }
        if output.shape == input.shape,
           let problem = unchangedProblem(input, output, path: path, divider: divider, vertical: vertical) {
            XCTFail("\(problem), for \(context)", file: file, line: line)
        }
        return output
    }

    private func forEachDivider(minimumHeight: Int32 = 1,
                                _ body: (inout LayoutGenerator, Cell, [Int], Int, Bool, String) -> Void) {
        for seed in seeds {
            var generator = LayoutGenerator(seed: seed, minimumHeight: minimumHeight)
            let input = generator.window()
            for path in input.splitPaths() {
                guard case let .split(vertical, _, _, _, _, children) = input.cell(at: path) else {
                    continue
                }
                for divider in 0..<(children.count - 1) {
                    body(&generator, input, path, divider, vertical,
                         "seed \(seed), split \(path), divider \(divider), layout \(input.layout)")
                }
            }
        }
    }

    private let statuses: [(iTermTmuxPaneBorderStatus, Int32)] = [(.off, 1), (.top, 2), (.bottom, 2)]

    // MARK: - Tests

    func testGeneratorMakesLayoutsTmuxAccepts() {
        for seed in seeds {
            var generator = LayoutGenerator(seed: seed, minimumHeight: 1)
            let cell = generator.window()
            XCTAssertNil(validityProblem(cell, paneBorderStatus: .off), cell.layout)
            XCTAssertEqual(LayoutReader.read(cell.layout)?.cell, cell)
        }
    }

    // If the window shows what tmux has, tmux must be sent back the layout it already has, for any
    // divider and with any pane-border-status.
    func testExactMeasurementsGiveBackTheSameLayout() {
        for (status, minimumHeight) in statuses {
            forEachDivider(minimumHeight: minimumHeight) { _, input, path, divider, vertical, context in
                let measured = exactMeasurements(input, vertical: vertical, paneBorderStatus: status)
                let result = move(input, split: path, divider: divider, measured: measured, paneBorderStatus: status)
                XCTAssertEqual(result.map { String($0.dropFirst(5)) }, input.body, "status \(status), \(context)")
            }
        }
    }

    // Any valid layout that only moves the dragged divider (sharing the change among nested splits
    // in any way) must come back exactly when the window shows it.
    func testAnyReachableLayoutRoundTrips() {
        for (status, minimumHeight) in statuses {
            forEachDivider(minimumHeight: minimumHeight) { generator, input, path, divider, vertical, context in
                for _ in 0..<3 {
                    let split = input.cell(at: path)
                    var children = split.children
                    let before = children[divider]
                    let after = children[divider + 1]
                    let total = before.extent(vertical: vertical) + after.extent(vertical: vertical)
                    let minimumBefore = generator.minimumExtent(before, vertical: vertical)
                    let minimumAfter = generator.minimumExtent(after, vertical: vertical)
                    let newBefore = generator.int(minimumBefore...(total - minimumAfter))
                    children[divider] = generator.resized(before, to: newBefore, vertical: vertical)
                    children[divider + 1] = generator.resized(after, to: total - newBefore, vertical: vertical)
                    let target = replacing(input, at: path, withChildren: children).placed(x: 0, y: 0)
                    XCTAssertNil(validityProblem(target, paneBorderStatus: status), "bad target for \(context)")

                    let measured = exactMeasurements(target, vertical: vertical, paneBorderStatus: status)
                    let result = move(input, split: path, divider: divider, measured: measured,
                                      paneBorderStatus: status)
                    XCTAssertEqual(result.map { String($0.dropFirst(5)) }, target.body,
                                   "status \(status), target \(target.layout), \(context)")
                }
            }
        }
    }

    // Measurements a window can't really produce (negative, zero, tiny, huge, or wildly
    // inconsistent between panes of one nested split) must still give a layout tmux accepts that
    // only moves the dragged divider.
    func testArbitraryMeasurementsGiveValidLayouts() {
        for (status, minimumHeight) in statuses {
            forEachDivider(minimumHeight: minimumHeight) { generator, input, path, divider, vertical, context in
                for trial in 0..<4 {
                    var measured = [Int32: Double]()
                    for leaf in input.leaves {
                        let extent = Double(leaf.extent(vertical: vertical))
                        switch generator.int(0...7) {
                        case 0: measured[leaf.panes[0]] = 0
                        case 1: measured[leaf.panes[0]] = -generator.double(0...1000)
                        case 2: measured[leaf.panes[0]] = 1e-12
                        case 3: measured[leaf.panes[0]] = 1e9
                        case 4: measured[leaf.panes[0]] = extent
                        default: measured[leaf.panes[0]] = generator.double(0...(extent * 3))
                        }
                    }
                    let result = move(input, split: path, divider: divider, measured: measured,
                                      paneBorderStatus: status)
                    checkedResult(result, input: input, path: path, divider: divider, paneBorderStatus: status,
                                  context: "status \(status), trial \(trial), measured \(measured), \(context)")
                }
            }
        }
    }

    // Values that would trap a Double to Int32 conversion must not crash.
    func testNonFiniteAndExtremeMeasurementsDoNotCrash() {
        let hostile: [Double] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                                 -.greatestFiniteMagnitude, .leastNonzeroMagnitude, 1e300, Double(Int32.max) * 4]
        forEachDivider { generator, input, path, divider, vertical, context in
            for value in hostile {
                for everywhere in [false, true] {
                    var measured = exactMeasurements(input, vertical: vertical, paneBorderStatus: .off)
                    if everywhere {
                        measured = measured.mapValues { _ in value }
                    } else {
                        let leaves = input.cell(at: path).children[divider].leaves
                        measured[leaves[Int(generator.int(0...Int32(leaves.count - 1)))].panes[0]] = value
                    }
                    let result = move(input, split: path, divider: divider, measured: measured)
                    if result != nil {
                        checkedResult(result, input: input, path: path, divider: divider, paneBorderStatus: .off,
                                      context: "\(value) everywhere: \(everywhere), \(context)")
                    }
                }
            }
        }
    }

    // Showing more of the cell before the divider never moves the divider back toward it.
    func testDividerMovesMonotonically() {
        forEachDivider { _, input, path, divider, vertical, context in
            let base = exactMeasurements(input, vertical: vertical, paneBorderStatus: .off)
            let beforePanes = Set(input.cell(at: path).children[divider].panes)
            var previous: Int32 = .min
            for step in 0...12 {
                let factor = Double(step) / 4
                let measured = Dictionary(uniqueKeysWithValues: base.map { pane, extent in
                    (pane, beforePanes.contains(pane) ? extent * factor : extent)
                })
                guard let output = checkedResult(move(input, split: path, divider: divider, measured: measured),
                                                 input: input, path: path, divider: divider, paneBorderStatus: .off,
                                                 context: "factor \(factor), \(context)") else {
                    return
                }
                let extent = output.cell(at: path).children[divider].extent(vertical: vertical)
                XCTAssertGreaterThanOrEqual(extent, previous, "factor \(factor), \(context)")
                previous = extent
            }
        }
    }

    // Panes outside the neighbors, and panes that aren't in the window, needn't be measured.
    func testOnlyTheNeighborsNeedMeasuring() {
        forEachDivider { _, input, path, divider, vertical, context in
            let all = exactMeasurements(input, vertical: vertical, paneBorderStatus: .off)
            let split = input.cell(at: path)
            let neighbors = Set(split.children[divider].panes + split.children[divider + 1].panes)
            var measured = all.filter { neighbors.contains($0.key) }
            measured[99_999] = 5
            measured[-1] = .nan
            XCTAssertEqual(move(input, split: path, divider: divider, measured: measured).map { String($0.dropFirst(5)) },
                           input.body, context)

            var missing = measured
            missing[split.children[divider + 1].panes.last!] = nil
            XCTAssertNil(move(input, split: path, divider: divider, measured: missing), context)
        }
    }

    // The split is named by its panes. Order and repeats don't matter, but a wrong set must not
    // match some other split.
    func testSplitIsFoundOnlyByItsExactPanes() {
        forEachDivider { generator, input, path, divider, vertical, context in
            let measured = exactMeasurements(input, vertical: vertical, paneBorderStatus: .off)
            let panes = input.cell(at: path).panes
            let shuffled = (panes + panes.prefix(2)).shuffled(using: &generator.rng)
            XCTAssertEqual(move(input, split: path, divider: divider, measured: measured, panes: shuffled)
                .map { String($0.dropFirst(5)) }, input.body, context)
            XCTAssertNil(move(input, split: path, divider: divider, measured: measured, panes: panes + [99_999]),
                         context)
            if panes.count > 2 {
                XCTAssertNil(move(input, split: path, divider: divider, measured: measured,
                                  panes: Array(panes.dropLast())), context)
            }
            XCTAssertNil(move(input, split: path, divider: divider, measured: measured, panes: []), context)
        }
    }

    // The parse tree belongs to the tab and is reused for the next drag.
    func testParseTreeIsNotModified() {
        for (status, minimumHeight) in statuses {
            forEachDivider(minimumHeight: minimumHeight) { generator, input, path, divider, vertical, context in
                let parser = TmuxLayoutParser.sharedInstance()!
                let tree = parser.parseTree(parser.parsedLayout(from: input.layout)!, adjustedFor: status)!
                let before = tree.description
                var extents = [NSNumber: NSNumber]()
                for leaf in input.leaves {
                    extents[NSNumber(value: leaf.panes[0])] = NSNumber(value: generator.double(0...50))
                }
                _ = TmuxDividerMover.layoutString(parseTree: tree,
                                                  dividerIndex: divider,
                                                  panes: input.cell(at: path).panes.map { NSNumber(value: $0) },
                                                  verticalDividers: vertical,
                                                  measuredExtents: extents,
                                                  paneBorderStatus: status)
                XCTAssertEqual(tree.description, before, context)
            }
        }
    }

    func testOutOfRangeDividersReturnNil() {
        for seed in seeds.prefix(20) {
            var generator = LayoutGenerator(seed: seed, minimumHeight: 1)
            let input = generator.window()
            for path in input.splitPaths() {
                let split = input.cell(at: path)
                let measured = exactMeasurements(input, vertical: true, paneBorderStatus: .off)
                for divider in [-1, Int.min, split.children.count - 1, split.children.count, Int(Int32.max), Int.max] {
                    XCTAssertNil(move(input, split: path, divider: divider, measured: measured),
                                 "seed \(seed), divider \(divider)")
                }
            }
        }
    }

    // A window with one pane has no divider to move.
    func testSinglePaneWindow() {
        let cell = Cell.leaf(width: 80, height: 24, x: 0, y: 0, pane: 7)
        let tree = parseTree(cell, paneBorderStatus: .off)
        for vertical in [true, false] {
            XCTAssertNil(TmuxDividerMover.layoutString(parseTree: tree,
                                                       dividerIndex: 0,
                                                       panes: [7],
                                                       verticalDividers: vertical,
                                                       measuredExtents: [7: 80],
                                                       paneBorderStatus: .off))
        }
    }

    // A malformed parse tree gives nil, not a crash or a half-built layout.
    func testMalformedParseTreesReturnNil() {
        let leaf: (Int) -> NSMutableDictionary = { pane in
            [kLayoutDictNodeType: NSNumber(value: LayoutNodeType.leafLayoutNode.rawValue),
             kLayoutDictWidthKey: "10", kLayoutDictHeightKey: "10", kLayoutDictWindowPaneKey: NSNumber(value: pane)]
        }
        let split: ([Any]) -> NSMutableDictionary = { children in
            [kLayoutDictNodeType: NSNumber(value: LayoutNodeType.vSplitLayoutNode.rawValue),
             kLayoutDictChildrenKey: children]
        }
        let noPane = leaf(2)
        noPane.removeObject(forKey: kLayoutDictWindowPaneKey)
        let badType = leaf(2)
        badType[kLayoutDictNodeType] = NSNumber(value: 42)
        let stringWidth = leaf(2)
        stringWidth[kLayoutDictWidthKey] = ["not", "a", "number"]
        let trees: [NSDictionary] = [
            [:],
            split([]),
            split([leaf(1), noPane]),
            split([leaf(1), badType]),
            split([leaf(1), stringWidth]),
            split([leaf(1), "not a dictionary"]),
            [kLayoutDictNodeType: NSNumber(value: LayoutNodeType.vSplitLayoutNode.rawValue),
             kLayoutDictChildrenKey: "not an array"],
        ]
        for tree in trees {
            XCTAssertNil(TmuxDividerMover.layoutString(parseTree: tree,
                                                       dividerIndex: 0,
                                                       panes: [1, 2],
                                                       verticalDividers: true,
                                                       measuredExtents: [1: 12, 2: 8],
                                                       paneBorderStatus: .off),
                         "\(tree)")
        }
    }

    // MARK: - Helpers

    private func replacing(_ cell: Cell, at path: [Int], withChildren newChildren: [Cell]) -> Cell {
        guard case let .split(verticalDividers, width, height, x, y, children) = cell else {
            return cell
        }
        if path.isEmpty {
            return .split(verticalDividers: verticalDividers, width: width, height: height, x: x, y: y,
                          children: newChildren)
        }
        var updated = children
        updated[path[0]] = replacing(children[path[0]], at: Array(path.dropFirst()), withChildren: newChildren)
        return .split(verticalDividers: verticalDividers, width: width, height: height, x: x, y: y, children: updated)
    }
}
