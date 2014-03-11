#import "VT100Terminal.h"
#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "VT100Parser.h"
#import <apr-1/apr_base64.h>  // for xterm's base64 decoding (paste64)
#include <term.h>

@interface VT100Terminal ()
@property(nonatomic, assign) BOOL reportFocus;
@property(nonatomic, assign) BOOL reverseVideo;
@property(nonatomic, assign) BOOL originMode;
@property(nonatomic, assign) BOOL isAnsi;
@property(nonatomic, assign) BOOL autorepeatMode;
@property(nonatomic, assign) int charset;
@property(nonatomic, assign) BOOL bracketedPasteMode;
@property(nonatomic, assign) BOOL allowColumnMode;
@property(nonatomic, assign) BOOL lineMode;  // YES=Newline, NO=Line feed
@property(nonatomic, assign) BOOL columnMode;  // YES=132 Column, NO=80 Column
@property(nonatomic, assign) BOOL scrollMode;  // YES=Smooth, NO=Jump
@property(nonatomic, assign) BOOL disableSmcupRmcup;

// A write-only property, at the moment. TODO: What should this do?
@property(nonatomic, assign) BOOL strictAnsiMode;

@end

@implementation VT100Terminal {
    // True if between BeginFile and EndFile codes.
    BOOL receivingFile_;
    
    // In FinalTerm command mode (user is at the prompt typing a command).
    BOOL inCommand_;

    id<VT100TerminalDelegate> delegate_;
    
    BOOL ansiMode_;         // YES=ANSI, NO=VT52
    BOOL xon_;               // YES=XON, NO=XOFF. Not currently used.
    BOOL numLock_;           // YES=ON, NO=OFF, default=YES;
    
    int fgColorCode_;
    int fgGreen_;
    int fgBlue_;
    ColorMode fgColorMode_;
    int bgColorCode_;
    int bgGreen_;
    int bgBlue_;
    ColorMode bgColorMode_;
    BOOL bold_, italic_, under_, blink_, reversed_;
    
    BOOL saveBold_, saveItalic_, saveUnder_, saveBlink_, saveReversed_;
    int saveCharset_;
    int saveForeground_;
    int saveFgGreen_;
    int saveFgBlue_;
    ColorMode saveFgColorMode_;
    int saveBackground_;
    int saveBgGreen_;
    int saveBgBlue_;
    ColorMode saveBgColorMode_;
    
    int sendModifiers_[NUM_MODIFIABLE_RESOURCES];
}

@synthesize delegate = delegate_;

#define DEL  0x7f

// character attributes
#define VT100CHARATTR_ALLOFF   0
#define VT100CHARATTR_BOLD     1
#define VT100CHARATTR_ITALIC   3
#define VT100CHARATTR_UNDER    4
#define VT100CHARATTR_BLINK    5
#define VT100CHARATTR_REVERSE  7

// xterm additions
#define VT100CHARATTR_NORMAL        22
#define VT100CHARATTR_NOT_ITALIC    23
#define VT100CHARATTR_NOT_UNDER     24
#define VT100CHARATTR_STEADY        25
#define VT100CHARATTR_POSITIVE      27

typedef enum {
    COLORCODE_BLACK = 0,
    COLORCODE_RED = 1,
    COLORCODE_GREEN = 2,
    COLORCODE_YELLOW = 3,
    COLORCODE_BLUE = 4,
    COLORCODE_PURPLE = 5,
    COLORCODE_WATER = 6,
    COLORCODE_WHITE = 7,
    COLORCODE_256 = 8,
    COLORS
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

// Color codes for 16-color mode. Black and white are the limits; other codes can be constructed
// similarly.
#define VT100CHARATTR_FG_HI_BASE  90
#define VT100CHARATTR_BG_HI_BASE  100

#define VT100CHARATTR_FG_HI_BLACK     (VT100CHARATTR_FG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_HI_WHITE     (VT100CHARATTR_FG_HI_BASE + COLORCODE_WHITE)

#define VT100CHARATTR_BG_HI_BLACK     (VT100CHARATTR_BG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_HI_WHITE     (VT100CHARATTR_BG_HI_BASE + COLORCODE_WHITE)

// Prevents runaway memory usage
static const int kMaxScreenColumns = 4096;
static const int kMaxScreenRows = 4096;

#pragma mark - Instance methods

- (id)init
{
    self = [super init];
    if (self) {
        _output = [[VT100Output alloc] init];
        _encoding = NSASCIIStringEncoding;
        _parser = [[VT100Parser alloc] init];
        _parser.encoding = _encoding;
        
        _wraparoundMode = YES;
        _autorepeatMode = YES;
        xon_ = YES;
        fgColorCode_ = ALTSEM_DEFAULT;
        fgColorMode_ = ColorModeAlternate;
        bgColorCode_ = ALTSEM_DEFAULT;
        bgColorMode_ = ColorModeAlternate;
        saveForeground_ = fgColorCode_;
        saveFgColorMode_ = fgColorMode_;
        saveBackground_ = bgColorCode_;
        saveBgColorMode_ = bgColorMode_;
        _mouseMode = MOUSE_REPORTING_NONE;
        _mouseFormat = MOUSE_FORMAT_XTERM;

        _allowKeypadMode = YES;

        numLock_ = YES;
    }
    return self;
}

- (void)dealloc
{
    [_output release];
    [_parser release];
    [_termType release];

    [super dealloc];
}

- (void)setEncoding:(NSStringEncoding)encoding {
    _encoding = encoding;
    _parser.encoding = encoding;
}

- (void)setTermType:(NSString *)termtype
{
    [_termType autorelease];
    _termType = [termtype copy];

    self.allowKeypadMode = [_termType rangeOfString:@"xterm"].location != NSNotFound;

    int r;

    setupterm((char *)[_termType UTF8String], fileno(stdout), &r);
    if (r != 1) {
        NSLog(@"Terminal type %s is not defined.", [_termType UTF8String]);
    }
    _output.termTypeIsValid = (r == 1);

    self.isAnsi = [_termType rangeOfString:@"ANSI"
                                   options:NSCaseInsensitiveSearch | NSAnchoredSearch ].location !=  NSNotFound;
    [delegate_ terminalTypeDidChange];
}

- (void)saveTextAttributes
{
    saveBold_ = bold_;
    saveItalic_ = italic_;
    saveUnder_ = under_;
    saveBlink_ = blink_;
    saveReversed_ = reversed_;
    saveCharset_ = _charset;
    saveForeground_ = fgColorCode_;
    saveFgGreen_ = fgGreen_;
    saveFgBlue_ = fgBlue_;
    saveFgColorMode_ = fgColorMode_;
    saveBackground_ = bgColorCode_;
    saveBgGreen_ = bgGreen_;
    saveBgBlue_ = bgBlue_;
    saveBgColorMode_ = bgColorMode_;
}

- (void)restoreTextAttributes
{
    bold_ = saveBold_;
    italic_ = saveItalic_;
    under_ = saveUnder_;
    blink_ = saveBlink_;
    reversed_ = saveReversed_;
    _charset = saveCharset_;
    fgColorCode_ = saveForeground_;
    fgGreen_ = saveFgGreen_;
    fgBlue_ = saveFgBlue_;
    fgColorMode_ = saveFgColorMode_;
    bgColorCode_ = saveBackground_;
    bgGreen_ = saveBgGreen_;
    bgBlue_ = saveBgBlue_;
    bgColorMode_ = saveBgColorMode_;
}

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem
{
    fgColorCode_ = fgColorCode;
    fgColorMode_ = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem
{
    bgColorCode_ = bgColorCode;
    bgColorMode_ = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)resetCharset {
    _charset = 0;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [delegate_ terminalSetCharset:i toLineDrawingMode:NO];
    }
}

- (void)resetPreservingPrompt:(BOOL)preservePrompt
{
    self.lineMode = NO;
    self.cursorMode = NO;
    self.columnMode = NO;
    self.scrollMode = NO;
    _reverseVideo = NO;
    _originMode = NO;
    self.wraparoundMode = YES;
    self.autorepeatMode = YES;
    self.keypadMode = NO;
    self.insertMode = NO;
    self.bracketedPasteMode = NO;
    saveCharset_ = _charset = 0;
    xon_ = YES;
    bold_ = italic_ = blink_ = reversed_ = under_ = NO;
    saveBold_ = saveItalic_ = saveBlink_ = saveReversed_ = saveUnder_ = NO;
    fgColorCode_ = ALTSEM_DEFAULT;
    fgGreen_ = 0;
    fgBlue_ = 0;
    fgColorMode_ = ColorModeAlternate;
    bgColorCode_ = ALTSEM_DEFAULT;
    bgGreen_ = 0;
    bgBlue_ = 0;
    bgColorMode_ = ColorModeAlternate;
    self.mouseMode = MOUSE_REPORTING_NONE;
    self.mouseFormat = MOUSE_FORMAT_XTERM;
    [delegate_ terminalMouseModeDidChangeTo:_mouseMode];
    [delegate_ terminalSetUseColumnScrollRegion:NO];
    _reportFocus = NO;

    self.strictAnsiMode = NO;
    self.allowColumnMode = NO;
    receivingFile_ = NO;
    [delegate_ terminalResetPreservingPrompt:preservePrompt];
}

- (void)setWraparoundMode:(BOOL)mode
{
    if (mode != _wraparoundMode) {
        _wraparoundMode = mode;
        [delegate_ terminalWraparoundModeDidChangeTo:mode];
    }
}

- (void)setCursorMode:(BOOL)cursorMode {
    _cursorMode = cursorMode;
    _output.cursorMode = cursorMode;
}

- (void)setMouseFormat:(MouseFormat)mouseFormat {
    _mouseFormat = mouseFormat;
    _output.mouseFormat = mouseFormat;
}

- (void)setKeypadMode:(BOOL)mode
{
    _keypadMode = mode && self.allowKeypadMode;
    _output.keypadMode = _keypadMode;
}

- (void)setAllowKeypadMode:(BOOL)allow
{
    _allowKeypadMode = allow;
    if (!allow) {
        self.keypadMode = NO;
    }
}

- (screen_char_t)foregroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed_) {
        if (bgColorMode_ == ColorModeAlternate && bgColorCode_ == ALTSEM_DEFAULT) {
            result.foregroundColor = ALTSEM_REVERSED_DEFAULT;
        } else {
            result.foregroundColor = bgColorCode_;
        }
        result.fgGreen = bgGreen_;
        result.fgBlue = bgBlue_;
        result.foregroundColorMode = bgColorMode_;
    } else {
        result.foregroundColor = fgColorCode_;
        result.fgGreen = fgGreen_;
        result.fgBlue = fgBlue_;
        result.foregroundColorMode = fgColorMode_;
    }
    result.bold = bold_;
    result.italic = italic_;
    result.underline = under_;
    result.blink = blink_;
    result.image = NO;
    return result;
}

