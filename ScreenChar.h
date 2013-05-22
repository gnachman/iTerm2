// -*- mode:objc -*-
/*
 **  ScreenChar.h
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Code related to screen_char_t. Most of this has to do with
 **    storing multiple code points together in one cell by using a "color
 **    palette" approach where the code point can be used as an index into a
 **    string table, and the strings can have surrogate pairs and combining
 **    marks.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Cocoa/Cocoa.h>
#import "NSStringITerm.h"

// This is used in the rightmost column when a double-width character would
// have been split in half and was wrapped to the next line. It is nonprintable
// and not selectable. It is not copied into the clipboard. A line ending in this
// character should always have EOL_DWC. These are stripped when adding a line
// to the scrollback buffer.
#define DWC_SKIP 0xf000

// When a tab is received, we insert some number of TAB_FILLER characters
// preceded by a \t character. This allows us to reconstruct the tab for
// copy-pasting.
#define TAB_FILLER 0xf001

// If DWC_SKIP appears in the input, we convert it to this to avoid causing confusion.
// NOTE: I think this isn't used because DWC_SKIP is caught early and converted to a '?'.
#define BOGUS_CHAR 0xf002

// Double-width characters have their "real" code in one cell and this code in
// the right-hand cell.
#define DWC_RIGHT 0xf003

// These codes go in the continuation character to the right of the
// rightmost column.
#define EOL_HARD 0 // Hard line break (explicit newline)
#define EOL_SOFT 1 // Soft line break (a long line was wrapped)
#define EOL_DWC  2 // Double-width character wrapped to next line

// The range of private codes we use, with specific instances defined
// above here.
#define ITERM2_PRIVATE_BEGIN 0xf000
#define ITERM2_PRIVATE_END 0xf003

#define ONECHAR_UNKNOWN ('?')   // Relacement character for encodings other than utf-8.

// Alternate semantics definitions
// Default background color
#define ALTSEM_BG_DEFAULT 0
// Default foreground color
#define ALTSEM_FG_DEFAULT 1
// Selected color
#define ALTSEM_SELECTED 2
// Cursor color
#define ALTSEM_CURSOR 3

// Max unichars in a glyph.
static const int kMaxParts = 20;

typedef struct screen_char_t
{
    // Normally, 'code' gives a utf-16 code point. If 'complexChar' is set then
    // it is a key into a string table of multiple utf-16 code points (for
    // example, a surrogate pair or base char+combining mark). These must render
    // to a single glyph. 'code' can take some special values which are valid
    // regardless of the setting of 'complexChar':
    //   0: Signifies no character was ever set at this location. Not selectable.
    //   DWC_SKIP, TAB_FILLER, BOGUS_CHAR, or DWC_RIGHT: See comments above.
    // In the WIDTH+1 position on a line, this takes the value of EOL_HARD,
    //  EOL_SOFT, or EOL_DWC. See the comments for those constants.
    unichar code;

    // With normal background semantics:
    //   The lower 9 bits have the same semantics for foreground and background
    //   color:
    //     Low three bits give color. 0-7 are black, red, green, yellow, blue,
    //       purple, cyan, and white.
    //     Values between 8 and 15 are bright versions of 0-7.
    //     Values between 16 and 255 are used for 256 color mode:
    //       16-232: rgb value given by 16 + r*36 + g*6 + b, with each color in
    //         the range [0,5].
    //       233-255: Grayscale values from dimmest gray 233 (which is not black)
    //         to brightest 255 (not white).
    // With alternate background semantics:
    //   ALTSEM_xxx (see comments above)
    unsigned int backgroundColor : 8;
    unsigned int foregroundColor : 8;

    // This flag determines the interpretation of backgroundColor.
    unsigned int alternateBackgroundSemantics : 1;

    // If set, the 'code' field does not give a utf-16 value but is intead a
    // key into a string table of more complex chars (combined, surrogate pairs,
    // etc.). Valid 'code' values for a complex char are in [1, 0xefff] and will
    // be recycled as needed.
    unsigned int complexChar : 1;

    // Foreground color has the same definition as background color.
    unsigned int alternateForegroundSemantics : 1;

    // Various bits affecting text appearance. The bold flag here is semantic
    // and may be rendered as some combination of font choice and color
    // intensity.
    unsigned int bold : 1;
    unsigned int italic : 1;
    unsigned int blink : 1;
    unsigned int underline : 1;

    // These bits aren't used but are defined here so that the entire memory
    // region can be initialized.
    unsigned int unused : 25;
} screen_char_t;

// Standard unicode replacement string. Is a double-width character.
static inline NSString* ReplacementString()
{
    const unichar kReplacementCharacter = UNICODE_REPLACEMENT_CHAR;
    return [NSString stringWithCharacters:&kReplacementCharacter length:1];
}

// Copy foreground color from one char to another.
static inline void CopyForegroundColor(screen_char_t* to, const screen_char_t from)
{
    to->foregroundColor = from.foregroundColor;
    to->alternateForegroundSemantics = from.alternateForegroundSemantics;
    to->bold = from.bold;
    to->italic = from.italic;
    to->blink = from.blink;
    to->underline = from.underline;
}

// COpy background color from one char to another.
static inline void CopyBackgroundColor(screen_char_t* to, const screen_char_t from)
{
    to->backgroundColor = from.backgroundColor;
    to->alternateBackgroundSemantics = from.alternateBackgroundSemantics;
}

// Returns true iff two background colors are equal.
static inline BOOL BackgroundColorsEqual(const screen_char_t a,
                                         const screen_char_t b)
{
    return a.backgroundColor == b.backgroundColor &&
    a.alternateBackgroundSemantics == b.alternateBackgroundSemantics;
}

// Returns true iff two foreground colors are equal.
static inline BOOL ForegroundColorsEqual(const screen_char_t a,
                                         const screen_char_t b)
{
    return a.foregroundColor == b.foregroundColor &&
           a.alternateForegroundSemantics == b.alternateForegroundSemantics &&
           a.bold == b.bold &&
           a.italic == b.italic &&
           a.blink == b.blink &&
           a.underline == b.underline;
}

// Look up the string associated with a complex char's key.
NSString* ComplexCharToStr(int key);

// Return a string with the contents of a screen char, which may or may not
// be complex.
NSString* ScreenCharToStr(screen_char_t* sct);
NSString* CharToStr(unichar code, BOOL isComplex);

// This is a faster version of ScreenCharToStr if what you want is an array of
// unichars. Returns the number of code points appended to dest.
int ExpandScreenChar(screen_char_t* sct, unichar* dest);

// Convert a code into a utf-32 char.
UTF32Char CharToLongChar(unichar code, BOOL isComplex);

// Add a code point to the end of an existing complex char. A replacement key is
// returned.
int AppendToComplexChar(int key, unichar codePoint);

// Create a new complex char from two code points. A key is returned.
int BeginComplexChar(unichar initialCodePoint, unichar combiningChar);

// Create or lookup & return the code for a complex char.
int GetOrSetComplexChar(NSString* str);

// Returns true if the given character is a combining mark, per chapter 3 of
// the Unicode 6.0 spec, D52.
BOOL IsCombiningMark(UTF32Char c);

// Translate a surrogate pair into a single utf-32 char.
UTF32Char DecodeSurrogatePair(unichar high, unichar low);

// Test for low surrogacy.
BOOL IsLowSurrogate(unichar c);

// Test for high surrogacy.
BOOL IsHighSurrogate(unichar c);

// Convert an array of screen_char_t into a string.
// After this call free(*backingStorePtr), free(*deltasPtr)
// *deltasPtr will be filled in with values that let you convert indices in
// the result string to indices in the original array.
// In other words:
// part or all of [result characterAtIndex:i] refers to all or part of screenChars[i - (*deltasPtr)[i]].

NSString* ScreenCharArrayToString(screen_char_t* screenChars,
                                  int start,
                                  int end,
                                  unichar** backingStorePtr,
                                  int** deltasPtr);

// Number of chars before a sequence of nuls at the end of the line.
int EffectiveLineLength(screen_char_t* theLine, int totalLength);

NSString* ScreenCharArrayToStringDebug(screen_char_t* screenChars,
                                       int lineLength);

// Convert an array of chars to a string, quickly.
NSString* CharArrayToString(unichar* charHaystack, int o);

void DumpScreenCharArray(screen_char_t* screenChars, int lineLength);
