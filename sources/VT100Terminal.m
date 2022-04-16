#import "VT100Terminal.h"

#include "sixel.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermParser.h"
#import "iTermPromise.h"
#import "iTermURLStore.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "VT100DCSParser.h"
#import "VT100Parser.h"

#import <apr-1/apr_base64.h>  // for xterm's base64 decoding (paste64)
#include <curses.h>
#include <term.h>

NSString *const kGraphicRenditionBoldKey = @"Bold";
NSString *const kGraphicRenditionBlinkKey = @"Blink";
NSString *const kGraphicRenditionInvisibleKey = @"Invisible";
NSString *const kGraphicRenditionUnderlineKey = @"Underline";
NSString *const kGraphicRenditionStrikethroughKey = @"Strikethrough";
NSString *const kGraphicRenditionUnderlineStyle = @"Underline Style";
NSString *const kGraphicRenditionReversedKey = @"Reversed";
NSString *const kGraphicRenditionFaintKey = @"Faint";
NSString *const kGraphicRenditionItalicKey = @"Italic";
NSString *const kGraphicRenditionForegroundColorCodeKey = @"FG Color/Red";
NSString *const kGraphicRenditionForegroundGreenKey = @"FG Green";
NSString *const kGraphicRenditionForegroundBlueKey = @"FG Blue";
NSString *const kGraphicRenditionForegroundModeKey = @"FG Mode";
NSString *const kGraphicRenditionBackgroundColorCodeKey = @"BG Color/Red";
NSString *const kGraphicRenditionBackgroundGreenKey = @"BG Green";
NSString *const kGraphicRenditionBackgroundBlueKey = @"BG Blue";
NSString *const kGraphicRenditionBackgroundModeKey = @"BG Mode";

NSString *const kGraphicRenditionHasUnderlineColorKey = @"Has underline color";
NSString *const kGraphicRenditionUnderlineColorCodeKey = @"Underline Color/Red";
NSString *const kGraphicRenditionUnderlineGreenKey = @"Underline Green";
NSString *const kGraphicRenditionUnderlineBlueKey = @"Underline Blue";
NSString *const kGraphicRenditionUnderlineModeKey = @"Underline Mode";

NSString *const kSavedCursorPositionKey = @"Position";
NSString *const kSavedCursorCharsetKey = @"Charset";
NSString *const kSavedCursorLineDrawingArrayKey = @"Line Drawing Flags";
NSString *const kSavedCursorGraphicRenditionKey = @"Graphic Rendition";
NSString *const kSavedCursorOriginKey = @"Origin";
NSString *const kSavedCursorWraparoundKey = @"Wraparound";
NSString *const kSavedCursorUnicodeVersion = @"Unicode Version";
NSString *const kSavedCursorProtectedMode = @"Protected Mode";

NSString *const kTerminalStateTermTypeKey = @"Term Type";
NSString *const kTerminalStateAnswerBackStringKey = @"Answerback String";
NSString *const kTerminalStateStringEncodingKey = @"String Encoding";
NSString *const kTerminalStateCanonicalEncodingKey = @"Canonical String Encoding";
NSString *const kTerminalStateReportFocusKey = @"Report Focus";
NSString *const kTerminalStateReverseVideoKey = @"Reverse Video";
NSString *const kTerminalStateOriginModeKey = @"Origin Mode";
NSString *const kTerminalStateMoreFixKey = @"More-Fix";
NSString *const kTerminalStateWraparoundModeKey = @"Wraparound Mode";
NSString *const kTerminalStateReverseWraparoundModeKey = @"Reverse Wraparound Mode";
NSString *const kTerminalStateIsAnsiKey = @"Is ANSI";
NSString *const kTerminalStateAutorepeatModeKey = @"Autorepeat Mode";
NSString *const kTerminalStateInsertModeKey = @"Insert Mode";
NSString *const kTerminalStateSendReceiveModeKey = @"Send/Receive Mode";
NSString *const kTerminalStateCharsetKey = @"Charset";
NSString *const kTerminalStateMouseModeKey = @"Mouse Mode";
NSString *const kTerminalStatePreviousMouseModeKey = @"Previous Mouse Mode";
NSString *const kTerminalStateMouseFormatKey = @"Mouse Format";
NSString *const kTerminalStateCursorModeKey = @"Cursor Mode";
NSString *const kTerminalStateKeypadModeKey = @"Keypad Mode";
NSString *const kTerminalStateAllowKeypadModeKey = @"Allow Keypad Mode";
NSString *const kTerminalStateAllowPasteBracketing = @"Allow Paste Bracketing";
NSString *const kTerminalStateBracketedPasteModeKey = @"Bracketed Paste Mode";
NSString *const kTerminalStateAnsiModeKey = @"ANSI Mode";
NSString *const kTerminalStateNumLockKey = @"Numlock";
NSString *const kTerminalStateGraphicRenditionKey = @"Graphic Rendition";
NSString *const kTerminalStateMainSavedCursorKey = @"Main Saved Cursor";
NSString *const kTerminalStateAltSavedCursorKey = @"Alt Saved Cursor";
NSString *const kTerminalStateAllowColumnModeKey = @"Allow Column Mode";
NSString *const kTerminalStateColumnModeKey = @"Column Mode";
NSString *const kTerminalStateDisableSMCUPAndRMCUPKey = @"Disable Alt Screen";
NSString *const kTerminalStateSoftAlternateScreenModeKey = @"Soft Alternate Screen Mode";
NSString *const kTerminalStateInCommandKey = @"In Command";
NSString *const kTerminalStateUnicodeVersionStack = @"Unicode Version Stack";
NSString *const kTerminalStateURL_DEPRECATED = @"URL";  // This was stored as an NSURL (which didn't work at all) and getting an URL code from an URL is hard (because it depends on the order of state restoration) and ultimately it's not that important to preserve this bit of state so it has been abandoned.
NSString *const kTerminalStateURLParams_DEPRECATED = @"URL Params";
NSString *const kTerminalStateReportKeyUp = @"Report Key Up";
NSString *const kTerminalStateMetaSendsEscape = @"Meta Sends Escape";
NSString *const kTerminalStateSendModifiers = @"Send Modifiers";
NSString *const kTerminalStateKeyReportingModeStack_Deprecated = @"Key Reporting Mode Stack";  // deprecated
NSString *const kTerminalStateKeyReportingModeStack_Main = @"Main Key Reporting Mode Stack";
NSString *const kTerminalStateKeyReportingModeStack_Alternate = @"Alternate Key Reporting Mode Stack";
NSString *const kTerminalStateSynchronizedUpdates = @"Synchronized Updates";
NSString *const kTerminalStatePreserveScreenOnDECCOLM = @"Preserve Screen On DECCOLM";
NSString *const kTerminalStateSavedColors = @"Saved Colors";  // For XTPUSHCOLORS/XTPOPCOLORS
NSString *const kTerminalStateAlternateScrollMode = @"Alternate Scroll Mode";
NSString *const kTerminalStateSGRStack = @"SGR Stack";
NSString *const kTerminalStateDECSACE = @"DECSACE";
NSString *const kTerminalStateProtectedMode = @"Protected Mode";

static const size_t VT100TerminalMaxSGRStackEntries = 10;

@interface VT100Terminal ()
@property(nonatomic, assign) BOOL reverseVideo;
@property(nonatomic, assign) BOOL originMode;
@property(nonatomic, assign) BOOL moreFix;
@property(nonatomic, assign) BOOL isAnsi;
@property(nonatomic, assign) BOOL autorepeatMode;
@property(nonatomic, assign) int charset;
@property(nonatomic, assign) BOOL allowColumnMode;
@property(nonatomic, assign) BOOL columnMode;  // YES=132 Column, NO=80 Column
@property(nonatomic, assign) BOOL disableSmcupRmcup;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) NSString *urlParams;

@end

#define NUM_CHARSETS 4

typedef struct {
    VT100GridCoord position;
    int charset;
    BOOL lineDrawing[NUM_CHARSETS];
    VT100GraphicRendition graphicRendition;
    BOOL origin;
    BOOL wraparound;
    NSInteger unicodeVersion;
    VT100TerminalProtectedMode protectedMode;
} VT100SavedCursor;

typedef enum {
    VT100SGRStackAttributeBold = 1,
    VT100SGRStackAttributeFaint = 2,
    VT100SGRStackAttributeItalicized = 3,
    VT100SGRStackAttributeUnderlined = 4,
    VT100SGRStackAttributeBlink = 5,
    VT100SGRStackAttributeInverse = 7,
    VT100SGRStackAttributeInvisible = 8,
    VT100SGRStackAttributeStrikethrough = 9,
    VT100SGRStackAttributeDoubleUnderline = 21,
    VT100SGRStackAttributeForegroundColor = 30,
    VT100SGRStackAttributeBackgroundColor = 31,
} VT100SGRStackAttribute;

typedef struct {
    VT100GraphicRendition graphicRendition;
    VT100SGRStackAttribute elements[VT100CSIPARAM_MAX];
    int numElements;
} VT100TerminalSGRStackEntry;

@interface VT100Terminal()
@property (nonatomic, strong, readwrite) NSMutableArray<NSNumber *> *sendModifiers;
@end

@implementation VT100Terminal {
    // In FinalTerm command mode (user is at the prompt typing a command).
    BOOL inCommand_;

    BOOL numLock_;           // YES=ON, NO=OFF, default=YES;

    VT100SavedCursor mainSavedCursor_;
    VT100SavedCursor altSavedCursor_;

    NSMutableArray *_unicodeVersionStack;

    // Code for the current hypertext link, or 0 if not in a hypertext link.
    unsigned int _currentURLCode;

    BOOL _softAlternateScreenMode;
    NSMutableArray<NSNumber *> *_mainKeyReportingModeStack;
    NSMutableArray<NSNumber *> *_alternateKeyReportingModeStack;
    VT100SavedColors *_savedColors;
    VT100TerminalSGRStackEntry _sgrStack[VT100TerminalMaxSGRStackEntries];
    int _sgrStackSize;
    BOOL _isScreenLike;
}

@synthesize receivingFile = receivingFile_;
@synthesize graphicRendition = graphicRendition_;

#define DEL  0x7f

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

// Prevents runaway memory usage
static const int kMaxScreenColumns = 4096;
static const int kMaxScreenRows = 4096;

#pragma mark - Instance methods

- (instancetype)init {
    self = [super init];
    if (self) {
        _output = [[VT100Output alloc] init];
        _encoding = _canonicalEncoding = NSASCIIStringEncoding;
        _parser = [[VT100Parser alloc] init];
        _parser.encoding = _encoding;

        _wraparoundMode = YES;
        _reverseWraparoundMode = NO;
        _autorepeatMode = YES;
        graphicRendition_.fgColorCode = ALTSEM_DEFAULT;
        graphicRendition_.fgColorMode = ColorModeAlternate;
        graphicRendition_.bgColorCode = ALTSEM_DEFAULT;
        graphicRendition_.bgColorMode = ColorModeAlternate;
        _mouseMode = MOUSE_REPORTING_NONE;
        _previousMouseMode = MOUSE_REPORTING_NORMAL;
        _mouseFormat = MOUSE_FORMAT_XTERM;

        _allowKeypadMode = YES;
        self.allowPasteBracketing = YES;
        _sendModifiers = [@[ @-1, @-1, @-1, @-1, @-1 ] mutableCopy];
        _mainKeyReportingModeStack = [[NSMutableArray alloc] init];
        _alternateKeyReportingModeStack = [[NSMutableArray alloc] init];
        numLock_ = YES;
        [self saveCursor];  // initialize save area
        _unicodeVersionStack = [[NSMutableArray alloc] init];
        _savedColors = [[VT100SavedColors alloc] init];
    }
    return self;
}

- (void)stopReceivingFile {
    DLog(@"%@", [NSThread callStackSymbols]);
    receivingFile_ = NO;
}

- (void)setEncoding:(NSStringEncoding)encoding {
    [self setEncoding:encoding canonical:YES];
}

- (void)setEncoding:(NSStringEncoding)encoding canonical:(BOOL)canonical {
    self.dirty = YES;
    if (canonical) {
        _canonicalEncoding = encoding;
    }
    _encoding = encoding;
    _parser.encoding = encoding;
}

- (void)setTermType:(NSString *)termtype {
    self.dirty = YES;
    DLog(@"setTermType:%@", termtype);
    _termType = [termtype copy];
    _isScreenLike = [termtype containsString:@"screen"];

    self.allowKeypadMode = [_termType rangeOfString:@"xterm"].location != NSNotFound;
    _output.termType = _termType;
    if ([termtype isEqualToString:@"VT100"]) {
        _output.vtLevel = VT100EmulationLevel100;
    } else if ([termtype hasPrefix:@"VT2"] || [termtype hasPrefix:@"VT3"]) {
        _output.vtLevel = VT100EmulationLevel200;
    } else {
        _output.vtLevel = VT100EmulationLevel400;
    }
    self.isAnsi = [_termType rangeOfString:@"ANSI"
                                   options:NSCaseInsensitiveSearch | NSAnchoredSearch ].location !=  NSNotFound;
    [_delegate terminalTypeDidChange];
}

- (void)setAnswerBackString:(NSString *)s {
    self.dirty = YES;
    s = [s stringByExpandingVimSpecialCharacters];
    _answerBackString = [s copy];
}

- (void)setForeground24BitColor:(NSColor *)color {
    self.dirty = YES;
    graphicRendition_.fgColorCode = color.redComponent * 255.0;
    graphicRendition_.fgGreen = color.greenComponent * 255.0;
    graphicRendition_.fgBlue = color.blueComponent * 255.0;
    graphicRendition_.fgColorMode = ColorMode24bit;
}

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem {
    self.dirty = YES;
    graphicRendition_.fgColorCode = fgColorCode;
    graphicRendition_.fgColorMode = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem {
    self.dirty = YES;
    graphicRendition_.bgColorCode = bgColorCode;
    graphicRendition_.bgColorMode = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)setSoftAlternateScreenMode:(BOOL)softAlternateScreenMode {
    if (softAlternateScreenMode == _softAlternateScreenMode) {
        return;
    }
    self.dirty = YES;
    _softAlternateScreenMode = softAlternateScreenMode;
    [self.delegate terminalSoftAlternateScreenModeDidChange];
}

- (void)setReverseVideo:(BOOL)reverseVideo {
    self.dirty = YES;
    _reverseVideo = reverseVideo;
}

- (void)setOriginMode:(BOOL)originMode {
    DLog(@"setOriginMode:%@\n%@", @(originMode), [NSThread callStackSymbols]);
    self.dirty = YES;
    _originMode = originMode;
}

- (void)setMoreFix:(BOOL)moreFix {
    self.dirty = YES;
    _moreFix = moreFix;
}

- (void)resetCharset {
    self.charset = 0;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [_delegate terminalSetCharset:i toLineDrawingMode:NO];
    }
}

- (void)commonReset {
    DLog(@"TERMINAL RESET");
    self.dirty = YES;
    self.cursorMode = NO;
    _reverseVideo = NO;
    _originMode = NO;
    _moreFix = NO;
    self.wraparoundMode = YES;
    self.reverseWraparoundMode = NO;
    self.autorepeatMode = YES;
    self.keypadMode = NO;
    self.reportKeyUp = NO;
    self.metaSendsEscape = NO;
    self.alternateScrollMode = NO;
    self.synchronizedUpdates = NO;
    self.preserveScreenOnDECCOLM = NO;
    self.insertMode = NO;
    self.sendReceiveMode = NO;
    self.bracketedPasteMode = NO;
    self.charset = 0;
    [self resetGraphicRendition];
    self.mouseMode = MOUSE_REPORTING_NONE;
    self.mouseFormat = MOUSE_FORMAT_XTERM;
    [self saveCursor];  // reset saved text attributes
    [_delegate terminalMouseModeDidChangeTo:_mouseMode];
    [_delegate terminalSetUseColumnScrollRegion:NO];
    self.reportFocus = NO;
    self.protectedMode = VT100TerminalProtectedModeNone;
    self.allowColumnMode = NO;
    receivingFile_ = NO;
    _copyingToPasteboard = NO;
    _encoding = _canonicalEncoding;
    _parser.encoding = _canonicalEncoding;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        mainSavedCursor_.lineDrawing[i] = NO;
        altSavedCursor_.lineDrawing[i] = NO;
    }
    [_mainKeyReportingModeStack removeAllObjects];
    [_alternateKeyReportingModeStack removeAllObjects];
    [self resetSavedCursorPositions];
    [_delegate terminalShowPrimaryBuffer];
    self.softAlternateScreenMode = NO;
    [self resetSendModifiersWithSideEffects:NO];
    [self.delegate terminalDidChangeSendModifiers];
}

- (void)resetSendModifiersWithSideEffects:(BOOL)sideEffects {
    DLog(@"reset send modifiers with side effects=%@", @(sideEffects));
    self.dirty = YES;
    for (int i = 0; i < NUM_MODIFIABLE_RESOURCES; i++) {
        _sendModifiers[i] = @-1;
    }
    self.dirty = YES;
    [_mainKeyReportingModeStack removeAllObjects];
    [_alternateKeyReportingModeStack removeAllObjects];
    if (sideEffects) {
        [self.delegate terminalDidChangeSendModifiers];
    }
}

- (void)gentleReset {
    [self commonReset];
    [_delegate terminalSetCursorVisible:YES];
}

- (void)resetByUserRequest:(BOOL)userInitiated {
    [self resetAllowingResize:YES preservePrompt:userInitiated resetParser:userInitiated modifyContent:YES];
}

- (void)resetForRelaunch {
    [self finishResettingParser:YES
                 preservePrompt:NO
                  modifyContent:NO];
}

- (void)setWidth:(int)width
  preserveScreen:(BOOL)preserveScreen
   updateRegions:(BOOL)updateRegions
    moveCursorTo:(VT100GridCoord)newCursorCoord
      completion:(void (^)(void))completion {
    [_delegate terminalSetWidth:width
                 preserveScreen:preserveScreen
                  updateRegions:updateRegions
                   moveCursorTo:newCursorCoord
                     completion:completion];
}

- (void)resetAllowingResize:(BOOL)canResize
             preservePrompt:(BOOL)preservePrompt
                resetParser:(BOOL)resetParser
              modifyContent:(BOOL)modifyContent {
    if (canResize && _columnMode) {
        __weak __typeof(self) weakSelf = self;
        [self setWidth:80
        preserveScreen:NO
        updateRegions:NO
          moveCursorTo:VT100GridCoordMake(-1, -1)
            completion:^{
            [weakSelf finishResettingParser:resetParser
                             preservePrompt:preservePrompt
                              modifyContent:modifyContent];
        }];
        return;
    }
    [self finishResettingParser:resetParser
                 preservePrompt:preservePrompt
                  modifyContent:modifyContent];
}

- (void)finishResettingParser:(BOOL)resetParser
               preservePrompt:(BOOL)preservePrompt
                modifyContent:(BOOL)modifyContent {
    self.columnMode = NO;
    [self commonReset];
    if (resetParser) {
        [_parser reset];
    }
    [_delegate terminalResetPreservingPrompt:preservePrompt modifyContent:modifyContent];
}

- (void)resetForTmuxUnpause {
    [self finishResettingParser:YES
                 preservePrompt:NO
                  modifyContent:YES];
}

- (void)setWraparoundMode:(BOOL)mode {
    if (mode != _wraparoundMode) {
        self.dirty = YES;
        _wraparoundMode = mode;
        [_delegate terminalWraparoundModeDidChangeTo:mode];
    }
}

- (void)setReverseWraparoundMode:(BOOL)reverseWraparoundMode {
    self.dirty = YES;
    _reverseWraparoundMode = reverseWraparoundMode;
}

- (void)setIsAnsi:(BOOL)isAnsi {
    self.dirty = YES;
    _isAnsi = isAnsi;
}

- (void)setAutorepeatMode:(BOOL)autorepeatMode {
    self.dirty = YES;
    _autorepeatMode = autorepeatMode;
}

- (void)setSendReceiveMode:(BOOL)sendReceiveMode {
    self.dirty = YES;
    _sendReceiveMode = sendReceiveMode;
}

- (void)setCharset:(int)charset {
    self.dirty = YES;
    _charset = charset;
}

- (void)setCursorMode:(BOOL)cursorMode {
    self.dirty = YES;
    _cursorMode = cursorMode;
    _output.cursorMode = cursorMode;
}

- (void)setMetaSendsEscape:(BOOL)metaSendsEscape {
    self.dirty = YES;
    _metaSendsEscape = metaSendsEscape;
}

- (void)setAlternateScrollMode:(BOOL)alternateScrollMode {
    self.dirty = YES;
    _alternateScrollMode = alternateScrollMode;
}

- (void)setDecsaceRectangleMode:(BOOL)decsaceRectangleMode {
    self.dirty = YES;
    _decsaceRectangleMode = decsaceRectangleMode;
}

- (void)setAllowPasteBracketing:(BOOL)allowPasteBracketing {
    self.dirty = YES;
    _allowPasteBracketing = allowPasteBracketing;
}

- (void)setAllowColumnMode:(BOOL)allowColumnMode {
    self.dirty = YES;
    _allowColumnMode = allowColumnMode;
}

- (void)setColumnMode:(BOOL)columnMode {
    self.dirty = YES;
    _columnMode = columnMode;
}

- (void)setDisableSmcupRmcup:(BOOL)value {
    self.dirty = YES;
    _disableSmcupRmcup = value;
}

- (void)setPreserveScreenOnDECCOLM:(BOOL)preserveScreenOnDECCOLM {
    self.dirty = YES;
    _preserveScreenOnDECCOLM = preserveScreenOnDECCOLM;
}

- (void)setMouseFormat:(MouseFormat)mouseFormat {
    self.dirty = YES;
    _mouseFormat = mouseFormat;
    _output.mouseFormat = mouseFormat;
}

- (void)setKeypadMode:(BOOL)mode {
    [self forceSetKeypadMode:(mode && self.allowKeypadMode)];
}

- (void)forceSetKeypadMode:(BOOL)mode {
    self.dirty = YES;
    _keypadMode = mode;
    _output.keypadMode = _keypadMode;
    [self.delegate terminalApplicationKeypadModeDidChange:mode];
}

- (void)setAllowKeypadMode:(BOOL)allow {
    self.dirty = YES;
    _allowKeypadMode = allow;
    if (!allow) {
        self.keypadMode = NO;
    }
}

- (void)setReportKeyUp:(BOOL)reportKeyUp {
    if (reportKeyUp == _reportKeyUp) {
        return;
    }
    self.dirty = YES;
    _reportKeyUp = reportKeyUp;
    [self.delegate terminalReportKeyUpDidChange:reportKeyUp];
}

- (VT100TerminalKeyReportingFlags)keyReportingFlags {
    if (self.currentKeyReportingModeStack.count) {
        return self.currentKeyReportingModeStack.lastObject.intValue;
    }
    switch (_sendModifiers[4].intValue) {
        case 0:
            return VT100TerminalKeyReportingFlagsNone;
        case 1:
            return VT100TerminalKeyReportingFlagsDisambiguateEscape;
        default:
            return VT100TerminalKeyReportingFlagsNone;
    }
}

