//
//  CharacterAtomIterator.swift
//  iTerm2
//
//  Created by George Nachman on 3/2/26.
//

import Foundation

/// Protocol for providing atoms to the iterator.
/// This mirrors iTermWordExtractorDataSource but is protocol-based for flexibility.
protocol CharacterAtomSource: AnyObject {
    func characterAt(_ coord: VT100GridCoord) -> screen_char_t
    func stringForCharacter(_ char: screen_char_t) -> String
    func logicalWindow() -> VT100GridRange

    /// Check if a character string is in the user's additionalWordCharacters preference.
    /// Characters in this set extend words across ICU boundaries.
    func isWordExtendingCharacter(_ string: String) -> Bool

    /// Enumerate characters in forward direction
    func enumerateCharsInRange(
        _ range: VT100GridWindowedRange,
        supportBidi: Bool,
        charBlock: ((UnsafePointer<screen_char_t>?, screen_char_t, iTermExternalAttribute?, VT100GridCoord, VT100GridCoord) -> Bool)?,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    )

    /// Enumerate characters in reverse direction
    func enumerateInReverseCharsInRange(
        _ range: VT100GridWindowedRange,
        charBlock: ((screen_char_t, VT100GridCoord, VT100GridCoord) -> Bool)?,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    )
}

/// Iterator that yields single-character atoms from the grid.
/// This is used for non-regex word selection where we iterate character-by-character.
///
/// For regex-based word selection, use RegexAtomIterator instead.
class CharacterAtomIterator {
    weak var dataSource: CharacterAtomSource?

    private let logicalWindow: VT100GridRange

    init(dataSource: CharacterAtomSource) {
        self.dataSource = dataSource
        self.logicalWindow = dataSource.logicalWindow()
    }

    /// Create an atom from a character at a specific coordinate.
    /// Returns nil if the character string cannot be obtained.
    /// - Parameters:
    ///   - char: The screen character
    ///   - coord: Grid coordinate of the character
    ///   - wordExtending: If true, this character extends words across ICU boundaries.
    ///                    Pass nil to auto-detect based on additionalWordCharacters.
    func createAtom(from char: screen_char_t, at coord: VT100GridCoord, wordExtending: Bool? = nil) -> WordSelectionAtom? {
        guard let ds = dataSource else { return nil }
        let string = ds.stringForCharacter(char)
        let isWordExtending = wordExtending ?? ds.isWordExtendingCharacter(string)
        return WordSelectionAtom.singleCharacter(char, string: string, coord: coord, wordExtending: isWordExtending)
    }

    // MARK: - Enumeration Methods

    /// Enumerate atoms in the forward direction.
    /// - Parameters:
    ///   - range: The windowed range to search within
    ///   - supportBidi: Whether to support bidirectional text
    ///   - atomBlock: Called for each atom; return true to stop iteration.
    ///                Parameters: (currentLine, atom, externalAttribute, logicalCoord, visualCoord)
    ///   - eolBlock: Called at end of each line; return true to stop iteration
    func enumerateAtomsForward(
        inRange range: VT100GridWindowedRange,
        supportBidi: Bool,
        atomBlock: @escaping (UnsafePointer<screen_char_t>?, WordSelectionAtom, iTermExternalAttribute?, VT100GridCoord, VT100GridCoord) -> Bool,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    ) {
        guard let ds = dataSource else { return }

        ds.enumerateCharsInRange(
            range,
            supportBidi: supportBidi,
            charBlock: { currentLine, theChar, ea, logicalCoord, visualCoord -> Bool in
                let string = ds.stringForCharacter(theChar)
                let wordExtending = ds.isWordExtendingCharacter(string)
                let atom = WordSelectionAtom.singleCharacter(theChar, string: string, coord: visualCoord, wordExtending: wordExtending)
                return atomBlock(currentLine, atom, ea, logicalCoord, visualCoord)
            },
            eolBlock: eolBlock
        )
    }

    /// Enumerate atoms in the reverse direction.
    /// - Parameters:
    ///   - range: The windowed range to search within
    ///   - atomBlock: Called for each atom; return true to stop iteration.
    ///                Parameters: (atom, logicalCoord, visualCoord)
    ///   - eolBlock: Called at end of each line; return true to stop iteration
    func enumerateAtomsReverse(
        inRange range: VT100GridWindowedRange,
        atomBlock: @escaping (WordSelectionAtom, VT100GridCoord, VT100GridCoord) -> Bool,
        eolBlock: ((unichar, Int32, Int32) -> Bool)?
    ) {
        guard let ds = dataSource else { return }

        ds.enumerateInReverseCharsInRange(
            range,
            charBlock: { theChar, logicalCoord, visualCoord -> Bool in
                let string = ds.stringForCharacter(theChar)
                let wordExtending = ds.isWordExtendingCharacter(string)
                let atom = WordSelectionAtom.singleCharacter(theChar, string: string, coord: visualCoord, wordExtending: wordExtending)
                return atomBlock(atom, logicalCoord, visualCoord)
            },
            eolBlock: eolBlock
        )
    }
}
