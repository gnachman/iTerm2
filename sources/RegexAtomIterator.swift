//
//  RegexAtomIterator.swift
//  iTerm2
//
//  Created by George Nachman on 3/4/26.
//

import Foundation

/// Protocol for providing coordinate navigation to RegexAtomIterator.
protocol RegexAtomIteratorDataSource: AnyObject {
    /// Returns the coordinate immediately after the given coordinate.
    /// Handles double-width characters, tab fillers, line wrapping, etc.
    func successorOfCoord(_ coord: VT100GridCoord) -> VT100GridCoord
}

/// Iterator that builds atoms from a located string using regex patterns.
///
/// Key design decisions:
/// 1. Takes `iTermLocatedString` directly, which has 1:1 mapping between UTF-16 code units and coords
/// 2. Uses the dataSource to check for double-width characters
/// 3. On regex match overflow, falls back to single-char atoms (doesn't break)
///
/// This is separate from CharacterAtomIterator because:
/// - CharacterAtomIterator iterates cell-by-cell through the grid
/// - RegexAtomIterator pre-computes atoms from extracted text
class RegexAtomIterator {
    /// Data source for double-width character detection
    weak var dataSource: RegexAtomIteratorDataSource?

    /// Regex patterns for word selection. Matches are treated as word characters.
    var regexPatterns: [String] = []

    /// Pre-computed atoms
    private(set) var atoms: [WordSelectionAtom]?

    /// Index of the atom containing the click location
    private(set) var clickAtomIndex: Int = 0

    /// Cached compiled regexes
    private var compiledRegexes: [NSRegularExpression]?

    init(dataSource: RegexAtomIteratorDataSource) {
        self.dataSource = dataSource
    }

    /// Check if pre-atomization has been performed
    var hasPrecomputedAtoms: Bool {
        return atoms != nil
    }

    /// Pre-atomize text for regex mode.
    ///
    /// - Parameters:
    ///   - locatedString: The located string containing text and 1:1 UTF-16 coords
    ///   - targetIndex: The UTF-16 index in text where the user clicked
    func preatomize(locatedString: iTermLocatedString, targetIndex: Int) {
        let text = locatedString.string
        let gridCoords = locatedString.gridCoords

        guard !text.isEmpty, gridCoords.count > 0 else {
            atoms = nil
            clickAtomIndex = 0
            return
        }

        atoms = buildAtoms(text: text, gridCoords: gridCoords)
        clickAtomIndex = findAtomContaining(targetIndex)
    }

    // MARK: - Atom Building

    /// Build atoms from text using regex patterns.
    ///
    /// This method handles the 1:1 relationship between UTF-16 code units and coords
    /// from `iTermLocatedString`. Each coord corresponds to one UTF-16 code unit.
    ///
    /// For double-width characters:
    /// - The character takes 1 UTF-16 code unit
    /// - It has 1 coord pointing to cell X
    /// - The coordRange should span cells X to X+2 (half-open)
    ///
    /// - Parameters:
    ///   - text: The text to atomize
    ///   - gridCoords: Grid coordinates, 1:1 with UTF-16 code units
    private func buildAtoms(text: String, gridCoords: GridCoordArray) -> [WordSelectionAtom] {
        guard !text.isEmpty, gridCoords.count > 0 else {
            return []
        }

        let context = AtomBuildingContext(text: text, gridCoords: gridCoords, regexes: getCompiledRegexes())
        var atoms = [WordSelectionAtom]()
        var textPosition = 0

        while textPosition < context.textLength && textPosition < context.coordCount {
            let (atom, nextPosition) = buildNextAtom(at: textPosition, context: context)
            atoms.append(atom)
            textPosition = nextPosition
        }

        return atoms
    }

    /// Context object holding immutable state for atom building
    private struct AtomBuildingContext {
        let text: String
        let nsString: NSString
        let textLength: Int
        let gridCoords: GridCoordArray
        let coordCount: Int
        let regexes: [NSRegularExpression]

        init(text: String, gridCoords: GridCoordArray, regexes: [NSRegularExpression]) {
            self.text = text
            self.nsString = text as NSString
            self.textLength = self.nsString.length
            self.gridCoords = gridCoords
            self.coordCount = gridCoords.count
            self.regexes = regexes
        }
    }

    /// Get compiled regexes, compiling them if needed
    private func getCompiledRegexes() -> [NSRegularExpression] {
        if compiledRegexes == nil {
            compiledRegexes = compileRegexes()
        }
        return compiledRegexes ?? []
    }

    /// Build the next atom starting at the given position.
    /// - Returns: A tuple of (atom, nextPosition)
    private func buildNextAtom(at textPosition: Int, context: AtomBuildingContext) -> (WordSelectionAtom, Int) {
        // Try to create a regex match atom first
        if let (atom, nextPosition) = tryBuildRegexMatchAtom(at: textPosition, context: context) {
            return (atom, nextPosition)
        }

        // Fall back to single-character atom
        return buildSingleCharAtom(at: textPosition, context: context)
    }

