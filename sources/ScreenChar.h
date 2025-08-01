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
#import "iTermTriState.h"
#import "NSStringITerm.h"
#import "VT100GridTypes.h"

@class iTermImage;
@class iTermImageInfo;
@protocol iTermImageInfoReading;

#define ITERM2_PRIVATE_BEGIN 0x0001
#define ITERM2_PRIVATE_END 0x0007

// This is used in the rightmost column when a double-width character would
// have been split in half and was wrapped to the next line. It is nonprintable
// and not selectable. It is not copied into the clipboard. A line ending in this
// character should always have EOL_DWC. These are stripped when adding a line
// to the scrollback buffer.
#define DWC_SKIP (ITERM2_PRIVATE_BEGIN + 0)

// When a tab is received, we insert some number of TAB_FILLER characters
// preceded by a \t character. This allows us to reconstruct the tab for
// copy-pasting.
#define TAB_FILLER (ITERM2_PRIVATE_BEGIN + 1)

// If DWC_SKIP appears in the input, we convert it to this to avoid causing confusion.
// NOTE: I think this isn't used because DWC_SKIP is caught early and converted to a '?'.
#define BOGUS_CHAR (ITERM2_PRIVATE_BEGIN + 2)

// Double-width characters have their "real" code in one cell and this code in
// the right-hand cell.
#define DWC_RIGHT (ITERM2_PRIVATE_BEGIN + 3)

// Placed in searchings while searching to match ^ or $
#define REGEX_START (ITERM2_PRIVATE_BEGIN + 4)
#define REGEX_END (ITERM2_PRIVATE_BEGIN + 5)

// This never occurs in a string.
#define IMPOSSIBLE_CHAR (ITERM2_PRIVATE_BEGIN + 6)

// The range of private codes we use, with specific instances defined
// above here.
#define ITERM2_LEGACY_PRIVATE_BEGIN 0xf000
#define ITERM2_LEGACY_PRIVATE_END 0xf003


// These codes go in the continuation character to the right of the
// rightmost column.
#define EOL_HARD 0 // Hard line break (explicit newline)
#define EOL_SOFT 1 // Soft line break (a long line was wrapped)
#define EOL_DWC  2 // Double-width character wrapped to next line

#define ONECHAR_UNKNOWN ('?')   // Replacement character for encodings other than utf-8.

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

#define ALTSEM_SYSTEM_MESSAGE 4

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

// Note that this is a bit field in screen_char_t. If you add to it ensure there is space to grow.
typedef NS_ENUM(unsigned int, VT100UnderlineStyle) {
    VT100UnderlineStyleSingle,
    VT100UnderlineStyleCurly,
    VT100UnderlineStyleDouble
};

typedef struct {
    int red;
    int green;
    int blue;
    ColorMode mode;
} VT100TerminalColorValue;

NSString *VT100TerminalColorValueDescription(VT100TerminalColorValue value, BOOL fg);

typedef struct legacy_screen_char_t {
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
    //       16-231: rgb value given by 16 + r*36 + g*6 + b, with each color in
    //         the range [0,5].
    //       232-255: Grayscale values from dimmest gray 233 (which is not black)
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

    // If set, the 'code' field does not give a utf-16 value but is instead a
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

    unsigned int strikethrough : 1;
    VT100UnderlineStyle underlineStyle : 2;  // VT100UnderlineStyle

    unsigned int invisible : 1;

    // fg and bg are swapped. Note that this flag doesn't affect rendering; it simply notes that the
    // colors in this struct were *already* exchanged because of SGR 7.
    unsigned int inverse : 1;

    // This comes after unused so it can be byte-aligned.
    // If the current text is part of a hypertext link, this gives an index into the URL store.
    unsigned short urlCode;
} legacy_screen_char_t;

typedef NS_ENUM(unsigned int, RTLStatus) {
    RTLStatusUnknown = 0,
    RTLStatusLTR = 1,
    RTLStatusRTL = 2
};