- (NSMutableArray<NSNumber *> *)currentKeyReportingModeStack {
    if ([self.delegate terminalIsInAlternateScreenMode]) {
        return _alternateKeyReportingModeStack;
    }
    return _mainKeyReportingModeStack;
}

- (void)updateExternalAttributes {
    if (!graphicRendition_.hasUnderlineColor && _currentURLCode == 0) {
        _externalAttributes = nil;
        return;
    }
    _externalAttributes = [[iTermExternalAttribute alloc] initWithUnderlineColor:graphicRendition_.underlineColor
                                                                         urlCode:_currentURLCode];
}

- (screen_char_t)foregroundColorCode {
    screen_char_t result = { 0 };
    if (graphicRendition_.reversed) {
        if (graphicRendition_.bgColorMode == ColorModeAlternate &&
            graphicRendition_.bgColorCode == ALTSEM_DEFAULT) {
            result.foregroundColor = ALTSEM_REVERSED_DEFAULT;
        } else {
            result.foregroundColor = graphicRendition_.bgColorCode;
        }
        result.fgGreen = graphicRendition_.bgGreen;
        result.fgBlue = graphicRendition_.bgBlue;
        result.foregroundColorMode = graphicRendition_.bgColorMode;
    } else {
        result.foregroundColor = graphicRendition_.fgColorCode;
        result.fgGreen = graphicRendition_.fgGreen;
        result.fgBlue = graphicRendition_.fgBlue;
        result.foregroundColorMode = graphicRendition_.fgColorMode;
    }
    result.bold = graphicRendition_.bold;
    result.faint = graphicRendition_.faint;
    result.italic = graphicRendition_.italic;
    result.underline = graphicRendition_.underline;
    result.strikethrough = graphicRendition_.strikethrough;
    result.underlineStyle = graphicRendition_.underlineStyle;
    result.blink = graphicRendition_.blink;
    result.invisible = graphicRendition_.invisible;
    result.image = NO;
    result.inverse = graphicRendition_.reversed;
    result.guarded = _protectedMode != VT100TerminalProtectedModeNone;
    result.unused = 0;
    return result;
}

- (screen_char_t)backgroundColorCode {
    screen_char_t result = { 0 };
    if (graphicRendition_.reversed) {
        if (graphicRendition_.fgColorMode == ColorModeAlternate &&
            graphicRendition_.fgColorCode == ALTSEM_DEFAULT) {
            result.backgroundColor = ALTSEM_REVERSED_DEFAULT;
        } else {
            result.backgroundColor = graphicRendition_.fgColorCode;
        }
        result.bgGreen = graphicRendition_.fgGreen;
        result.bgBlue = graphicRendition_.fgBlue;
        result.backgroundColorMode = graphicRendition_.fgColorMode;
    } else {
        result.backgroundColor = graphicRendition_.bgColorCode;
        result.bgGreen = graphicRendition_.bgGreen;
        result.bgBlue = graphicRendition_.bgBlue;
        result.backgroundColorMode = graphicRendition_.bgColorMode;
    }
    return result;
}

- (screen_char_t)foregroundColorCodeReal {
    screen_char_t result = { 0 };
    result.foregroundColor = graphicRendition_.fgColorCode;
    result.fgGreen = graphicRendition_.fgGreen;
    result.fgBlue = graphicRendition_.fgBlue;
    result.foregroundColorMode = graphicRendition_.fgColorMode;
    result.bold = graphicRendition_.bold;
    result.faint = graphicRendition_.faint;
    result.italic = graphicRendition_.italic;
    result.underline = graphicRendition_.underline;
    result.strikethrough = graphicRendition_.strikethrough;
    result.underlineStyle = graphicRendition_.underlineStyle;
    result.blink = graphicRendition_.blink;
    result.invisible = graphicRendition_.invisible;
    result.inverse = graphicRendition_.reversed;
    result.guarded = _protectedMode != VT100TerminalProtectedModeNone;
    result.unused = 0;
    return result;
}

- (screen_char_t)backgroundColorCodeReal {
    screen_char_t result = { 0 };
    result.backgroundColor = graphicRendition_.bgColorCode;
    result.bgGreen = graphicRendition_.bgGreen;
    result.bgBlue = graphicRendition_.bgBlue;
    result.backgroundColorMode = graphicRendition_.bgColorMode;
    return result;
}

- (void)setInsertMode:(BOOL)mode {
    if (_insertMode != mode) {
        self.dirty = YES;
        _insertMode = mode;
        [_delegate terminalInsertModeDidChangeTo:mode];
    }
}

- (void)toggleAlternateScreen {
    // The delegate tracks "hard" alternate screen mode, which is what this affects. We only track
    // soft alternate screen mode. No point tracking it in two places.
    const BOOL useAlternateScreenMode = ![self.delegate terminalIsInAlternateScreenMode];
    if (useAlternateScreenMode) {
        [_delegate terminalShowAltBuffer];
    } else {
        [_delegate terminalShowPrimaryBuffer];
    }
    self.softAlternateScreenMode = useAlternateScreenMode;
}

- (void)executeDecSetReset:(VT100Token *)token {
    assert(token->type == VT100CSI_DECSET ||
           token->type == VT100CSI_DECRST);
    BOOL mode = (token->type == VT100CSI_DECSET);

    for (int i = 0; i < token.csi->count; i++) {
        switch (token.csi->p[i]) {
            case -1:
                // This was removed by translating from screen -> xterm for tmux mode.
                break;
            case 1:
                self.cursorMode = mode;
                break;
            case 2:
                // This was never implemented and we don't generally support switching emulation modes.
                // In practice this doesn't seem to provide any benefit to modern users, and it can
                // cause harm. For example, `CSI 2 l` puts the terminal in vt52 mode which is not
                // useful except for maybe legacy systems. Getting this code on a modern system
                // appears to break everything from the user's POV.
                break;
            case 3:  // DECCOLM
                if (self.allowColumnMode) {
                    const BOOL changed = (self.columnMode != mode);
                    self.columnMode = mode;
                    VT100GridCoord coord = VT100GridCoordMake(self.delegate.terminalCursorX,
                                                              self.delegate.terminalCursorY);
                    [self setWidth:(self.columnMode ? 132 : 80)
                    preserveScreen:!changed || self.preserveScreenOnDECCOLM
                     updateRegions:changed
                      moveCursorTo:VT100GridCoordMake(MIN(coord.x, self.delegate.terminalSizeInCells.width),
                                                      coord.y)
                        completion:nil];
                }
                break;
            case 4:
                // Smooth vs jump scrolling. Not supported.
                break;
            case 5:
                self.reverseVideo = mode;
                [_delegate terminalNeedsRedraw];
                break;
            case 6:
                self.originMode = mode;
                [_delegate terminalMoveCursorToX:1 y:1];
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
            case 12:
                [_delegate terminalSetCursorBlinking:mode];
                break;
            case 20:
                // This used to be the setter for "line mode", but it wasn't used and it's not
                // supported by xterm. Seemed to have something to do with CR vs LF.
                break;
            case 25:
                [_delegate terminalSetCursorVisible:mode];
                break;
            case 40:
                self.allowColumnMode = mode;
                break;
            case 41:
                self.moreFix = mode;
                break;
            case 45:
                self.reverseWraparoundMode = mode;
                break;
            case 66:
                self.keypadMode = mode;
                break;
            case 69:
                [_delegate terminalSetUseColumnScrollRegion:mode];
                break;

                // TODO: 80 - DECSDM
            case 95:
                self.preserveScreenOnDECCOLM = mode;
                break;
            case 1000:
            // case 1001:
            // TODO: MOUSE_REPORTING_HIGHLIGHT not implemented.
            case 1002:
            case 1003:
                if (mode) {
                    self.mouseMode = token.csi->p[i] - 1000;
                } else {
                    self.mouseMode = MOUSE_REPORTING_NONE;
                }
                [_delegate terminalMouseModeDidChangeTo:_mouseMode];
                break;
            case 1004:
                self.reportFocus = mode && [_delegate terminalFocusReportingAllowed];
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

            case 1007:
                self.alternateScrollMode = mode;
                break;

            case 1015:
                if (mode) {
                    self.mouseFormat = MOUSE_FORMAT_URXVT;
                } else {
                    self.mouseFormat = MOUSE_FORMAT_XTERM;
                }
                break;

            case 1016:
                if (mode) {
                    self.mouseFormat = MOUSE_FORMAT_SGR_PIXEL;
                } else {
                    self.mouseFormat = MOUSE_FORMAT_XTERM;
                }
                break;

            case 1036:
                self.metaSendsEscape = mode;
                break;

            case 1337:
                self.reportKeyUp = mode;
                break;

            // Here's how xterm behaves:
            //        main -> alt                 alt -> main                     main -> main     alt -> alt
            //      +----------------------------+-------------------------------+----------------+---------------------------+
            //   47 |              switch        |        switch                 | noop           | noop                      |
            // 1047 |              switch        | clear, switch                 | noop           | noop                      |
            // 1049 | save cursor, switch, clear |        switch, restore cursor | restore cursor | save cursor, clear screen |
            case 47:
                // alternate screen buffer mode
                if (!self.disableSmcupRmcup) {
                    if (mode) {
                        const int x = [_delegate terminalCursorX];
                        const int y = [_delegate terminalCursorY];
                        [_delegate terminalShowAltBuffer];
                        [_delegate terminalSetCursorX:x];
                        [_delegate terminalSetCursorY:y];
                    } else {
                        const int x = [_delegate terminalCursorX];
                        const int y = [_delegate terminalCursorY];
                        [_delegate terminalShowPrimaryBuffer];
                        [_delegate terminalSetCursorX:x];
                        [_delegate terminalSetCursorY:y];
                    }
                }
                self.softAlternateScreenMode = mode;
                break;
            case 1047:
                if (!self.disableSmcupRmcup) {
                    if (mode) {
                        const int x = [_delegate terminalCursorX];
                        const int y = [_delegate terminalCursorY];
                        [_delegate terminalShowAltBuffer];
                        [_delegate terminalSetCursorX:x];
                        [_delegate terminalSetCursorY:y];
                    } else {
                        if ([_delegate terminalIsShowingAltBuffer]) {
                            [_delegate terminalClearScreen];
                        }
                        const int x = [_delegate terminalCursorX];
                        const int y = [_delegate terminalCursorY];
                        [_delegate terminalShowPrimaryBuffer];
                        [_delegate terminalSetCursorX:x];
                        [_delegate terminalSetCursorY:y];
                    }
                }
                self.softAlternateScreenMode = mode;
                break;

            case 1048:
                if (!self.disableSmcupRmcup) {  // by analogy to xterm's titeInhibit resource.
                    if (mode) {
                        [self saveCursor];
                    } else {
                        [self restoreCursor];
                    }
                }
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
                        [self saveCursor];
                        [_delegate terminalShowAltBuffer];
                        [_delegate terminalClearScreen];
                        [_delegate terminalMoveCursorToX:1 y:1];
                    } else {
                        [_delegate terminalShowPrimaryBuffer];
                        [self restoreCursor];
                    }
                }
                self.softAlternateScreenMode = mode;
                break;

            case 2004:
                // Set bracketed paste mode
                [self setBracketedPasteMode:mode && self.allowPasteBracketing withSideEffects:YES];
                break;

            case 2026:
                // https://github.com/microsoft/terminal/issues/8331
                self.synchronizedUpdates = mode;
                break;
        }
    }
}

- (void)setSynchronizedUpdates:(BOOL)synchronizedUpdates {
    self.dirty = YES;
    _synchronizedUpdates = synchronizedUpdates;
    [self.delegate terminalSynchronizedUpdate:synchronizedUpdates];
}

- (void)setProtectedMode:(VT100TerminalProtectedMode)protectedMode {
    if (protectedMode == _protectedMode) {
        return;
    }
    _protectedMode = protectedMode;
    [self.delegate terminalProtectedModeDidChangeTo:_protectedMode];
}

- (void)resetGraphicRendition {
    self.dirty = YES;
    memset(&graphicRendition_, 0, sizeof(graphicRendition_));
    [self updateExternalAttributes];
}

// The actual spec for this is called ITU T.416-199303
// You can download it for free! If you prefer to spend money, ISO/IEC 8613-6
// is supposedly the same thing.
//
// Here's a sad story about CSI 38:2, which is used to do 24-bit color.
//
// Lots of terminal emulators, iTerm2 included, misunderstood the spec. That's
// easy to understand if you read it, which I can't recommend doing unless
// you're looking for inspiration for your next Bulwer-Lytton Fiction Contest
// entry.
//
// See issue 6377 for more context.
//
// Ignoring color types we don't support like CMYK, the spec says to do this:
// CSI 38:2:[color space]:[red]:[green]:[blue]:[unused]:[tolerance]:[tolerance colorspace]
//
// Everything after [blue] is optional. Values are decimal numbers in 0...255.
//
// Unfortunately, what was implemented for a long time was this:
// CSI 38:2:[red]:[green]:[blue]:[unused]:[tolerance]:[tolerance colorspace]
//
// And for xterm compatibility, the following was also accepted:
// CSI 38;2;[red];[green];[blue]
//
// The New Order
// -------------
// Tolerance never did anything, so we'll accept this non-standards compliant
// code, which people use:
// CSI 38:2:[red]:[green]:[blue]
//
// As well as the following forms:
// CSI 38:2:[colorspace]:[red]:[green]:[blue]
// CSI 38:2:[colorspace]:[red]:[green]:[blue]:<one or more additional colon-delimited arguments, all ignored>
// CSI 38;2;[red];[green];[blue]   // Notice semicolons in place of colons here
//
// NOTE: If you change this you must also update -sgrCodesForGraphicRendition:
- (VT100TerminalColorValue)colorValueFromSGRToken:(VT100Token *)token fromParameter:(inout int *)index {
    const int i = *index;
    int subs[VT100CSISUBPARAM_MAX];
    const int numberOfSubparameters = iTermParserGetAllCSISubparametersForParameter(token.csi, i, subs);
    if (numberOfSubparameters > 0) {
        // Preferred syntax using colons to delimit subparameters
        if (numberOfSubparameters >= 2 && subs[0] == 5) {
            // CSI 38:5:P m
            return (VT100TerminalColorValue){
                .red = subs[1],
                .green = 0,
                .blue = 0,
                .mode = ColorModeNormal
            };
        }
        if (numberOfSubparameters >= 4 && subs[0] == 2) {
            // 24-bit color
            if (numberOfSubparameters >= 5) {
                // Spec-compliant. Likely rarely used in 2017.
                // CSI 38:2:colorspace:R:G:B m
                // TODO: Respect the color space argument. See ITU-T Rec. T.414,
                // but good luck actually finding the colour space IDs.
                return (VT100TerminalColorValue){
                    .red = subs[2],
                    .green = subs[3],
                    .blue = subs[4],
                    .mode = ColorMode24bit
                };
            }
            // Misinterpretation compliant.
            // CSI 38:2:R:G:B m  <- misinterpretation compliant
            return (VT100TerminalColorValue) {
                .red = subs[1],
                .green = subs[2],
                .blue = subs[3],
                .mode = ColorMode24bit
            };
        }
        return (VT100TerminalColorValue) {
            .red = -1,
            .green = -1,
            .blue = -1,
            .mode = ColorMode24bit
        };
    }
    if (token.csi->count - i >= 3 && token.csi->p[i + 1] == 5) {
        // For 256-color mode (indexed) use this for the foreground:
        // CSI 38;5;N m
        // where N is a value between 0 and 255. See the colors described in screen_char_t
        // in the comments for fgColorCode.
        *index += 2;
        return (VT100TerminalColorValue) {
            .red = token.csi->p[i + 2],
            .green = 0,
            .blue = 0,
            .mode = ColorModeNormal
        };
    }
    if (token.csi->count - i >= 5 && token.csi->p[i + 1] == 2) {
        // CSI 38;2;R;G;B m
        // Hack for xterm compatibility
        // 24-bit color support
        *index += 4;
        return (VT100TerminalColorValue) {
            .red = token.csi->p[i + 2],
            .green = token.csi->p[i + 3],
            .blue = token.csi->p[i + 4],
            .mode = ColorMode24bit
        };
    }
    return (VT100TerminalColorValue) {
        .red = -1,
        .green = -1,
        .blue = -1,
        .mode = ColorMode24bit
    };
}

// TODO: Respect DECSACE
- (void)executeDECCARA:(VT100Token *)token {
    if (token.csi->count < 5) {
        return;
    }
    const VT100GridRect rect = [self rectangleInToken:token startingAtIndex:0 defaultRectangle:[self defaultRectangle]];
    if (rect.origin.x < 0 ||
        rect.origin.y < 0 ||
        rect.size.width <= 0 ||
        rect.size.height <= 0) {
        return;
    }
    for (int i = 4; i < token.csi->count; i++) {
        [_delegate terminalSetAttribute:token.csi->p[i] inRect:rect];
    }
}

- (void)executeDECRARA:(VT100Token *)token {
    if (token.csi->count < 5) {
        return;
    }
    const VT100GridRect rect = [self rectangleInToken:token startingAtIndex:0 defaultRectangle:[self defaultRectangle]];
    if (rect.origin.x < 0 ||
        rect.origin.y < 0 ||
        rect.size.width <= 0 ||
        rect.size.height <= 0) {
        return;
    }
    for (int i = 4; i < token.csi->count; i++) {
        [_delegate terminalToggleAttribute:token.csi->p[i] inRect:rect];
    }
}

- (void)executeDECSACE:(VT100Token *)token {
    switch (token.csi->p[0]) {
        case 0:
        case 1:
            self.decsaceRectangleMode = NO;
            break;
        case 2:
            self.decsaceRectangleMode = YES;
            break;
    }
}

- (void)executeDECCRA:(VT100Token *)token {
    const VT100GridRect rect = [self rectangleInToken:token startingAtIndex:0 defaultRectangle:[self defaultRectangle]];
    if (rect.origin.x < 0 ||
        rect.origin.y < 0 ||
        rect.size.width <= 0 ||
        rect.size.height <= 0) {
        return;
    }
    const VT100GridCoord dest = VT100GridCoordMake(token.csi->p[5] - 1, token.csi->p[6] - 1);
    if (dest.x < 0 || dest.y < 0) {
        return;
    }
    [_delegate terminalCopyFrom:rect to:dest];
}

- (void)executeDECFRA:(VT100Token *)token {
    if (token.csi->count < 1) {
        return;
    }
    const unichar ch = token.csi->p[0];
    if (ch < 32) {
        return;
    }
    if (ch > 126 && ch < 160) {
        return;
    }
    if (ch > 255) {
        return;
    }
    const VT100GridRect rect = [self rectangleInToken:token startingAtIndex:1 defaultRectangle:[self defaultRectangle]];
    if (rect.origin.x < 0 ||
        rect.origin.y < 0 ||
        rect.size.width <= 0 ||
        rect.size.height <= 0) {
        return;
    }
    [self.delegate terminalFillRectangle:rect withCharacter:ch];
}

- (void)executeDECERA:(VT100Token *)token {
    const VT100GridRect rect = [self rectangleInToken:token startingAtIndex:0 defaultRectangle:[self defaultRectangle]];
    if (rect.origin.x < 0 ||
        rect.origin.y < 0 ||
        rect.size.width <= 0 ||
        rect.size.height <= 0) {
        return;
    }
    [self.delegate terminalEraseRectangle:rect];
}

- (VT100GridRect)defaultRectangle {
    const VT100GridSize size = [_delegate terminalSizeInCells];
    return VT100GridRectMake(0, 0, size.width, size.height);
}

- (void)executeSGR:(VT100Token *)token {
    self.dirty = YES;
    assert(token->type == VT100CSI_SGR);
    if (token.csi->count == 0) {
        [self resetGraphicRendition];
    } else {
        int i;
        for (i = 0; i < token.csi->count; ++i) {
            int n = token.csi->p[i];
            switch (n) {
                case VT100CHARATTR_ALLOFF:
                    [self resetGraphicRendition];
                    break;
                case VT100CHARATTR_BOLD:
                    graphicRendition_.bold = YES;
                    break;
                case VT100CHARATTR_FAINT:
                    graphicRendition_.faint = YES;
                    break;
                case VT100CHARATTR_ITALIC:
                    graphicRendition_.italic = YES;
                    break;
                case VT100CHARATTR_UNDERLINE: {
                    graphicRendition_.underline = YES;
                    int subs[VT100CSISUBPARAM_MAX];
                    const int numberOfSubparameters = iTermParserGetAllCSISubparametersForParameter(token.csi, i, subs);
                    if (numberOfSubparameters > 0) {
                        switch (subs[0]) {
                            case 0:
                                graphicRendition_.underline = NO;
                                break;
                            case 1:
                                graphicRendition_.underlineStyle = VT100UnderlineStyleSingle;
                                break;
                            case 3:
                                graphicRendition_.underlineStyle = VT100UnderlineStyleCurly;
                                break;
                        }
                    } else {
                        graphicRendition_.underlineStyle = VT100UnderlineStyleSingle;
                    }
                    break;
                }
                case VT100CHARATTR_BLINK:
                    graphicRendition_.blink = YES;
                    break;
                case VT100CHARATTR_REVERSE:
                    graphicRendition_.reversed = YES;
                    break;
                case VT100CHARATTR_INVISIBLE:
                    graphicRendition_.invisible = YES;
                    break;
                case VT100CHARATTR_STRIKETHROUGH:
                    graphicRendition_.strikethrough = YES;
                    break;

                case VT100CHARATTR_DOUBLE_UNDERLINE:
                    graphicRendition_.underline = YES;
                    graphicRendition_.underlineStyle = VT100UnderlineStyleDouble;
                    break;

                case VT100CHARATTR_NORMAL:
                    graphicRendition_.faint = graphicRendition_.bold = NO;
                    break;
                case VT100CHARATTR_NOT_ITALIC:
                    graphicRendition_.italic = NO;
                    break;
                case VT100CHARATTR_NOT_UNDERLINE:
                    graphicRendition_.underline = NO;
                    break;
                case VT100CHARATTR_STEADY:
                    graphicRendition_.blink = NO;
                    break;
                case VT100CHARATTR_POSITIVE:
                    graphicRendition_.reversed = NO;
                    break;
                case VT100CHARATTR_VISIBLE:
                    graphicRendition_.invisible = NO;
                    break;
                case VT100CHARATTR_NOT_STRIKETHROUGH:
                    graphicRendition_.strikethrough = NO;
                    break;

                case VT100CHARATTR_FG_DEFAULT:
                    graphicRendition_.fgColorCode = ALTSEM_DEFAULT;
                    graphicRendition_.fgGreen = 0;
                    graphicRendition_.fgBlue = 0;
                    graphicRendition_.fgColorMode = ColorModeAlternate;
                    break;
                case VT100CHARATTR_BG_DEFAULT:
                    graphicRendition_.bgColorCode = ALTSEM_DEFAULT;
                    graphicRendition_.bgGreen = 0;
                    graphicRendition_.bgBlue = 0;
                    graphicRendition_.bgColorMode = ColorModeAlternate;
                    break;
                case VT100CHARATTR_UNDERLINE_COLOR_DEFAULT:
                    graphicRendition_.hasUnderlineColor = NO;
                    [self updateExternalAttributes];
                    break;
                case VT100CHARATTR_UNDERLINE_COLOR: {
                    const VT100TerminalColorValue value = [self colorValueFromSGRToken:token fromParameter:&i];
                    if (value.red < 0) {
                        break;
                    }
                    graphicRendition_.hasUnderlineColor = YES;
                    graphicRendition_.underlineColor = value;
                    [self updateExternalAttributes];
                    break;
                }
                case VT100CHARATTR_FG_256: {
                    const VT100TerminalColorValue value = [self colorValueFromSGRToken:token fromParameter:&i];
                    if (value.red < 0) {
                        break;
                    }
                    graphicRendition_.fgColorCode = value.red;
                    graphicRendition_.fgGreen = value.green;
                    graphicRendition_.fgBlue = value.blue;
                    graphicRendition_.fgColorMode = value.mode;
                    break;
                }
                case VT100CHARATTR_BG_256: {
                    const VT100TerminalColorValue value = [self colorValueFromSGRToken:token fromParameter:&i];
                    if (value.red < 0) {
                        break;
                    }
                    graphicRendition_.bgColorCode = value.red;
                    graphicRendition_.bgGreen = value.green;
                    graphicRendition_.bgBlue = value.blue;
                    graphicRendition_.bgColorMode = value.mode;
                    break;
                }
                default:
                    // 8 color support
                    if (n >= VT100CHARATTR_FG_BLACK &&
                        n <= VT100CHARATTR_FG_WHITE) {
                        graphicRendition_.fgColorCode = n - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                        graphicRendition_.fgGreen = 0;
                        graphicRendition_.fgBlue = 0;
                        graphicRendition_.fgColorMode = ColorModeNormal;
                    } else if (n >= VT100CHARATTR_BG_BLACK &&
                               n <= VT100CHARATTR_BG_WHITE) {
                        graphicRendition_.bgColorCode = n - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                        graphicRendition_.bgGreen = 0;
                        graphicRendition_.bgBlue = 0;
                        graphicRendition_.bgColorMode = ColorModeNormal;
                    }
                    // 16 color support
                    if (n >= VT100CHARATTR_FG_HI_BLACK &&
                        n <= VT100CHARATTR_FG_HI_WHITE) {
                        graphicRendition_.fgColorCode = n - VT100CHARATTR_FG_HI_BASE - COLORCODE_BLACK + 8;
                        graphicRendition_.fgGreen = 0;
                        graphicRendition_.fgBlue = 0;
                        graphicRendition_.fgColorMode = ColorModeNormal;
                    } else if (n >= VT100CHARATTR_BG_HI_BLACK &&
                               n <= VT100CHARATTR_BG_HI_WHITE) {
                        graphicRendition_.bgColorCode = n - VT100CHARATTR_BG_HI_BASE - COLORCODE_BLACK + 8;
                        graphicRendition_.bgGreen = 0;
                        graphicRendition_.bgBlue = 0;
                        graphicRendition_.bgColorMode = ColorModeNormal;
                    }
            }
        }
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
            NSColor *color = [NSColor it_colorInDefaultColorSpaceWithRed:((double)r)/255.0
                                                                   green:((double)g)/255.0
                                                                    blue:((double)b)/255.0
                                                                   alpha:1];
            *numberPtr = n;
            return color;
        }
    }
    return nil;
}

