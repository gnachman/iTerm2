//
//  WordSelectionAtom.swift
//  iTerm2
//
//  Created by George Nachman on 3/2/26.
//

import Foundation

/// Represents a unit of iteration in word selection.
/// Can be a single character or a multi-character chunk (e.g., regex match).
struct WordSelectionAtom {
    /// Grid coordinates spanned by this atom (for multi-char atoms, this is the full range)
    let coordRange: VT100GridCoordRange

    /// String content of this atom
    let string: String

    /// If true, this atom is classified as word regardless of character content
    /// (used for regex matches)
    let forcedWordClass: Bool

    /// The screen character (for single-character atoms)
    let character: screen_char_t?

    /// Length in UTF-16 code units (for position tracking in NSString)
    /// This is used to correctly track positions when iterating through atoms.
    let utf16Length: Int

    /// If true, this atom extends words across ICU boundaries.
    /// - Regex matches are always word-extending (they bridge word boundaries)
    /// - Characters in additionalWordCharacters preference are word-extending
    /// - Regular characters are not word-extending (ICU decides boundaries)
    let wordExtending: Bool

    /// Create an atom for a single character
    /// - Parameters:
    ///   - char: The screen character
    ///   - string: String representation of the character
    ///   - coord: Grid coordinate of the character
    ///   - wordExtending: If true, this character extends words across ICU boundaries
    static func singleCharacter(
        _ char: screen_char_t,
        string: String,
        coord: VT100GridCoord,
        wordExtending: Bool = false
    ) -> WordSelectionAtom {
        let coordRange = VT100GridCoordRangeMake(
            coord.x, coord.y,
            coord.x + 1, coord.y
        )
        return WordSelectionAtom(
            coordRange: coordRange,
            string: string,
            forcedWordClass: false,
            character: char,
            utf16Length: (string as NSString).length,
            wordExtending: wordExtending
        )
    }

    /// Create an atom for a regex match
    /// Regex matches are always word-extending (they bridge ICU word boundaries)
    static func regexMatch(
        string: String,
        coordRange: VT100GridCoordRange
    ) -> WordSelectionAtom {
        return WordSelectionAtom(
            coordRange: coordRange,
            string: string,
            forcedWordClass: true,
            character: nil,
            utf16Length: (string as NSString).length,
            wordExtending: true  // Regex matches always bridge ICU boundaries
        )
    }
}