typedef struct screen_char_t {
    // Normally, 'code' gives a utf-16 code point. If 'complexChar' is set then
    // it is a key into a string table of multiple utf-16 code points (for
    // example, a surrogate pair or base char+combining mark). These must render
    // to a single glyph. 'code' can take some special values which are valid
    // regardless of the setting of 'complexChar':
    //   0: Signifies no character was ever set at this location. Not selectable.
    //   DWC_SKIP, TAB_FILLER, BOGUS_CHAR, or DWC_RIGHT: See comments above.
    // In the WIDTH+1 position on a line, this takes the value of EOL_HARD,
    //  EOL_SOFT, or EOL_DWC. See the comments for those constants.
    // If this is an image:
    //   - If it is a virtualPlacement, it acts like a complexChar (code indexes into string table)
    //   - If it is *not* a virtualPlacement, code is an image number.
    unichar code;

    // With normal background semantics:
    //   The lower 9 bits have the same semantics for foreground and background
    //   color:
    //     Low three bits give color. 0-7 are black, red, green, yellow, blue,
    //       magenta, cyan, and white.
    //     Values between 8 and 15 are bright versions of 0-7.
    //     Values between 16 and 255 are used for 256 color mode:
    //       16-231: rgb value given by 16 + r*36 + g*6 + b, with each color in
    //         the range [0,5].
    //       232-255: Grayscale values from dimmest gray 233 (which is not black)
    //         to brightest 255 (not white).
    // With alternate background semantics:
    //   ALTSEM_xxx (see comments above)
    // With 24-bit semantics:
    //   foreground/backgroundColor gives red component and fg/bgGreen, fg/bgBlue
    //     give the rest of the color's components
    // For non-virtualPlacement images, foregroundColor doubles as the x index.
    unsigned int foregroundColor : 8;
    unsigned int fgGreen : 8;
    unsigned int fgBlue  : 8;

    // For non-virtualPlacement images, backgroundColor doubles as the y index.
    unsigned int backgroundColor : 8;
    unsigned int bgGreen : 8;
    unsigned int bgBlue  : 8;

    // These determine the interpretation of foreground/backgroundColor.
    unsigned int foregroundColorMode : 2;
    unsigned int backgroundColorMode : 2;

    // If set, the 'code' field does not give a utf-16 value but is instead a
    // key into a string table of more complex chars (combined, surrogate pairs,
    // etc.). Valid 'code' values for a complex char are in [1, 0xefff] and will
    // be recycled as needed.
    // See the notes in `code` about how this interacts with images.
    unsigned int complexChar : 1;

    // Various bits affecting text appearance. The bold flag here is semantic
    // and may be rendered as some combination of font choice and color
    // intensity.
    unsigned int bold : 1;
    unsigned int faint : 1;
    unsigned int italic : 1;
    unsigned int blink : 1;
    unsigned int underline : 1;

    // Is this actually an image? Changes the semantics of code, complexChar,
    // foregroundColor, and backgroundColor (see notes above).
    unsigned int image : 1;  // See also virtualPlaceholder, below.

    unsigned int strikethrough : 1;
    VT100UnderlineStyle underlineStyle : 2;  // VT100UnderlineStyle

    unsigned int invisible : 1;

    // fg and bg are swapped. Note that this flag doesn't affect rendering; it simply notes that the
    // colors in this struct were *already* exchanged because of SGR 7.
    unsigned int inverse : 1;

    // Character can't be erased when screen is in protected mode. See DECSCA, SPA, and EPA.
    unsigned int guarded : 1;

    // Only valid when this is an image. If set, this is a Kitty-style virtual placeholder.
    unsigned int virtualPlaceholder : 1;

    // BiDi disposition, if any.
    RTLStatus rtlStatus : 2;

    unsigned int unused : 12;
} screen_char_t;


// Standard unicode replacement string. Is a double-width character.
static inline NSString* ReplacementString(void) {
    const unichar kReplacementCharacter = UNICODE_REPLACEMENT_CHAR;
    return [NSString stringWithCharacters:&kReplacementCharacter length:1];
}