- (void)setMouseMode:(MouseMode)mode {
    self.dirty = YES;
    if (_mouseMode != MOUSE_REPORTING_NONE) {
        _previousMouseMode = self.mouseMode;
    }
    _mouseMode = mode;
    [_delegate terminalMouseModeDidChangeTo:_mouseMode];
}

- (void)handleDeviceStatusReportWithToken:(VT100Token *)token withQuestion:(BOOL)withQuestion {
    if ([_delegate terminalShouldSendReport]) {
        switch (token.csi->p[0]) {
            case 3: // response from VT100 -- Malfunction -- retry
                break;

            case 5: // Command from host -- Please report status
                [_delegate terminalSendReport:[self.output reportStatus]];
                break;

            case 6: // Command from host -- Please report active position
                if (self.originMode) {
                    // This is compatible with Terminal but not old xterm :(. it always did what
                    // we do in the else clause. This behavior of xterm is fixed by Patch #297.
                    [_delegate terminalSendReport:[self.output reportActivePositionWithX:[_delegate terminalRelativeCursorX]
                                                                                Y:[_delegate terminalRelativeCursorY]
                                                                     withQuestion:withQuestion]];
                } else {
                    [_delegate terminalSendReport:[self.output reportActivePositionWithX:[_delegate terminalCursorX]
                                                                                Y:[_delegate terminalCursorY]
                                                                     withQuestion:withQuestion]];
                }
                break;

            case 15:  // Printer status
                [_delegate terminalSendReport:[self.output reportDECDSR:13]];  // "No printer" since printing is unsupported.
                break;

            case 25:
                [_delegate terminalSendReport:[self.output reportDECDSR:20]];  //  Locking is unsupported so report unlocked.
                break;

            // 26 might be nice to support some day.

            case 53:
            case 55:
                [_delegate terminalSendReport:[self.output reportDECDSR:50]];  // Locator unavailable becuase DEC locator support unimplemented.
                break;

            case 56:
                [_delegate terminalSendReport:[self.output reportDECDSR:57 :0]];  // No locator support
                break;

            case 62:  // Request DECMSR
                [_delegate terminalSendReport:[self.output reportMacroSpace:0]];  // Macros are unsupported so report 0 space
                break;

            case 63:  // Request DECCKSR
                [_delegate terminalSendReport:[self.output reportMemoryChecksum:0 id:token.csi->p[1]]];  // Memory checksum
                break;

            case 75: // Data integrity check
                [_delegate terminalSendReport:[self.output reportDECDSR:70]];
                break;

            case 85:  // Multi-session configuration
                [_delegate terminalSendReport:[self.output reportDECDSR:83]];
                break;

            case 1337:  // iTerm2 extension
                [_delegate terminalSendReport:[self.output reportiTerm2Version]];
                break;

            case 0: // Response from VT100 -- Ready, No malfunctions detected
            default:
                break;
        }
    }
}

- (VT100GridRect)rectangleInToken:(VT100Token *)token
                  startingAtIndex:(int)index
                 defaultRectangle:(VT100GridRect)defaultRectangle {
    CSIParam *csi = token.csi;
    VT100GridCoord defaultMax = VT100GridRectMax(defaultRectangle);

    // First, construct a coord range from the passed-in parameters. They may be -1 for default
    // values.
    int top = csi->p[index];
    int left = csi->p[index + 1];
    int bottom = csi->p[index + 2];
    int right = csi->p[index + 3];
    VT100GridCoordRange coordRange = VT100GridCoordRangeMake(left, top, right, bottom);

    // Replace default values with the passed-in defaults.
    if (coordRange.start.x < 0) {
        coordRange.start.x = defaultRectangle.origin.x + 1;
    }
    if (coordRange.start.y < 0) {
        coordRange.start.y = defaultRectangle.origin.y + 1;
    }
    if (coordRange.end.x < 0) {
        coordRange.end.x = defaultMax.x + 1;
    }
    if (coordRange.end.y < 0) {
        coordRange.end.y = defaultMax.y + 1;
    }

    if (self.originMode) {
        VT100GridRect scrollRegion = [_delegate terminalScrollRegion];
        coordRange.start.x += scrollRegion.origin.x;
        coordRange.start.y += scrollRegion.origin.y;
        coordRange.end.x += scrollRegion.origin.x;
        coordRange.end.y += scrollRegion.origin.y;
    }

    // Convert the coordRange to a 0-based rect (all coords are 1-based so far) and return it.
    return VT100GridRectMake(MAX(0, coordRange.start.x - 1),
                             MAX(0, coordRange.start.y - 1),
                             coordRange.end.x - coordRange.start.x + 1,
                             coordRange.end.y - coordRange.start.y + 1);
}

- (BOOL)rectangleIsValid:(VT100GridRect)rect {
    if (self.originMode) {
        VT100GridRect scrollRegion = [_delegate terminalScrollRegion];
        if (rect.origin.y < scrollRegion.origin.y ||
            rect.origin.x < scrollRegion.origin.x ||
            VT100GridRectMax(rect).y > VT100GridRectMax(scrollRegion).y ||
            VT100GridRectMax(rect).x > VT100GridRectMax(scrollRegion).x) {
            return NO;
        }
    }
    return (rect.size.width >= 0 &&
            rect.size.height >= 0);
}

- (void)sendChecksumReportWithId:(int)identifier
                       rectangle:(VT100GridRect)rect {
    if (![_delegate terminalShouldSendReport]) {
        return;
    }
    if (identifier < 0) {
        return;
    }
    if (![self rectangleIsValid:rect]) {
        [_delegate terminalSendReport:[self.output reportChecksum:0 withIdentifier:identifier]];
        return;
    }
    // TODO: Respect origin mode
    int checksum = [_delegate terminalChecksumInRectangle:rect];
    // DCS Pid ! ~ D..D ST
    [_delegate terminalSendReport:[self.output reportChecksum:checksum withIdentifier:identifier]];
}

- (void)sendSGRReportWithRectangle:(VT100GridRect)rect {
    if (![_delegate terminalShouldSendReport]) {
        return;
    }
    if (![self rectangleIsValid:rect]) {
        [_delegate terminalSendReport:[self.output reportSGRCodes:@[]]];
        return;
    }
    // TODO: Respect origin mode
    NSArray<NSString *> *codes = [_delegate terminalSGRCodesInRectangle:rect];
    [_delegate terminalSendReport:[self.output reportSGRCodes:codes]];
}

- (NSString *)decodedBase64PasteCommand:(NSString *)commandString query:(NSString **)query {
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
    const char *bufferStart = [commandString UTF8String];
    const char *buffer = bufferStart;
    *query = nil;

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
        *query = [commandString substringToIndex:buffer - bufferStart - 1];
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

    NSString *resultString = [[NSString alloc] initWithData:data
                                                   encoding:[self encoding]];
    return resultString;
}

// The main and alternate screens have different saved cursors. This returns the current one. In
// tmux mode, only one is used to more closely approximate tmux's behavior.
- (VT100SavedCursor *)savedCursor {
    if (_tmuxMode) {
        return &mainSavedCursor_;
    }
    VT100SavedCursor *savedCursor;
    if ([_delegate terminalIsShowingAltBuffer]) {
        savedCursor = &altSavedCursor_;
    } else {
        savedCursor = &mainSavedCursor_;
    }
    return savedCursor;
}

- (void)saveCursor {
    self.dirty = YES;
    VT100SavedCursor *savedCursor = [self savedCursor];

    savedCursor->position = VT100GridCoordMake([_delegate terminalCursorX] - 1,
                                               [_delegate terminalCursorY] - 1);
    savedCursor->charset = _charset;

    for (int i = 0; i < NUM_CHARSETS; i++) {
        savedCursor->lineDrawing[i] = [_delegate terminalLineDrawingFlagForCharset:i];
    }
    savedCursor->graphicRendition = graphicRendition_;
    savedCursor->origin = self.originMode;
    savedCursor->wraparound = self.wraparoundMode;
    savedCursor->unicodeVersion = [_delegate terminalUnicodeVersion];
    savedCursor->protectedMode = _protectedMode;
}

- (void)setReportFocus:(BOOL)reportFocus {
    self.dirty = YES;
    [self.delegate terminalReportFocusWillChangeTo:reportFocus];
    _reportFocus = reportFocus;
}

- (void)setBracketedPasteMode:(BOOL)bracketedPasteMode {
    [self setBracketedPasteMode:bracketedPasteMode withSideEffects:NO];
}

- (void)setBracketedPasteMode:(BOOL)bracketedPasteMode withSideEffects:(BOOL)sideEffects {
    self.dirty = YES;
    if (sideEffects) {
        [_delegate terminalPasteBracketingWillChangeTo:bracketedPasteMode];
    }
    _bracketedPasteMode = bracketedPasteMode;
}

- (void)resetSavedCursorPositions {
    self.dirty = YES;
    mainSavedCursor_.position = VT100GridCoordMake(0, 0);
    altSavedCursor_.position = VT100GridCoordMake(0, 0);
}

- (void)clampSavedCursorToScreenSize:(VT100GridSize)newSize {
    self.dirty = YES;
    mainSavedCursor_.position = VT100GridCoordMake(MIN(newSize.width - 1, mainSavedCursor_.position.x),
                                                   MIN(newSize.height - 1, mainSavedCursor_.position.y));
    altSavedCursor_.position = VT100GridCoordMake(MIN(newSize.width - 1, altSavedCursor_.position.x),
                                                  MIN(newSize.height - 1, altSavedCursor_.position.y));
}

- (void)setSavedCursorPosition:(VT100GridCoord)position {
    self.dirty = YES;
    VT100SavedCursor *savedCursor = [self savedCursor];
    savedCursor->position = position;
}

- (void)restoreCursor {
    self.dirty = YES;
    VT100SavedCursor *savedCursor = [self savedCursor];
    [_delegate terminalSetCursorX:savedCursor->position.x + 1];
    [_delegate terminalSetCursorY:savedCursor->position.y + 1];
    self.charset = savedCursor->charset;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [_delegate terminalSetCharset:i toLineDrawingMode:savedCursor->lineDrawing[i]];
    }

    graphicRendition_ = savedCursor->graphicRendition;

    self.originMode = savedCursor->origin;
    self.wraparoundMode = savedCursor->wraparound;
    self.protectedMode = savedCursor->protectedMode;
    [_delegate terminalSetUnicodeVersion:savedCursor->unicodeVersion];
}

// These steps are derived from xterm's source.
- (void)softReset {
    self.dirty = YES;
    // The steps here are derived from xterm's implementation. The order is different but not in
    // a significant way.
    int x = [_delegate terminalCursorX];
    int y = [_delegate terminalCursorY];

    // Show cursor
    [_delegate terminalSetCursorVisible:YES];

    // Reset cursor shape to default
    [_delegate terminalSetCursorType:CURSOR_DEFAULT];

    // Remove tb and lr margins
    const VT100GridSize size = [_delegate terminalSizeInCells];
    [_delegate terminalSetScrollRegionTop:0
                                   bottom:size.height - 1];
    [_delegate terminalSetLeftMargin:0 rightMargin:size.width - 1];


    // Turn off origin mode
    self.originMode = NO;

    // Reset colors
    graphicRendition_.fgColorCode = 0;
    graphicRendition_.fgGreen = 0;
    graphicRendition_.fgBlue = 0;
    graphicRendition_.fgColorMode = 0;

    graphicRendition_.bgColorCode = 0;
    graphicRendition_.bgGreen = 0;
    graphicRendition_.bgBlue = 0;
    graphicRendition_.bgColorMode = 0;

    // Reset character-sets to initial state
    self.charset = 0;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [_delegate terminalSetCharset:i toLineDrawingMode:NO];
    }

    self.protectedMode = VT100TerminalProtectedModeNone;

    // Reset DECCKM
    self.cursorMode = NO;

    // (Not supported: Reset KAM)

    // Reset DECKPAM
    self.keypadMode = NO;

    self.reportKeyUp = NO;
    self.metaSendsEscape = NO;
    self.alternateScrollMode = NO;
    self.synchronizedUpdates = NO;
    self.preserveScreenOnDECCOLM = NO;

    // Set WRAPROUND to initial value
    self.wraparoundMode = YES;

    // Set REVERSEWRAP to initial value
    self.reverseWraparoundMode = NO;

    // Reset INSERT
    self.insertMode = NO;

    // Reset SRM
    self.sendReceiveMode = NO;

    // Reset INVERSE
    graphicRendition_.reversed = NO;

    // Reset BOLD
    graphicRendition_.bold = NO;

    // Reset BLINK
    graphicRendition_.blink = NO;

    // Reset INVISIBLE
    graphicRendition_.invisible = NO;

    // Reset UNDERLINE & STRIKETHROUGH
    graphicRendition_.underline = NO;
    graphicRendition_.strikethrough = NO;
    graphicRendition_.underlineStyle = VT100UnderlineStyleSingle;

    self.url = nil;
    self.urlParams = nil;
    _currentURLCode = 0;

    // (Not supported: Reset INVISIBLE)

    // Save screen flags
    // Save fg, bg colors
    // Save charset flags
    // Save current charset
    [self saveCursor];

    // Reset saved cursor position to 1,1.
    VT100SavedCursor *savedCursor = [self savedCursor];
    savedCursor->position = VT100GridCoordMake(0, 0);

    [_delegate terminalSetCursorX:x];
    [_delegate terminalSetCursorY:y];
}

- (VT100GridCoord)savedCursorPosition {
    VT100SavedCursor *savedCursor = [self savedCursor];
    return savedCursor->position;
}

static BOOL VT100TokenIsTmux(VT100Token *token) {
    return (token->type == TMUX_EXIT ||
            token->type == TMUX_LINE ||
            token->type == DCS_TMUX_HOOK);
}

- (void)executeToken:(VT100Token *)token {
    if (_lastToken != nil &&
        VT100TokenIsTmux(_lastToken) &&
        !VT100TokenIsTmux(token)) {
        // Have the delegate roll back this token and pause execution.fdslfj
        [_delegate terminalDidTransitionOutOfTmuxMode];
        // Nil out last token so we don't take this code path a second time.
        _lastToken = nil;
        return;
    }
    [self reallyExecuteToken:token];
    _lastToken = token;
}

