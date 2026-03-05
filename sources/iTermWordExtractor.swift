//
//  iTermWordExtractor.swift
//  iTerm2
//
//  Created by George Nachman on 11/11/24.
//  Ported to Swift on 3/2/26.
//

import Foundation

// MARK: - CharacterAtomSource Adapter

/// Adapter class that wraps iTermWordExtractorDataSource and implements CharacterAtomSource
private class DataSourceCharacterAtomAdapter: CharacterAtomSource {
    private let dataSource: iTermWordExtractorDataSource
    private let additionalWordCharacters: String?

    init(_ dataSource: iTermWordExtractorDataSource, additionalWordCharacters: String? = nil) {
        self.dataSource = dataSource
        self.additionalWordCharacters = additionalWordCharacters
    }

    func characterAt(_ coord: VT100GridCoord) -> screen_char_t {
        return dataSource.character(at: coord)
    }

    func stringForCharacter(_ char: screen_char_t) -> String {
        return dataSource.string(forCharacter: char)
    }

    func logicalWindow() -> VT100GridRange {
        return dataSource.wordExtractorLogicalWindow()
    }

    func isWordExtendingCharacter(_ string: String) -> Bool {
        guard let chars = additionalWordCharacters, !chars.isEmpty else {
            return false
        }
        return chars.contains(string)
    }

    func enumerateCharsInRange(
        _ range: VT100GridWindowedRange,
        supportBidi: Bool,
        charBlock: ((UnsafePointer<screen_char_t>?, screen_char_t, iTermExternalAttribute?, VT100GridCoord, VT100GridCoord) -> Bool)?,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    ) {
        dataSource.enumerateChars(in: range, supportBidi: supportBidi, charBlock: charBlock, eolBlock: eolBlock)
    }

    func enumerateInReverseCharsInRange(
        _ range: VT100GridWindowedRange,
        charBlock: ((screen_char_t, VT100GridCoord, VT100GridCoord) -> Bool)?,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    ) {
        dataSource.enumerateInReverseChars(in: range, charBlock: charBlock, eolBlock: eolBlock)
    }
}

// MARK: - RegexAtomIteratorDataSource Adapter

/// Adapter class that wraps iTermWordExtractorDataSource and implements RegexAtomIteratorDataSource
private class DataSourceRegexAtomAdapter: RegexAtomIteratorDataSource {
    private let dataSource: iTermWordExtractorDataSource

    init(_ dataSource: iTermWordExtractorDataSource) {
        self.dataSource = dataSource
    }

    func successorOfCoord(_ coord: VT100GridCoord) -> VT100GridCoord {
        return dataSource.successor(of: coord)
    }
}

/// Definition of what constitutes an alphanumeric character for word extraction.
private enum AlphaNumericDefinition {
    case narrow       // Only allows hyphen
    case userDefined  // Uses additionalWordCharacters preference
    case unixCommands // Allows _ and -
    case bigWords     // Any non-whitespace
}

// Type alias for shorter enum references
private typealias TextClass = iTermTextExtractorClass

// Extension to provide shorter case names
private extension iTermTextExtractorClass {
    static let whitespace = iTermTextExtractorClass.textExtractorClassWhitespace
    static let word = iTermTextExtractorClass.textExtractorClassWord
    static let null = iTermTextExtractorClass.textExtractorClassNull
    static let doubleWidthPlaceholder = iTermTextExtractorClass.textExtractorClassDoubleWidthPlaceholder
    static let other = iTermTextExtractorClass.textExtractorClassOther
}

/// Extracts words from terminal screen content.
///
/// This class handles word extraction for double-click selection and similar features.
/// It supports multiple word boundary definitions and language-specific segmentation.
@objc(iTermWordExtractor)
@objcMembers
class WordExtractor: NSObject {
    /// The starting location for word extraction
    @objc var location: VT100GridCoord

    /// Maximum number of characters to search
    @objc var maximumLength: Int

    /// Whether to use "big word" mode (whitespace-delimited)
    @objc var big: Bool

