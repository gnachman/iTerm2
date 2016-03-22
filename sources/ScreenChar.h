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
#import "VT100GridTypes.h"

@class iTermImageInfo;

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

// The range of private codes we use, with specific instances defined
// above here.
#define ITERM2_PRIVATE_BEGIN 0xf000
#define ITERM2_PRIVATE_END 0xf003

// These codes go in the continuation character to the right of the
// rightmost column.
#define EOL_HARD 0 // Hard line break (explicit newline)
#define EOL_SOFT 1 // Soft line break (a long line was wrapped)
#define EOL_DWC  2 // Double-width character wrapped to next line

#define ONECHAR_UNKNOWN ('?')   // Relacement character for encodings other than utf-8.

// Alternate semantics definitions
// Default foreground/background color
#define ALTSEM_DEFAULT 0
// Selected color
#define ALTSEM_SELECTED 1
// Cursor color
#define ALTSEM_CURSOR 2
// Use default foreground/background, but use default background for foreground and default
// foreground for background (reverse video).
#define ALTSEM_REVERSED_DEFAULT 3

typedef NS_ENUM(NSUInteger, kiTermScreenCharAnsiColor) {
    kiTermScreenCharAnsiColorBlack,
    kiTermScreenCharAnsiColorRed,
    kiTermScreenCharAnsiColorGreen,
    kiTermScreenCharAnsiColorYellow,
    kiTermScreenCharAnsiColorBlue,
    kiTermScreenCharAnsiColorMagenta,
    kiTermScreenCharAnsiColorCyan,
    kiTermScreenCharAnsiColorWhite,
    kiTermScreenCharAnsiColorBrightBlack,
    kiTermScreenCharAnsiColorBrightRed,
    kiTermScreenCharAnsiColorBrightGreen,
    kiTermScreenCharAnsiColorBrightYellow,
    kiTermScreenCharAnsiColorBrightBlue,
    kiTermScreenCharAnsiColorBrightMagenta,
    kiTermScreenCharAnsiColorBrightCyan,
    kiTermScreenCharAnsiColorBrightWhite
};



// Max unichars in a glyph.
static const int kMaxParts = 20;

typedef enum {
    ColorModeAlternate = 0,  // ALTSEM_XXX values
    ColorModeNormal = 1,  // kiTermScreenCharAnsiColor values
    ColorMode24bit = 2,
    ColorModeInvalid = 3
} ColorMode;


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
    //       magenta, cyan, and white.
    //     Values between 8 and 15 are bright versions of 0-7.
    //     Values between 16 and 255 are used for 256 color mode:
    //       16-232: rgb value given by 16 + r*36 + g*6 + b, with each color in
    //         the range [0,5].
    //       233-255: Grayscale values from dimmest gray 233 (which is not black)
    //         to brightest 255 (not white).
    // With alternate background semantics:
    //   ALTSEM_xxx (see comments above)
    // With 24-bit semantics:
    //   foreground/backgroundColor gives red component and fg/bgGreen, fg/bgBlue
    //     give the rest of the color's components
    // For images, foregroundColor doubles as the x index.
    unsigned int foregroundColor : 8;
    unsigned int fgGreen : 8;
    unsigned int fgBlue  : 8;

    // For images, backgroundColor doubles as the y index.
    unsigned int backgroundColor : 8;
    unsigned int bgGreen : 8;
    unsigned int bgBlue  : 8;

    // These determine the interpretation of foreground/backgroundColor.
    unsigned int foregroundColorMode : 2;
    unsigned int backgroundColorMode : 2;

    // If set, the 'code' field does not give a utf-16 value but is intead a
    // key into a string table of more complex chars (combined, surrogate pairs,
    // etc.). Valid 'code' values for a complex char are in [1, 0xefff] and will
    // be recycled as needed.
    unsigned int complexChar : 1;

    // Various bits affecting text appearance. The bold flag here is semantic
    // and may be rendered as some combination of font choice and color
    // intensity.
    unsigned int bold : 1;
    unsigned int faint : 1;
    unsigned int italic : 1;
    unsigned int blink : 1;
    unsigned int underline : 1;

    // Is this actually an image? Changes the semantics of code,
    // foregroundColor, and backgroundColor (see notes above).
    unsigned int image : 1;

    // These bits aren't used but are defined here so that the entire memory
    // region can be initialized.
    unsigned int unused : 6;
} screen_char_t;