- (void)reallyExecuteToken:(VT100Token *)token {
    // Handle tmux stuff, which completely bypasses all other normal execution steps.
    if (token->type == DCS_TMUX_HOOK) {
        [_delegate terminalStartTmuxModeWithDCSIdentifier:token.string];
        return;
    } else if (token->type == TMUX_EXIT || token->type == TMUX_LINE) {
        [_delegate terminalHandleTmuxInput:token];
        return;
    }

    if (_isScreenLike && [iTermAdvancedSettingsModel translateScreenToXterm]) {
        [token translateFromScreenTerminal];
    }

    // Handle file downloads, which come as a series of MULTITOKEN_BODY tokens.
    if (receivingFile_) {
        if (token->type == XTERMCC_MULTITOKEN_BODY) {
            [_delegate terminalDidReceiveBase64FileData:token.string ?: @""];
            return;
        } else if (token->type == VT100_ASCIISTRING) {
            [_delegate terminalDidReceiveBase64FileData:[token stringForAsciiData]];
            return;
        } else if (token->type == XTERMCC_MULTITOKEN_END) {
            [_delegate terminalDidFinishReceivingFile];
            receivingFile_ = NO;
            return;
        } else {
            DLog(@"Unexpected field receipt end");
            [_delegate terminalFileReceiptEndedUnexpectedly];
            receivingFile_ = NO;
        }
    } else if (_copyingToPasteboard) {
        if (token->type == XTERMCC_MULTITOKEN_BODY) {
            [_delegate terminalDidReceiveBase64PasteboardString:token.string ?: @""];
            return;
        } else if (token->type == VT100_ASCIISTRING) {
            [_delegate terminalDidReceiveBase64PasteboardString:[token stringForAsciiData]];
            return;
        } else if (token->type == XTERMCC_MULTITOKEN_END) {
            [_delegate terminalDidFinishReceivingPasteboard];
            _copyingToPasteboard = NO;
            return;
        } else {
            [_delegate terminalPasteboardReceiptEndedUnexpectedly];
            _copyingToPasteboard = NO;
        }
    }
    if (token->savingData &&
        token->type != VT100_SKIP) {  // This is the old code that echoes to the screen. Its use is discouraged.
        // We are probably copying text to the clipboard until esc]1337;EndCopy^G is received.
        if (token->type != XTERMCC_SET_KVP ||
            ![token.string hasPrefix:@"CopyToClipboard"]) {
            // Append text to clipboard except for initial command that turns on copying to
            // the clipboard.

            [_delegate terminalAppendDataToPasteboard:token.savedData];
        }
    }

    // Disambiguate
    switch (token->type) {
        case VT100CSI_DECSLRM_OR_ANSICSI_SCP:
            if ([_delegate terminalUseColumnScrollRegion]) {
                token->type = VT100CSI_DECSLRM;
                iTermParserSetCSIParameterIfDefault(token.csi, 0, 1);
                iTermParserSetCSIParameterIfDefault(token.csi, 1, 1);
            } else {
                token->type = ANSICSI_SCP;
                iTermParserSetCSIParameterIfDefault(token.csi, 0, 0);
            }
            break;

        default:
            break;
    }

    // Farm out work to the delegate.
    switch (token->type) {
        // our special code
        case VT100_STRING:
            [_delegate terminalAppendString:token.string];
            break;
        case VT100_ASCIISTRING:
            [_delegate terminalAppendAsciiData:token.asciiData];
            break;

        case VT100_UNKNOWNCHAR:
            break;
        case VT100_NOTSUPPORT:
            break;

        //  VT100 CC
        case VT100CC_ENQ:
            [_delegate terminalSendReport:[_answerBackString dataUsingEncoding:self.encoding]];
            break;
        case VT100CC_BEL:
            [_delegate terminalRingBell];
            break;
        case VT100CC_BS:
            [_delegate terminalBackspace];
            break;
        case VT100CC_HT:
            [_delegate terminalAppendTabAtCursor:!_softAlternateScreenMode];
            break;
        case VT100CC_LF:
        case VT100CC_VT:
        case VT100CC_FF:
            [_delegate terminalLineFeed];
            break;
        case VT100CC_CR:
            [_delegate terminalCarriageReturn];
            break;
        case VT100CC_SI:
            self.charset = 0;
            break;
        case VT100CC_SO:
            self.charset = 1;
            break;
        case VT100CC_DC1:
        case VT100CC_DC3:
            // Set XON/XOFF, but why would we want to support that?
            break;
        case VT100CC_CAN:
        case VT100CC_SUB:
        case VT100CC_DEL:
            break;

        // VT100 CSI
        case VT100CSI_CPR:
            break;
        case VT100CSI_CUB:
            [_delegate terminalCursorLeft:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_CUD:
            [_delegate terminalCursorDown:token.csi->p[0] > 0 ? token.csi->p[0] : 1
                         andToStartOfLine:NO];
            break;
        case VT100CSI_CUF:
            [_delegate terminalCursorRight:token.csi->p[0] > 0 ? token.csi->p[0] : 1];
            break;
        case VT100CSI_CUP:
            [_delegate terminalMoveCursorToX:token.csi->p[1] y:token.csi->p[0]];
            break;
        case VT100CSI_CHT:
            for (int i = 0; i < token.csi->p[0]; i++) {
                [_delegate terminalAppendTabAtCursor:!_softAlternateScreenMode];
            }
            break;
        case VT100CSI_CUU:
            [_delegate terminalCursorUp:token.csi->p[0] > 0 ? token.csi->p[0] : 1
                       andToStartOfLine:NO];
            break;
        case VT100CSI_CNL:
            [_delegate terminalCursorDown:token.csi->p[0] > 0 ? token.csi->p[0] : 1
                         andToStartOfLine:YES];
            break;
        case VT100CSI_CPL:
            [_delegate terminalCursorUp:token.csi->p[0] > 0 ? token.csi->p[0] : 1
                       andToStartOfLine:YES];
            break;
        case VT100CSI_DA:
            if (token.csi->p[0] == 0 && [_delegate terminalShouldSendReport]) {
                [_delegate terminalSendReport:[self.output reportDeviceAttribute]];
            }
            break;
        case VT100CSI_DA2:
            if ([_delegate terminalShouldSendReport]) {
                [_delegate terminalSendReport:[self.output reportSecondaryDeviceAttribute]];
            }
            break;
        case VT100CSI_DA3:
            if ([_delegate terminalShouldSendReport]) {
                [_delegate terminalSendReport:[self.output reportTertiaryDeviceAttribute]];
            }
            break;
        case VT100CSI_XDA:
            if ([_delegate terminalShouldSendReport]) {
                if (token.csi->p[0] == 0 || token.csi->p[0] == -1) {
                    [_delegate terminalSendReport:[self.output reportExtendedDeviceAttribute]];
                }
            }
            break;
        case VT100CSI_DECALN:
            [_delegate terminalShowTestPattern];
            break;
        case VT100CSI_DECDHL:
        case VT100CSI_DECDWL:
        case VT100CSI_DECID:
            break;
        case VT100CSI_DECKPNM:
            self.keypadMode = NO;  // Keypad sequences
            break;
        case VT100CSI_DECKPAM:
            self.keypadMode = YES;  // Application sequences
            break;

        case ANSICSI_RCP:
        case VT100CSI_DECRC:
            [self restoreCursor];
            break;

        case ANSICSI_SCP:
            // ANSI SC is just like DECSC, but it's only available when left-right mode is off.
            // There's code before the big switch statement that changes the token type for this
            // case, so if we get here it's definitely the same as DECSC.
            // Fall through.
        case VT100CSI_DECSC:
            [self saveCursor];
            break;

        case VT100CSI_DECSTBM: {
            int top;
            if (token.csi->count == 0 || token.csi->p[0] < 0) {
                top = 0;
            } else {
                top = MAX(1, token.csi->p[0]) - 1;
            }

            int bottom;
            const VT100GridSize size = [_delegate terminalSizeInCells];
            if (token.csi->count < 2 || token.csi->p[1] <= 0) {
                bottom = size.height - 1;
            } else {
                bottom = MIN(size.height, token.csi->p[1]) - 1;
            }

            [_delegate terminalSetScrollRegionTop:top
                                           bottom:bottom];
            // http://www.vt100.net/docs/vt510-rm/DECSTBM.html says:
            // “DECSTBM moves the cursor to column 1, line 1 of the page.”
            break;
        }
        case VT100CSI_DSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:NO];
            break;
        case VT100CSI_DECRQCRA: {
            if ([_delegate terminalIsTrusted]) {
                if (![_delegate terminalCanUseDECRQCRA]) {
                    break;
                }
                [self sendChecksumReportWithId:token.csi->p[0]
                                     rectangle:[self rectangleInToken:token
                                                      startingAtIndex:2
                                                     defaultRectangle:[self defaultRectangle]]];
            }
            break;
        }
        case VT100CSI_DECDSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:YES];
            break;
        case VT100CSI_ED:
            switch (token.csi->p[0]) {
                case 1:
                    [_delegate terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
                    break;

                case 2:
                    [_delegate terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];
                    break;

                case 3:
                    [_delegate terminalClearScrollbackBuffer];
                    break;

                case 0:
                default:
                    [_delegate terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_EL:
            switch (token.csi->p[0]) {
                case 1:
                    [_delegate terminalEraseLineBeforeCursor:YES afterCursor:NO];
                    break;
                case 2:
                    [_delegate terminalEraseLineBeforeCursor:YES afterCursor:YES];
                    break;
                case 0:
                    [_delegate terminalEraseLineBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_HTS:
            [_delegate terminalSetTabStopAtCursor];
            break;
        case VT100CC_SPA:
            self.protectedMode = VT100TerminalProtectedModeISO;
            break;

        case VT100CC_EPA:
            // Note that xterm doesn't update the screen state for EPA even though it does for SPA.
            // I believe that's because the screen state is about whether there could possibly be
            // protected characters on-screen.
            self.dirty = YES;
            _protectedMode = VT100TerminalProtectedModeNone;
            break;

        case VT100CSI_DECSERA:
            [_delegate terminalSelectiveEraseRectangle:[self rectangleInToken:token
                                                              startingAtIndex:0
                                                             defaultRectangle:[self defaultRectangle]]];
            break;

        case VT100CSI_DECSED:
            [_delegate terminalSelectiveEraseInDisplay:token.csi->p[0]];
            break;

        case VT100CSI_DECSEL:
            [_delegate terminalSelectiveEraseInLine:token.csi->p[0]];
            break;

        case VT100CSI_DECSCA:
            // The weird logic about lying to the delegate is based on xterm 369. DECSCA puts the
            // screen in DEC mode regardless of the parameter.
            switch (token.csi->p[0]) {
                case 0:
                case 2:
                    self.dirty = YES;
                    _protectedMode = VT100TerminalProtectedModeNone;
                    break;
                case 1:
                    self.dirty = YES;
                    _protectedMode = VT100TerminalProtectedModeDEC;
                    break;
            }
            [_delegate terminalProtectedModeDidChangeTo:VT100TerminalProtectedModeDEC];
            break;

        case VT100CSI_HVP:
            [_delegate terminalMoveCursorToX:token.csi->p[1] y:token.csi->p[0]];
            break;
        case VT100CSI_NEL:
            // We do the linefeed first because it's a no-op if the cursor is outside the left-
            // right margin. Carriage return will move it to the left margin.
            [_delegate terminalLineFeed];
            [_delegate terminalCarriageReturn];
            break;
        case VT100CSI_IND:
            [_delegate terminalLineFeed];
            break;
        case VT100CSI_RI:
            [_delegate terminalReverseIndex];
            break;
        case VT100CSI_RIS:
            // As far as I can tell, this is not part of the standard and should not be
            // supported.  -- georgen 7/31/11
            break;

        case ANSI_RIS:
            [self resetByUserRequest:NO];
            break;
        case VT100CSI_SM:
        case VT100CSI_RM: {
            int mode = (token->type == VT100CSI_SM);

            for (int i = 0; i < token.csi->count; i++) {
                switch (token.csi->p[i]) {
                    case 4:
                        self.insertMode = mode;
                        break;
                    case 12:
                        self.sendReceiveMode = !mode;
                        break;
                }
            }
            break;
        }
        case VT100CSI_XTREPORTSGR: {
            if ([_delegate terminalIsTrusted]) {
                [self sendSGRReportWithRectangle:[self rectangleInToken:token
                                                        startingAtIndex:0
                                                       defaultRectangle:[self defaultRectangle]]];
            }
            break;
        }

        case XTERMCC_XTPUSHCOLORS:
            [self executePushColors:token];
            break;

        case XTERMCC_XTPOPCOLORS:
            [self executePopColors:token];
            break;

        case XTERMCC_XTREPORTCOLORS:
            [self executeReportColors:token];
            break;

        case XTERMCC_XTSMGRAPHICS:
            [self executeSetRequestGraphics:token];
            break;

        case VT100CSI_DECSTR:
            [self softReset];
            break;

        case VT100CSI_DECSCUSR:
            switch (token.csi->p[0]) {
                case 0:
                    [_delegate terminalResetCursorTypeAndBlink];
                    break;
                case 1:
                    [_delegate terminalSetCursorBlinking:YES];
                    [_delegate terminalSetCursorType:CURSOR_BOX];
                    break;
                case 2:
                    [_delegate terminalSetCursorBlinking:NO];
                    [_delegate terminalSetCursorType:CURSOR_BOX];
                    break;
                case 3:
                    [_delegate terminalSetCursorBlinking:YES];
                    [_delegate terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 4:
                    [_delegate terminalSetCursorBlinking:NO];
                    [_delegate terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 5:
                    [_delegate terminalSetCursorBlinking:YES];
                    [_delegate terminalSetCursorType:CURSOR_VERTICAL];
                    break;
                case 6:
                    [_delegate terminalSetCursorBlinking:NO];
                    [_delegate terminalSetCursorType:CURSOR_VERTICAL];
                    break;
            }
            break;

        case VT100CSI_DECSLRM: {
            int scrollLeft = token.csi->p[0] - 1;
            int scrollRight = token.csi->p[1] - 1;
            const int width = [_delegate terminalSizeInCells].width;
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
            [_delegate terminalSetLeftMargin:scrollLeft rightMargin:scrollRight];
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
             * 0 to 3 inclusive. It is an index into Screen's charsetUsesLineDrawingMode array.
             * In iTerm2, it is an array of booleans where 0 means normal behavior and 1 means
             * line-drawing. There should be a bunch of other values too (like
             * locale-specific char sets). This is pretty far away from the spec,
             * but it works well enough for common behavior, and it seems the spec
             * doesn't work well with common behavior (esp line drawing).
             */
        case VT100CSI_SCS0:
            [_delegate terminalSetCharset:0 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS1:
            [_delegate terminalSetCharset:1 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS2:
            [_delegate terminalSetCharset:2 toLineDrawingMode:(token->code=='0')];
            break;
        case VT100CSI_SCS3:
            [_delegate terminalSetCharset:3 toLineDrawingMode:(token->code=='0')];
            break;

        // The parser sets its own encoding property when these codes are parsed because it must
        // change synchronously, since it also does decoding in its own thread (possibly long before
        // this happens in the main thread).
        case ISO2022_SELECT_UTF_8:
            _encoding = NSUTF8StringEncoding;
            break;
        case ISO2022_SELECT_LATIN_1:
            _encoding = NSISOLatin1StringEncoding;
            break;

        case VT100CSI_SGR:
            [self executeSGR:token];
            break;

        case VT100CSI_DECCARA:
            [self executeDECCARA:token];
            break;

        case VT100CSI_DECRARA:
            [self executeDECRARA:token];
            break;

        case VT100CSI_DECSACE:
            [self executeDECSACE:token];
            break;

        case VT100CSI_DECCRA:
            [self executeDECCRA:token];
            break;

        case VT100CSI_DECFRA:
            [self executeDECFRA:token];
            break;

        case VT100CSI_DECERA:
            [self executeDECERA:token];
            break;

        case VT100CSI_TBC:
            switch (token.csi->p[0]) {
                case 3:
                    [_delegate terminalRemoveTabStops];
                    break;

                case 0:
                    [_delegate terminalRemoveTabStopAtCursor];
            }
            break;

        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            [self executeDecSetReset:token];
            break;

        case VT100CSI_REP:
            [_delegate terminalRepeatPreviousCharacter:token.csi->p[0]];
            break;

        case VT100CSI_DECRQPSR:
            [self executeDECRQPSR:token.csi->p[0]];
            break;

        case VT100_DECFI:
            [self forwardIndex];
            break;

        case VT100_DECBI:
            [self backIndex];
            break;

        case VT100CSI_PUSH_KEY_REPORTING_MODE:
            [self pushKeyReportingFlags:token.csi->p[0]];
            break;

        case VT100CSI_POP_KEY_REPORTING_MODE:
            [self popKeyReportingModes:token.csi->p[0]];
            break;

        case VT100CSI_QUERY_KEY_REPORTING_MODE:
            if ([_delegate terminalShouldSendReport]) {
                [_delegate terminalSendReport:[_output reportKeyReportingMode:self.currentKeyReportingModeStack.lastObject.intValue]];
            }
            break;

        case VT100CSI_DECRQM_DEC:  // CSI ? Pd $ p
            [self executeDECRequestMode:token.csi->p[0]];
            break;

        case VT100CSI_DECRQM_ANSI:  // CSI Pa $ p
            [self executeANSIRequestMode:token.csi->p[0]];
            break;

        case VT100CSI_HPR:
            [self executeCharacterPositionRelative:token.csi->p[0]];
            break;

            // ANSI CSI
        case ANSICSI_CBT:
            [_delegate terminalBackTab:token.csi->p[0]];
            break;
        case ANSICSI_CHA:
            [_delegate terminalSetCursorX:token.csi->p[0]];
            break;
        case ANSICSI_VPA:
            [_delegate terminalSetCursorY:token.csi->p[0]];
            break;
        case ANSICSI_VPR:
            [_delegate terminalCursorDown:token.csi->p[0] > 0 ? token.csi->p[0] : 1
                         andToStartOfLine:NO];
            break;
        case ANSICSI_ECH:
            [_delegate terminalEraseCharactersAfterCursor:token.csi->p[0]];
            break;

        case STRICT_ANSI_MODE:
            // See note on DECANM
            break;

        case ANSICSI_PRINT:
            switch (token.csi->p[0]) {
                case 4:
                    [_delegate terminalPrintBuffer];
                    break;
                case 5:
                    [_delegate terminalBeginRedirectingToPrintBuffer];
                    break;
                default:
                    [_delegate terminalPrintScreen];
            }
            break;

            // XTERM extensions
        case XTERMCC_WIN_TITLE:
            [_delegate terminalSetWindowTitle:[[self sanitizedTitle:[self stringBeforeNewline:token.string]] stringByReplacingControlCharactersWithCaretLetter]];
            break;
        case XTERMCC_WINICON_TITLE: {
            NSString *title = [[self stringBeforeNewline:token.string] stringByReplacingControlCharactersWithCaretLetter];
            NSString *subtitle = [[self subtitleFromIconTitle:token.string] stringByReplacingControlCharactersWithCaretLetter];
            if (!subtitle || title.length > 0) {
                [_delegate terminalSetWindowTitle:title];
                [_delegate terminalSetIconTitle:title];
            }
            if (subtitle) {
                [_delegate terminalSetSubtitle:subtitle];
            }
            break;
        }
        case XTERMCC_PASTE64: {
            if (token.string) {
                NSString *query = nil;
                NSString *decoded = [self decodedBase64PasteCommand:token.string query:&query];
                if (decoded) {
                    [_delegate terminalCopyStringToPasteboard:decoded];
                } else if (query && [_delegate terminalShouldSendReport]) {
                    [_delegate terminalReportPasteboard:query];
                }
            }
            break;
        }
        case XTERMCC_RESET_COLOR:
            [self resetColors:token.string];
            break;
        case XTERMCC_RESET_VT100_TEXT_FOREGROUND_COLOR:
            [_delegate terminalResetColor:VT100TerminalColorIndexText];
            break;
        case XTERMCC_RESET_VT100_TEXT_BACKGROUND_COLOR:
            [_delegate terminalResetColor:VT100TerminalColorIndexBackground];
            break;
        case XTERMCC_RESET_TEXT_CURSOR_COLOR:
            [_delegate terminalResetColor:VT100TerminalColorIndexCursor];
            break;
        case XTERMCC_RESET_HIGHLIGHT_COLOR:
            [_delegate terminalResetColor:VT100TerminalColorIndexSelectionBackground];
            break;
        case XTERMCC_RESET_HIGHLIGHT_FOREGROUND_COLOR:
            [_delegate terminalResetColor:VT100TerminalColorIndexSelectionForeground];
            break;

        case XTERMCC_TEXT_FOREGROUND_COLOR:
            [self executeSetDynamicColor:VT100TerminalColorIndexText
                                     arg:token.string];
            break;

        case XTERMCC_XTPUSHSGR:
            [self executePushSGR:token];
            break;

        case XTERMCC_XTPOPSGR:
            [self executePopSGR];
            break;

        case XTERMCC_TEXT_BACKGROUND_COLOR:
            [self executeSetDynamicColor:VT100TerminalColorIndexBackground
                                     arg:token.string];
            break;
        case XTERMCC_SET_TEXT_CURSOR_COLOR:
            [self executeSetDynamicColor:VT100TerminalColorIndexCursor
                                     arg:token.string];
            break;
        case XTERMCC_SET_HIGHLIGHT_COLOR:
            [self executeSetDynamicColor:VT100TerminalColorIndexSelectionBackground
                                     arg:token.string];
            break;
        case XTERMCC_SET_HIGHLIGHT_FOREGROUND_COLOR:
            [self executeSetDynamicColor:VT100TerminalColorIndexSelectionForeground
                                     arg:token.string];
            break;

        case XTERMCC_FINAL_TERM:
            [self executeFinalTermToken:token];
            break;
        case XTERMCC_ICON_TITLE: {
            NSString *subtitle = [[self subtitleFromIconTitle:token.string] stringByReplacingControlCharactersWithCaretLetter];
            if (!subtitle || token.string.length > 0) {
                [_delegate terminalSetIconTitle:[[self stringBeforeNewline:token.string] stringByReplacingControlCharactersWithCaretLetter]];
            }
            if (subtitle) {
                [_delegate terminalSetSubtitle:subtitle];
            }
            break;
        }
        case VT100CSI_ICH:
            [_delegate terminalInsertEmptyCharsAtCursor:token.csi->p[0]];
            break;
        case VT100CSI_SL:
            [_delegate terminalShiftLeft:token.csi->p[0]];
            break;
        case VT100CSI_SR:
            [_delegate terminalShiftRight:token.csi->p[0]];
            break;
        case XTERMCC_INSLN:
            [_delegate terminalInsertBlankLinesAfterCursor:token.csi->p[0]];
            break;
        case XTERMCC_DELCH:
            [_delegate terminalDeleteCharactersAtCursor:token.csi->p[0]];
            break;
        case XTERMCC_DELLN:
            [_delegate terminalDeleteLinesAtCursor:token.csi->p[0]];
            break;
        case VT100_DECSLPP:
            [_delegate terminalSetRows:MIN(kMaxScreenRows, token.csi->p[0])
                            andColumns:-1];
            break;
        case XTERMCC_WINDOWSIZE:
            [_delegate terminalSetRows:MIN(token.csi->p[1], kMaxScreenRows)
                            andColumns:MIN(token.csi->p[2], kMaxScreenColumns)];
            break;
        case XTERMCC_WINDOWSIZE_PIXEL:
            [_delegate terminalSetPixelWidth:token.csi->p[2]
                                      height:token.csi->p[1]];

            break;
        case XTERMCC_WINDOWPOS:
            [_delegate terminalMoveWindowTopLeftPointTo:NSMakePoint(token.csi->p[1], token.csi->p[2])];
            break;
        case XTERMCC_ICONIFY:
            [_delegate terminalMiniaturize:YES];
            break;
        case XTERMCC_DEICONIFY:
            [_delegate terminalMiniaturize:NO];
            break;
        case XTERMCC_RAISE:
            [_delegate terminalRaise:YES];
            break;
        case XTERMCC_LOWER:
            [_delegate terminalRaise:NO];
            break;
        case XTERMCC_SU:
            [_delegate terminalScrollUp:token.csi->p[0]];
            break;

        case XTERMCC_SD:
            if (token.csi->count == 1) {
                [_delegate terminalScrollDown:token.csi->p[0]];
            }
            break;

        case VT100CSI_SD:
            [_delegate terminalScrollDown:token.csi->p[0]];
            break;

        case XTERMCC_REPORT_WIN_STATE: {
            NSString *s = [NSString stringWithFormat:@"\033[%dt",
                           ([_delegate terminalWindowIsMiniaturized] ? 2 : 1)];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_POS: {
            NSPoint topLeft = [_delegate terminalWindowTopLeftPixelCoordinate];
            NSString *s = [NSString stringWithFormat:@"\033[3;%d;%dt",
                           (int)topLeft.x, (int)topLeft.y];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_PIX_SIZE: {
            // TODO: Some kind of adjustment for panes?
            NSString *s = [NSString stringWithFormat:@"\033[4;%d;%dt",
                           [_delegate terminalWindowHeightInPixels],
                           [_delegate terminalWindowWidthInPixels]];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_SIZE: {
            const VT100GridSize size = [_delegate terminalSizeInCells];
            NSString *s = [NSString stringWithFormat:@"\033[8;%d;%dt",
                           size.height,
                           size.width];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_SCREEN_SIZE: {
            NSString *s = [NSString stringWithFormat:@"\033[9;%d;%dt",
                           [_delegate terminalScreenHeightInCells],
                           [_delegate terminalScreenWidthInCells]];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_ICON_TITLE: {
            NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                           [_delegate terminalIconTitle]];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_TITLE: {
            // NOTE: In versions prior to 2.9.20150415, we used "L" as the leader here, not "l".
            // That was wrong and may cause bug reports due to breaking bugward compatibility.
            // (see xterm docs)
            NSString *s = [NSString stringWithFormat:@"\033]l%@\033\\",
                           [_delegate terminalWindowTitle]];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_PUSH_TITLE: {
            switch (token.csi->p[1]) {
                case 0:
                    [_delegate terminalPushCurrentTitleForWindow:YES];
                    [_delegate terminalPushCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [_delegate terminalPushCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [_delegate terminalPushCurrentTitleForWindow:YES];
                    break;
                // TODO: Support 3 (UTF-8)
            }
            break;
        }
        case XTERMCC_POP_TITLE: {
            switch (token.csi->p[1]) {
                case 0:
                    [_delegate terminalPopCurrentTitleForWindow:YES];
                    [_delegate terminalPopCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [_delegate terminalPopCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [_delegate terminalPopCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
        // Our iTerm specific codes
        case ITERM_USER_NOTIFICATION:
            [_delegate terminalPostUserNotification:token.string];
            break;

        case XTERMCC_MULTITOKEN_HEADER_SET_KVP:
        case XTERMCC_SET_KVP:
            [self executeXtermSetKvp:token];
            break;

        case XTERMCC_MULTITOKEN_BODY:
            // You'd get here if the user stops a file download before it finishes.
            [_delegate terminalAppendString:token.string];
            break;

        case XTERMCC_MULTITOKEN_END:
            // Handled prior to switch.
            break;

        case VT100_BINARY_GARBAGE:
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
        case VT100CSI_SCS:
            break;

        case VT100CSI_RESET_MODIFIERS:
            if (token.csi->count == 0) {
                [self resetSendModifiersWithSideEffects:YES];
                break;
            }
            int resource = token.csi->p[0];
            if (resource >= 0 && resource <= NUM_MODIFIABLE_RESOURCES) {
                _sendModifiers[resource] = @-1;
                self.dirty = YES;
                [self.currentKeyReportingModeStack removeAllObjects];
                [self.delegate terminalDidChangeSendModifiers];
            }
            self.dirty = YES;
            break;

        case VT100CSI_SET_MODIFIERS: {
            if (token.csi->count == 0) {
                [self resetSendModifiersWithSideEffects:YES];
                break;
            }
            const int resource = token.csi->p[0];
            if (resource < 0 || resource >= NUM_MODIFIABLE_RESOURCES) {
                break;
            }
            int value;
            if (token.csi->count == 1) {
                value = -1;
            } else {
                value = token.csi->p[1];
                if (value < 0) {
                    break;
                }
            }
            self.dirty = YES;
            _sendModifiers[resource] = @(value);
            // The protocol described here:
            // https://sw.kovidgoyal.net/kitty/keyboard-protocol/#progressive-enhancement
            // is flawed because if CSI > 4 ; 0 m pops the stack it would leave
            // it in the wrong state if CSI > 4 ; 1 m were sent twice.
            // CSI m will nuke the stack and CSI u will respect it.
            self.dirty = YES;
            [self.currentKeyReportingModeStack removeAllObjects];
            [self.delegate terminalDidChangeSendModifiers];
            break;
        }

        case VT100CSI_DECSCPP:
            [self executeDECSCPP:token.csi->p[0]];
            break;

        case VT100CSI_DECSNLS:
            [self executeDECSNLS:token.csi->p[0]];
            break;

        case VT100CSI_DECIC:
            [_delegate terminalInsertColumns:token.csi->p[0]];
            break;

        case VT100CSI_DECDC:
            [_delegate terminalDeleteColumns:token.csi->p[0]];
            break;

        case XTERMCC_PROPRIETARY_ETERM_EXT:
            [self executeXtermProprietaryEtermExtension:token];
            break;

        case XTERMCC_PWD_URL:
            [self executeWorkingDirectoryURL:token];
            break;

        case XTERMCC_LINK:
            [self executeLink:token];
            break;

        case XTERMCC_SET_PALETTE:
            [self executeXtermSetPalette:token];
            break;

        case XTERMCC_SET_RGB:
            [self executeXtermSetRgb:token];
            break;

        case DCS_TMUX_CODE_WRAP:
            // This is a no-op and it shouldn't happen.
            break;

        case DCS_BEGIN_SYNCHRONIZED_UPDATE:
            self.synchronizedUpdates = YES;
            break;

        case DCS_END_SYNCHRONIZED_UPDATE:
            self.synchronizedUpdates = NO;
            break;

        case DCS_REQUEST_TERMCAP_TERMINFO:
            [self executeRequestTermcapTerminfo:token];
            break;

        case DCS_SIXEL:
            [_delegate terminalAppendSixelData:token.savedData];
            break;

        case DCS_DECRQSS: {
            const NSStringEncoding encoding = _encoding;
            __weak id<VT100TerminalDelegate> delegate = _delegate;
            [[self decrqssPromise:token.string] then:^(NSString * _Nonnull value) {
                [delegate terminalSendReport:[value dataUsingEncoding:encoding]];
            }];
            break;
        }

        case DCS_DECRSPS_DECCIR:
            [self executeDECRSPS_DECCIR:token.string];
            break;

        case DCS_DECRSPS_DECTABSR:
            [self executeDECRSPS_DECTABSR:token.string];
            break;

        case DCS_XTSETTCAP:
            [self executeXTSETTCAP:token.string];
            break;

        default:
            NSLog(@"Unexpected token type %d", (int)token->type);
            break;
    }
}

- (void)pruneKeyReportingModeStack:(NSMutableArray *)array {
    self.dirty = YES;
    const NSInteger maxCount = 1024;
    if (array.count < maxCount) {
        return;
    }
    [array removeObjectsInRange:NSMakeRange(array.count - maxCount, maxCount)];
}

- (void)pushKeyReportingFlags:(VT100TerminalKeyReportingFlags)flags {
    self.dirty = YES;
    DLog(@"Push key reporting flags %@", @(flags));
    [self.currentKeyReportingModeStack addObject:@(flags)];
    [self pruneKeyReportingModeStack:self.currentKeyReportingModeStack];
    DLog(@"Stack:\n%@", self.currentKeyReportingModeStack);
    [self.delegate terminalKeyReportingFlagsDidChange];
}

- (void)popKeyReportingModes:(int)count {
    self.dirty = YES;
    DLog(@"pop key reporting modes count=%@", @(count));
    if (count <= 0) {
        [self popKeyReportingModes:1];
        return;
    }
    for (int i = 0; i < count && self.currentKeyReportingModeStack.count > 0; i++) {
        [self.currentKeyReportingModeStack removeLastObject];
    }
    DLog(@"Stack:\n%@", self.currentKeyReportingModeStack);
    [self.delegate terminalKeyReportingFlagsDidChange];
}

- (void)executeRequestTermcapTerminfo:(VT100Token *)token {
    iTermPromise<NSString *> *(^key)(unsigned short, NSEventModifierFlags, NSString *, NSString *) =
    ^iTermPromise<NSString *> *(unsigned short keyCode,
                                NSEventModifierFlags flags,
                                NSString *characters,
                                NSString *charactersIgnoringModifiers) {
        return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            iTermPromise<NSString *> *unencodedValuePromise =
            [self.delegate terminalStringForKeypressWithCode:keyCode
                                                       flags:flags
                                                  characters:characters
                                 charactersIgnoringModifiers:charactersIgnoringModifiers];
            [[unencodedValuePromise then:^(NSString * _Nonnull value) {
                [seal fulfill:[value hexEncodedString]];
            }] catchError:^(NSError * _Nonnull error) {
                [seal rejectWithDefaultError];
            }];
        }];
    };
    NSString *(^c)(UTF32Char c) = ^NSString *(UTF32Char c) {
        return [NSString stringWithLongCharacter:c];
    };
    static NSString *const kFormat = @"%@=%@";
    __block BOOL ok = NO;
    NSMutableArray<iTermPromise<NSString *> *> *parts = [NSMutableArray array];
    NSDictionary *inverseMap = [VT100DCSParser termcapTerminfoInverseNameDictionary];
    for (int i = 0; i < token.csi->count; i++) {
        NSString *cached = self.stringForKeypress[@(token.csi->p[i])];
        if (cached) {
            if ([cached isKindOfClass:[NSNull class]]) {
                [parts addObject:[iTermPromise promiseDefaultError]];
            } else {
                DLog(@"Use cached value %@ -> %@", @(token.csi->p[i]), cached);
                [parts addObject:[iTermPromise promiseValue:cached]];
            }
            ok = YES;
            continue;
        }
        NSString *stringKey = inverseMap[@(token.csi->p[i])];
        NSString *hexEncodedKey = [stringKey hexEncodedString];
        DLog(@"requestTermcapTerminfo key=%@ for %@", stringKey, token);
        void (^add)(unsigned short, NSEventModifierFlags, NSString *, NSString *) =
            ^void(unsigned short keyCode,
                  NSEventModifierFlags flags,
                  NSString *characters,
                  NSString *charactersIgnoringModifiers) {
                // First get the value. This is legit async.
                iTermPromise<NSString *> *keyStringPromise = key(keyCode, flags, characters, charactersIgnoringModifiers);

                // Once the value is computed, format it into key=value.
                iTermPromise<NSString *> *promise =
                [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
                    [[keyStringPromise then:^(NSString * _Nonnull value) {
                        NSString *kvp = [NSString stringWithFormat:kFormat, hexEncodedKey, value];
                        [seal fulfill:kvp];
                    }] catchError:^(NSError * _Nonnull error) {
                        [seal rejectWithDefaultError];
                    }];
                }];
                DLog(@"Add %@", promise.maybeValue);
                [parts addObject:promise];
                ok = YES;
            };
        switch (token.csi->p[i]) {
            case kDcsTermcapTerminfoRequestTerminfoName:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [_termType hexEncodedString]]]];
                ok = YES;
                break;
            case kDcsTermcapTerminfoRequestTerminalName:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [_termType hexEncodedString]]]];
                ok = YES;
                break;
            case kDcsTermcapTerminfoRequestiTerm2ProfileName:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [[_delegate terminalProfileName] hexEncodedString]]]];
                ok = YES;
                break;
            case kDcsTermcapTerminfoRequestUnrecognizedName:
                break;
            case kDcsTermcapTerminfoRequestNumberOfColors:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [@"256" hexEncodedString]]]];
                break;
            case kDcsTermcapTerminfoRequestNumberOfColors2:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [@"256" hexEncodedString]]]];
                break;
            case kDcsTermcapTerminfoRequestDirectColorWidth:
                [parts addObject:[iTermPromise promiseValue:[NSString stringWithFormat:kFormat,
                                                             hexEncodedKey,
                                                             [@"8" hexEncodedString]]]];
                break;

            // key_backspace               kbs       kb     backspace key
            case kDcsTermcapTerminfoRequestKey_kb:
                add(kVK_Delete, 0, @"\x7f", @"\x7f");
                break;
            // key_dc                      kdch1     kD     delete-character key
            case kDcsTermcapTerminfoRequestKey_kD:
                add(kVK_ForwardDelete, NSEventModifierFlagFunction, c(NSDeleteFunctionKey), c(NSDeleteFunctionKey));
                  break;
            // key_down                    kcud1     kd     down-arrow key
            case kDcsTermcapTerminfoRequestKey_kd:
                add(kVK_DownArrow, NSEventModifierFlagFunction, c(NSDownArrowFunctionKey), c(NSDownArrowFunctionKey));
                  break;
            // key_end                     kend      @7     end key
            case kDcsTermcapTerminfoRequestKey_at_7:
                add(kVK_End, NSEventModifierFlagFunction, c(NSEndFunctionKey), c(NSEndFunctionKey));
                  break;
            // key_enter                   kent      @8     enter/send key
            case kDcsTermcapTerminfoRequestKey_at_8:
                 add(kVK_Return, NSEventModifierFlagFunction, @"\r", @"\r");
                break;
            // key_f1                      kf1       k1     F1 function key
            case kDcsTermcapTerminfoRequestKey_k1:
                add(kVK_F1, NSEventModifierFlagFunction, c(NSF1FunctionKey), c(NSF1FunctionKey));
                break;
            // key_f2                      kf2       k2     F2 function key
            case kDcsTermcapTerminfoRequestKey_k2:
                add(kVK_F2, NSEventModifierFlagFunction, c(NSF2FunctionKey), c(NSF2FunctionKey));
                break;
            // key_f3                      kf3       k3     F3 function key
            case kDcsTermcapTerminfoRequestKey_k3:
                add(kVK_F3, NSEventModifierFlagFunction, c(NSF3FunctionKey), c(NSF3FunctionKey));
                break;
            // key_f4                      kf4       k4     F4 function key
            case kDcsTermcapTerminfoRequestKey_k4:
                add(kVK_F4, NSEventModifierFlagFunction, c(NSF4FunctionKey), c(NSF4FunctionKey));
                break;
            // key_f5                      kf5       k5     F5 function key
            case kDcsTermcapTerminfoRequestKey_k5:
                add(kVK_F5, NSEventModifierFlagFunction, c(NSF5FunctionKey), c(NSF5FunctionKey));
                break;
            // key_f6                      kf6       k6     F6 function key
            case kDcsTermcapTerminfoRequestKey_k6:
                add(kVK_F6, NSEventModifierFlagFunction, c(NSF6FunctionKey), c(NSF6FunctionKey));
                break;
            // key_f7                      kf7       k7     F7 function key
            case kDcsTermcapTerminfoRequestKey_k7:
                add(kVK_F7, NSEventModifierFlagFunction, c(NSF7FunctionKey), c(NSF7FunctionKey));
                break;
            // key_f8                      kf8       k8     F8 function key
            case kDcsTermcapTerminfoRequestKey_k8:
                add(kVK_F8, NSEventModifierFlagFunction, c(NSF8FunctionKey), c(NSF8FunctionKey));
                break;
            // key_f9                      kf9       k9     F9 function key
            case kDcsTermcapTerminfoRequestKey_k9:
                add(kVK_F9, NSEventModifierFlagFunction, c(NSF9FunctionKey), c(NSF9FunctionKey));
                break;
            // key_f10                     kf10      k;     F10 function key
            case kDcsTermcapTerminfoRequestKey_k_semi:
                add(kVK_F10, NSEventModifierFlagFunction, c(NSF10FunctionKey), c(NSF10FunctionKey));
                break;
            // key_f11                     kf11      F1     F11 function key
            case kDcsTermcapTerminfoRequestKey_F1:
                add(kVK_F11, NSEventModifierFlagFunction, c(NSF11FunctionKey), c(NSF11FunctionKey));
                break;
            // key_f12                     kf12      F2     F12 function key
            case kDcsTermcapTerminfoRequestKey_F2:
                add(kVK_F12, NSEventModifierFlagFunction, c(NSF12FunctionKey), c(NSF12FunctionKey));
                break;
                // key_f13                     kf13      F3     F13 function key
            case kDcsTermcapTerminfoRequestKey_F3:
                add(kVK_F13, NSEventModifierFlagFunction, c(NSF13FunctionKey), c(NSF13FunctionKey));
                break;
                // key_f14                     kf14      F4     F14 function key
            case kDcsTermcapTerminfoRequestKey_F4:
                add(kVK_F14, NSEventModifierFlagFunction, c(NSF14FunctionKey), c(NSF14FunctionKey));
                break;
            // key_f15                     kf15      F5     F15 function key
            case kDcsTermcapTerminfoRequestKey_F5:
                add(kVK_F15, NSEventModifierFlagFunction, c(NSF15FunctionKey), c(NSF15FunctionKey));
                break;
            // key_f16                     kf16      F6     F16 function key
            case kDcsTermcapTerminfoRequestKey_F6:
                add(kVK_F16, NSEventModifierFlagFunction, c(NSF16FunctionKey), c(NSF16FunctionKey));
                break;
            // key_f17                     kf17      F7     F17 function key
            case kDcsTermcapTerminfoRequestKey_F7:
                add(kVK_F17, NSEventModifierFlagFunction, c(NSF17FunctionKey), c(NSF17FunctionKey));
                break;
            // key_f18                     kf18      F8     F18 function key
            case kDcsTermcapTerminfoRequestKey_F8:
                add(kVK_F18, NSEventModifierFlagFunction, c(NSF18FunctionKey), c(NSF18FunctionKey));
                break;
            // key_f19                     kf19      F9     F19 function key
            case kDcsTermcapTerminfoRequestKey_F9:
                add(kVK_F19, NSEventModifierFlagFunction, c(NSF19FunctionKey), c(NSF19FunctionKey));
                break;
            // key_home                    khome     kh     home key
            case kDcsTermcapTerminfoRequestKey_kh:
                add(kVK_Home, NSEventModifierFlagFunction, c(NSHomeFunctionKey), c(NSHomeFunctionKey));
                break;
            // key_left                    kcub1     kl     left-arrow key
            case kDcsTermcapTerminfoRequestKey_kl:
                add(kVK_LeftArrow, NSEventModifierFlagFunction, c(NSLeftArrowFunctionKey), c(NSLeftArrowFunctionKey));
                break;
            // key_npage                   knp       kN     next-page key
            case kDcsTermcapTerminfoRequestKey_kN:
                add(kVK_PageDown, NSEventModifierFlagFunction, c(NSPageDownFunctionKey), c(NSPageDownFunctionKey));
                break;
            // key_ppage                   kpp       kP     previous-page key
            case kDcsTermcapTerminfoRequestKey_kP:
                add(kVK_PageUp, NSEventModifierFlagFunction, c(NSPageUpFunctionKey), c(NSPageUpFunctionKey));
                break;
            // key_right                   kcuf1     kr     right-arrow key
            case kDcsTermcapTerminfoRequestKey_kr:
                add(kVK_RightArrow, NSEventModifierFlagFunction, c(NSRightArrowFunctionKey), c(NSRightArrowFunctionKey));
                break;
            // key_sdc                     kDC       *4     shifted delete-character key
            case kDcsTermcapTerminfoRequestKey_star_4:
                add(kVK_ForwardDelete,NSEventModifierFlagFunction |  NSEventModifierFlagShift, c(NSDeleteFunctionKey), c(NSDeleteFunctionKey));
                break;
            // key_send                    kEND      *7     shifted end key
            case kDcsTermcapTerminfoRequestKey_star_7:
                add(kVK_End, NSEventModifierFlagFunction | NSEventModifierFlagShift, c(NSEndFunctionKey), c(NSEndFunctionKey));
                break;
            // key_shome                   kHOM      #2     shifted home key
            case kDcsTermcapTerminfoRequestKey_pound_2:
                add(kVK_Home, NSEventModifierFlagFunction | NSEventModifierFlagShift, c(NSHomeFunctionKey), c(NSHomeFunctionKey));
                break;
            // key_sleft                   kLFT      #4     shifted left-arrow key
            case kDcsTermcapTerminfoRequestKey_pound_4:
                add(kVK_LeftArrow, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagShift, c(NSLeftArrowFunctionKey), c(NSLeftArrowFunctionKey));
                break;
            // key_sright                  kRIT      %i     shifted right-arrow key
            case kDcsTermcapTerminfoRequestKey_pct_i:
                add(kVK_RightArrow, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagShift, c(NSRightArrowFunctionKey), c(NSRightArrowFunctionKey));
                break;
            // key_up                      kcuu1     ku     up-arrow key
            case kDcsTermcapTerminfoRequestKey_ku:
                add(kVK_UpArrow, NSEventModifierFlagFunction, c(NSUpArrowFunctionKey), c(NSUpArrowFunctionKey));
                break;

        }
    }

    __weak __typeof(self) weakSelf = self;
    DLog(@"Gather parts...");
    iTermTokenExecutorUnpauser *unpauser = [self.delegate terminalPause];
    [iTermPromise gather:parts queue:[self.delegate terminalQueue] completion:^(NSArray<iTermOr<id, NSError *> *> * _Nonnull values) {
        NSArray<NSString *> *strings = [values mapWithBlock:^id(iTermOr<id,NSError *> *or) {
            return or.maybeFirst;
        }];
        DLog(@"Got them all. It is %@", strings);
        DLog(@"result is %@ for %@", [strings componentsJoinedByString:@", "], token);
        [weakSelf finishRequestTermcapTerminfoWithValues:strings
                                                      ok:ok];
        DLog(@"Unpause");
        [unpauser unpause];
    }];
}

- (void)finishRequestTermcapTerminfoWithValues:(NSArray<NSString *> *)parts
                                            ok:(BOOL)ok {
    if (gDebugLogging) {
        [parts enumerateObjectsUsingBlock:^(NSString *kvp, NSUInteger idx, BOOL * _Nonnull stop) {
            iTermTuple<NSString *, NSString *> *tuple = [kvp keyValuePair];
            NSMutableString *line = [NSMutableString stringWithFormat:@"%@=",
                                     [[NSString alloc] initWithData:[tuple.firstObject dataFromHexValues] encoding:NSUTF8StringEncoding]];
            NSData *value = [tuple.secondObject dataFromHexValues];
            const char *bytes = (const char *)value.bytes;
            for (NSInteger i = 0; i < value.length; i++) {
                char b = bytes[i];
                [line appendFormat:@"%c", b];
            }
            [line appendString:@"  ( "];
            for (NSInteger i = 0; i < value.length; i++) {
                [line appendFormat:@"%02x ", ((int)bytes[i]) & 0xff];
            }
            [line appendString:@"("];
            DLog(@"%@", line);
        }];
    }

    NSString *s = [NSString stringWithFormat:@"\033P%d+r%@\033\\",
                   ok ? 1 : 0,
                   [parts componentsJoinedByString:@";"]];
    [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
}

- (iTermPromise<NSString *> *)decrqssPromise:(NSString *)pt {
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [[[self decrqssPayloadPromise:pt] then:^(NSString * _Nonnull payload) {
            [seal fulfill:[NSString stringWithFormat:@"%cP1$r%@%@%c\\", VT100CC_ESC, payload, pt, VT100CC_ESC]];

        }] catchError:^(NSError * _Nonnull error) {
            [seal fulfill:[NSString stringWithFormat:@"%cP0$r%@%c\\", VT100CC_ESC, pt, VT100CC_ESC]];
        }];
    }];
}

- (NSString *)decrqssSGR {
    NSArray<NSString *> *codes = [[VT100Terminal sgrCodesForGraphicRendition:graphicRendition_].array sortedArrayUsingSelector:@selector(compare:)];
    return [codes componentsJoinedByString:@";"];
}

- (NSString *)decrqssDECSCL {
    switch (_output.vtLevel) {
        case VT100EmulationLevel100:
            return @"61";
        case VT100EmulationLevel200:
            return @"62";
        case VT100EmulationLevel400:
            return @"64";
    }
    return @"61";
}

- (iTermPromise<NSString *> *)decrqssDECSCUSRPromise {
    return [iTermPromise promise:^(id<iTermPromiseSeal> _Nonnull seal) {
        [self.delegate terminalGetCursorInfoWithCompletion:^(ITermCursorType type, BOOL blinking) {
            int code = 0;
            switch (type) {
                case CURSOR_DEFAULT:
                case CURSOR_BOX:
                    code = 1;
                    break;
                case CURSOR_UNDERLINE:
                    code = 3;
                    break;
                case CURSOR_VERTICAL:
                    code = 5;
                    break;
            }
            if (!blinking) {
                code++;
            }
            [seal fulfill:[@(code) stringValue]];
        }];
    }];
}

- (NSString *)decrqssDECSCA {
    return (_protectedMode != VT100TerminalProtectedModeNone &&
            [_delegate terminalProtectedMode] == VT100TerminalProtectedModeDEC) ? @"1" : @"0";
}

- (NSString *)decrqssDECSTBM {
    return [self.delegate terminalTopBottomRegionString];
}

- (NSString *)decrqssDECSLRM {
    return [self.delegate terminalLeftRightRegionString];
}

- (NSString *)decrqssDECSLPP {
    const int height = MAX(24, [self.delegate terminalSizeInCells].height);
    return [@(height) stringValue];
 }

- (NSString *)decrqssDECSCPP {
    return self.columnMode ? @"132" : @"80";
}

- (NSString *)decrqssDECNLS {
    return [@([self.delegate terminalSizeInCells].height) stringValue];
}

- (iTermPromise<NSString *> *)decrqssPayloadPromise:(NSString *)pt {
    if ([pt isEqualToString:@"m"]) {
        return [iTermPromise promiseValue:[self decrqssSGR]];
    }
    if ([pt isEqualToString:@"\"p"]) {
        return [iTermPromise promiseValue:[self decrqssDECSCL]];
    }
    if ([pt isEqualToString:@" q"]) {
        return [self decrqssDECSCUSRPromise];
    }
    if ([pt isEqualToString:@"\"q"]) {
        return [iTermPromise promiseValue:[self decrqssDECSCA]];
    }
    if ([pt isEqualToString:@"r"]) {
        return [iTermPromise promiseValue:[self decrqssDECSTBM]];
    }
    if ([pt isEqualToString:@"s"]) {
        return [iTermPromise promiseValue:[self decrqssDECSLRM]];
    }
    if ([pt isEqualToString:@"t"]) {
        return [iTermPromise promiseValue:[self decrqssDECSLPP]];
    }
    if ([pt isEqualToString:@"$|"]) {
        return [iTermPromise promiseValue:[self decrqssDECSCPP]];
    }
    if ([pt isEqualToString:@"*|"]) {
        return [iTermPromise promiseValue:[self decrqssDECNLS]];
    }

    return [iTermPromise promiseDefaultError];
}

+ (NSOrderedSet<NSString *> *)sgrCodesForCharacter:(screen_char_t)c
                                externalAttributes:(iTermExternalAttribute *)ea {
    VT100GraphicRendition g = {
        .bold = c.bold,
        .blink = c.blink,
        .invisible = c.invisible,
        .underline = c.underline,
        .underlineStyle = c.underlineStyle,
        .strikethrough = c.strikethrough,
        .reversed = c.inverse,
        .faint = c.faint,
        .italic = c.italic,
        .fgColorCode = c.foregroundColor,
        .fgGreen = c.fgGreen,
        .fgBlue = c.fgBlue,
        .fgColorMode = c.foregroundColorMode,

        .bgColorCode = c.backgroundColor,
        .bgGreen = c.bgGreen,
        .bgBlue = c.bgBlue,
        .bgColorMode = c.backgroundColorMode,

        .hasUnderlineColor = ea.hasUnderlineColor,
        .underlineColor = ea.underlineColor,
    };
    return [self sgrCodesForGraphicRendition:g];
}

+ (NSOrderedSet<NSString *> *)sgrCodesForGraphicRendition:(VT100GraphicRendition)graphicRendition {
    NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
    [result addObject:@"0"];  // for xterm compatibility. Also makes esctest happy.
    switch (graphicRendition.fgColorMode) {
        case ColorModeNormal:
            if (graphicRendition.fgColorCode < 8) {
                [result addObject:[NSString stringWithFormat:@"%@", @(graphicRendition.fgColorCode + 30)]];
            } else if (graphicRendition.fgColorCode < 16) {
                [result addObject:[NSString stringWithFormat:@"%@", @(graphicRendition.fgColorCode + 90)]];
            } else {
                [result addObject:[NSString stringWithFormat:@"38:5:%@", @(graphicRendition.fgColorCode)]];
            }
            break;

        case ColorModeAlternate:
            switch (graphicRendition.fgColorCode) {
                case ALTSEM_DEFAULT:
                    break;
                case ALTSEM_REVERSED_DEFAULT:  // Not sure quite how to handle this, going with the simplest approach for now.
                    [result addObject:@"39"];
                    break;

                case ALTSEM_SYSTEM_MESSAGE:
                    // There is no SGR code for this case.
                    break;

                case ALTSEM_SELECTED:
                case ALTSEM_CURSOR:
                    // This isn't used as far as I can tell.
                    break;

            }
            break;

        case ColorMode24bit:
            [result addObject:[NSString stringWithFormat:@"38:2:1:%@:%@:%@",
              @(graphicRendition.fgColorCode), @(graphicRendition.fgGreen), @(graphicRendition.fgBlue)]];
            break;

        case ColorModeInvalid:
            break;
    }

    switch (graphicRendition.bgColorMode) {
        case ColorModeNormal:
            if (graphicRendition.bgColorCode < 8) {
                [result addObject:[NSString stringWithFormat:@"%@", @(graphicRendition.bgColorCode + 40)]];
            } else if (graphicRendition.bgColorCode < 16) {
                [result addObject:[NSString stringWithFormat:@"%@", @(graphicRendition.bgColorCode + 100)]];
            } else {
                [result addObject:[NSString stringWithFormat:@"48:5:%@", @(graphicRendition.bgColorCode)]];
            }
            break;

        case ColorModeAlternate:
            switch (graphicRendition.bgColorCode) {
                case ALTSEM_DEFAULT:
                    break;
                case ALTSEM_REVERSED_DEFAULT:  // Not sure quite how to handle this, going with the simplest approach for now.
                    [result addObject:@"49"];
                    break;

                case ALTSEM_SYSTEM_MESSAGE:
                    // There is no SGR code for this case.
                    break;

                case ALTSEM_SELECTED:
                case ALTSEM_CURSOR:
                    // This isn't used as far as I can tell.
                    break;

            }
            break;

        case ColorMode24bit:
            [result addObject:[NSString stringWithFormat:@"48:2:1:%@:%@:%@",
              @(graphicRendition.bgColorCode), @(graphicRendition.bgGreen), @(graphicRendition.bgBlue)]];
            break;

        case ColorModeInvalid:
            break;
    }

    if (graphicRendition.bold) {
        [result addObject:@"1"];
    }
    if (graphicRendition.faint) {
        [result addObject:@"2"];
    }
    if (graphicRendition.italic) {
        [result addObject:@"3"];
    }
    if (graphicRendition.underline) {
        switch (graphicRendition.underlineStyle) {
            case VT100UnderlineStyleSingle:
                [result addObject:@"4"];
                break;
            case VT100UnderlineStyleCurly:
                [result addObject:@"4:3"];
                break;
            case VT100UnderlineStyleDouble:
                [result addObject:@"21"];
                break;
        }
    }
    if (graphicRendition.blink) {
        [result addObject:@"5"];
    }
    if (graphicRendition.invisible) {
        [result addObject:@"8"];
    }
    if (graphicRendition.reversed) {
        [result addObject:@"7"];
    }
    if (graphicRendition.strikethrough) {
        [result addObject:@"9"];
    }
    if (graphicRendition.hasUnderlineColor) {
        switch (graphicRendition.underlineColor.mode) {
            case ColorModeNormal:
                [result addObject:[NSString stringWithFormat:@"58:5:%d",
                                   graphicRendition.underlineColor.red]];
                break;
            case ColorMode24bit:
                [result addObject:[NSString stringWithFormat:@"58:2:%d:%d:%d",
                                   graphicRendition.underlineColor.red,
                                   graphicRendition.underlineColor.green,
                                   graphicRendition.underlineColor.blue]];
                 break;
            case ColorModeInvalid:
            case ColorModeAlternate:
                break;
        }
    }
    return result;
}

- (NSArray<NSNumber *> *)xtermParseColorArgument:(NSString *)part {
    if ([part hasPrefix:@"rgb:"]) {
        // The format of this command is "<index>;rgb:<redhex>/<greenhex>/<bluehex>", e.g. "105;rgb:00/cc/ff"
        NSString *componentsString = [part substringFromIndex:4];
        NSArray *components = [componentsString componentsSeparatedByString:@"/"];
        if (components.count == 3) {
            CGFloat colors[3];
            BOOL ok = YES;
            for (int j = 0; j < 3; j++) {
                NSScanner *scanner = [NSScanner scannerWithString:components[j]];
                unsigned int intValue;
                if (![scanner scanHexInt:&intValue]) {
                    ok = NO;
                } else {
                    ok = (intValue <= 255);
                }
                if (ok) {
                    int limit = (1 << (4 * [components[j] length])) - 1;
                    colors[j] = (CGFloat)intValue / (CGFloat)limit;
                } else {
                    break;
                }
            }
            if (ok) {
                return @[ @(colors[0]), @(colors[1]), @(colors[2]) ];
            }
        }
    }
    if ([part hasPrefix:@"#"]) {
        unsigned int red, green, blue;
        if (![part getHashColorRed:&red green:&green blue:&blue]) {
            return nil;
        }
        return @[ @(red / 65535.0), @(green / 65535.0), @(blue / 65535.0) ];
    }
    return nil;
}

- (void)executeXtermSetRgb:(VT100Token *)token {
    NSArray *parts = [token.string componentsSeparatedByString:@";"];
    int theIndex = 0;
    for (int i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        if ((i % 2) == 0 ) {
            theIndex = [part intValue];
        } else {
            NSArray<NSNumber *> *components = [self xtermParseColorArgument:part];
            if (components) {
                // This is supposed to work like XParserColor which doesn't seem to be aware of
                // color spaces besides "rgb" and various irrelevant others. I will take this as license
                // to use the preferred color space.
                NSColor *theColor = [NSColor it_colorInDefaultColorSpaceWithRed:components[0].doubleValue
                                                                          green:components[1].doubleValue
                                                                           blue:components[2].doubleValue
                                                                          alpha:1];
                [_delegate terminalSetColorTableEntryAtIndex:theIndex
                                                       color:theColor];
            } else if ([part isEqualToString:@"?"]) {
                NSColor *theColor = [_delegate terminalColorForIndex:theIndex];
                [_delegate terminalSendReport:[self.output reportColor:theColor atIndex:theIndex prefix:@"4;"]];
            }
        }
    }
}

- (void)executeFileCommandWithValue:(NSString *)value {
    // Takes semicolon-delimited arguments.
    // File=<arg>;<arg>;...;<arg>
    // <arg> is one of:
    //   name=<base64-encoded filename>    Default: Unnamed file
    //   size=<integer file size>          Default: 0
    //   width=auto|<integer>px|<integer>  Default: auto
    //   height=auto|<integer>px|<integer> Default: auto
    //   preserveAspectRatio=<bool>        Default: yes
    //   inline=<bool>                     Default: no
    //   type=<string>                     Default: auto-detect; otherwise gives a mime type ("text/plain"), file extension preceded by dot (".txt"), or language name ("plaintext").
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

    NSString *type = dict[@"type"];

    NSString *widthString = dict[@"width"];
    VT100TerminalUnits widthUnits = kVT100TerminalUnitsCells;
    NSString *heightString = dict[@"height"];
    VT100TerminalUnits heightUnits = kVT100TerminalUnitsCells;
    int width = [widthString intValue];
    if ([widthString isEqualToString:@"auto"]) {
        widthUnits = kVT100TerminalUnitsAuto;
    } else if ([widthString hasSuffix:@"px"]) {
        widthUnits = kVT100TerminalUnitsPixels;
    } else if ([widthString hasSuffix:@"%"]) {
        widthUnits = kVT100TerminalUnitsPercentage;
    }
    int height = [heightString intValue];
    if ([heightString isEqualToString:@"auto"]) {
        heightUnits = kVT100TerminalUnitsAuto;
    } else if ([heightString hasSuffix:@"px"]) {
        heightUnits = kVT100TerminalUnitsPixels;
    } else if ([heightString hasSuffix:@"%"]) {
        heightUnits = kVT100TerminalUnitsPercentage;
    }

    CGFloat insetTop = [dict[@"insetTop"] doubleValue];
    CGFloat insetLeft = [dict[@"insetLeft"] doubleValue];
    CGFloat insetBottom = [dict[@"insetBottom"] doubleValue];
    CGFloat insetRight = [dict[@"insetRight"] doubleValue];

    NSString *name = [dict[@"name"] stringByBase64DecodingStringWithEncoding:NSISOLatin1StringEncoding];
    if (!name) {
        name = @"Unnamed file";
    }
    __weak __typeof(self) weakSelf = self;
    if ([dict[@"inline"] boolValue]) {
        NSEdgeInsets inset = {
            .top = insetTop,
            .left = insetLeft,
            .bottom = insetBottom,
            .right = insetRight
        };
        [_delegate terminalWillReceiveInlineFileNamed:name
                                               ofSize:[dict[@"size"] integerValue]
                                                width:width
                                                units:widthUnits
                                               height:height
                                                units:heightUnits
                                  preserveAspectRatio:[dict[@"preserveAspectRatio"] boolValue]
                                                inset:inset
                                                 type:type
                                           completion:^(BOOL ok) {
                  if (ok) {
                      [weakSelf startReceivingFile];
                  }
        }];
    } else {
        [_delegate terminalWillReceiveFileNamed:name
                                         ofSize:[dict[@"size"] integerValue]
                                     completion:^(BOOL ok) {
            if (ok) {
                [weakSelf startReceivingFile];
            }
        }];
    }
}

- (void)startReceivingFile {
    DLog(@"Start file receipt");
    receivingFile_ = YES;
}

- (NSArray *)keyValuePairInToken:(VT100Token *)token {
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
  return @[ key, value ];
}

- (void)resetColors:(NSString *)arg {
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    NSArray<NSString *> *parts = arg.length == 0 ? @[] : [arg componentsSeparatedByString:@";"];
    for (NSString *part in parts) {
        NSNumber *param = [part integerNumber];
        if (!param) {
            continue;
        }
        if (param.intValue < 0 || param.intValue > 255) {
            continue;
        }
        [indexes addObject:param];
    }
    if (parts.count > 0 && indexes.count == 0) {
        // All inputs were illegal
        return;
    }
    if (indexes.count == 0) {
        for (int i = 0; i < 256; i++) {
            [indexes addObject:@(i)];
        }
    }
    [indexes enumerateObjectsUsingBlock:^(NSNumber * _Nonnull n, NSUInteger idx, BOOL * _Nonnull stop) {
        [_delegate terminalResetColor:n.intValue];
    }];
}

- (int)xtermIndexForTerminalColorIndex:(VT100TerminalColorIndex)ptyIndex {
    switch (ptyIndex) {
        case VT100TerminalColorIndexText:
            return 10;
        case VT100TerminalColorIndexBackground:
            return 11;
        case VT100TerminalColorIndexCursor:
            return 12;
        case VT100TerminalColorIndexSelectionBackground:
            return 17;
        case VT100TerminalColorIndexSelectionForeground:
            return 19;
        case VT100TerminalColorIndexFirst8BitColorIndex:
        case VT100TerminalColorIndexLast8BitColorIndex:
            break;
    }
    return -1;
}

- (void)executeSetDynamicColor:(VT100TerminalColorIndex)ptyIndex arg:(NSString *)arg {
    // arg is like one of:
    //   rgb:ffff/ffff/ffff
    //   ?
    const int xtermIndex = [self xtermIndexForTerminalColorIndex:ptyIndex];
    if ([arg isEqualToString:@"?"]) {
        NSColor *theColor = [_delegate terminalColorForIndex:ptyIndex];
        if (xtermIndex >= 0) {
            [_delegate terminalSendReport:[self.output reportColor:theColor atIndex:xtermIndex prefix:@""]];
        }
    } else {
        NSArray<NSNumber *> *components = [self xtermParseColorArgument:arg];
        if (components) {
            // See comment in executeXtermSetRgb about color spaces.
            NSColor *theColor = [NSColor it_colorInDefaultColorSpaceWithRed:components[0].doubleValue
                                                                      green:components[1].doubleValue
                                                                       blue:components[2].doubleValue
                                                                      alpha:1];
            [_delegate terminalSetColorTableEntryAtIndex:ptyIndex
                                                   color:theColor];
        }
    }
}

- (void)executeWorkingDirectoryURL:(VT100Token *)token {
    if ([_delegate terminalIsTrusted]) {
        [_delegate terminalSetWorkingDirectoryURL:token.string];
    }
}

- (void)executeLink:(VT100Token *)token {
    NSInteger index = [token.string rangeOfString:@";"].location;
    if (index == NSNotFound) {
        return;
    }
    NSString *params = [token.string substringToIndex:index];
    NSString *urlString = [token.string substringFromIndex:index + 1];
    if (urlString.length > 2083) {
        return;
    }
    self.url = urlString.length ? [NSURL URLWithUserSuppliedString:urlString] : nil;
    if (self.url == nil) {
        if (_currentURLCode) {
            [_delegate terminalWillEndLinkWithCode:_currentURLCode];
        }
        _currentURLCode = 0;
        self.urlParams = nil;
    } else {
        self.urlParams = params;
        unsigned int code = [[iTermURLStore sharedInstance] codeForURL:self.url withParams:params];
        if (code) {
            if (_currentURLCode) {
                [_delegate terminalWillEndLinkWithCode:_currentURLCode];
            } else {
                [_delegate terminalWillStartLinkWithCode:code];
            }
            _currentURLCode = code;
        }
    }
    [self updateExternalAttributes];
}

- (void)executeXtermSetKvp:(VT100Token *)token {
    if (!token.string) {
        return;
    }
    NSArray *kvp = [self keyValuePairInToken:token];
    NSString *key = kvp[0];
    NSString *value = kvp[1];
    if ([key isEqualToString:@"CursorShape"]) {
        // Value must be an integer. Bogusly, non-numbers are treated as 0.
        int shape = [value intValue];
        ITermCursorType shapeMap[] = { CURSOR_BOX, CURSOR_VERTICAL, CURSOR_UNDERLINE };
        if (shape >= 0 && shape < sizeof(shapeMap)/sizeof(*shapeMap)) {
            [_delegate terminalSetCursorType:shapeMap[shape]];
        }
    } else if ([key isEqualToString:@"ShellIntegrationVersion"]) {
        [_delegate terminalSetShellIntegrationVersion:value];
    } else if ([key isEqualToString:@"RemoteHost"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalSetRemoteHost:value];
        }
    } else if ([key isEqualToString:@"SetMark"]) {
        [_delegate terminalSaveScrollPositionWithArgument:value];
    } else if ([key isEqualToString:@"StealFocus"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalStealFocus];
        }
    } else if ([key isEqualToString:@"ClearScrollback"]) {
        [_delegate terminalClearBuffer];
    } else if ([key isEqualToString:@"CurrentDir"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalCurrentDirectoryDidChangeTo:value];
        }
    } else if ([key isEqualToString:@"SetProfile"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalProfileShouldChangeTo:(NSString *)value];
        }
    } else if ([key isEqualToString:@"AddNote"] ||  // Deprecated
               [key isEqualToString:@"AddAnnotation"]) {
        [_delegate terminalAddNote:(NSString *)value show:YES];
    } else if ([key isEqualToString:@"AddHiddenNote"] ||  // Deprecated
               [key isEqualToString:@"AddHiddenAnnotation"]) {
        [_delegate terminalAddNote:(NSString *)value show:NO];
    } else if ([key isEqualToString:@"HighlightCursorLine"]) {
        [_delegate terminalSetHighlightCursorLine:value.length ? [value boolValue] : YES];
    } else if ([key isEqualToString:@"ClearCapturedOutput"]) {
        [_delegate terminalClearCapturedOutput];
    } else if ([key isEqualToString:@"CopyToClipboard"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalSetPasteboard:value];
        }
    } else if ([key isEqualToString:@"File"]) {
        if ([_delegate terminalIsTrusted]) {
            [self executeFileCommandWithValue:value];
        } else {
            // Enter multitoken mode to avoid showing the base64 gubbins of the image.
            receivingFile_ = YES;
            [_delegate terminalAppendString:[NSString stringWithLongCharacter:0x1F6AB]];
        }
    } else if ([key isEqualToString:@"Copy"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalBeginCopyToPasteboard];
            _copyingToPasteboard = YES;
        }
    } else if ([key isEqualToString:@"RequestUpload"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalRequestUpload:value];
        }
    } else if ([key isEqualToString:@"BeginFile"]) {
        XLog(@"Deprecated and unsupported code BeginFile received. Use File instead.");
    } else if ([key isEqualToString:@"EndFile"]) {
        XLog(@"Deprecated and unsupported code EndFile received. Use File instead.");
    } else if ([key isEqualToString:@"EndCopy"]) {
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalCopyBufferToPasteboard];
        }
    } else if ([key isEqualToString:@"RequestAttention"]) {
        if ([value isEqualToString:@"fireworks"]) {
            [_delegate terminalRequestAttention:VT100AttentionRequestTypeFireworks];
        } else if ([value isEqualToString:@"once"]) {
            [_delegate terminalRequestAttention:VT100AttentionRequestTypeBounceOnceDockIcon];
        } else if ([value isEqualToString:@"flash"]) {
            [_delegate terminalRequestAttention:VT100AttentionRequestTypeFlash];
        } else if ([value boolValue]) {
            [_delegate terminalRequestAttention:VT100AttentionRequestTypeStartBouncingDockIcon];
        } else {
            [_delegate terminalRequestAttention:VT100AttentionRequestTypeStopBouncingDockIcon];
        }
    } else if ([key isEqualToString:@"SetBackgroundImageFile"]) {
        DLog(@"Handle SetBackgroundImageFile");
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalSetBackgroundImageFile:value];
        }
    } else if ([key isEqualToString:@"SetBadgeFormat"]) {
        [_delegate terminalSetBadgeFormat:value];
    } else if ([key isEqualToString:@"SetUserVar"]) {
        [_delegate terminalSetUserVar:value];
    } else if ([key isEqualToString:@"ReportCellSize"]) {
        if ([_delegate terminalShouldSendReport]) {
            double floatScale;
            NSSize size = [_delegate terminalCellSizeInPoints:&floatScale];
            NSString *width = [[NSString stringWithFormat:@"%0.2f", size.width] stringByCompactingFloatingPointString];
            NSString *height = [[NSString stringWithFormat:@"%0.2f", size.height] stringByCompactingFloatingPointString];
            NSString *scale = [[NSString stringWithFormat:@"%0.2f", floatScale] stringByCompactingFloatingPointString];
            NSString *s = [NSString stringWithFormat:@"\033]1337;ReportCellSize=%@;%@;%@\033\\",
                           height, width, scale];
            [_delegate terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
        }
    } else if ([key isEqualToString:@"UnicodeVersion"]) {
        if ([value hasPrefix:@"push"]) {
            [self pushUnicodeVersion:value];
        } else if ([value hasPrefix:@"pop"]) {
            [self popUnicodeVersion:value];
        } else if ([value isNumeric]) {
            [_delegate terminalSetUnicodeVersion:[value integerValue]];
        }
    } else if ([key isEqualToString:@"SetColors"]) {
        for (NSString *part in [value componentsSeparatedByString:@","]) {
            NSInteger equal = [part rangeOfString:@"="].location;
            if (equal == 0 || equal == NSNotFound || equal + 1 == part.length) {
                continue;
            }
            NSString *name = [part substringToIndex:equal];
            NSString *colorString = [part substringFromIndex:equal + 1];
            [_delegate terminalSetColorNamed:name to:colorString];
        }
    } else if ([key isEqualToString:@"SetKeyLabel"]) {
        NSInteger i = [value rangeOfString:@"="].location;
        if (i != NSNotFound && i > 0 && i + 1 <= value.length) {
            NSString *keyName = [value substringToIndex:i];
            NSString *label = [value substringFromIndex:i + 1];
            [_delegate terminalSetLabel:label forKey:keyName];
        }
    } else if ([key isEqualToString:@"PushKeyLabels"]) {
        [_delegate terminalPushKeyLabels:value];
    } else if ([key isEqualToString:@"PopKeyLabels"]) {
        [_delegate terminalPopKeyLabels:value];
    } else if ([key isEqualToString:@"Disinter"]) {
        [_delegate terminalDisinterSession];
    } else if ([key isEqualToString:@"ReportVariable"]) {
        if ([_delegate terminalIsTrusted] && [_delegate terminalShouldSendReport]) {
            NSData *valueAsData = [value dataUsingEncoding:NSISOLatin1StringEncoding];
            if (!valueAsData) {
                return;
            }
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedData:valueAsData options:0];
            NSString *name = [decodedData stringWithEncoding:self.encoding];
            if (name) {
                [_delegate terminalReportVariableNamed:name];
            }
        }
    } else if ([key isEqualToString:@"Custom"]) {
        if ([_delegate terminalIsTrusted]) {
            // Custom=key1=value1;key2=value2;...;keyN=valueN:payload
            // ex:
            // Custom=id=SenderIdentity:MessageGoesHere
            NSInteger colon = [value rangeOfString:@":"].location;
            if (colon != NSNotFound) {
                NSArray<NSString *> *parts = [[value substringToIndex:colon] componentsSeparatedByString:@";"];
                NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
                [parts enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSInteger equals = [obj rangeOfString:@"="].location;
                    if (equals != NSNotFound) {
                        NSString *key = [obj substringToIndex:equals];
                        NSString *parameterValue = [obj substringFromIndex:equals + 1];
                        parameters[key] = parameterValue;
                    }
                }];
                NSString *payload = [value substringFromIndex:colon + 1];
                [_delegate terminalCustomEscapeSequenceWithParameters:parameters
                                                              payload:payload];
            }
        }
    } else if ([key isEqualToString:@"Capabilities"]) {
        if ([_delegate terminalIsTrusted] && [_delegate terminalShouldSendReport]) {
            [_delegate terminalSendCapabilitiesReport];
        }
    }
}

