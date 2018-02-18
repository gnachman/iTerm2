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
#import "ITAddressBookMgr.h"
#import "NSStringITerm.h"
#import "VT100GridTypes.h"
#import "iTermScreenChar.h"

@class iTermImage;
@class iTermImageInfo;

#if __cplusplus
extern "C" {
#endif

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

static inline BOOL ScreenCharacterAttributesEqual(screen_char_t *c1, screen_char_t *c2) {
    return (c1->foregroundColor == c2->foregroundColor &&
            c1->fgGreen == c2->fgGreen &&
            c1->fgBlue == c2->fgBlue &&
            c1->backgroundColor == c2->backgroundColor &&
            c1->bgGreen == c2->bgGreen &&
            c1->bgBlue == c2->bgBlue &&
            c1->foregroundColorMode == c2->foregroundColorMode &&
            c1->backgroundColorMode == c2->backgroundColorMode &&
            c1->bold == c2->bold &&
            c1->faint == c2->faint &&
            c1->italic == c2->italic &&
            c1->blink == c2->blink &&
            c1->underline == c2->underline &&
            !c1->urlCode == !c2->urlCode &&  // Only tests if urlCode is zero/nonzero in both
            c1->image == c2->image);
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
    to->urlCode = from.urlCode;
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
        a.underline != b.underline ||
        !a.urlCode != !b.urlCode) {
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
            !s.underline &&
            !s.urlCode);
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

// Performs the appropriate normalization.
NSString *StringByNormalizingString(NSString *theString, iTermUnicodeNormalization normalization);

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
void BeginComplexChar(screen_char_t *screenChar, unichar combiningChar, iTermUnicodeNormalization normalization);

// Place a complex char in a screen char.
void SetComplexCharInScreenChar(screen_char_t *screenChar, NSString *theString, iTermUnicodeNormalization normalization);

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
                         iTermUnicodeNormalization normalization,
                         NSInteger unicodeVersion);

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
void SetDecodedImage(unichar code, iTermImage *image, NSData *data);

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

#if __cplusplus
}
#endif
