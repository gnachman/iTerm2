//
//  VT100GraphicRendition.h
//  iTerm2
//
//  Created by George Nachman on 3/19/25.
//

#import <Cocoa/Cocoa.h>
#import "iTermExternalAttributeIndex.h"
#import "iTermParser.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"

// character attributes
#define VT100CHARATTR_ALLOFF           0
#define VT100CHARATTR_BOLD             1
#define VT100CHARATTR_FAINT            2
#define VT100CHARATTR_ITALIC           3
#define VT100CHARATTR_UNDERLINE        4
#define VT100CHARATTR_BLINK            5
#define VT100CHARATTR_REVERSE          7
#define VT100CHARATTR_INVISIBLE        8
#define VT100CHARATTR_STRIKETHROUGH    9

// xterm additions
#define VT100CHARATTR_DOUBLE_UNDERLINE  21
#define VT100CHARATTR_NORMAL            22
#define VT100CHARATTR_NOT_ITALIC        23
#define VT100CHARATTR_NOT_UNDERLINE     24
#define VT100CHARATTR_STEADY            25
#define VT100CHARATTR_POSITIVE          27
#define VT100CHARATTR_VISIBLE           28
#define VT100CHARATTR_NOT_STRIKETHROUGH 29

typedef enum {
    COLORCODE_BLACK = 0,
    COLORCODE_RED = 1,
    COLORCODE_GREEN = 2,
    COLORCODE_YELLOW = 3,
    COLORCODE_BLUE = 4,
    COLORCODE_MAGENTA = 5,
    COLORCODE_WATER = 6,
    COLORCODE_WHITE = 7,
    COLORCODE_256 = 8,
} colorCode;

// Color constants
// Color codes for 8-color mode. Black and white are the limits; other codes can be constructed
// similarly.
#define VT100CHARATTR_FG_BASE  30
#define VT100CHARATTR_BG_BASE  40

#define VT100CHARATTR_FG_BLACK     (VT100CHARATTR_FG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_WHITE     (VT100CHARATTR_FG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_FG_256       (VT100CHARATTR_FG_BASE + COLORCODE_256)
#define VT100CHARATTR_FG_DEFAULT   (VT100CHARATTR_FG_BASE + 9)

#define VT100CHARATTR_BG_BLACK     (VT100CHARATTR_BG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_WHITE     (VT100CHARATTR_BG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_BG_256       (VT100CHARATTR_BG_BASE + COLORCODE_256)
#define VT100CHARATTR_BG_DEFAULT   (VT100CHARATTR_BG_BASE + 9)

#define VT100CHARATTR_UNDERLINE_COLOR 58
#define VT100CHARATTR_UNDERLINE_COLOR_DEFAULT 59

// Color codes for 16-color mode. Black and white are the limits; other codes can be constructed
// similarly.
#define VT100CHARATTR_FG_HI_BASE  90
#define VT100CHARATTR_BG_HI_BASE  100

#define VT100CHARATTR_FG_HI_BLACK     (VT100CHARATTR_FG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_HI_WHITE     (VT100CHARATTR_FG_HI_BASE + COLORCODE_WHITE)

#define VT100CHARATTR_BG_HI_BLACK     (VT100CHARATTR_BG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_HI_WHITE     (VT100CHARATTR_BG_HI_BASE + COLORCODE_WHITE)

typedef struct {
    BOOL bold;
    BOOL blink;
    BOOL invisible;
    BOOL underline;
    VT100UnderlineStyle underlineStyle;
    BOOL strikethrough;
    BOOL reversed;
    BOOL faint;
    BOOL italic;

    int fgColorCode;
    int fgGreen;
    int fgBlue;
    ColorMode fgColorMode;

    int bgColorCode;
    int bgGreen;
    int bgBlue;
    ColorMode bgColorMode;

    BOOL hasUnderlineColor;
    VT100TerminalColorValue underlineColor;
} VT100GraphicRendition;

typedef NS_ENUM(NSUInteger, VT100GraphicRenditionSideEffect) {
    VT100GraphicRenditionSideEffectNone,
    VT100GraphicRenditionSideEffectReset,
    VT100GraphicRenditionSideEffectUpdateExternalAttributes,
    VT100GraphicRenditionSideEffectSkip2AndUpdateExternalAttributes,
    VT100GraphicRenditionSideEffectSkip4AndUpdateExternalAttributes,
    VT100GraphicRenditionSideEffectSkip2,
    VT100GraphicRenditionSideEffectSkip4,
};

// Modify rendition given the CSI parameters at index i. Returns side effects the caller should apply.
VT100GraphicRenditionSideEffect VT100GraphicRenditionExecuteSGR(VT100GraphicRendition *rendition, CSIParam *csi, int i);

// Creates a default rendition.
void VT100GraphicRenditionInitialize(VT100GraphicRendition *rendition);

// Parses 24-bit and 256-mode colors like 38:5:99m. See comment in implementation for details.
// Starts at *index and then updates index if additional parameters were used for janky 38;5;99m style codes.
VT100TerminalColorValue VT100TerminalColorValueFromCSI(CSIParam *csi, int *index);

// Backwardsly creates a rendition from an existing character.
VT100GraphicRendition VT100GraphicRenditionFromCharacter(const screen_char_t *c, iTermExternalAttribute *attr);

// Updates the foreground attributes of c
void VT100GraphicRenditionUpdateForeground(const VT100GraphicRendition *rendition, BOOL applyReverse, BOOL protectedMode, screen_char_t *c);

// Updates the background attributes of c
void VT100GraphicRenditionUpdateBackground(const VT100GraphicRendition *rendition, BOOL applyReverse, screen_char_t *c);