- (void)executeXtermSetPalette:(VT100Token *)token {
    int n;
    NSColor *theColor = [self colorForXtermCCSetPaletteString:token.string
                                               colorNumberPtr:&n];
    if (theColor) {
        switch (n) {
            case 16:
                [_delegate terminalSetForegroundColor:theColor];
                break;
            case 17:
                [_delegate terminalSetBackgroundColor:theColor];
                break;
            case 18:
                [_delegate terminalSetBoldColor:theColor];
                break;
            case 19:
                [_delegate terminalSetSelectionColor:theColor];
                break;
            case 20:
                [_delegate terminalSetSelectedTextColor:theColor];
                break;
            case 21:
                [_delegate terminalSetCursorColor:theColor];
                break;
            case 22:
                [_delegate terminalSetCursorTextColor:theColor];
                break;
            default:
                [_delegate terminalSetColorTableEntryAtIndex:n color:theColor];
                break;
        }
    }
}

- (void)executeXtermProprietaryEtermExtension:(VT100Token *)token {
    NSString* argument = token.string;
    if (![argument startsWithDigit]) {  // Support for proxy icon, if argument is empty clears current proxy icon
        if ([_delegate terminalIsTrusted]) {
            [_delegate terminalSetProxyIcon:argument];
        }
        return;
    }
    NSArray* parts = [argument componentsSeparatedByString:@";"];
    NSString* func = nil;
    if ([parts count] >= 1) {
        func = [parts objectAtIndex:0];
    }
    if (func) {
        if ([func isEqualToString:@"1"]) {
            // Adjusts a color modifier. This attempts to roughly follow the pattern that Eterm
            // defines.
            //
            // ESC ] 6 ; 1 ; class ; color ; attribute ; value BEL
            // ESC ] 6 ; 1 ; class ; color ; action BEL
            //
            // The "parts" array starts with "1".
            //
            // Adjusts a color modifier.
            // For the 5-argument version:
            //     class: determines which image class will have its color modifier altered:
            //       legal values: bg (background), * (all, unless a value is given),
            //       or a number 0-15 (color palette entries).
            //     color: The color component to modify.
            //       legal values: red, green, or blue.
            //     attribute: how to modify it.
            //       legal values: brightness
            //     value: the new value for this attribute.
            //       legal values: decimal integers in 0-255.
            // Only one code is accepted in the 4-argument version:
            //     class="bg"
            //     color="*"
            //     action="default"
            //     This resets the color to its default value.
            if ([parts count] == 4) {
                NSString* class = parts[1];
                NSString* color = parts[2];
                NSString* attribute = parts[3];
                if ([class isEqualToString:@"bg"] &&
                    [color isEqualToString:@"*"] &&
                    [attribute isEqualToString:@"default"]) {
                    [_delegate terminalSetCurrentTabColor:nil];
                }
            } else if ([parts count] == 5) {
                NSString* class = parts[1];
                NSString* color = parts[2];
                NSString* attribute = parts[3];
                NSString* value = parts[4];
                if ([class isEqualToString:@"bg"] &&
                    [attribute isEqualToString:@"brightness"]) {
                    double numValue = MIN(1, ([value intValue] / 255.0));
                    if (numValue >= 0 && numValue <= 1) {
                        if ([color isEqualToString:@"red"]) {
                            [_delegate terminalSetTabColorRedComponentTo:numValue];
                        } else if ([color isEqualToString:@"green"]) {
                            [_delegate terminalSetTabColorGreenComponentTo:numValue];
                        } else if ([color isEqualToString:@"blue"]) {
                            [_delegate terminalSetTabColorBlueComponentTo:numValue];
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
    // <A>prompt<B>ls -l
    // <C>output 1
    // output 2<D>
    // <A>prompt<B>
    switch ([command characterAtIndex:0]) {
        case 'A':
            // Sequence marking the start of the command prompt (FTCS_PROMPT_START)
            self.softAlternateScreenMode = NO;  // We can reasonably assume alternate screen mode has ended if there's a prompt. Could be ssh dying, etc.
            self.dirty = YES;
            inCommand_ = NO;  // Issue 7954
            self.alternateScrollMode = NO;  // Avoid leaving it on when ssh dies.
            [_delegate terminalPromptDidStart];
            break;

        case 'B':
            // Sequence marking the start of the command read from the command prompt
            // (FTCS_COMMAND_START)
            [_delegate terminalCommandDidStart];
            self.dirty = YES;
            inCommand_ = YES;
            break;

        case 'C':
            // Sequence marking the end of the command read from the command prompt (FTCS_COMMAND_END)
            if (inCommand_) {
                [_delegate terminalCommandDidEnd];
                self.dirty = YES;
                inCommand_ = NO;
            }
            break;

        case 'D':
            // Return code of last command
            if (inCommand_) {
                [_delegate terminalAbortCommand];
                self.dirty = YES;
                inCommand_ = NO;
            } else if (args.count >= 2) {
                int returnCode = [args[1] intValue];
                [_delegate terminalReturnCodeOfLastCommandWas:returnCode];
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
                    [_delegate terminalSemanticTextDidStartOfType:type];
                }
            }
            break;

        case 'F':
            // Semantic text is ending.
            // First argument is same as 'D'.
            if (args.count >= 2) {
                VT100TerminalSemanticTextType type = [args[1] intValue];
                if (type >= 1 && type < kVT100TerminalSemanticTextTypeMax) {
                    [_delegate terminalSemanticTextDidEndOfType:type];
                }
            }
            break;

        case 'G':
            // Update progress bar.
            // First argument: percentage
            // Second argument: title
            if (args.count == 1) {
                [_delegate terminalProgressDidFinish];
            } else {
                int percent = [args[1] intValue];
                double fraction = MAX(MIN(1, 100.0 / (double)percent), 0);
                NSString *label = nil;

                if (args.count >= 3) {
                    label = args[2];
                }

                [_delegate terminalProgressAt:fraction label:label];
            }
            break;

        case 'H':
            // Terminal command.
            [_delegate terminalFinalTermCommand:[args subarrayWithRange:NSMakeRange(1, args.count - 1)]];
            break;
    }
}

typedef NS_ENUM(int, iTermDECRPMSetting)  {
    iTermDECRPMSettingNotRecognized = 0,
    iTermDECRPMSettingSet = 1,
    iTermDECRPMSettingReset = 2,
    iTermDECRPMSettingPermanentlySet = 3,
    iTermDECRPMSettingPermanentlyReset = 4
};

- (NSData *)decrpmForMode:(int)mode
                  setting:(iTermDECRPMSetting)setting
                     ansi:(BOOL)ansi {
    NSString *string;
    if (ansi) {
        string = [NSString stringWithFormat:@"%c[%d;%d$y", VT100CC_ESC, mode, setting];
    } else {
        string = [NSString stringWithFormat:@"%c[?%d;%d$y", VT100CC_ESC, mode, setting];
    }
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)forwardIndex {
    [self.delegate terminalForwardIndex];
}

- (void)backIndex {
    [self.delegate terminalBackIndex];
}

- (void)executeANSIRequestMode:(int)mode {
    const iTermDECRPMSetting setting = [self settingForANSIRequestMode:mode];
    [self.delegate terminalSendReport:[self decrpmForMode:mode setting:setting ansi:YES]];
}

- (void)executeCharacterPositionRelative:(int)dx {
    const int width = [_delegate terminalSizeInCells].width;
    const int proposed = [_delegate terminalCursorX] + dx;
    const int x = MIN(proposed, width);
    [_delegate terminalSetCursorX:x];
}

- (void)executeDECRequestMode:(int)mode {
    [[self promiseOfSettingForDECRequestMode:mode] then:^(NSNumber * _Nonnull value) {
        const iTermDECRPMSetting setting = [value intValue];
        [self.delegate terminalSendReport:[self decrpmForMode:mode setting:setting ansi:NO]];
    }];
}

- (void)executeDECRQPSR:(int)ps {
    switch (ps) {
        case 1:
            [self sendDECCIR];
            break;
        case 2:
            [self sendDECTABSR];
            break;
    }
}

- (void)executeDECRSPS_DECCIR:(NSString *)string {
    self.dirty = YES;
    BOOL ok = NO;
    const VT100OutputCursorInformation info = VT100OutputCursorInformationFromString(string, &ok);
    if (!ok) {
        return;
    }
    [self.delegate terminalSetCursorX:VT100OutputCursorInformationGetCursorX(info)];
    [self.delegate terminalSetCursorY:VT100OutputCursorInformationGetCursorY(info)];
    graphicRendition_.reversed = VT100OutputCursorInformationGetReverseVideo(info);
    graphicRendition_.blink = VT100OutputCursorInformationGetBlink(info);
    graphicRendition_.underline = VT100OutputCursorInformationGetUnderline(info);
    graphicRendition_.bold = VT100OutputCursorInformationGetBold(info);
    if (self.wraparoundMode && VT100OutputCursorInformationGetAutowrapPending(info)) {
        [self.delegate terminalAdvanceCursorPastLastColumn];
    }
    self.originMode = VT100OutputCursorInformationGetOriginMode(info);
    if (VT100OutputCursorInformationGetLineDrawingMode(info)) {
        [self.delegate terminalSetCharset:self.charset toLineDrawingMode:YES];
    }
}

- (void)executeDECRSPS_DECTABSR:(NSString *)string {
    NSArray<NSNumber *> *stops = [[string componentsSeparatedByString:@"/"] mapWithBlock:^NSNumber *(NSString *ts) {
        if (ts.intValue <= 0) {
            return nil;
        }
        return @(ts.intValue);
    }];
    [self.delegate terminalSetTabStops:stops];
}

- (void)executeXTSETTCAP:(NSString *)term {
    // This rather sketchy algorithm comes from xterm's
    // isLegalTcapName. I'm not sure it does anything useful
    // at all, but perhaps it's there to avoid tickling bad
    // behavior in setupterm() so I'll keep it.
    for (NSUInteger i = 0; i < term.length; i++) {
        unichar c = [term characterAtIndex:i];
        if (c >= 127) {
            return;
        }
        if (!isgraph(c)) {
            return;
        }
        if (c == '\\' || c == '|' || c == '.' || c == ':' || c == '\'' || c == '"') {
            return;
        }
    }
    int ignored;
    char *temp = strdup(term.UTF8String);
    if (setupterm(temp, fileno(stdout), &ignored) == OK) {
        // We recognize this $TERM, ok to proceed.
        self.termType = term;
    }
    free(temp);
}

- (void)executePushColors:(VT100Token *)token {
    if (token.csi && token.csi->count > 0) {
        for (int i = 0; i < token.csi->count; i++) {
            [self xtermPushColors:token.csi->p[i]];
        }
    } else {
        [self xtermPushColors:-1];
    }
}

- (void)executePopColors:(VT100Token *)token {
    self.dirty = YES;
    VT100SavedColorsSlot *newColors = nil;
    if (token.csi->count > 0) {
        // Only the last parameter matters. Previous pops are completely over replaced by subsequent pops.
        newColors = [self xtermPopColors:token.csi->p[token.csi->count - 1]];
    } else {
        newColors = [self xtermPopColors:-1];
    }
    if (newColors) {
        [self.delegate terminalRestoreColorsFromSlot:newColors];
    }
}

- (void)executeReportColors:(VT100Token *)token {
    if (![_delegate terminalShouldSendReport]) {
        return;
    }
    [_delegate terminalSendReport:[_output reportSavedColorsUsed:_savedColors.used largestUsed:_savedColors.last]];
}

- (void)executeSetRequestGraphics:(VT100Token *)token {
    if (token.csi->count < 2) {
        return;
    }
    if (token.csi->p[1] == 3) {
        // Need 3 args for "set"
        if (token.csi->count < 3) {
            return;
        }
    }
    switch (token.csi->p[0]) {
        case 1:
            [self executeSetRequestNumberOfColorRegisters:token];
            break;
        case 2:
            [self executeSetRequestSixelGeometry:token];
            break;
        case 3:
            [self executeSetRequestReGISGeometry:token];
            break;
        default:
            [self sendGraphicsAttributeReportForToken:token status:1 value:@""];
            break;
    }
}

- (void)executeSetRequestNumberOfColorRegisters:(VT100Token *)token {
    switch (token.csi->p[1]) {
        case 1:
            [self executeReadNumberOfColorRegisters:token];
            break;
        case 2:
            [self executeResetNumberOfColorRegisters:token];
            break;
        case 3:
            [self executeSetNumberOfColorRegisters:token];
            break;
        case 4:
            [self executeReadMaximumValueOfNumberOfColorRegisters:token];
            break;
        default:
            [self sendGraphicsAttributeReportForToken:token status:2 value:@""];
            break;
    }
}

- (void)executeSetRequestSixelGeometry:(VT100Token *)token {
    switch (token.csi->p[1]) {
        case 1:
            [self executeReadSixelGeometry:token];
            break;
        case 2:
            [self executeResetSixelGeometry:token];
            break;
        case 3:
            [self executeSetSixelGeometry:token];
            break;
        case 4:
            [self executeReadMaximumValueOfSixelGeometry:token];
            break;
        default:
            [self sendGraphicsAttributeReportForToken:token status:2 value:@""];
            break;
    }
}

- (void)executeSetRequestReGISGeometry:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:1 value:@""];
}

- (void)executeReadNumberOfColorRegisters:(VT100Token *)token {
    // First arg after # gives the sixel register number. This is how I determined that
    // SIXEL_PALETTE_MAX corresponds to the number of registers.
    [self sendGraphicsAttributeReportForToken:token status:0 value:[@(SIXEL_PALETTE_MAX) stringValue]];
}

- (void)executeResetNumberOfColorRegisters:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:3 value:@""];
}

- (void)executeSetNumberOfColorRegisters:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:3 value:@""];
}

