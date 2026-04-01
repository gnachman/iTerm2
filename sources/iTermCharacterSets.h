//
//  iTermCharacterSets.h
//  iTerm2
//
//  Fast character set membership tests using bitmaps and binary search.
//  Replaces NSCharacterSet lookups in StringToScreenChars hot path.
//

#ifndef iTermCharacterSets_h
#define iTermCharacterSets_h

#import <Foundation/Foundation.h>

// Check if a code point is a default ignorable character.
// The zeroWidthSpaceAdvancesCursor parameter controls whether U+200B is ignorable.
BOOL iTermIsIgnorableCharacter(uint32_t cp, BOOL zeroWidthSpaceAdvancesCursor);

// Check if a code point is a spacing combining mark (gc=Mc).
BOOL iTermIsSpacingCombiningMark(uint32_t cp);

// Check if a code point is an emoji that accepts VS16 (U+FE0F).
BOOL iTermIsEmojiAcceptingVS16(uint32_t cp);

// Check if a code point is a modifier forcing full-width rendition
// (VS16 or skin tone modifier).
NS_INLINE BOOL iTermIsModifierForcingFullWidth(uint32_t cp) {
    return cp == 0xFE0F || (cp >= 0x1F3FB && cp <= 0x1F3FF);
}

// Check if a code point is an RTL-indicating code point.
BOOL iTermIsRTLCodePoint(uint32_t cp);

// Scan a CFString for any RTL code point. Returns YES if found.
BOOL iTermStringContainsRTL(CFStringRef s);

// Scan a CFString for any modifier forcing full-width rendition.
// Returns YES if it contains VS16 (U+FE0F) or skin tone modifiers.
BOOL iTermStringContainsModifierForcingFullWidth(CFStringRef s);

// Scan a CFString for any spacing combining mark (gc=Mc). Returns YES if found.
BOOL iTermStringContainsSpacingCombiningMark(CFStringRef s);

// Check if a code point should have its own cell.
// This is the union of Grapheme_Base - Default_Ignorable, spacing combining marks, and modifier letters.
BOOL iTermIsCodePointWithOwnCell(uint32_t cp);

// Find the first code point with its own cell in a UTF-16 buffer.
// When aggressive is YES, checks against the full codePointsWithOwnCell set
// (Grapheme_Base - Default_Ignorable + spacing combining marks + modifier letters).
// When aggressive is NO, only checks for 0xFF9E and 0xFF9F.
// Returns the UTF-16 index of the first match, or kCFNotFound.
CFIndex iTermFindFirstCodePointWithOwnCell(const UniChar *chars,
                                           CFIndex start,
                                           CFIndex length,
                                           BOOL aggressive);

#endif /* iTermCharacterSets_h */