- (screen_char_t)backgroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed_) {
        if (fgColorMode_ == ColorModeAlternate && fgColorCode_ == ALTSEM_DEFAULT) {
            result.backgroundColor = ALTSEM_REVERSED_DEFAULT;
        } else {
            result.backgroundColor = fgColorCode_;
        }
        result.bgGreen = fgGreen_;
        result.bgBlue = fgBlue_;
        result.backgroundColorMode = fgColorMode_;
    } else {
        result.backgroundColor = bgColorCode_;
        result.bgGreen = bgGreen_;
        result.bgBlue = bgBlue_;
        result.backgroundColorMode = bgColorMode_;
    }
    return result;
}

- (screen_char_t)foregroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.foregroundColor = fgColorCode_;
    result.fgGreen = fgGreen_;
    result.fgBlue = fgBlue_;
    result.foregroundColorMode = fgColorMode_;
    result.bold = bold_;
    result.italic = italic_;
    result.underline = under_;
    result.blink = blink_;
    return result;
}

- (screen_char_t)backgroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.backgroundColor = bgColorCode_;
    result.bgGreen = bgGreen_;
    result.bgBlue = bgBlue_;
    result.backgroundColorMode = bgColorMode_;
    return result;
}

- (void)setInsertMode:(BOOL)mode
{
    if (_insertMode != mode) {
        _insertMode = mode;
        [delegate_ terminalInsertModeDidChangeTo:mode];
    }
}

- (void)executeModeUpdates:(VT100Token *)token
{
    BOOL mode;
    int i;

    switch (token->type) {
        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            mode = (token->type == VT100CSI_DECSET);

            for (i = 0; i < token.csi->count; i++) {
                switch (token.csi->p[i]) {
                    case 20:
                        self.lineMode = mode;
                        break;
                    case 1:
                        self.cursorMode = mode;
                        break;
                    case 2:
                        ansiMode_ = mode;
                        break;
                    case 3:
                        self.columnMode = mode;
                        break;
                    case 4:
                        self.scrollMode = mode;
                        break;
                    case 5:
                        self.reverseVideo = mode;
                        [delegate_ terminalNeedsRedraw];
                        break;
                    case 6:
                        self.originMode = mode;
                        [delegate_ terminalMoveCursorToX:1 y:1];
                        break;
                    case 7:
                        self.wraparoundMode = mode;
                        break;
                    case 8:
                        self.autorepeatMode = mode;
                        break;
                    case 9:
                        // TODO: This should send mouse x&y on button press.
                        break;
                    case 25:
                        [delegate_ terminalSetCursorVisible:mode];
                        break;
                    case 40:
                        self.allowColumnMode = mode;
                        break;
                    case 69:
                        [delegate_ terminalSetUseColumnScrollRegion:mode];
                        break;

                    case 1049:
                        // From the xterm release log:
                        // Implement new escape sequence, private mode 1049, which combines
                        // the switch to/from alternate screen mode with screen clearing and
                        // cursor save/restore.  Unlike the existing escape sequence, this
                        // clears the alternate screen when switching to it rather than when
                        // switching to the normal screen, thus retaining the alternate screen
                        // contents for select/paste operations.
                        if (!self.disableSmcupRmcup) {
                            if (mode) {
                                [self saveTextAttributes];
                                [delegate_ terminalSaveCharsetFlags];
                                [delegate_ terminalShowAltBuffer];
                                [delegate_ terminalClearScreen];
                            } else {
                                [delegate_ terminalShowPrimaryBufferRestoringCursor:YES];
                                [self restoreTextAttributes];
                                [delegate_ terminalRestoreCharsetFlags];
                            }
                        }
                        break;

                    case 2004:
                        // Set bracketed paste mode
                        self.bracketedPasteMode = mode;
                        break;

                    case 47:
                        // alternate screen buffer mode
                        if (!self.disableSmcupRmcup) {
                            if (mode) {
                                [delegate_ terminalShowAltBuffer];
                            } else {
                                [delegate_ terminalShowPrimaryBufferRestoringCursor:NO];
                            }
                        }
                        break;

                    case 1000:
                    // case 1001:
                        // TODO: MOUSE_REPORTING_HILITE not implemented.
                    case 1002:
                    case 1003:
                        if (mode) {
                            self.mouseMode = token.csi->p[i] - 1000;
                        } else {
                            self.mouseMode = MOUSE_REPORTING_NONE;
                        }
                        [delegate_ terminalMouseModeDidChangeTo:_mouseMode];
                        break;
                    case 1004:
                        self.reportFocus = mode;
                        break;

                    case 1005:
                        if (mode) {
                            self.mouseFormat = MOUSE_FORMAT_XTERM_EXT;
                        } else {
                            self.mouseFormat = MOUSE_FORMAT_XTERM;
                        }
                        break;


                    case 1006:
                        if (mode) {
                            self.mouseFormat = MOUSE_FORMAT_SGR;
                        } else {
                            self.mouseFormat = MOUSE_FORMAT_XTERM;
                        }
                        break;

                    case 1015:
                        if (mode) {
                            self.mouseFormat = MOUSE_FORMAT_URXVT;
                        } else {
                            self.mouseFormat = MOUSE_FORMAT_XTERM;
                        }
                        break;
                }
            }
            break;
        case VT100CSI_SM:
        case VT100CSI_RM:
            mode = (token->type == VT100CSI_SM);

            for (i = 0; i < token.csi->count; i++) {
                switch (token.csi->p[i]) {
                    case 4:
                        self.insertMode = mode;
                        break;
                }
            }
            break;
        case VT100CSI_DECKPAM:
            self.keypadMode = YES;
            break;
        case VT100CSI_DECKPNM:
            self.keypadMode = NO;
            break;
        case VT100CC_SI:
            _charset = 0;
            break;
        case VT100CC_SO:
            _charset = 1;
            break;
        case VT100CC_DC1:
            xon_ = YES;
            break;
        case VT100CC_DC3:
            xon_ = NO;
            break;
        case VT100CSI_DECRC:
            [self restoreTextAttributes];
            [delegate_ terminalRestoreCursor];
            break;
        case VT100CSI_DECSC:
            [self saveTextAttributes];
            [delegate_ terminalSaveCursor];
            break;
        case VT100CSI_DECSTR:
            self.wraparoundMode = YES;
            self.originMode = NO;
            break;
        case VT100CSI_RESET_MODIFIERS:
            if (token.csi->count == 0) {
                sendModifiers_[2] = -1;
            } else {
                int resource = token.csi->p[0];
                if (resource >= 0 && resource <= NUM_MODIFIABLE_RESOURCES) {
                    sendModifiers_[resource] = -1;
                }
            }
            [delegate_ terminalSendModifiersDidChangeTo:sendModifiers_
                                              numValues:NUM_MODIFIABLE_RESOURCES];
            break;

        case VT100CSI_SET_MODIFIERS: {
            if (token.csi->count == 0) {
                for (int i = 0; i < NUM_MODIFIABLE_RESOURCES; i++) {
                    sendModifiers_[i] = 0;
                }
            } else {
                int resource = token.csi->p[0];
                int value;
                if (token.csi->count == 1) {
                    value = 0;
                } else {
                    value = token.csi->p[1];
                }
                if (resource >= 0 && resource < NUM_MODIFIABLE_RESOURCES && value >= 0) {
                    sendModifiers_[resource] = value;
                }
            }
            [delegate_ terminalSendModifiersDidChangeTo:sendModifiers_
                                              numValues:NUM_MODIFIABLE_RESOURCES];
            break;
        }

        default:
            break;
    }
}