- (void)executeReadMaximumValueOfNumberOfColorRegisters:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:0 value:[@(SIXEL_PALETTE_MAX) stringValue]];
}

- (void)executeReadSixelGeometry:(VT100Token *)token {
    double scale = 0;
    const NSSize cellSize = [_delegate terminalCellSizeInPoints:&scale];
    const VT100GridSize size = [_delegate terminalSizeInCells];
    const int width = MIN(255, size.width);
    const int height = MIN(255, size.height);

    [self sendGraphicsAttributeReportForToken:token
                                       status:0
                                        value:[NSString stringWithFormat:@"%@;%@",
                                               @(width * cellSize.width * scale),
                                               @(height * cellSize.height * scale)]];
}

- (void)executeResetSixelGeometry:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:3 value:@""];
}

- (void)executeSetSixelGeometry:(VT100Token *)token {
    [self sendGraphicsAttributeReportForToken:token status:3 value:@""];
}

- (void)executeReadMaximumValueOfSixelGeometry:(VT100Token *)token {
    const int maxDimension = [self.delegate terminalMaximumTheoreticalImageDimension];
    [self sendGraphicsAttributeReportForToken:token status:0 value:[NSString stringWithFormat:@"%d;%d", maxDimension, maxDimension]];
}

- (void)executePushSGR:(VT100Token *)token {
    if (_sgrStackSize == VT100TerminalMaxSGRStackEntries) {
        return;
    }
    self.dirty = YES;
    _sgrStack[_sgrStackSize].graphicRendition = self.graphicRendition;
    int j = 0;
    if (token.csi->count == 0) {
        const int values[] = {
            VT100SGRStackAttributeBold,
            VT100SGRStackAttributeFaint,
            VT100SGRStackAttributeItalicized,
            VT100SGRStackAttributeUnderlined,
            VT100SGRStackAttributeBlink,
            VT100SGRStackAttributeInverse,
            VT100SGRStackAttributeInvisible,
            VT100SGRStackAttributeStrikethrough,
            VT100SGRStackAttributeDoubleUnderline,
            VT100SGRStackAttributeForegroundColor,
            VT100SGRStackAttributeBackgroundColor,
        };
        for (int i = 0; i < sizeof(values) / sizeof(*values); i++) {
            _sgrStack[_sgrStackSize].elements[j++] = values[i];
        }
    } else {
        for (int i = 0; i < token.csi->count; i++) {
            const int attr = token.csi->p[i];
            _sgrStack[_sgrStackSize].elements[j++] = attr;
        }
    }
    _sgrStack[_sgrStackSize].numElements = j;
    _sgrStackSize += 1;
}