    /// Data source providing screen content
    @objc weak var dataSource: iTermWordExtractorDataSource? {
        didSet {
            if let ds = dataSource {
                logicalWindow = ds.wordExtractorLogicalWindow()
            }
            // Invalidate cached atom iterator when data source changes
            cachedAtomSource = nil
            cachedAtomIterator = nil
        }
    }

    /// Additional characters to treat as part of a word
    @objc var additionalWordCharacters: String?

    /// Regex patterns for word selection. Matches are treated as word characters.
    @objc var regexPatterns: [String] = []

    private var logicalWindow = VT100GridRange()
    private var internalAdditionalWordCharacters: String?

    // Cached atom iterator to avoid redundant heap allocations during word extraction
    private var cachedAtomSource: DataSourceCharacterAtomAdapter?
    private var cachedAtomIterator: CharacterAtomIterator?

    @objc init(location: VT100GridCoord, maximumLength: Int, big: Bool) {
        self.location = location
        self.maximumLength = maximumLength
        self.big = big
        self.internalAdditionalWordCharacters = iTermPreferences.string(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        super.init()
    }

    // MARK: - Cached Atom Iterator

    /// Returns a cached atom iterator, creating it if needed.
    /// This avoids redundant heap allocations during word extraction.
    private func getAtomIterator(for ds: iTermWordExtractorDataSource) -> CharacterAtomIterator {
        if let cachedIterator = cachedAtomIterator {
            return cachedIterator
        }
        let effectiveAdditionalChars = additionalWordCharacters ?? internalAdditionalWordCharacters
        let atomSource = DataSourceCharacterAtomAdapter(ds, additionalWordCharacters: effectiveAdditionalChars)
        let atomIterator = CharacterAtomIterator(dataSource: atomSource)
        cachedAtomSource = atomSource
        cachedAtomIterator = atomIterator
        return atomIterator
    }

    // MARK: - Public Methods

    /// Extracts a word range for "big word" mode.
    ///
    /// In big word mode, words are delimited by whitespace only.
    @objc func windowedRangeForBigWord() -> VT100GridWindowedRange {
        let unsafeLocation = location
        if unsafeLocation.y < 0 {
            return errorLocation()
        }

        guard let ds = dataSource else {
            return errorLocation()
        }

        let lockedLocation = ds.successor(of: coordLockedToWindow(unsafeLocation))
        let predecessor = ds.predecessor(of: lockedLocation)

        let classAtLocation = classForCharacter(ds.character(at: predecessor), bigWords: true)

        let subExtractor = WordExtractor(location: predecessor, maximumLength: maximumLength, big: true)
        subExtractor.dataSource = dataSource
        var wordRange = subExtractor.windowedRange()

        if classAtLocation == .whitespace {
            subExtractor.location = ds.predecessor(of: wordRange.coordRange.start)
            let beforeRange = subExtractor.windowedRange()
            wordRange.coordRange.start = beforeRange.coordRange.start
        } else {
            // wordRange is a half-open interval so end gives the successor
            subExtractor.location = wordRange.coordRange.end
            subExtractor.big = false
            let afterRange = subExtractor.windowedRange()
            wordRange.coordRange.end = afterRange.coordRange.end
        }

        return wordRange
    }

    /// Extracts the word range at the current location.
    @objc func windowedRange() -> VT100GridWindowedRange {
        guard locationIsValid, dataSource != nil else {
            return errorLocation()
        }

        DLog("Compute range for word at \(VT100GridCoordDescription(location)), max length \(maximumLength)")
        DLog("These special chars will be treated as alphanumeric: \(iTermPreferences.string(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection) ?? "nil")")

        let lockedLocation = coordLockedToWindow(location)
        return windowedRange(forLocation: lockedLocation)
    }

    /// Fast word extraction that returns just the string.
    ///
    /// This uses a stricter definition of word characters (excluding most punctuation)
    /// and has a fixed maximum length of 20 characters.
    @objc func fastString() -> String? {
        guard let ds = dataSource else {
            return nil
        }

        let lockedLocation = coordLockedToWindow(location)
        let theClass = classForCharacter(ds.character(at: location))

        if theClass == .doubleWidthPlaceholder {
            let predecessor = ds.predecessor(of: location)
            if predecessor.x != location.x || predecessor.y != location.y {
                return fastString(at: predecessor)
            }
        } else if theClass == .other {
            return nil
        }

        return fastString(at: lockedLocation)
    }

    // MARK: - Private Methods

    private var locationIsValid: Bool {
        return location.y >= 0
    }

    private func errorLocation() -> VT100GridWindowedRange {
        return VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(-1, -1, -1, -1),
            logicalWindow.location,
            logicalWindow.length
        )
    }