static inline BOOL ScreenCharacterAttributesEqual(const screen_char_t c1, const screen_char_t c2) {
    return (c1.foregroundColor == c2.foregroundColor &&
            c1.fgGreen == c2.fgGreen &&
            c1.fgBlue == c2.fgBlue &&
            c1.backgroundColor == c2.backgroundColor &&
            c1.bgGreen == c2.bgGreen &&
            c1.bgBlue == c2.bgBlue &&
            c1.foregroundColorMode == c2.foregroundColorMode &&
            c1.backgroundColorMode == c2.backgroundColorMode &&
            c1.bold == c2.bold &&
            c1.faint == c2.faint &&
            c1.italic == c2.italic &&
            c1.blink == c2.blink &&
            c1.invisible == c2.invisible &&
            c1.underline == c2.underline &&
            c1.underlineStyle == c2.underlineStyle &&
            c1.strikethrough == c2.strikethrough &&
            c1.image == c2.image &&
            c1.virtualPlaceholder == c2.virtualPlaceholder &&
            c1.rtlStatus == c2.rtlStatus);
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
    to->invisible = from.invisible;
    to->underline = from.underline;
    to->underlineStyle = from.underlineStyle;
    to->strikethrough = from.strikethrough;
    to->unused = from.unused;
    to->image = from.image;
    to->virtualPlaceholder = from.virtualPlaceholder;
    to->inverse = from.inverse;
    to->guarded = from.guarded;
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

static inline BOOL ScreenCharHasDefaultAttributesAndColors(const screen_char_t s,
                                                           unsigned int urlCode) {
    return (s.backgroundColor == ALTSEM_DEFAULT &&
            s.foregroundColor == ALTSEM_DEFAULT &&
            s.backgroundColorMode == ColorModeAlternate &&
            s.foregroundColorMode == ColorModeAlternate &&
            !s.complexChar &&
            !s.bold &&
            !s.faint &&
            !s.italic &&
            !s.blink &&
            !s.invisible &&
            !s.underline &&
            s.underlineStyle == VT100UnderlineStyleSingle &&
            !s.strikethrough &&
            urlCode == 0);
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
+ (instancetype)bell;

// Note: this strips controls and private use characters.
- (instancetype)initWithScreenChars:(const screen_char_t *)screenChars
                             length:(NSInteger)length;

- (NSRange)rangeOfScreenCharsForRangeInString:(NSRange)rangeInString;

@end

// Look up the string associated with a complex char's key.
NSString* ComplexCharToStr(int key);
BOOL ComplexCharCodeIsSpacingCombiningMark(unichar code);

// Return a string with the contents of a screen char, which may or may not
// be complex.
NSString* ScreenCharToStr(const screen_char_t *const sct);
NSString* CharToStr(unichar code, BOOL isComplex);
NSString* ScreenCharToKittyPlaceholder(const screen_char_t *const sct);

// This is a faster version of ScreenCharToStr if what you want is an array of
// unichars. Returns the number of code points appended to dest.
int ExpandScreenChar(const screen_char_t *sct, unichar* dest);

// Add a code point to the end of an existing complex char. A replacement key is
// returned.
unichar AppendToComplexChar(unichar key, unichar codePoint);

// Add a code point to the end of an existing char, whether complex or not.
void AppendToChar(screen_char_t *dest, unichar c);

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
NSString* ScreenCharArrayToString(const screen_char_t *screenChars,
                                  int start,
                                  int end,
                                  unichar** backingStorePtr,
                                  int** deltasPtr);

// Number of chars before a sequence of nuls at the end of the line.
int EffectiveLineLength(screen_char_t* theLine, int totalLength);

NSString* ScreenCharArrayToStringDebug(const screen_char_t* screenChars,
                                       int lineLength);

NSString *DebugStringForScreenChar(screen_char_t c);

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
                         NSInteger unicodeVersion,
                         BOOL softAlternateScreenMode,
                         BOOL *rtlFound);

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
id<iTermImageInfoReading> GetImageInfo(unichar code);
iTermImageInfo* GetMutableImageInfo(unichar code);

// Returns the position of a character within an image in cells with the origin
// at the top left.
VT100GridCoord GetPositionOfImageInChar(screen_char_t c);

// Returns a dictionary of restorable state
NSDictionary *ScreenCharEncodedRestorableState(void);
NSInteger ScreenCharGeneration(void);
void ScreenCharDecodeRestorableState(NSDictionary *state);
void ScreenCharGarbageCollectImages(void);
void ScreenCharClearProvisionalFlagForImageWithCode(int code);

NSString *ScreenCharDescription(screen_char_t c);
void ScreenCharInvert(screen_char_t *c);

// Returns true if any RTL was found. Sets the rtlState on all characters in c.
BOOL AnnotateRightToLeftInScreenChars(screen_char_t *c, int len);

// This may return a value for the next cell if `cellOffset` points at something without a corresponding
// code point, such as a DWC_RIGHT.
int UTF16OffsetFromCellOffset(int cellOffset,  // search for utf-16 offset with this cell offset
                              const int *deltas,  // indexed by code point
                              int numCodePoints);

// Converts an offset into an NSString to a cell index in the SCA that created it with ScreenCharArrayToString.
int CellOffsetFromUTF16Offset(int utf16Offset,
                              const int *deltas);

NS_INLINE BOOL ScreenCharIsDWC_SKIP(screen_char_t c) {
    if (c.complexChar) {
        return NO;
    }
    if (c.image) {
        return NO;
    }
    return c.code == DWC_SKIP;
}

NS_INLINE BOOL ScreenCharIsDWC_RIGHT(screen_char_t c) {
    // These tests are arranged in order of most- to least-likely for performance.
    if (c.code != DWC_RIGHT) {
        return NO;
    }
    if (c.complexChar) {
        return NO;
    }
    if (c.image) {
        return NO;
    }
    return YES;
}

NS_INLINE BOOL ScreenCharIsTAB_FILLER(screen_char_t c) {
    if (c.complexChar) {
        return NO;
    }
    if (c.image) {
        return NO;
    }
    return c.code == TAB_FILLER;
}

NS_INLINE void ScreenCharSetDWC_SKIP(screen_char_t *c) {
    c->complexChar = NO;
    c->image = NO;
    c->virtualPlaceholder = NO;
    c->code = DWC_SKIP;
}

NS_INLINE void ScreenCharSetTAB_FILLER(screen_char_t *c) {
    c->complexChar = NO;
    c->image = NO;
    c->virtualPlaceholder = NO;
    c->code = TAB_FILLER;
}

NS_INLINE void ScreenCharSetDWC_RIGHT(screen_char_t *c) {
    c->complexChar = NO;
    c->image = NO;
    c->virtualPlaceholder = NO;
    c->code = DWC_RIGHT;
}
