//
//  iTermScreenChar.h
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

#ifdef __METAL_VERSION__
typedef unsigned short unichar;
#endif

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
    unichar code;  // 0,1

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
    unsigned int foregroundColor : 8;  // 2
    unsigned int fgGreen : 8;  // 3
    unsigned int fgBlue  : 8;  // 4

    // For images, backgroundColor doubles as the y index.
    unsigned int backgroundColor : 8;  // 5
    unsigned int bgGreen : 8;  // 6
    unsigned int bgBlue  : 8;  // 7

    // These determine the interpretation of foreground/backgroundColor.
    unsigned int foregroundColorMode : 2;  // 8:0,8:1
    unsigned int backgroundColorMode : 2;  // 8:2,8:3

    // If set, the 'code' field does not give a utf-16 value but is intead a
    // key into a string table of more complex chars (combined, surrogate pairs,
    // etc.). Valid 'code' values for a complex char are in [1, 0xefff] and will
    // be recycled as needed.
    unsigned int complexChar : 1;  // 8:4

    // Various bits affecting text appearance. The bold flag here is semantic
    // and may be rendered as some combination of font choice and color
    // intensity.
    unsigned int bold : 1;  // 8:5
    unsigned int faint : 1;  // 8:6
    unsigned int italic : 1;  // 8:7
    unsigned int blink : 1;  // 9:0
    unsigned int underline : 1;  // 9:1

    // Is this actually an image? Changes the semantics of code,
    // foregroundColor, and backgroundColor (see notes above).
    unsigned int image : 1;  // 9:2

    // These bits aren't used but are defined here so that the entire memory
    // region can be initialized.
    unsigned int unused : 5;  // 9:3,...,9:7

    // This comes after unused so it can be byte-aligned.
    // If the current text is part of a hypertext link, this gives an index into the URL store.
    unsigned short urlCode;  // 10,11
} screen_char_t;

typedef enum {
    ColorModeAlternate = 0,  // ALTSEM_XXX values
    ColorModeNormal = 1,  // kiTermScreenCharAnsiColor values
    ColorMode24bit = 2,
    ColorModeInvalid = 3
} ColorMode;