- (void)resetSGR {
    // all attributes off
    bold_ = italic_ = under_ = blink_ = reversed_ = NO;
    fgColorCode_ = ALTSEM_DEFAULT;
    fgGreen_ = 0;
    fgBlue_ = 0;
    fgColorMode_ = ColorModeAlternate;
    bgColorCode_ = ALTSEM_DEFAULT;
    bgGreen_ = 0;
    bgBlue_ = 0;
    bgColorMode_ = ColorModeAlternate;
}

- (void)executeSGR:(VT100Token *)token
{
    if (token->type == VT100CSI_SGR) {
        if (token.csi->count == 0) {
            [self resetSGR];
        } else {
            int i;
            for (i = 0; i < token.csi->count; ++i) {
                int n = token.csi->p[i];
                switch (n) {
                    case VT100CHARATTR_ALLOFF:
                        // all attribute off
                        bold_ = italic_ = under_ = blink_ = reversed_ = NO;
                        fgColorCode_ = ALTSEM_DEFAULT;
                        fgGreen_ = 0;
                        fgBlue_ = 0;
                        bgColorCode_ = ALTSEM_DEFAULT;
                        bgGreen_ = 0;
                        bgBlue_ = 0;
                        fgColorMode_ = ColorModeAlternate;
                        bgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_BOLD:
                        bold_ = YES;
                        break;
                    case VT100CHARATTR_NORMAL:
                        bold_ = NO;
                        break;
                    case VT100CHARATTR_ITALIC:
                        italic_ = YES;
                        break;
                    case VT100CHARATTR_NOT_ITALIC:
                        italic_ = NO;
                        break;
                    case VT100CHARATTR_UNDER:
                        under_ = YES;
                        break;
                    case VT100CHARATTR_NOT_UNDER:
                        under_ = NO;
                        break;
                    case VT100CHARATTR_BLINK:
                        blink_ = YES;
                        break;
                    case VT100CHARATTR_STEADY:
                        blink_ = NO;
                        break;
                    case VT100CHARATTR_REVERSE:
                        reversed_ = YES;
                        break;
                    case VT100CHARATTR_POSITIVE:
                        reversed_ = NO;
                        break;
                    case VT100CHARATTR_FG_DEFAULT:
                        fgColorCode_ = ALTSEM_DEFAULT;
                        fgGreen_ = 0;
                        fgBlue_ = 0;
                        fgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_BG_DEFAULT:
                        bgColorCode_ = ALTSEM_DEFAULT;
                        bgGreen_ = 0;
                        bgBlue_ = 0;
                        bgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_FG_256:
                        /*
                         First subparam means:   # additional subparams:  Accepts optional params:
                         1: transparent          0                        NO
                         2: RGB                  3                        YES
                         3: CMY                  3                        YES
                         4: CMYK                 4                        YES
                         5: Indexed color        1                        NO
                         
                         Optional paramters go at position 7 and 8, and indicate toleranace as an
                         integer; and color space (0=CIELUV, 1=CIELAB). Example:
                         
                         CSI 38:2:255:128:64:0:5:1 m
                         
                         Also accepted for xterm compatibility, but never with optional parameters:
                         CSI 38;2;255;128;64 m
                         
                         Set the foreground color to red=255, green=128, blue=64 with a tolerance of
                         5 in the CIELAB color space. The 0 at the 6th position has no meaning and
                         is just a filler. */
                        
                        if (token.csi->subCount[i] > 0) {
                            // Preferred syntax using colons to delimit subparameters
                            if (token.csi->subCount[i] >= 2 && token.csi->sub[i][0] == 5) {
                                // CSI 38:5:P m
                                fgColorCode_ = token.csi->sub[i][1];
                                fgGreen_ = 0;
                                fgBlue_ = 0;
                                fgColorMode_ = ColorModeNormal;
                            } else if (token.csi->subCount[i] >= 4 && token.csi->sub[i][0] == 2) {
                                // CSI 38:2:R:G:B m
                                // 24-bit color
                                fgColorCode_ = token.csi->sub[i][1];
                                fgGreen_ = token.csi->sub[i][2];
                                fgBlue_ = token.csi->sub[i][3];
                                fgColorMode_ = ColorMode24bit;
                            }
                        } else if (token.csi->count - i >= 3 && token.csi->p[i + 1] == 5) {
                            // CSI 38;5;P m
                            fgColorCode_ = token.csi->p[i + 2];
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                            i += 2;
                        } else if (token.csi->count - i >= 5 && token.csi->p[i + 1] == 2) {
                            // CSI 38;2;R;G;B m
                            // 24-bit color support
                            fgColorCode_ = token.csi->p[i + 2];
                            fgGreen_ = token.csi->p[i + 3];
                            fgBlue_ = token.csi->p[i + 4];
                            fgColorMode_ = ColorMode24bit;
                            i += 4;
                        }
                        break;
                    case VT100CHARATTR_BG_256:
                        if (token.csi->subCount[i] > 0) {
                            // Preferred syntax using colons to delimit subparameters
                            if (token.csi->subCount[i] >= 2 && token.csi->sub[i][0] == 5) {
                                // CSI 48:5:P m
                                bgColorCode_ = token.csi->sub[i][1];
                                bgGreen_ = 0;
                                bgBlue_ = 0;
                                bgColorMode_ = ColorModeNormal;
                            } else if (token.csi->subCount[i] >= 4 && token.csi->sub[i][0] == 2) {
                                // CSI 48:2:R:G:B m
                                // 24-bit color
                                bgColorCode_ = token.csi->sub[i][1];
                                bgGreen_ = token.csi->sub[i][2];
                                bgBlue_ = token.csi->sub[i][3];
                                bgColorMode_ = ColorMode24bit;
                            }
                        } else if (token.csi->count - i >= 3 && token.csi->p[i + 1] == 5) {
                            // CSI 48;5;P m
                            bgColorCode_ = token.csi->p[i + 2];
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                            i += 2;
                        } else if (token.csi->count - i >= 5 && token.csi->p[i + 1] == 2) {
                            // CSI 48;2;R;G;B m
                            // 24-bit color
                            bgColorCode_ = token.csi->p[i + 2];
                            bgGreen_ = token.csi->p[i + 3];
                            bgBlue_ = token.csi->p[i + 4];
                            bgColorMode_ = ColorMode24bit;
                            i += 4;
                        }
                        break;
                    default:
                        // 8 color support
                        if (n >= VT100CHARATTR_FG_BLACK &&
                            n <= VT100CHARATTR_FG_WHITE) {
                            fgColorCode_ = n - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                        } else if (n >= VT100CHARATTR_BG_BLACK &&
                                   n <= VT100CHARATTR_BG_WHITE) {
                            bgColorCode_ = n - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                        }
                        // 16 color support
                        if (n >= VT100CHARATTR_FG_HI_BLACK &&
                            n <= VT100CHARATTR_FG_HI_WHITE) {
                            fgColorCode_ = n - VT100CHARATTR_FG_HI_BASE - COLORCODE_BLACK + 8;
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                        } else if (n >= VT100CHARATTR_BG_HI_BLACK &&
                                   n <= VT100CHARATTR_BG_HI_WHITE) {
                            bgColorCode_ = n - VT100CHARATTR_BG_HI_BASE - COLORCODE_BLACK + 8;
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                        }
                }
            }
        }
    } else if (token->type == VT100CSI_DECSTR) {
        [self resetSGR];
    }
}