// Typically used to store a single screen line.
@interface ScreenCharArray : NSObject {
    screen_char_t *_line;  // Array of chars
    int _length;  // Number of chars in _line
    int _eol;  // EOL_SOFT, EOL_HARD, or EOL_DWC
}

@property (nonatomic, assign) screen_char_t *line;  // Assume const unless instructed otherwise
@property (nonatomic, assign) int length;
@property (nonatomic, assign) int eol;
@end

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
    to->fgGreen = from.fgGreen;
    to->fgBlue = from.fgBlue;
    to->foregroundColorMode = from.foregroundColorMode;
    to->bold = from.bold;
    to->faint = from.faint;
    to->italic = from.italic;
    to->blink = from.blink;
    to->underline = from.underline;
    to->image = from.image;
}

// Copy background color from one char to another.
static inline void CopyBackgroundColor(screen_char_t* to, const screen_char_t from)
{
    to->backgroundColor = from.backgroundColor;
    to->bgGreen = from.bgGreen;
    to->bgBlue = from.bgBlue;
    to->backgroundColorMode = from.backgroundColorMode;
}

// Returns true iff two background colors are equal.
static inline BOOL BackgroundColorsEqual(const screen_char_t a,
                                         const screen_char_t b)
{
    if (a.backgroundColorMode == b.backgroundColorMode) {
        if (a.backgroundColorMode != ColorMode24bit) {
            // for normal and alternate ColorMode
            return a.backgroundColor == b.backgroundColor;
        } else {
            // RGB must all be equal for 24bit color
            return a.backgroundColor == b.backgroundColor &&
                a.bgGreen == b.bgGreen &&
                a.bgBlue == b.bgBlue;
        }
    } else {
        // different ColorMode == different colors
        return NO;
    }
}

// Returns true iff two foreground colors are equal.
static inline BOOL ForegroundAttributesEqual(const screen_char_t a,
                                             const screen_char_t b)
{
    if (a.bold != b.bold ||
        a.faint != b.faint ||
        a.italic != b.italic ||
        a.blink != b.blink ||
        a.underline != b.underline) {
        return NO;
    }
    if (a.foregroundColorMode == b.foregroundColorMode) {
        if (a.foregroundColorMode != ColorMode24bit) {
            // for normal and alternate ColorMode
            return a.foregroundColor == b.foregroundColor;
        } else {
            // RGB must all be equal for 24bit color
            return a.foregroundColor == b.foregroundColor &&
                a.fgGreen == b.fgGreen &&
                a.fgBlue == b.fgBlue;
        }
    } else {
        // different ColorMode == different colors
        return NO;
    }
}

static inline BOOL ScreenCharHasDefaultAttributesAndColors(const screen_char_t s) {
    return (s.backgroundColor == ALTSEM_DEFAULT &&
            s.foregroundColor == ALTSEM_DEFAULT &&
            s.backgroundColorMode == ColorModeAlternate &&
            s.foregroundColorMode == ColorModeAlternate &&
            !s.complexChar &&
            !s.bold &&
            !s.faint &&
            !s.italic &&
            !s.blink &&
            !s.underline);
}

// Represents an array of screen_char_t's as a string and facilitates mapping a
// range in the string into a range in the screen chars. Useful for highlight
// regex matches, for example. Generally a nicer interface than calling
// ScreenCharArrayToString directly.
@interface iTermStringLine : NSObject
@property(nonatomic, readonly) NSString *stringValue;