    private func coordLockedToWindow(_ coord: VT100GridCoord) -> VT100GridCoord {
        if logicalWindow.length == 0 {
            return coord
        }
        var result = coord
        result.x = min(max(coord.x, logicalWindow.location),
                       logicalWindow.location + logicalWindow.length - 1)
        return result
    }

    private func windowedRange(forLocation location: VT100GridCoord) -> VT100GridWindowedRange {
        guard let ds = dataSource else {
            return errorLocation()
        }

        let numberOfLines = Int(ds.wordExtractorNumberOfLines())
        if Int(location.y) >= numberOfLines {
            return VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(-1, -1, -1, -1),
                logicalWindow.location,
                logicalWindow.length
            )
        }

        // Handle special cases before collecting atoms
        let theClass = classForCharacter(ds.character(at: location), bigWords: big)

        DLog("Initial class for '\(ds.string(forCharacter: ds.character(at: location)))' at \(VT100GridCoordDescription(location)) is \(theClass)")

        if theClass == .doubleWidthPlaceholder {
            DLog("Location is a DWC placeholder. Try again with predecessor")
            let predecessor = ds.predecessor(of: location)
            if predecessor.x != location.x || predecessor.y != location.y {
                return windowedRange(forLocation: predecessor)
            }
        }

        if theClass == .other {
            DLog("Character class is other, select one character.")
            return ds.windowedRange(with: VT100GridCoordRangeMake(
                location.x, location.y,
                location.x + 1, location.y
            ))
        }

        // Collect atoms around the location (works for both character and regex modes)
        guard let collection = collectAtomsAroundLocation(location) else {
            DLog("Failed to collect atoms")
            return ds.windowedRange(with: VT100GridCoordRangeMake(
                location.x, location.y,
                location.x, location.y
            ))
        }

        let atoms = collection.atoms
        let clickIndex = collection.clickIndex

        // For regex mode, we need to re-classify based on the clicked atom
        // (since regex matches may have forcedWordClass)
        let effectiveClass: TextClass
        if !regexPatterns.isEmpty {
            effectiveClass = classForAtomWithString(atoms[clickIndex], bigWords: big)
            DLog("Regex mode: clicked atom '\(atoms[clickIndex].string)' has class \(effectiveClass)")

            if effectiveClass == .other {
                // Select just the single atom
                DLog("Class is other, selecting single atom")
                return ds.windowedRange(with: atoms[clickIndex].coordRange)
            }
        } else {
            effectiveClass = theClass
        }

        // Search forward and backward for atoms of the same class
        let boundaries = searchForSameClassBoundaries(
            atoms: atoms,
            clickIndex: clickIndex,
            theClass: effectiveClass
        )

        guard boundaries.startIndex < boundaries.endIndex else {
            return ds.windowedRange(with: VT100GridCoordRangeMake(
                location.x, location.y,
                location.x, location.y
            ))
        }

        // For word class (not big word mode), apply ICU segmentation
        if effectiveClass == .word && !big {
            var result = VT100GridWindowedRange()
            ds.performBlock(lineCache: {
                result = self.applyICUSegmentationToAtoms(
                    atoms: atoms,
                    startAtomIndex: boundaries.startIndex,
                    endAtomIndex: boundaries.endIndex,
                    clickAtomIndex: clickIndex
                )
            })
            return result
        }