- (void)executePopSGR {
    if (_sgrStackSize == 0) {
        return;
    }
    self.dirty = YES;
    _sgrStackSize -= 1;
    VT100TerminalSGRStackEntry entry = _sgrStack[_sgrStackSize];

    VT100Token *token = [VT100Token token];
    token->type = VT100CSI_SGR;
    token.string = nil;

    VT100UnderlineStyle desiredUnderlineStyle = 0;
    int wantUnderline = -1;  // -1: no opinion, 0: no, 1: yes

    for (int i = 0; i < entry.numElements; i++) {
        switch (entry.elements[i]) {
            case VT100SGRStackAttributeBold:
                graphicRendition_.bold = entry.graphicRendition.bold;
                break;

            case VT100SGRStackAttributeFaint:
                graphicRendition_.faint = entry.graphicRendition.faint;
                break;

            case VT100SGRStackAttributeItalicized:
                graphicRendition_.italic = entry.graphicRendition.italic;
                break;

            case VT100SGRStackAttributeUnderlined:
                if (entry.graphicRendition.underline && (entry.graphicRendition.underlineStyle == VT100UnderlineStyleSingle ||
                                                         entry.graphicRendition.underlineStyle == VT100UnderlineStyleCurly)) {
                    wantUnderline = 1;
                    desiredUnderlineStyle = entry.graphicRendition.underlineStyle;
                } else if (!entry.graphicRendition.underline) {
                    wantUnderline = 0;
                }
                break;

            case VT100SGRStackAttributeBlink:
                graphicRendition_.blink = entry.graphicRendition.blink;
                break;

            case VT100SGRStackAttributeInverse:
                graphicRendition_.reversed = entry.graphicRendition.reversed;
                break;

            case VT100SGRStackAttributeInvisible:
                graphicRendition_.invisible = entry.graphicRendition.invisible;
                break;

            case VT100SGRStackAttributeStrikethrough:
                graphicRendition_.strikethrough = entry.graphicRendition.strikethrough;
                break;

            case VT100SGRStackAttributeDoubleUnderline:
                if (entry.graphicRendition.underline && entry.graphicRendition.underlineStyle == VT100UnderlineStyleDouble) {
                    wantUnderline = 1;
                    desiredUnderlineStyle = entry.graphicRendition.underlineStyle;
                } else if (!entry.graphicRendition.underline) {
                    wantUnderline = 0;
                }
                break;

            case VT100SGRStackAttributeForegroundColor:
                graphicRendition_.fgColorMode = entry.graphicRendition.fgColorMode;
                graphicRendition_.fgColorCode = entry.graphicRendition.fgColorCode;
                graphicRendition_.fgGreen = entry.graphicRendition.fgGreen;
                graphicRendition_.fgBlue = entry.graphicRendition.fgBlue;
                break;

            case VT100SGRStackAttributeBackgroundColor:
                graphicRendition_.bgColorMode = entry.graphicRendition.bgColorMode;
                graphicRendition_.bgColorCode = entry.graphicRendition.bgColorCode;
                graphicRendition_.bgGreen = entry.graphicRendition.bgGreen;
                graphicRendition_.bgBlue = entry.graphicRendition.bgBlue;
                break;
        }
        if (wantUnderline != -1) {
            graphicRendition_.underline = !!wantUnderline;
            if (wantUnderline) {
                graphicRendition_.underlineStyle = desiredUnderlineStyle;
            }
        }
    }
}

- (void)executeDECSCPP:(int)param {
    int cols = 0;
    switch (param) {
        case 0:
        case 80:
            cols = 80;
            break;
        case 132:
            cols = 132;
            break;
    }
    if (cols == 0) {
        return;
    }
    self.columnMode = (cols == 132);
    [self setWidth:cols
    preserveScreen:YES
    updateRegions:NO
      moveCursorTo:VT100GridCoordMake(-1, -1)
        completion:nil];
}

- (void)executeDECSNLS:(int)rows {
    if (rows <= 0 || rows >= 256) {
        return;
    }
    [_delegate terminalSetRows:rows andColumns:-1];
}

- (void)sendGraphicsAttributeReportForToken:(VT100Token *)token
                                     status:(int)status
                                      value:(NSString *)value {
    if (![_delegate terminalShouldSendReport]) {
        return;
    }
    [_delegate terminalSendReport:[_output reportGraphicsAttributeWithItem:token.csi->p[0]
                                                                    status:status
                                                                     value:value]];
}

// Valuie is either -1 to push a color on top of the stack or a 1-based index into an existing stack.
- (void)xtermPushColors:(int)value {
    VT100SavedColorsSlot *slot = [self.delegate terminalSavedColorsSlot];
    if (!slot) {
        return;
    }
    if (value == 0) {
        return;
    }
    self.dirty = YES;
    if (value < 0) {
        [_savedColors push:slot];
    } else {
        [_savedColors setSlot:slot at:value - 1];
    }
}

- (VT100SavedColorsSlot *)xtermPopColors:(int)value {
    return value <= 0 ? [_savedColors pop] : [_savedColors slotAt:value - 1];
}

- (void)sendDECCIR {
    if ([_delegate terminalShouldSendReport]) {
        const int width = [_delegate terminalSizeInCells].width;
        const int x = _delegate.terminalCursorX;
        const BOOL lineDrawingMode = [_delegate terminalLineDrawingFlagForCharset:self.charset];
        VT100OutputCursorInformation info =
        VT100OutputCursorInformationCreate([_delegate terminalCursorY],
                                           MIN(width, x),
                                           self.graphicRendition.reversed,
                                           self.graphicRendition.blink,
                                           self.graphicRendition.underline,
                                           self.graphicRendition.bold,
                                           [_delegate terminalWillAutoWrap] && self.wraparoundMode,
                                           lineDrawingMode,
                                           self.originMode);
        [_delegate terminalSendReport:[self.output reportCursorInformation:info]];
    }
}

- (void)sendDECTABSR {
    if ([_delegate terminalShouldSendReport]) {
        [_delegate terminalSendReport:[self.output reportTabStops:[_delegate terminalTabStops]]];
    }
}

static iTermDECRPMSetting VT100TerminalDECRPMSettingFromBoolean(BOOL flag) {
    return flag ? iTermDECRPMSettingSet : iTermDECRPMSettingReset;
}

// Number is a iTermDECRPMSetting
static iTermPromise<NSNumber *> *VT100TerminalPromiseOfDECRPMSettingFromBoolean(BOOL flag) {
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [seal fulfill:@(VT100TerminalDECRPMSettingFromBoolean(flag))];
    }];
};

- (iTermDECRPMSetting)settingForANSIRequestMode:(int)mode {
    switch (mode) {
        case 4:
            return VT100TerminalDECRPMSettingFromBoolean(self.insertMode);
        case 12:
            return VT100TerminalDECRPMSettingFromBoolean(self.sendReceiveMode);
    }
    return iTermDECRPMSettingPermanentlyReset;
}