// This is not how you'd normally construct a string line, since it's supposed to come from screen
// characters. It's useful if you need a string line that doesn't represent actual characters on
// the screen, though.
+ (instancetype)stringLineWithString:(NSString *)string;

- (instancetype)initWithScreenChars:(screen_char_t *)screenChars
                             length:(NSInteger)length;

- (NSRange)rangeOfScreenCharsForRangeInString:(NSRange)rangeInString;

@end

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

// Takes a non-complex character and adds a combining mark to it. It may or may not
// become complex as a result, depending on whether there is an NFC form for the
// new composite.
void BeginComplexChar(screen_char_t *screenChar, unichar combiningChar, BOOL useHFSPlusMapping);

// Place a complex char in a screen char.
void SetComplexCharInScreenChar(screen_char_t *screenChar, NSString *theString, BOOL useHFSPlusMapping);

// Create or lookup & return the code for a complex char.
int GetOrSetComplexChar(NSString* str);

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

// Convert a string into screen_char_t. This deals with padding out double-
// width characters, joining combining marks, and skipping zero-width spaces.
//
// The buffer size must be at least twice the length of the string (worst case:
//   every character is double-width).
// Pass prototype foreground and background colors in fg and bg.
// *len is filled in with the number of elements of *buf that were set.
// encoding is currently ignored and it's assumed to be UTF-16.
// A good choice for ambiguousIsDoubleWidth is [SESSION treatAmbiguousWidthAsDoubleWidth].
// If not null, *cursorIndex gives an index into s and is changed into the
//   corresponding index into buf.
void StringToScreenChars(NSString *s,
                         screen_char_t *buf,
                         screen_char_t fg,
                         screen_char_t bg,
                         int *len,
                         BOOL ambiguousIsDoubleWidth,
                         int *cursorIndex,
                         BOOL *foundDwc,
                         BOOL useHFSPlusMapping);

// Copy attributes from fg and bg, and zero out other fields. Text attributes like bold, italic, etc.
// come from fg.
void InitializeScreenChar(screen_char_t *s, screen_char_t fg, screen_char_t bg);

// Translates normal characters into graphics characters, as defined in charsets.h. Must not contain
// complex characters.
void ConvertCharsToGraphicsCharset(screen_char_t *s, int len);

// Indicates if s contains any combining marks.
BOOL StringContainsCombiningMark(NSString *s);

// Allocates a new image code and sets in the return value. The image will be
// displayed in the terminal with width x height cells. If preserveAspectRatio
// is set then background-color bars will be added on the edges so the image is
// not distorted. Insets should be specified as a fraction of cell size (all inset values should be
// in [0, 1] and will be multiplied by cell width and height before rendering.).
screen_char_t ImageCharForNewImage(NSString *name,
                                   int width,
                                   int height,
                                   BOOL preserveAspectRatio,
                                   NSEdgeInsets insets);

// Sets the row and column number in an image cell. Goes from 0 to width/height
// as specified in the preceding call to ImageCharForNewImage.
void SetPositionInImageChar(screen_char_t *charPtr, int x, int y);

// Assigns an image to a code allocated by ImageCharForNewImage. data is optional and only used for
// animated gifs.
void SetDecodedImage(unichar code, NSImage *image, NSData *data);

// Releases all memory associated with an image. The code comes from ImageCharForNewImage.
void ReleaseImage(unichar code);

// Returns image info for a code found in a screen_char_t with field image==1.
iTermImageInfo *GetImageInfo(unichar code);

// Returns the position of a character within an image in cells with the origin
// at the top left.
VT100GridCoord GetPositionOfImageInChar(screen_char_t c);

// Returns a dictionary of restorable state
NSDictionary *ScreenCharEncodedRestorableState(void);
void ScreenCharDecodeRestorableState(NSDictionary *state);