        // For non-word classes or big word mode, use atom boundaries directly
        return buildCoordRangeFromAtoms(atoms, startIndex: boundaries.startIndex, endIndex: boundaries.endIndex)
    }

    // MARK: - Atom Collection

    /// Result of collecting atoms around a location.
    private struct AtomCollection {
        let atoms: [WordSelectionAtom]
        let clickIndex: Int
    }

    /// Collect atoms around the given location.
    /// For regex mode: extracts wrapped line and uses RegexAtomIterator.
    /// For character mode: uses CharacterAtomIterator to enumerate atoms.
    private func collectAtomsAroundLocation(_ location: VT100GridCoord) -> AtomCollection? {
        if !regexPatterns.isEmpty {
            return collectAtomsUsingRegex(around: location)
        } else {
            return collectAtomsUsingCharacterIterator(around: location)
        }
    }

    /// Collect atoms using RegexAtomIterator (for regex mode).
    private func collectAtomsUsingRegex(around location: VT100GridCoord) -> AtomCollection? {
        guard let ds = dataSource else { return nil }

        DLog("Collecting atoms using regex at \(VT100GridCoordDescription(location))")

        var targetOffset: Int32 = 0
        let locatedString = ds.locatedString(forWrappedLineEncompassing: location, targetOffset: &targetOffset)

        guard locatedString.length > 0 else {
            DLog("No text extracted for regex matching")
            return nil
        }

        DLog("Extracted \(locatedString.length) UTF-16 code units, target offset \(targetOffset)")

        let regexDataSource = DataSourceRegexAtomAdapter(ds)
        let atomIterator = RegexAtomIterator(dataSource: regexDataSource)
        atomIterator.regexPatterns = regexPatterns
        atomIterator.preatomize(locatedString: locatedString, targetIndex: Int(targetOffset))

        guard let atoms = atomIterator.atoms, !atoms.isEmpty else {
            DLog("No atoms created")
            return nil
        }

        DLog("Created \(atoms.count) atoms, click atom index \(atomIterator.clickAtomIndex)")
        return AtomCollection(atoms: atoms, clickIndex: atomIterator.clickAtomIndex)
    }

    /// Collect atoms using CharacterAtomIterator (for character mode).
    /// Enumerates forward and backward from the location to build an atom array.
    private func collectAtomsUsingCharacterIterator(around location: VT100GridCoord) -> AtomCollection? {
        guard let ds = dataSource else { return nil }

        DLog("Collecting atoms using character iterator at \(VT100GridCoordDescription(location))")

        let atomIterator = getAtomIterator(for: ds)
        let xLimit = Int(ds.xLimit())
        let width = Int(ds.wordExtractorWidth())
        let numberOfLines = Int(ds.wordExtractorNumberOfLines())
        let windowTouchesLeftMargin = logicalWindow.location == 0
        let windowTouchesRightMargin = xLimit == width

        // Collect atoms forward (including click location)
        var forwardAtoms: [WordSelectionAtom] = []
        let forwardRange = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(location.x, location.y, Int32(width), Int32(numberOfLines - 1)),
            logicalWindow.location,
            logicalWindow.length
        )

        atomIterator.enumerateAtomsForward(
            inRange: forwardRange,
            supportBidi: false,
            atomBlock: { _, atom, _, _, _ in
                // Filter out private use area characters (same as original searchForwards)
                if let theChar = atom.character,
                   theChar.complexChar != 0 ||
                    theChar.code < ITERM2_PRIVATE_BEGIN ||
                    theChar.code > ITERM2_PRIVATE_END {
                    forwardAtoms.append(atom)
                }
                return forwardAtoms.count >= self.maximumLength
            },
            eolBlock: { code, numPrecedingNulls, line in
                return ds.shouldStopEnumerating(
                    withCode: code,
                    numNulls: numPrecedingNulls,
                    windowTouchesLeftMargin: windowTouchesLeftMargin,
                    windowTouchesRightMargin: windowTouchesRightMargin,
                    ignoringNewlines: false
                )
            }
        )

        // Collect atoms backward (not including click location)
        var backwardAtoms: [WordSelectionAtom] = []
        let backwardRange = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(0, 0, location.x, location.y),
            logicalWindow.location,
            logicalWindow.length
        )

        atomIterator.enumerateAtomsReverse(
            inRange: backwardRange,
            atomBlock: { atom, _, _ in
                if let theChar = atom.character,
                   theChar.complexChar != 0 ||
                    theChar.code < ITERM2_PRIVATE_BEGIN ||
                    theChar.code > ITERM2_PRIVATE_END {
                    backwardAtoms.append(atom)
                }
                return backwardAtoms.count >= self.maximumLength
            },
            eolBlock: { code, numPrecedingNulls, line in
                return ds.shouldStopEnumerating(
                    withCode: code,
                    numNulls: numPrecedingNulls,
                    windowTouchesLeftMargin: windowTouchesLeftMargin,
                    windowTouchesRightMargin: windowTouchesRightMargin,
                    ignoringNewlines: false
                )
            }
        )

        // Reverse backward atoms to get correct order
        backwardAtoms.reverse()

        // Combine: backward + forward
        let clickIndex = backwardAtoms.count
        let atoms = backwardAtoms + forwardAtoms

        guard !atoms.isEmpty else {
            DLog("No atoms collected")
            return nil
        }

        DLog("Collected \(atoms.count) atoms, click index \(clickIndex)")
        return AtomCollection(atoms: atoms, clickIndex: clickIndex)
    }

    // MARK: - Atom Search

    /// Search boundaries for atoms of the same class.
    private struct AtomSearchBoundaries {
        let startIndex: Int
        let endIndex: Int  // Half-open: one past the last atom
    }

    /// Search forward and backward from the click index to find atoms of the same class.
    private func searchForSameClassBoundaries(
        atoms: [WordSelectionAtom],
        clickIndex: Int,
        theClass: TextClass
    ) -> AtomSearchBoundaries {
        // Search forward for the end of the word
        var endAtomIndex = clickIndex
        while endAtomIndex < atoms.count {
            let atom = atoms[endAtomIndex]
            let atomClass = classForAtomWithString(atom, bigWords: big)
            DLog("Forward search: atom[\(endAtomIndex)] = '\(atom.string)', class=\(atomClass), theClass=\(theClass), wordExtending=\(atom.wordExtending)")
            if atomClass != theClass && atomClass != .doubleWidthPlaceholder {
                DLog("Breaking forward search at \(endAtomIndex)")
                break
            }
            endAtomIndex += 1
            if endAtomIndex - clickIndex > maximumLength {
                DLog("Max length hit searching forward")
                break
            }
        }

        // Search backward for the start of the word
        var startAtomIndex = clickIndex
        while startAtomIndex > 0 {
            let atom = atoms[startAtomIndex - 1]
            let atomClass = classForAtomWithString(atom, bigWords: big)
            DLog("Backward search: atom[\(startAtomIndex - 1)] = '\(atom.string)', class=\(atomClass), theClass=\(theClass), wordExtending=\(atom.wordExtending)")
            if atomClass != theClass && atomClass != .doubleWidthPlaceholder {
                DLog("Breaking backward search at \(startAtomIndex)")
                break
            }
            startAtomIndex -= 1
            if clickIndex - startAtomIndex > maximumLength {
                DLog("Max length hit searching backward")
                break
            }
        }

        DLog("searchForSameClassBoundaries result: atoms \(startAtomIndex) to \(endAtomIndex - 1)")
        return AtomSearchBoundaries(startIndex: startAtomIndex, endIndex: endAtomIndex)
    }

    /// Build a coordinate range from atom boundaries.
    private func buildCoordRangeFromAtoms(
        _ atoms: [WordSelectionAtom],
        startIndex: Int,
        endIndex: Int
    ) -> VT100GridWindowedRange {
        guard let ds = dataSource, startIndex < endIndex else {
            return errorLocation()
        }

        let startCoord = atoms[startIndex].coordRange.start
        var endCoord = atoms[endIndex - 1].coordRange.end

        // Make sure to include the DWC_RIGHT after the last character
        if endCoord.x < ds.xLimit() && ds.haveDoubleWidthExtension(at: endCoord) {
            endCoord.x += 1
        }

        return ds.windowedRange(with: VT100GridCoordRangeMake(
            startCoord.x, startCoord.y,
            endCoord.x, endCoord.y
        ))
    }

    /// Apply ICU segmentation to a range of atoms.
    /// This refines word boundaries using the OS's text boundary analysis,
    /// while respecting word-extending atoms (regex matches and user-defined characters).
    ///
    /// - Parameters:
    ///   - atoms: All atoms in the line
    ///   - startAtomIndex: Initial start of the word (from class-based search)
    ///   - endAtomIndex: Initial end of the word (half-open, from class-based search)
    ///   - clickAtomIndex: The atom that was clicked
    /// - Returns: The refined coordinate range
    private func applyICUSegmentationToAtoms(
        atoms: [WordSelectionAtom],
        startAtomIndex: Int,
        endAtomIndex: Int,
        clickAtomIndex: Int
    ) -> VT100GridWindowedRange {
        guard let ds = dataSource else {
            return errorLocation()
        }

        DLog("Applying ICU segmentation to atoms \(startAtomIndex)..<\(endAtomIndex)")

        // Build the combined string and index mapping from the atom range
        var combinedString = ""
        var atomIndexes: [Int] = []  // For each atom, the string index where it starts

        for i in startAtomIndex..<endAtomIndex {
            atomIndexes.append(combinedString.count)
            combinedString += atoms[i].string
        }

        let attributedString = NSAttributedString(string: combinedString, attributes: [:])

        // Find the click position within the atom range
        let clickOffsetInRange = clickAtomIndex - startAtomIndex
        let clickStringIndex = atomIndexes[clickOffsetInRange]

        DLog("Combined string: '\(combinedString)', click at string index \(clickStringIndex)")

        // Search forward: find end boundary
        var newEndAtomIndex = clickAtomIndex
        var i = clickAtomIndex

        while i < endAtomIndex {
            let atom = atoms[i]
            let offsetInRange = i - startAtomIndex

            if atom.wordExtending {
                // Word-extending atoms always continue the word
                DLog("Atom \(i) '\(atom.string)' is word-extending, continuing")
                newEndAtomIndex = i + 1
                i += 1
            } else {
                // Non-word-extending atom: use ICU to find the word boundary
                let stringIndex = atomIndexes[offsetInRange]
                let icuRange = attributedString.doubleClick(at: stringIndex)
                let icuEnd = icuRange.location + icuRange.length

                DLog("ICU range at \(stringIndex): \(icuRange), looking for atoms up to string index \(icuEnd)")

                // Find the last atom that's within the ICU word boundary
                for j in i..<endAtomIndex {
                    let checkOffset = j - startAtomIndex
                    let atomStart = atomIndexes[checkOffset]
                    if atomStart < icuEnd {
                        newEndAtomIndex = j + 1
                    } else {
                        break
                    }
                }

                // Check if the next atom after ICU boundary is word-extending
                if newEndAtomIndex < endAtomIndex && atoms[newEndAtomIndex].wordExtending {
                    // Continue from the word-extending atom
                    i = newEndAtomIndex
                } else {
                    // We've found the final boundary
                    break
                }
            }
        }

        // Search backward: find start boundary
        var newStartAtomIndex = clickAtomIndex
        i = clickAtomIndex

        while i >= startAtomIndex {
            let atom = atoms[i]
            let offsetInRange = i - startAtomIndex

            if atom.wordExtending {
                // Word-extending atoms always continue the word
                DLog("Atom \(i) '\(atom.string)' is word-extending, continuing backward")
                newStartAtomIndex = i
                i -= 1
            } else {
                // Non-word-extending atom: use ICU to find the word boundary
                let stringIndex = atomIndexes[offsetInRange]
                let icuRange = attributedString.doubleClick(at: stringIndex)
                let icuStart = icuRange.location

                DLog("ICU range at \(stringIndex): \(icuRange), looking for atoms from string index \(icuStart)")

                // Find the first atom that's within the ICU word boundary
                for j in stride(from: i, through: startAtomIndex, by: -1) {
                    let checkOffset = j - startAtomIndex
                    let atomStart = atomIndexes[checkOffset]
                    if atomStart >= icuStart {
                        newStartAtomIndex = j
                    } else {
                        break
                    }
                }

                // Check if the previous atom before ICU boundary is word-extending
                if newStartAtomIndex > startAtomIndex && atoms[newStartAtomIndex - 1].wordExtending {
                    // Continue from the word-extending atom
                    i = newStartAtomIndex - 1
                } else {
                    // We've found the final boundary
                    break
                }
            }
        }

        DLog("After ICU segmentation: atoms \(newStartAtomIndex)..<\(newEndAtomIndex)")

        guard newStartAtomIndex < newEndAtomIndex else {
            return ds.windowedRange(with: VT100GridCoordRangeMake(
                atoms[clickAtomIndex].coordRange.start.x,
                atoms[clickAtomIndex].coordRange.start.y,
                atoms[clickAtomIndex].coordRange.end.x,
                atoms[clickAtomIndex].coordRange.end.y
            ))
        }

        // Build the final coordinate range
        let startCoord = atoms[newStartAtomIndex].coordRange.start
        var endCoord = atoms[newEndAtomIndex - 1].coordRange.end

        // Make sure to include the DWC_RIGHT after the last character
        if endCoord.x < ds.xLimit() && ds.haveDoubleWidthExtension(at: endCoord) {
            endCoord.x += 1
        }

        return ds.windowedRange(with: VT100GridCoordRangeMake(
            startCoord.x, startCoord.y,
            endCoord.x, endCoord.y
        ))
    }

    /// Classify an atom for word selection.
    /// Uses the atom's character data when available for full compatibility with classForCharacter.
    /// Falls back to string-based classification for regex match atoms.
    private func classForAtomWithString(_ atom: WordSelectionAtom, bigWords: Bool) -> TextClass {
        if atom.forcedWordClass {
            return .word
        }

        // If we have character data, use classForCharacter for full compatibility
        if let char = atom.character {
            return classForCharacter(char, bigWords: bigWords)
        }

        // For atoms without character data (regex matches), classify based on string
        let string = atom.string
        if string.isEmpty {
            return .null
        }

        // Check for whitespace
        let whitespaceRange = string.rangeOfCharacter(from: .whitespaces)
        if let range = whitespaceRange, string.distance(from: range.lowerBound, to: range.upperBound) == string.count {
            return .whitespace
        }

        // Check if alphanumeric or user-defined word character
        if characterIsAlphanumeric(string) ||
           characterShouldBeTreatedAsAlphanumeric(string, definitionOfAlphanumeric: bigWords ? .bigWords : .userDefined) {
            return .word
        }

        return .other
    }

    private func fastString(at location: VT100GridCoord) -> String? {
        guard let ds = dataSource else {
            return nil
        }

        let theClass = classForCharacter(ds.character(at: location))
        let xLimit = Int(ds.xLimit())
        let width = Int(ds.wordExtractorWidth())
        let numberOfLines = Int(ds.wordExtractorNumberOfLines())

        if Int(location.y) >= numberOfLines {
            return nil
        }

        var iterations = 0
        let maxLength = 20
        let windowTouchesLeftMargin = logicalWindow.location == 0
        let windowTouchesRightMargin = xLimit == width

        var theRange = VT100GridCoordRangeMake(
            location.x, location.y,
            Int32(width), location.y + 1
        )

        var foundWord = (theClass == .word)
        var word = ""

        if theClass == .word {
            // Search forward for the end of the word if the cursor was over a letter.
            ds.enumerateChars(
                in: VT100GridWindowedRangeMake(theRange, logicalWindow.location, logicalWindow.length),
                supportBidi: false,
                charBlock: { currentLine, theChar, ea, logicalCoord, coord in
                    iterations += 1
                    if iterations == maxLength {
                        return true
                    }
                    let newClass = self.classForCharacter(theChar, definitionOfAlphanumeric: .unixCommands)
                    if newClass == .word {
                        foundWord = true
                        if theChar.complexChar != 0 ||
                            theChar.code < ITERM2_PRIVATE_BEGIN ||
                            theChar.code > ITERM2_PRIVATE_END {
                            let s = ds.string(forCharacter: theChar)
                            word += s
                        }
                        return false
                    } else {
                        return foundWord
                    }
                },
                eolBlock: { code, numPrecedingNulls, line in
                    return ds.shouldStopEnumerating(
                        withCode: code,
                        numNulls: numPrecedingNulls,
                        windowTouchesLeftMargin: windowTouchesLeftMargin,
                        windowTouchesRightMargin: windowTouchesRightMargin,
                        ignoringNewlines: false
                    )
                }
            )
        }

        if iterations == maxLength {
            return nil
        }

        // Search backward for the beginning of the word
        theRange = VT100GridCoordRangeMake(0, 0, location.x, location.y)

        ds.enumerateInReverseChars(
            in: VT100GridWindowedRangeMake(theRange, logicalWindow.location, logicalWindow.length),
            charBlock: { theChar, logicalCoord, coord in
                iterations += 1
                if iterations == maxLength {
                    return true
                }
                let newClass = self.classForCharacter(theChar, definitionOfAlphanumeric: .unixCommands)
                if newClass == .word {
                    foundWord = true
                    if theChar.complexChar != 0 ||
                        theChar.code < ITERM2_PRIVATE_BEGIN ||
                        theChar.code > ITERM2_PRIVATE_END {
                        let s = ds.string(forCharacter: theChar)
                        word.insert(contentsOf: s, at: word.startIndex)
                    }
                    return false
                } else {
                    return foundWord
                }
            },
            eolBlock: { code, numPrecedingNulls, line in
                return ds.shouldStopEnumerating(
                    withCode: code,
                    numNulls: numPrecedingNulls,
                    windowTouchesLeftMargin: windowTouchesLeftMargin,
                    windowTouchesRightMargin: windowTouchesRightMargin,
                    ignoringNewlines: false
                )
            }
        )

        if iterations == maxLength {
            return nil
        }

        if foundWord && !word.isEmpty {
            return word
        } else {
            return nil
        }
    }

    private func classForCharacter(_ theCharacter: screen_char_t) -> TextClass {
        return classForCharacter(theCharacter, bigWords: false)
    }

    private func classForCharacter(_ theCharacter: screen_char_t, bigWords: Bool) -> TextClass {
        return classForCharacter(
            theCharacter,
            definitionOfAlphanumeric: bigWords ? .bigWords : .userDefined
        )
    }

    // MARK: - Character Classification

    private func classForCharacter(
        _ theCharacter: screen_char_t,
        definitionOfAlphanumeric definition: AlphaNumericDefinition
    ) -> TextClass {
        if theCharacter.image != 0 {
            return .other
        }

        if theCharacter.complexChar == 0 && theCharacter.image == 0 {
            if theCharacter.code == TAB_FILLER {
                return .whitespace
            } else if theCharacter.code == DWC_RIGHT || theCharacter.code == DWC_SKIP {
                return .doubleWidthPlaceholder
            }
        }

        if theCharacter.code == 0 {
            return .null
        }

        guard let asString = dataSource?.string(forCharacter: theCharacter) else {
            return .other
        }

        let whitespaceRange = asString.rangeOfCharacter(from: .whitespaces)
        if let range = whitespaceRange, asString.distance(from: range.lowerBound, to: range.upperBound) == asString.count {
            return .whitespace
        }

        if characterIsAlphanumeric(asString) ||
            characterShouldBeTreatedAsAlphanumeric(asString, definitionOfAlphanumeric: definition) {
            return .word
        }

        return .other
    }

    private func characterIsAlphanumeric(_ characterAsString: String) -> Bool {
        let range = characterAsString.rangeOfCharacter(from: .alphanumerics)
        if let range = range {
            return characterAsString.distance(from: range.lowerBound, to: range.upperBound) == characterAsString.count
        }
        return false
    }

    private func characterShouldBeTreatedAsAlphanumeric(
        _ characterAsString: String?,
        definitionOfAlphanumeric definition: AlphaNumericDefinition
    ) -> Bool {
        guard let characterAsString = characterAsString else {
            return false
        }

        switch definition {
        case .userDefined:
            let additionalChars = additionalWordCharacters ?? internalAdditionalWordCharacters ?? ""
            return additionalChars.contains(characterAsString)

        case .unixCommands:
            return "_-".contains(characterAsString)

        case .narrow:
            return characterAsString == "-"

        case .bigWords:
            return characterAsString.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }
    }
}