    /// Try to build a regex match atom at the given position.
    /// - Returns: (atom, nextPosition) if successful, nil if no valid match
    private func tryBuildRegexMatchAtom(at textPosition: Int, context: AtomBuildingContext) -> (WordSelectionAtom, Int)? {
        guard let match = findLongestRegexMatch(at: textPosition, context: context) else {
            return nil
        }

        let matchEndPosition = textPosition + match.range.length

        // Check if we have enough coords for this match
        guard matchEndPosition <= context.coordCount else {
            // Match extends beyond coords - caller should fall back to single-char
            return nil
        }

        let atom = createRegexMatchAtom(
            matchString: match.string,
            startPosition: textPosition,
            endPosition: matchEndPosition,
            gridCoords: context.gridCoords
        )
        return (atom, matchEndPosition)
    }

    /// Find the longest regex match anchored at the given position.
    private func findLongestRegexMatch(at textPosition: Int, context: AtomBuildingContext) -> (range: NSRange, string: String)? {
        var longestMatch: (range: NSRange, string: String)?
        let searchRange = NSRange(location: textPosition, length: context.textLength - textPosition)

        for regex in context.regexes {
            guard let match = regex.firstMatch(in: context.text, options: .anchored, range: searchRange) else {
                continue
            }
            let matchRange = match.range
            guard matchRange.length > 0 else {
                continue
            }
            if longestMatch == nil || matchRange.length > longestMatch!.range.length {
                longestMatch = (matchRange, context.nsString.substring(with: matchRange))
            }
        }

        return longestMatch
    }

    /// Create an atom for a regex match.
    private func createRegexMatchAtom(
        matchString: String,
        startPosition: Int,
        endPosition: Int,
        gridCoords: GridCoordArray
    ) -> WordSelectionAtom {
        let startCoord = gridCoords.coord(at: startPosition)
        let endCoord = gridCoords.coord(at: endPosition - 1)
        let afterEnd = successorCoord(of: endCoord)

        let coordRange = VT100GridCoordRangeMake(
            startCoord.x, startCoord.y,
            afterEnd.x, afterEnd.y
        )

        return WordSelectionAtom.regexMatch(string: matchString, coordRange: coordRange)
    }

    /// Build a single-character atom at the given position.
    /// Fallback atoms are not word-extending - only regex matches bridge ICU boundaries.
    private func buildSingleCharAtom(at textPosition: Int, context: AtomBuildingContext) -> (WordSelectionAtom, Int) {
        let coord = context.gridCoords.coord(at: textPosition)
        let charRange = context.nsString.rangeOfComposedCharacterSequence(at: textPosition)
        let charString = context.nsString.substring(with: charRange)
        let afterEnd = successorCoord(of: coord)

        let coordRange = VT100GridCoordRangeMake(
            coord.x, coord.y,
            afterEnd.x, afterEnd.y
        )

        let atom = WordSelectionAtom(
            coordRange: coordRange,
            string: charString,
            forcedWordClass: false,
            character: nil,
            utf16Length: charRange.length,
            wordExtending: false  // Fallback atoms are not word-extending
        )

        let nextPosition = textPosition + charRange.length
        return (atom, nextPosition)
    }

    /// Calculate the end coordinate after a character.
    /// Handles double-width characters, tab fillers, line wrapping, etc.
    private func successorCoord(of coord: VT100GridCoord) -> VT100GridCoord {
        guard let ds = dataSource else {
            // Fallback: just increment x
            return VT100GridCoord(x: coord.x + 1, y: coord.y)
        }
        return ds.successorOfCoord(coord)
    }

    /// Compile regex patterns, filtering out invalid ones
    private func compileRegexes() -> [NSRegularExpression] {
        var regexes = [NSRegularExpression]()
        for pattern in regexPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                regexes.append(regex)
            } catch {
                // Invalid regex pattern - skip it
                DLog("Invalid regex pattern '\(pattern)': \(error)")
            }
        }
        return regexes
    }

    /// Find which atom contains the target UTF-16 code unit index.
    /// - Parameter targetIndex: UTF-16 code unit index into the text
    private func findAtomContaining(_ targetIndex: Int) -> Int {
        guard let atoms = atoms else {
            return 0
        }

        var utf16Position = 0
        for (atomIndex, atom) in atoms.enumerated() {
            let atomUtf16Length = atom.utf16Length
            if targetIndex >= utf16Position && targetIndex < utf16Position + atomUtf16Length {
                return atomIndex
            }
            utf16Position += atomUtf16Length
        }

        // If not found, return the last atom index
        return max(0, atoms.count - 1)
    }
}