- (NSColor *)colorForXtermCCSetPaletteString:(NSString *)argument colorNumberPtr:(int *)numberPtr {
    if ([argument length] == 7) {
        int n, r, g, b;
        int count = 0;
        count += sscanf([[argument substringWithRange:NSMakeRange(0, 1)] UTF8String], "%x", &n);
        if (count == 0) {
            unichar c = [argument characterAtIndex:0];
            n = c - 'a' + 10;
            // fg = 16 ('g')
            // bg = 17
            // bold = 18
            // selection = 19
            // selected text = 20
            // cursor = 21
            // cursor text = 22
            if (n >= 16 && n <= 22) {
                ++count;
            }
        }
        count += sscanf([[argument substringWithRange:NSMakeRange(1, 2)] UTF8String], "%x", &r);
        count += sscanf([[argument substringWithRange:NSMakeRange(3, 2)] UTF8String], "%x", &g);
        count += sscanf([[argument substringWithRange:NSMakeRange(5, 2)] UTF8String], "%x", &b);
        if (count == 4 &&
            n >= 0 &&
            n <= 22 &&
            r >= 0 &&
            r <= 255 &&
            g >= 0 &&
            g <= 255 &&
            b >= 0 &&
            b <= 255) {
            NSColor* theColor = [NSColor colorWithCalibratedRed:((double)r)/255.0
                                                          green:((double)g)/255.0
                                                           blue:((double)b)/255.0
                                                          alpha:1];
            *numberPtr = n;
            return theColor;
        }
    }
    return nil;
}

- (void)setMouseMode:(MouseMode)mode
{
    _mouseMode = mode;
    [delegate_ terminalMouseModeDidChangeTo:_mouseMode];
}

- (void)handleDeviceStatusReportWithToken:(VT100Token *)token withQuestion:(BOOL)withQuestion {
    if ([delegate_ terminalShouldSendReport]) {
        switch (token.csi->p[0]) {
            case 3: // response from VT100 -- Malfunction -- retry
                break;

            case 5: // Command from host -- Please report status
                [delegate_ terminalSendReport:[self.output reportStatus]];
                break;

            case 6: // Command from host -- Please report active position
                if (self.originMode) {
                    // This is compatible with Terminal but not old xterm :(. it always did what
                    // we do in the else clause. This behavior of xterm is fixed by Patch #297.
                    [delegate_ terminalSendReport:[self.output reportActivePositionWithX:[delegate_ terminalRelativeCursorX]
                                                                                Y:[delegate_ terminalRelativeCursorY]
                                                                     withQuestion:withQuestion]];
                } else {
                    [delegate_ terminalSendReport:[self.output reportActivePositionWithX:[delegate_ terminalCursorX]
                                                                                Y:[delegate_ terminalCursorY]
                                                                     withQuestion:withQuestion]];
                }
                break;

            case 0: // Response from VT100 -- Ready, No malfuctions detected
            default:
                break;
        }
    }
}