// The number is a iTermDECRPMSetting
- (iTermPromise<NSNumber *> *)promiseOfSettingForDECRequestMode:(int)mode {
    switch (mode) {
        case 1:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.cursorMode);
        case 2:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(YES);
        case 3:
            if (self.allowColumnMode) {
                return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.columnMode);
            } else {
                return VT100TerminalPromiseOfDECRPMSettingFromBoolean(NO);
            }
        case 4:
            // Smooth vs jump scrolling. Not supported.
            break;
        case 5:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.reverseVideo);
        case 6:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.originMode);
        case 7:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.wraparoundMode);
        case 8:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.autorepeatMode);
        case 9:
            // TODO: This should send mouse x&y on button press.
            break;
        case 12: {
            iTermPromise<NSNumber *> *blinkPromise = [self.delegate terminalCursorIsBlinkingPromise];
            return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
                [blinkPromise then:^(NSNumber * _Nonnull value) {
                    [seal fulfill:@(VT100TerminalDECRPMSettingFromBoolean(value.boolValue))];
                }];
            }];
        }
        case 20:
            // This used to be the setter for "line mode", but it wasn't used and it's not
            // supported by xterm. Seemed to have something to do with CR vs LF.
            break;
        case 25: {
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean([self.delegate terminalCursorVisible]);
        }
        case 40:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.allowColumnMode);
        case 41:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.moreFix);
        case 45:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.reverseWraparoundMode);
        case 1047:
        case 1049:
        case 47:
            // alternate screen buffer mode
            if (self.disableSmcupRmcup) {
                return VT100TerminalPromiseOfDECRPMSettingFromBoolean(NO);
            } else {
                return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.softAlternateScreenMode);
            }
        case 66:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.keypadMode);

        case 69:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean([_delegate terminalUseColumnScrollRegion]);
        case 95:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.preserveScreenOnDECCOLM);
        case 1000:
        case 1001:
        case 1002:
        case 1003:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.mouseMode + 1000 == mode);

        case 1004:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.reportFocus && [_delegate terminalFocusReportingAllowed]);

        case 1005:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.mouseFormat == MOUSE_FORMAT_XTERM_EXT);

        case 1006:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.mouseFormat == MOUSE_FORMAT_SGR);

        case 1007:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.alternateScrollMode);

        case 1015:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.mouseFormat == MOUSE_FORMAT_URXVT);

        case 10016:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.mouseFormat == MOUSE_FORMAT_SGR_PIXEL);

        case 1036:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.metaSendsEscape);

        case 1048:
            // lol xterm always returns that this is set, but not with the "permanently set" code.
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(YES);

        case 1337:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.reportKeyUp);

        case 2004:
            // Set bracketed paste mode
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.bracketedPasteMode);

        case 2026:
            return VT100TerminalPromiseOfDECRPMSettingFromBoolean(self.synchronizedUpdates);
    }
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [seal fulfill:@(iTermDECRPMSettingPermanentlyReset)];
    }];
}

- (NSString *)substringAfterSpaceInString:(NSString *)string {
    NSInteger i = [string rangeOfString:@" "].location;
    if (i == NSNotFound) {
        return nil;
    } else {
        return [string substringFromIndex:i + 1];
    }
}

- (void)pushUnicodeVersion:(NSString *)label {
    self.dirty = YES;
    label = [self substringAfterSpaceInString:label];
    [_unicodeVersionStack addObject:@[ label ?: @"", @([_delegate terminalUnicodeVersion]) ]];
}

- (void)popUnicodeVersion:(NSString *)label {
    self.dirty = YES;
    label = [self substringAfterSpaceInString:label];
    while (_unicodeVersionStack.count > 0) {
        id entry = [_unicodeVersionStack lastObject];
        [_unicodeVersionStack removeLastObject];

        NSNumber *value = nil;
        NSString *entryLabel = nil;
        if ([entry isKindOfClass:[NSNumber class]]) {
            // A restored value might have just a number. New values are always an array.
            value = entry;
        } else {
            entryLabel = [entry objectAtIndex:0];
            value = [entry objectAtIndex:1];
        }
        if (label.length == 0 || [label isEqualToString:entryLabel]) {
            [_delegate terminalSetUnicodeVersion:value.integerValue];
            return;
        }
    }
}

- (NSDictionary *)dictionaryForGraphicRendition:(VT100GraphicRendition)graphicRendition {
    return @{ kGraphicRenditionBoldKey: @(graphicRendition.bold),
              kGraphicRenditionBlinkKey: @(graphicRendition.blink),
              kGraphicRenditionInvisibleKey: @(graphicRendition.invisible),
              kGraphicRenditionUnderlineKey: @(graphicRendition.underline),
              kGraphicRenditionStrikethroughKey: @(graphicRendition.strikethrough),
              kGraphicRenditionUnderlineStyle: @(graphicRendition.underlineStyle),
              kGraphicRenditionReversedKey: @(graphicRendition.reversed),
              kGraphicRenditionFaintKey: @(graphicRendition.faint),
              kGraphicRenditionItalicKey: @(graphicRendition.italic),
              kGraphicRenditionForegroundColorCodeKey: @(graphicRendition.fgColorCode),
              kGraphicRenditionForegroundGreenKey: @(graphicRendition.fgGreen),
              kGraphicRenditionForegroundBlueKey: @(graphicRendition.fgBlue),
              kGraphicRenditionForegroundModeKey: @(graphicRendition.fgColorMode),
              kGraphicRenditionBackgroundColorCodeKey: @(graphicRendition.bgColorCode),
              kGraphicRenditionBackgroundGreenKey: @(graphicRendition.bgGreen),
              kGraphicRenditionBackgroundBlueKey: @(graphicRendition.bgBlue),
              kGraphicRenditionBackgroundModeKey: @(graphicRendition.bgColorMode),
              kGraphicRenditionHasUnderlineColorKey: @(graphicRendition.hasUnderlineColor),
              kGraphicRenditionUnderlineColorCodeKey: @(graphicRendition.underlineColor.red),
              kGraphicRenditionUnderlineGreenKey: @(graphicRendition.underlineColor.green),
              kGraphicRenditionUnderlineBlueKey: @(graphicRendition.underlineColor.blue),
              kGraphicRenditionUnderlineModeKey: @(graphicRendition.underlineColor.mode),
    };
}

- (VT100GraphicRendition)graphicRenditionFromDictionary:(NSDictionary *)dict {
    VT100GraphicRendition graphicRendition = { 0 };
    graphicRendition.bold = [dict[kGraphicRenditionBoldKey] boolValue];
    graphicRendition.blink = [dict[kGraphicRenditionBlinkKey] boolValue];
    graphicRendition.invisible = [dict[kGraphicRenditionInvisibleKey] boolValue];
    graphicRendition.underline = [dict[kGraphicRenditionUnderlineKey] boolValue];
    graphicRendition.strikethrough = [dict[kGraphicRenditionStrikethroughKey] boolValue];
    graphicRendition.underlineStyle = [dict[kGraphicRenditionUnderlineStyle] unsignedIntegerValue];
    graphicRendition.reversed = [dict[kGraphicRenditionReversedKey] boolValue];
    graphicRendition.faint = [dict[kGraphicRenditionFaintKey] boolValue];
    graphicRendition.italic = [dict[kGraphicRenditionItalicKey] boolValue];

    graphicRendition.fgColorCode = [dict[kGraphicRenditionForegroundColorCodeKey] intValue];
    graphicRendition.fgGreen = [dict[kGraphicRenditionForegroundGreenKey] intValue];
    graphicRendition.fgBlue = [dict[kGraphicRenditionForegroundBlueKey] intValue];
    graphicRendition.fgColorMode = [dict[kGraphicRenditionForegroundModeKey] intValue];

    graphicRendition.bgColorCode = [dict[kGraphicRenditionBackgroundColorCodeKey] intValue];
    graphicRendition.bgGreen = [dict[kGraphicRenditionBackgroundGreenKey] intValue];
    graphicRendition.bgBlue = [dict[kGraphicRenditionBackgroundBlueKey] intValue];
    graphicRendition.bgColorMode = [dict[kGraphicRenditionBackgroundModeKey] intValue];

    graphicRendition.hasUnderlineColor = [dict[kGraphicRenditionHasUnderlineColorKey] boolValue];
    graphicRendition.underlineColor.red = [dict[kGraphicRenditionUnderlineColorCodeKey] intValue];
    graphicRendition.underlineColor.green = [dict[kGraphicRenditionUnderlineGreenKey] intValue];
    graphicRendition.underlineColor.blue = [dict[kGraphicRenditionUnderlineBlueKey] intValue];
    graphicRendition.underlineColor.mode = [dict[kGraphicRenditionUnderlineModeKey] intValue];

    return graphicRendition;
}

- (NSDictionary *)dictionaryForSavedCursor:(VT100SavedCursor)savedCursor {
    NSMutableArray *lineDrawingArray = [NSMutableArray array];
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [lineDrawingArray addObject:@(savedCursor.lineDrawing[i])];
    }
    return @{ kSavedCursorPositionKey: [NSDictionary dictionaryWithGridCoord:savedCursor.position],
              kSavedCursorCharsetKey: @(savedCursor.charset),
              kSavedCursorLineDrawingArrayKey: lineDrawingArray,
              kSavedCursorGraphicRenditionKey: [self dictionaryForGraphicRendition:savedCursor.graphicRendition],
              kSavedCursorOriginKey: @(savedCursor.origin),
              kSavedCursorWraparoundKey: @(savedCursor.wraparound),
              kSavedCursorUnicodeVersion: @(savedCursor.unicodeVersion),
              kSavedCursorProtectedMode: @(savedCursor.protectedMode)
    };
}

- (VT100SavedCursor)savedCursorFromDictionary:(NSDictionary *)dict {
    VT100SavedCursor savedCursor;
    savedCursor.position = [dict[kSavedCursorPositionKey] gridCoord];
    savedCursor.charset = [dict[kSavedCursorCharsetKey] intValue];
    for (int i = 0; i < NUM_CHARSETS && i < [dict[kSavedCursorLineDrawingArrayKey] count]; i++) {
        NSNumber *n = [dict[kSavedCursorLineDrawingArrayKey] objectAtIndex:i];
        savedCursor.lineDrawing[i] = [n boolValue];
    }
    savedCursor.graphicRendition = [self graphicRenditionFromDictionary:dict[kSavedCursorGraphicRenditionKey]];
    savedCursor.origin = [dict[kSavedCursorOriginKey] boolValue];
    savedCursor.wraparound = [dict[kSavedCursorWraparoundKey] boolValue];
    savedCursor.unicodeVersion = [dict[kSavedCursorUnicodeVersion] integerValue];
    savedCursor.protectedMode = [dict[kSavedCursorProtectedMode] unsignedIntegerValue];

    return savedCursor;
}

- (NSDictionary *)stateDictionary {
    NSDictionary *dict =
        @{ kTerminalStateTermTypeKey: self.termType ?: [NSNull null],
           kTerminalStateAnswerBackStringKey: self.answerBackString ?: [NSNull null],
           kTerminalStateStringEncodingKey: @(self.encoding),
           kTerminalStateCanonicalEncodingKey: @(self.canonicalEncoding),
           kTerminalStateReportFocusKey: @(self.reportFocus),
           kTerminalStateReverseVideoKey: @(self.reverseVideo),
           kTerminalStateOriginModeKey: @(self.originMode),
           kTerminalStateMoreFixKey: @(self.moreFix),
           kTerminalStateWraparoundModeKey: @(self.wraparoundMode),
           kTerminalStateReverseWraparoundModeKey: @(self.reverseWraparoundMode),
           kTerminalStateIsAnsiKey: @(self.isAnsi),
           kTerminalStateAutorepeatModeKey: @(self.autorepeatMode),
           kTerminalStateInsertModeKey: @(self.insertMode),
           kTerminalStateSendReceiveModeKey: @(self.sendReceiveMode),
           kTerminalStateCharsetKey: @(self.charset),
           kTerminalStateMouseModeKey: @(self.mouseMode),
           kTerminalStatePreviousMouseModeKey: @(_previousMouseMode),
           kTerminalStateMouseFormatKey: @(self.mouseFormat),
           kTerminalStateCursorModeKey: @(self.cursorMode),
           kTerminalStateKeypadModeKey: @(self.keypadMode),
           kTerminalStateReportKeyUp: @(self.reportKeyUp),
           kTerminalStateMetaSendsEscape: @(self.metaSendsEscape),
           kTerminalStateAlternateScrollMode: @(self.alternateScrollMode),
           kTerminalStateSGRStack: [self sgrStack],
           kTerminalStateDECSACE: @(_decsaceRectangleMode),
           kTerminalStateSendModifiers: _sendModifiers ?: @[],
           kTerminalStateKeyReportingModeStack_Main: _mainKeyReportingModeStack.copy,
           kTerminalStateKeyReportingModeStack_Alternate: _alternateKeyReportingModeStack.copy,
           kTerminalStateAllowKeypadModeKey: @(self.allowKeypadMode),
           kTerminalStateAllowPasteBracketing: @(self.allowPasteBracketing),
           kTerminalStateBracketedPasteModeKey: @(self.bracketedPasteMode),
           kTerminalStateAnsiModeKey: @YES,  // For compatibility with downgrades; older versions need this for DECRQM.
           kTerminalStateNumLockKey: @(numLock_),
           kTerminalStateGraphicRenditionKey: [self dictionaryForGraphicRendition:graphicRendition_],
           kTerminalStateMainSavedCursorKey: [self dictionaryForSavedCursor:mainSavedCursor_],
           kTerminalStateAltSavedCursorKey: [self dictionaryForSavedCursor:altSavedCursor_],
           kTerminalStateAllowColumnModeKey: @(self.allowColumnMode),
           kTerminalStateColumnModeKey: @(self.columnMode),
           kTerminalStateDisableSMCUPAndRMCUPKey: @(self.disableSmcupRmcup),
           kTerminalStateSoftAlternateScreenModeKey: @(_softAlternateScreenMode),
           kTerminalStateInCommandKey: @(inCommand_),
           kTerminalStateUnicodeVersionStack: _unicodeVersionStack,
           kTerminalStateSynchronizedUpdates: @(self.synchronizedUpdates),
           kTerminalStatePreserveScreenOnDECCOLM: @(self.preserveScreenOnDECCOLM),
           kTerminalStateSavedColors: _savedColors.plist,
           kTerminalStateProtectedMode: @(_protectedMode),
        };
    return [dict dictionaryByRemovingNullValues];
}

- (void)setStateFromDictionary:(NSDictionary *)dict {
    if (!dict) {
        return;
    }
    self.dirty = YES;
    self.termType = [dict[kTerminalStateTermTypeKey] nilIfNull];

    self.answerBackString = dict[kTerminalStateAnswerBackStringKey];
    if ([self.answerBackString isKindOfClass:[NSNull class]]) {
        self.answerBackString = nil;
    }

    self.encoding = [dict[kTerminalStateStringEncodingKey] unsignedIntegerValue];
    self.canonicalEncoding = [dict[kTerminalStateCanonicalEncodingKey] unsignedIntegerValue];
    self.reportFocus = [dict[kTerminalStateReportFocusKey] boolValue];
    self.reverseVideo = [dict[kTerminalStateReverseVideoKey] boolValue];
    self.originMode = [dict[kTerminalStateOriginModeKey] boolValue];
    self.moreFix = [dict[kTerminalStateMoreFixKey] boolValue];
    self.wraparoundMode = [dict[kTerminalStateWraparoundModeKey] boolValue];
    self.reverseWraparoundMode = [dict[kTerminalStateReverseWraparoundModeKey] boolValue];
    self.isAnsi = [dict[kTerminalStateIsAnsiKey] boolValue];
    self.autorepeatMode = [dict[kTerminalStateAutorepeatModeKey] boolValue];
    self.insertMode = [dict[kTerminalStateInsertModeKey] boolValue];
    self.sendReceiveMode = [dict[kTerminalStateSendReceiveModeKey] boolValue];
    self.charset = [dict[kTerminalStateCharsetKey] intValue];
    self.mouseMode = [dict[kTerminalStateMouseModeKey] intValue];
    _previousMouseMode = [dict[kTerminalStatePreviousMouseModeKey] ?: @(MOUSE_REPORTING_NORMAL) intValue];
    self.mouseFormat = [dict[kTerminalStateMouseFormatKey] intValue];
    self.cursorMode = [dict[kTerminalStateCursorModeKey] boolValue];
    self.keypadMode = [dict[kTerminalStateKeypadModeKey] boolValue];
    self.reportKeyUp = [dict[kTerminalStateReportKeyUp] boolValue];
    self.metaSendsEscape = [dict[kTerminalStateMetaSendsEscape] boolValue];
    self.alternateScrollMode = [dict[kTerminalStateAlternateScrollMode] boolValue];
    [self setSGRStack:dict[kTerminalStateSGRStack]];
    _decsaceRectangleMode = [dict[kTerminalStateDECSACE] boolValue];
    self.synchronizedUpdates = [dict[kTerminalStateSynchronizedUpdates] boolValue];
    self.preserveScreenOnDECCOLM = [dict[kTerminalStatePreserveScreenOnDECCOLM] boolValue];
    _savedColors = [VT100SavedColors fromData:[NSData castFrom:dict[kTerminalStateSavedColors]]] ?: [[VT100SavedColors alloc] init];
    self.protectedMode = [dict[kTerminalStateProtectedMode] unsignedIntegerValue];

    if (!_sendModifiers) {
        self.sendModifiers = [@[ @-1, @-1, @-1, @-1, @-1 ] mutableCopy];
    } else {
        while (_sendModifiers.count < NUM_MODIFIABLE_RESOURCES) {
            [_sendModifiers addObject:@-1];
        }
    }
    if ([dict[kTerminalStateKeyReportingModeStack_Deprecated] isKindOfClass:[NSArray class]]) {
        // Migration code path for deprecated key.
        _mainKeyReportingModeStack = [dict[kTerminalStateKeyReportingModeStack_Deprecated] mutableCopy];
        _alternateKeyReportingModeStack = [dict[kTerminalStateKeyReportingModeStack_Deprecated] mutableCopy];
    } else {
        //  Modern code path.
        if ([dict[kTerminalStateKeyReportingModeStack_Main] isKindOfClass:[NSArray class]]) {
            _mainKeyReportingModeStack = [dict[kTerminalStateKeyReportingModeStack_Main] mutableCopy];
        }
        if ([dict[kTerminalStateKeyReportingModeStack_Alternate] isKindOfClass:[NSArray class]]) {
            _alternateKeyReportingModeStack = [dict[kTerminalStateKeyReportingModeStack_Alternate] mutableCopy];
        }
    }
    self.allowKeypadMode = [dict[kTerminalStateAllowKeypadModeKey] boolValue];
    self.allowPasteBracketing = [dict[kTerminalStateAllowPasteBracketing] boolValue];

    self.bracketedPasteMode = [dict[kTerminalStateBracketedPasteModeKey] boolValue];
    numLock_ = [dict[kTerminalStateNumLockKey] boolValue];
    graphicRendition_ = [self graphicRenditionFromDictionary:dict[kTerminalStateGraphicRenditionKey]];
    mainSavedCursor_ = [self savedCursorFromDictionary:dict[kTerminalStateMainSavedCursorKey]];
    altSavedCursor_ = [self savedCursorFromDictionary:dict[kTerminalStateAltSavedCursorKey]];
    self.allowColumnMode = [dict[kTerminalStateAllowColumnModeKey] boolValue];
    self.columnMode = [dict[kTerminalStateColumnModeKey] boolValue];
    self.disableSmcupRmcup = [dict[kTerminalStateDisableSMCUPAndRMCUPKey] boolValue];
    _softAlternateScreenMode = [dict[kTerminalStateSoftAlternateScreenModeKey] boolValue];
    inCommand_ = [dict[kTerminalStateInCommandKey] boolValue];
    [_unicodeVersionStack removeAllObjects];
    if (dict[kTerminalStateUnicodeVersionStack]) {
        [_unicodeVersionStack addObjectsFromArray:dict[kTerminalStateUnicodeVersionStack]];
    }
}

- (NSString *)stringBeforeNewline:(NSString *)title {
    NSCharacterSet *newlinesCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSRange newlineRange = [title rangeOfCharacterFromSet:newlinesCharacterSet];
    if (newlineRange.location == NSNotFound) {
        return title;
    }
    return [title substringToIndex:newlineRange.location];
}

- (NSString *)subtitleFromIconTitle:(NSString *)title {
    NSCharacterSet *newlinesCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSRange newlineRange = [title rangeOfCharacterFromSet:newlinesCharacterSet options:NSBackwardsSearch];
    if (newlineRange.location == NSNotFound) {
        return nil;
    }
    return [title substringFromIndex:NSMaxRange(newlineRange)];
}

- (NSString *)sanitizedTitle:(NSString *)unsafeTitle {
    // Very long titles are slow to draw in the tabs. Limit their length and
    // cut off anything after newline since it wouldn't be visible anyway.
    NSCharacterSet *newlinesCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSRange newlineRange = [unsafeTitle rangeOfCharacterFromSet:newlinesCharacterSet];

    if (newlineRange.location != NSNotFound) {
        return [unsafeTitle substringToIndex:newlineRange.location];
    } else if (unsafeTitle.length > 256) {
        return [unsafeTitle substringToIndex:256];
    } else {
        return unsafeTitle;
    }
}

- (NSArray<NSDictionary *> *)sgrStack {
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < _sgrStackSize; i++) {
        NSMutableArray<NSNumber *> *elements = [NSMutableArray array];
        for (int j = 0; j < _sgrStack[i].numElements; j++) {
            [elements addObject:@(_sgrStack[i].elements[j])];
        }
        [result addObject:@{ @"state": [self dictionaryForGraphicRendition:_sgrStack[i].graphicRendition],
                             @"elements": elements }];
    }
    return result;
}

- (void)setSGRStack:(id)obj {
    self.dirty = YES;
    NSArray *array = [NSArray castFrom:obj];
    if (!array) {
        _sgrStackSize = 0;
        return;
    }
    [array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= VT100TerminalMaxSGRStackEntries) {
            *stop = YES;
            return;
        }
        NSDictionary *dict = [NSDictionary castFrom:obj];
        if (!dict) {
            *stop = YES;
            return;
        }
        NSDictionary *state = [NSDictionary castFrom:dict[@"state"]];
        if (!state) {
            *stop = YES;
            return;
        }
        self->_sgrStack[idx].graphicRendition = [self graphicRenditionFromDictionary:state];
        NSArray *elements = [NSArray castFrom:dict[@"elements"]];
        if (!elements) {
            *stop = YES;
            return;
        }
        if (elements.count > VT100CSIPARAM_MAX) {
            *stop = YES;
            return;
        }
        if ([elements anyWithBlock:^BOOL(id anObject) {
            return ![anObject isKindOfClass:[NSNumber class]];
        }]) {
            *stop = YES;
            return;
        }
        [elements enumerateObjectsUsingBlock:^(NSNumber *_Nonnull n, NSUInteger j, BOOL * _Nonnull stop) {
            _sgrStack[idx].elements[j] = n.intValue;
        }];
        _sgrStack[idx].numElements = elements.count;
        _sgrStackSize = idx;
    }];
}

@end