- (NSString *)decodedBase64PasteCommand:(NSString *)commandString {
    //
    // - write access
    //   ESC ] 5 2 ; Pc ; <base64 encoded string> ST
    //
    // - read access
    //   ESC ] 5 2 ; Pc ; ? ST
    //
    // Pc consists from:
    //   'p', 's', 'c', '0', '1', '2', '3', '4', '5', '6', '7'
    //
    // Note: Pc is ignored now.
    //
    const char *buffer = [commandString UTF8String];

    // ignore first parameter now
    while (strchr("psc01234567", *buffer)) {
        ++buffer;
    }
    if (*buffer != ';') {
        return nil; // fail to parse
    }
    ++buffer;
    if (*buffer == '?') { // PASTE64(OSC 52) read access
        // Now read access is not implemented due to security issues.
        return nil;
    }

    // decode base64 string.
    int destLength = apr_base64_decode_len(buffer);
    if (destLength < 1) {
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    if (resultLength < 0) {
        return nil;
    }

    // sanitize buffer
    const char *inputIterator = decodedBuffer;
    char *outputIterator = decodedBuffer;
    int outputLength = 0;
    for (int i = 0; i < resultLength + 1; ++i) {
        char c = *inputIterator;
        if (c == 0x00) {
            *outputIterator = 0; // terminate string with NULL
            break;
        }
        if (c > 0 && c < 0x20) { // if c is control character
            // check if c is TAB/LF/CR
            if (c != 0x9 && c != 0xa && c != 0xd) {
                // skip it
                ++inputIterator;
                continue;
            }
        }
        *outputIterator = c;
        ++inputIterator;
        ++outputIterator;
        ++outputLength;
    }
    [data setLength:outputLength];

    NSString *resultString = [[[NSString alloc] initWithData:data
                                                    encoding:[self encoding]] autorelease];
    return resultString;
}

- (void)executeToken:(VT100Token *)token {
    // Handle tmux stuff, which completely bypasses all other normal execution steps.
    if (token->type == DCS_TMUX) {
        [delegate_ terminalStartTmuxMode];
        return;
    } else if (token->type == TMUX_EXIT || token->type == TMUX_LINE) {
        [delegate_ terminalHandleTmuxInput:token];
        return;
    }
    
    // Handle sending input to pasteboard/receving files.
    if (receivingFile_) {
        if (token->type == VT100CC_BEL) {
            [delegate_ terminalDidFinishReceivingFile];
            receivingFile_ = NO;
            return;
        } else if (token->type == VT100_ASCIISTRING) {
            [delegate_ terminalDidReceiveBase64FileData:[token stringForAsciiData]];
            return;
        } else if (token->type == VT100CC_CR ||
                   token->type == VT100CC_LF ||
                   token->type == XTERMCC_SET_KVP) {
            return;
        } else {
            [delegate_ terminalFileReceiptEndedUnexpectedly];
            receivingFile_ = NO;
        }
    }
    if (token->savingData &&
        token->type != VT100_SKIP &&
        [delegate_ terminalIsAppendingToPasteboard]) {
        // We are probably copying text to the clipboard until esc]1337;EndCopy^G is received.
        if (token->type != XTERMCC_SET_KVP ||
            ![token.string hasPrefix:@"CopyToClipboard"]) {
            // Append text to clipboard except for initial command that turns on copying to
            // the clipboard.
            
            [delegate_ terminalAppendDataToPasteboard:token.savedData];
        }
    }

    // Disambiguate
    switch (token->type) {
        case VT100CSI_DECSLRM_OR_ANSICSI_SCP:
            if ([delegate_ terminalUseColumnScrollRegion]) {
                token->type = VT100CSI_DECSLRM;
                SET_PARAM_DEFAULT(token.csi, 0, 1);
                SET_PARAM_DEFAULT(token.csi, 1, 1);
            } else {
                token->type = ANSICSI_SCP;
                SET_PARAM_DEFAULT(token.csi, 0, 0);
            }
            break;
            
        default:
            break;
    }

    // Update internal state.
    [self executeModeUpdates:token];
    [self executeSGR:token];
    
    // Farm out work to the delegate.
    switch (token->type) {
            // our special code
        case VT100_STRING:
            [delegate_ terminalAppendString:token.string];
            break;
        case VT100_ASCIISTRING:
            [delegate_ terminalAppendAsciiData:token.asciiData];
            break;

        case VT100_UNKNOWNCHAR:
            break;
        case VT100_NOTSUPPORT:
            break;

            //  VT100 CC
        case VT100CC_ENQ:
            break;
        case VT100CC_BEL:
            [delegate_ terminalRingBell];
            break;
        case VT100CC_BS:
            [delegate_ terminalBackspace];
            break;
        case VT100CC_HT:
            [delegate_ terminalAppendTabAtCursor];
            break;
        case VT100CC_LF:
        case VT100CC_VT:
        case VT100CC_FF:
            [delegate_ terminalLineFeed];
            break;
        case VT100CC_CR:
            [delegate_ terminalCarriageReturn];
            break;
        case VT100CC_SO:
        case VT100CC_SI:
        case VT100CC_DC1:
        case VT100CC_DC3:
        case VT100CC_CAN:
        case VT100CC_SUB:
            break;
        case VT100CC_DEL:
            [delegate_ terminalDeleteCharactersAtCursor:1];
            break;

            // VT100 CSI
        case VT100CSI_CPR:
            break;
        case VT100CSI_CUB:
            [delegate_ terminalCursorLeft:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_CUD:
            [delegate_ terminalCursorDown:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_CUF:
            [delegate_ terminalCursorRight:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_CUP:
            [delegate_ terminalMoveCursorToX:token.csi->p[1] y:token.csi->p[0]];
            break;
        case VT100CSI_CUU:
            [delegate_ terminalCursorUp:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_DA:
            if ([delegate_ terminalShouldSendReport]) {
                [delegate_ terminalSendReport:[self.output reportDeviceAttribute]];
            }
            break;
        case VT100CSI_DA2:
            if ([delegate_ terminalShouldSendReport]) {
                [delegate_ terminalSendReport:[self.output reportSecondaryDeviceAttribute]];
            }
            break;
        case VT100CSI_DECALN:
            [delegate_ terminalShowTestPattern];
            break;
        case VT100CSI_DECDHL:
        case VT100CSI_DECDWL:
        case VT100CSI_DECID:
        case VT100CSI_DECKPAM:
        case VT100CSI_DECKPNM:
        case VT100CSI_DECLL:
            break;
        case VT100CSI_DECRC:
            [self restoreTextAttributes];
            [delegate_ terminalRestoreCursor];
            break;
        case VT100CSI_DECREPTPARM:
        case VT100CSI_DECREQTPARM:
            break;
        case VT100CSI_DECSC:
            [self saveTextAttributes];
            [delegate_ terminalSaveCursor];
            break;
        case VT100CSI_DECSTBM:
            [delegate_ terminalSetScrollRegionTop:token.csi->p[0] == 0 ? 0 : token.csi->p[0] - 1
                                           bottom:token.csi->p[1] == 0 ? [delegate_ terminalHeight] - 1 : token.csi->p[1] - 1];
            break;
        case VT100CSI_DECSWL:
        case VT100CSI_DECTST:
            break;
        case VT100CSI_DSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:NO];
            break;
        case VT100CSI_DECDSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:YES];
            break;
        case VT100CSI_ED:
            switch (token.csi->p[0]) {
                case 1:
                    [delegate_ terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
                    break;

                case 2:
                    [delegate_ terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];
                    break;

                case 3:
                    [delegate_ terminalClearScrollbackBuffer];
                    break;

                case 0:
                default:
                    [delegate_ terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_EL:
            switch (token.csi->p[0]) {
                case 1:
                    [delegate_ terminalEraseLineBeforeCursor:YES afterCursor:NO];
                    break;
                case 2:
                    [delegate_ terminalEraseLineBeforeCursor:YES afterCursor:YES];
                    break;
                case 0:
                    [delegate_ terminalEraseLineBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_HTS:
            [delegate_ terminalSetTabStopAtCursor];
            break;
        case VT100CSI_HVP:
            [delegate_ terminalMoveCursorToX:token.csi->p[1] y:token.csi->p[0]];
            break;
        case VT100CSI_NEL:
            [delegate_ terminalCarriageReturn];
            // fall through
        case VT100CSI_IND:
            [delegate_ terminalLineFeed];  // TODO Make sure this is kosher. How does xterm handle index with scroll regions?
            break;
        case VT100CSI_RI:
            [delegate_ terminalReverseIndex];
            break;
        case VT100CSI_RIS:
            // As far as I can tell, this is not part of the standard and should not be
            // supported.  -- georgen 7/31/11
            break;

        case ANSI_RIS:
            [delegate_ terminalResetPreservingPrompt:NO];
            break;
        case VT100CSI_RM:
            break;
        case VT100CSI_DECSTR:
            [delegate_ terminalSoftReset];
            break;
        case VT100CSI_DECSCUSR:
            switch (token.csi->p[0]) {
                case 0:
                case 1:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_BOX];
                    break;
                case 2:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_BOX];
                    break;
                case 3:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 4:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 5:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_VERTICAL];
                    break;
                case 6:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_VERTICAL];
                    break;
            }
            break;

        case VT100CSI_DECSLRM: {
            int scrollLeft = token.csi->p[0] - 1;
            int scrollRight = token.csi->p[1] - 1;
            int width = [delegate_ terminalWidth];
            if (scrollLeft < 0) {
                scrollLeft = 0;
            }
            if (scrollRight == 0) {
                scrollRight = width - 1;
            }
            // check wrong parameter
            if (scrollRight - scrollLeft < 1) {
                scrollLeft = 0;
                scrollRight = width - 1;
            }
            if (scrollRight > width - 1) {
                scrollRight = width - 1;
            }
            [delegate_ terminalSetLeftMargin:scrollLeft rightMargin:scrollRight];
            break;
        }

            /* My interpretation of this:
             * http://www.cl.cam.ac.uk/~mgk25/unicode.html#term
             * is that UTF-8 terminals should ignore SCS because
             * it's either a no-op (in the case of iso-8859-1) or
             * insane. Also, mosh made fun of Terminal and I don't
             * want to be made fun of:
             * "Only Mosh will never get stuck in hieroglyphs when a nasty
             * program writes to the terminal. (See Markus Kuhn's discussion of
             * the relationship between ISO 2022 and UTF-8.)"
             * http://mosh.mit.edu/#techinfo
             *
             * I'm going to throw this out there (4/15/2012) and see if this breaks
             * anything for anyone.
             *
             * UPDATE: In bug 1997, we see that it breaks line-drawing chars, which
             * are in SCS0. Indeed, mosh fails to draw these as well.
             *
             * UPDATE: In bug 2358, we see that SCS1 is also legitimately used in
             * UTF-8.
             *
             * Here's my take on the way things work. There are four charsets: G0
             * (default), G1, G2, and G3. They are switched between with codes like SI
             * (^O), SO (^N), LS2 (ESC n), and LS3 (ESC o). You can get the current
             * character set from [terminal_ charset], and that gives you a number from
             * 0 to 3 inclusive. It is an index into Screen's charsetUsesLineDrawingMode_ array.
             * In iTerm2, it is an array of booleans where 0 means normal behavior and 1 means
             * line-drawing. There should be a bunch of other values too (like
             * locale-specific char sets). This is pretty far away from the spec,
             * but it works well enough for common behavior, and it seems the spec
             * doesn't work well with common behavior (esp line drawing).
             */
        case VT100CSI_SCS0:
            [delegate_ terminalSetCharset:0 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS1:
            [delegate_ terminalSetCharset:1 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS2:
            [delegate_ terminalSetCharset:2 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS3:
            [delegate_ terminalSetCharset:3 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SGR:
        case VT100CSI_SM:
            break;
        case VT100CSI_TBC:
            switch (token.csi->p[0]) {
                case 3:
                    [delegate_ terminalRemoveTabStops];
                    break;

                case 0:
                    [delegate_ terminalRemoveTabStopAtCursor];
            }
            break;

        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            if (token.csi->p[0] == 3 && // DECCOLM
                self.allowColumnMode) {
                [delegate_ terminalSetWidth:(self.columnMode ? 132 : 80)];
            }
            break;

            // ANSI CSI
        case ANSICSI_CBT:
            [delegate_ terminalBackTab:token.csi->p[0]];
            break;
        case ANSICSI_CHA:
            [delegate_ terminalSetCursorX:token.csi->p[0]];
            break;
        case ANSICSI_VPA:
            [delegate_ terminalSetCursorY:token.csi->p[0]];
            break;
        case ANSICSI_VPR:
            [delegate_ terminalCursorDown:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case ANSICSI_ECH:
            [delegate_ terminalEraseCharactersAfterCursor:token.csi->p[0]];
            break;

        case STRICT_ANSI_MODE:
            self.strictAnsiMode = !self.strictAnsiMode;
            break;

        case ANSICSI_PRINT:
            switch (token.csi->p[0]) {
                case 4:
                    [delegate_ terminalPrintBuffer];
                    break;
                case 5:
                    [delegate_ terminalBeginRedirectingToPrintBuffer];
                    break;
                default:
                    [delegate_ terminalPrintScreen];
            }
            break;
        case ANSICSI_SCP:
            [delegate_ terminalSaveCursor];
            [delegate_ terminalSaveCharsetFlags];
            break;
        case ANSICSI_RCP:
            [delegate_ terminalRestoreCursor];
            [delegate_ terminalRestoreCharsetFlags];
            break;

            // XTERM extensions
        case XTERMCC_WIN_TITLE:
            [delegate_ terminalSetWindowTitle:token.string];
            break;
        case XTERMCC_WINICON_TITLE:
            [delegate_ terminalSetWindowTitle:token.string];
            [delegate_ terminalSetIconTitle:token.string];
            break;
        case XTERMCC_PASTE64: {
            NSString *decoded = [self decodedBase64PasteCommand:token.string];
            if (decoded) {
                [delegate_ terminalPasteString:decoded];
            }
            break;
        }
        case XTERMCC_FINAL_TERM:
            [self executeFinalTermToken:token];
            break;
        case XTERMCC_ICON_TITLE:
            [delegate_ terminalSetIconTitle:token.string];
            break;
        case XTERMCC_INSBLNK:
            [delegate_ terminalInsertEmptyCharsAtCursor:token.csi->p[0]];
            break;
        case XTERMCC_INSLN:
            [delegate_ terminalInsertBlankLinesAfterCursor:token.csi->p[0]];
            break;
        case XTERMCC_DELCH:
            [delegate_ terminalDeleteCharactersAtCursor:token.csi->p[0]];
            break;
        case XTERMCC_DELLN:
            [delegate_ terminalDeleteLinesAtCursor:token.csi->p[0]];
            break;
        case XTERMCC_WINDOWSIZE:
            [delegate_ terminalSetRows:MIN(token.csi->p[1], kMaxScreenRows)
                            andColumns:MIN(token.csi->p[2], kMaxScreenColumns)];
            break;
        case XTERMCC_WINDOWSIZE_PIXEL:
            [delegate_ terminalSetPixelWidth:token.csi->p[2]
                                      height:token.csi->p[1]];

            break;
        case XTERMCC_WINDOWPOS:
            [delegate_ terminalMoveWindowTopLeftPointTo:NSMakePoint(token.csi->p[1], token.csi->p[2])];
            break;
        case XTERMCC_ICONIFY:
            [delegate_ terminalMiniaturize:YES];
            break;
        case XTERMCC_DEICONIFY:
            [delegate_ terminalMiniaturize:NO];
            break;
        case XTERMCC_RAISE:
            [delegate_ terminalRaise:YES];
            break;
        case XTERMCC_LOWER:
            [delegate_ terminalRaise:NO];
            break;
        case XTERMCC_SU:
            [delegate_ terminalScrollUp:token.csi->p[0]];
            break;
        case XTERMCC_SD:
            [delegate_ terminalScrollDown:token.csi->p[0]];
            break;
        case XTERMCC_REPORT_WIN_STATE: {
            NSString *s = [NSString stringWithFormat:@"\033[%dt",
                           ([delegate_ terminalWindowIsMiniaturized] ? 2 : 1)];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_POS: {
            NSPoint topLeft = [delegate_ terminalWindowTopLeftPixelCoordinate];
            NSString *s = [NSString stringWithFormat:@"\033[3;%d;%dt",
                           (int)topLeft.x, (int)topLeft.y];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_PIX_SIZE: {
            // TODO: Some kind of adjustment for panes?
            NSString *s = [NSString stringWithFormat:@"\033[4;%d;%dt",
                           [delegate_ terminalWindowHeightInPixels],
                           [delegate_ terminalWindowWidthInPixels]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_SIZE: {
            NSString *s = [NSString stringWithFormat:@"\033[8;%d;%dt",
                           [delegate_ terminalHeight],
                           [delegate_ terminalWidth]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_SCREEN_SIZE: {
            NSString *s = [NSString stringWithFormat:@"\033[9;%d;%dt",
                           [delegate_ terminalScreenHeightInCells],
                           [delegate_ terminalScreenWidthInCells]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_ICON_TITLE: {
            NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                           [delegate_ terminalIconTitle]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_TITLE: {
            NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                           [delegate_ terminalWindowTitle]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_PUSH_TITLE: {
            switch (token.csi->p[1]) {
                case 0:
                    [delegate_ terminalPushCurrentTitleForWindow:YES];
                    [delegate_ terminalPushCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ terminalPushCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ terminalPushCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
        case XTERMCC_POP_TITLE: {
            switch (token.csi->p[1]) {
                case 0:
                    [delegate_ terminalPopCurrentTitleForWindow:YES];
                    [delegate_ terminalPopCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ terminalPopCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ terminalPopCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
            // Our iTerm specific codes
        case ITERM_GROWL:
            [delegate_ terminalPostGrowlNotification:token.string];
            break;
            
        case XTERMCC_SET_KVP:
            [self executeXtermSetKvp:token];
            break;

        case VT100CC_NULL:
        case VT100CC_SOH:
        case VT100_INVALID_SEQUENCE:
        case VT100_SKIP:
        case VT100_WAIT:
        case VT100CC_ACK:
        case VT100CC_DC2:
        case VT100CC_DC4:
        case VT100CC_DLE:
        case VT100CC_EM:
        case VT100CC_EOT:
        case VT100CC_ESC:
        case VT100CC_ETB:
        case VT100CC_ETX:
        case VT100CC_FS:
        case VT100CC_GS:
        case VT100CC_NAK:
        case VT100CC_RS:
        case VT100CC_STX:
        case VT100CC_SYN:
        case VT100CC_US:
        case VT100CSI_RESET_MODIFIERS:
        case VT100CSI_SCS:
        case VT100CSI_SET_MODIFIERS:
            break;

        case XTERMCC_PROPRIETARY_ETERM_EXT:
            [self executeXtermProprietaryExtermExtension:token];
            break;

        case XTERMCC_SET_PALETTE:
            [self executeXtermSetPalette:token];
            break;

        case XTERMCC_SET_RGB:
            [self executeXtermSetRgb:token];
            break;

        default:
            NSLog(@"Unexpected token type %d", (int)token->type);
            break;
    }
}

- (void)executeXtermSetRgb:(VT100Token *)token {
    // The format of this command is "<index>;rgb:<redhex>/<greenhex>/<bluehex>", e.g. "105;rgb:00/cc/ff"
    // TODO(georgen): xterm has extended this quite a bit and we're behind. Catch up.
    const char *s = [token.string UTF8String];
    int theIndex = 0;
    while (isdigit(*s)) {
        theIndex = 10*theIndex + *s++ - '0';
    }
    if (*s++ != ';') {
        return;
    }
    if (*s++ != 'r') {
        return;
    }
    if (*s++ != 'g') {
        return;
    }
    if (*s++ != 'b') {
        return;
    }
    if (*s++ != ':') {
        return;
    }
    int r = 0, g = 0, b = 0;
    
    while (isxdigit(*s)) {
        r = 16*r + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
    }
    if (*s++ != '/') {
        return;
    }
    while (isxdigit(*s)) {
        g = 16*g + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
    }
    if (*s++ != '/') {
        return;
    }
    while (isxdigit(*s)) {
        b = 16*b + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
    }
    if (theIndex >= 0 && theIndex <= 255 &&
        r >= 0 && r <= 255 &&
        g >= 0 && g <= 255 &&
        b >= 0 && b <= 255) {
        [delegate_ terminalSetColorTableEntryAtIndex:theIndex
                                               color:[NSColor colorWith8BitRed:r
                                                                         green:g
                                                                          blue:b]];
    }
}

- (void)executeXtermSetKvp:(VT100Token *)token {
    // argument is of the form key=value
    // key: Sequence of characters not = or ^G
    // value: Sequence of characters not ^G
    NSString* argument = token.string;
    NSRange eqRange = [argument rangeOfString:@"="];
    NSString* key;
    NSString* value;
    if (eqRange.location != NSNotFound) {
        key = [argument substringToIndex:eqRange.location];;
        value = [argument substringFromIndex:eqRange.location+1];
    } else {
        key = argument;
        value = @"";
    }
    if ([key isEqualToString:@"CursorShape"]) {
        // Value must be an integer. Bogusly, non-numbers are treated as 0.
        int shape = [value intValue];
        ITermCursorType shapeMap[] = { CURSOR_BOX, CURSOR_VERTICAL, CURSOR_UNDERLINE };
        if (shape >= 0 && shape < sizeof(shapeMap)/sizeof(int)) {
            [delegate_ terminalSetCursorType:shapeMap[shape]];
        }
    } else if ([key isEqualToString:@"RemoteHost"]) {
        [delegate_ terminalSetRemoteHost:value];
    } else if ([key isEqualToString:@"SetMark"]) {
        [delegate_ terminalSaveScrollPositionWithArgument:value];
    } else if ([key isEqualToString:@"StealFocus"]) {
        [delegate_ terminalStealFocus];
    } else if ([key isEqualToString:@"ClearScrollback"]) {
        [delegate_ terminalClearBuffer];
    } else if ([key isEqualToString:@"CurrentDir"]) {
        [delegate_ terminalCurrentDirectoryDidChangeTo:value];
    } else if ([key isEqualToString:@"SetProfile"]) {
        [delegate_ terminalProfileShouldChangeTo:(NSString *)value];
    } else if ([key isEqualToString:@"AddNote"]) {
        [delegate_ terminalAddNote:(NSString *)value show:YES];
    } else if ([key isEqualToString:@"AddHiddenNote"]) {
        [delegate_ terminalAddNote:(NSString *)value show:NO];
    } else if ([key isEqualToString:@"HighlightCursorLine"]) {
        [delegate_ terminalSetHighlightCursorLine:value.length ? [value boolValue] : YES];
    } else if ([key isEqualToString:@"CopyToClipboard"]) {
        [delegate_ terminalSetPasteboard:value];
    } else if ([key isEqualToString:@"File"]) {
        // Takes semicolon-delimited arguments.
        // File=<arg>;<arg>;...;<arg>
        // <arg> is one of:
        //   name=<base64-encoded filename>    Default: Unnamed file
        //   size=<integer file size>          Default: 0
        //   width=auto|<integer>px|<integer>  Default: auto
        //   height=auto|<integer>px|<integer> Default: auto
        //   preserveAspectRatio=<bool>        Default: yes
        //   inline=<bool>                     Default: no
        NSArray *parts = [value componentsSeparatedByString:@";"];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"size"] = @(0);
        dict[@"width"] = @"auto";
        dict[@"height"] = @"auto";
        dict[@"preserveAspectRatio"] = @YES;
        dict[@"inline"] = @NO;
        for (NSString *part in parts) {
            NSRange eq = [part rangeOfString:@"="];
            if (eq.location != NSNotFound && eq.location > 0) {
                NSString *left = [part substringToIndex:eq.location];
                NSString *right = [part substringFromIndex:eq.location + 1];
                dict[left] = right;
            } else {
                dict[part] = @"";
            }
        }
        
        NSString *widthString = dict[@"width"];
        VT100TerminalUnits widthUnits = kVT100TerminalUnitsCells;
        NSString *heightString = dict[@"height"];
        VT100TerminalUnits heightUnits = kVT100TerminalUnitsCells;
        int width = [widthString intValue];
        if ([widthString isEqualToString:@"auto"]) {
            widthUnits = kVT100TerminalUnitsAuto;
        } else if ([widthString hasSuffix:@"px"]) {
            widthUnits = kVT100TerminalUnitsPixels;
        }
        int height = [heightString intValue];
        if ([heightString isEqualToString:@"auto"]) {
            heightUnits = kVT100TerminalUnitsAuto;
        } else if ([heightString hasSuffix:@"px"]) {
            heightUnits = kVT100TerminalUnitsPixels;
        }
        
        NSString *name = [dict[@"name"] stringByBase64DecodingStringWithEncoding:NSISOLatin1StringEncoding];
        if (!name) {
            name = @"Unnamed file";
        }
        if ([dict[@"inline"] boolValue]) {
            [delegate_ terminalWillReceiveInlineFileNamed:name
                                                   ofSize:[dict[@"size"] intValue]
                                                    width:width
                                                    units:widthUnits
                                                   height:height
                                                    units:heightUnits
                                      preserveAspectRatio:[dict[@"preserveAspectRatio"] boolValue]];
        } else {
            [delegate_ terminalWillReceiveFileNamed:name ofSize:[dict[@"size"] intValue]];
        }
        receivingFile_ = YES;
    } else if ([key isEqualToString:@"BeginFile"]) {
        // DEPRECATED. Use File instead.
        // Takes 2-5 args separated by newline. First is filename, second is size in bytes.
        // Arg 3,4 are width,height in cells for an inline image.
        // Arg 5 is whether to preserve the aspect ratio for an inline image.
        NSArray *parts = [value componentsSeparatedByString:@"\n"];
        NSString *name = nil;
        int size = -1;
        if (parts.count >= 1) {
            name = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (parts.count >= 2) {
            size = [parts[1] intValue];
        }
        int width = 0, height = 0;
        VT100TerminalUnits widthUnits = kVT100TerminalUnitsCells, heightUnits = kVT100TerminalUnitsCells;
        if (parts.count >= 4) {
            NSString *widthString =
            [parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *heightString =
            [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            width = [widthString intValue];
            if ([widthString isEqualToString:@"auto"]) {
                widthUnits = kVT100TerminalUnitsAuto;
                width = 1;
            } else if ([widthString hasSuffix:@"px"]) {
                widthUnits = kVT100TerminalUnitsPixels;
            }
            height = [heightString intValue];
            if ([heightString isEqualToString:@"auto"]) {
                heightUnits = kVT100TerminalUnitsAuto;
                height = 1;
            } else if ([heightString hasSuffix:@"px"]) {
                heightUnits = kVT100TerminalUnitsPixels;
            }
        }
        BOOL preserveAspectRatio = YES;
        if (parts.count >= 5) {
            preserveAspectRatio = [parts[4] boolValue];
        }
        if (width > 0 && height > 0) {
            [delegate_ terminalWillReceiveInlineFileNamed:name
                                                   ofSize:size
                                                    width:width
                                                    units:widthUnits
                                                   height:height
                                                    units:heightUnits
                                      preserveAspectRatio:preserveAspectRatio];
        } else {
            [delegate_ terminalWillReceiveFileNamed:name ofSize:size];
        }
        receivingFile_ = YES;
    } else if ([key isEqualToString:@"EndFile"]) {
        [delegate_ terminalDidFinishReceivingFile];
        receivingFile_ = NO;
    } else if ([key isEqualToString:@"EndCopy"]) {
        [delegate_ terminalCopyBufferToPasteboard];
    } else if ([key isEqualToString:@"RequestAttention"]) {
        [delegate_ terminalRequestAttention:[value boolValue]];  // true: request, false: cancel
    }
}

- (void)executeXtermSetPalette:(VT100Token *)token {
    int n;
    NSColor *theColor = [self colorForXtermCCSetPaletteString:token.string
                                               colorNumberPtr:&n];
    if (theColor) {
        switch (n) {
            case 16:
                [delegate_ terminalSetForegroundColor:theColor];
                break;
            case 17:
                [delegate_ terminalSetBackgroundColor:theColor];
                break;
            case 18:
                [delegate_ terminalSetBoldColor:theColor];
                break;
            case 19:
                [delegate_ terminalSetSelectionColor:theColor];
                break;
            case 20:
                [delegate_ terminalSetSelectedTextColor:theColor];
                break;
            case 21:
                [delegate_ terminalSetCursorColor:theColor];
                break;
            case 22:
                [delegate_ terminalSetCursorTextColor:theColor];
                break;
            default:
                [delegate_ terminalSetColorTableEntryAtIndex:n color:theColor];
                break;
        }
    }
}

- (void)executeXtermProprietaryExtermExtension:(VT100Token *)token {
    NSString* argument = token.string;
    NSArray* parts = [argument componentsSeparatedByString:@";"];
    NSString* func = nil;
    if ([parts count] >= 1) {
        func = [parts objectAtIndex:0];
    }
    if (func) {
        if ([func isEqualToString:@"1"]) {
            // Adjusts a color modifier. This attempts to roughly follow the pattern that Eterm
            // estabilshed.
            //
            // ESC ] 6 ; 1 ; class ; color ; attribute ; value BEL
            //
            // Adjusts a color modifier.
            // class: determines which image class will have its color modifier altered:
            //   legal values: bg (background), or a number 0-15 (color palette entries).
            // color: The color component to modify.
            //   legal values: red, green, or blue.
            // attribute: how to modify it.
            //   legal values: brightness
            // value: the new value for this attribute.
            //   legal values: decimal integers in 0-255.
            if ([parts count] == 4) {
                NSString* class = [parts objectAtIndex:1];
                NSString* color = [parts objectAtIndex:2];
                NSString* attribute = [parts objectAtIndex:3];
                if ([class isEqualToString:@"bg"] &&
                    [color isEqualToString:@"*"] &&
                    [attribute isEqualToString:@"default"]) {
                    [delegate_ terminalSetCurrentTabColor:nil];
                }
            } else if ([parts count] == 5) {
                NSString* class = [parts objectAtIndex:1];
                NSString* color = [parts objectAtIndex:2];
                NSString* attribute = [parts objectAtIndex:3];
                NSString* value = [parts objectAtIndex:4];
                if ([class isEqualToString:@"bg"] &&
                    [attribute isEqualToString:@"brightness"]) {
                    double numValue = MIN(1, ([value intValue] / 255.0));
                    if (numValue >= 0 && numValue <= 1) {
                        if ([color isEqualToString:@"red"]) {
                            [delegate_ terminalSetTabColorRedComponentTo:numValue];
                        } else if ([color isEqualToString:@"green"]) {
                            [delegate_ terminalSetTabColorGreenComponentTo:numValue];
                        } else if ([color isEqualToString:@"blue"]) {
                            [delegate_ terminalSetTabColorBlueComponentTo:numValue];
                        }
                    }
                }
            }
        }
    }
}

- (void)executeFinalTermToken:(VT100Token *)token {
    NSString *value = token.string;
    NSArray *args = [value componentsSeparatedByString:@";"];
    if (args.count == 0) {
        return;
    }
   
    NSString *command = args[0];
    if (command.length != 1) {
        return;
    }
    switch ([command characterAtIndex:0]) {
        case 'A':
            // Sequence marking the start of the command prompt (FTCS_PROMPT_START)
            [delegate_ terminalPromptDidStart];
            break;
            
        case 'B':
            // Sequence marking the start of the command read from the command prompt
            // (FTCS_COMMAND_START)
            if (!inCommand_) {
                [delegate_ terminalCommandDidStart];
                inCommand_ = YES;
            }
            break;
            
        case 'C':
            // Sequence marking the end of the command read from the command prompt (FTCS_COMMAND_END)
            if (inCommand_) {
                [delegate_ terminalCommandDidEnd];
                inCommand_ = NO;
            }
            break;
            
        case 'D':
            // Return code of last command
            if (args.count >= 2) {
                int returnCode = [args[1] intValue];
                [delegate_ terminalReturnCodeOfLastCommandWas:returnCode];
            }

        case 'E':
            // Semantic text is starting.
            // First argument:
            //    1: file name
            //    2: directory name
            //    3: pid
            if (args.count >= 2) {
                VT100TerminalSemanticTextType type = [args[1] intValue];
                if (type >= 1 && type < kVT100TerminalSemanticTextTypeMax) {
                    [delegate_ terminalSemanticTextDidStartOfType:type];
                }
            }
            break;
            
        case 'F':
            // Semantic text is ending.
            // First argument is same as 'D'.
            if (args.count >= 2) {
                VT100TerminalSemanticTextType type = [args[1] intValue];
                if (type >= 1 && type < kVT100TerminalSemanticTextTypeMax) {
                    [delegate_ terminalSemanticTextDidEndOfType:type];
                }
            }
            break;
            
        case 'G':
            // Update progress bar.
            // First argument: perecentage
            // Second argument: title
            if (args.count == 1) {
                [delegate_ terminalProgressDidFinish];
            } else {
                int percent = [args[1] intValue];
                double fraction = MAX(MIN(1, 100.0 / (double)percent), 0);
                NSString *label = nil;
                
                if (args.count >= 3) {
                    label = args[2];
                }

                [delegate_ terminalProgressAt:fraction label:label];
            }
            break;

        case 'H':
            // Terminal command.
            [delegate_ terminalFinalTermCommand:[args subarrayWithRange:NSMakeRange(1, args.count - 1)]];
            break;
    }
}

@end
