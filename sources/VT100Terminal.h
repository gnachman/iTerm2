// Parses input into escape codes, text, etc. Although it's called VT100Terminal, it's more of an
// xterm emulator. The real work of acting on escape codes is handled by the delegate.

#import <Cocoa/Cocoa.h>
#import "iTermCursor.h"
#import "ScreenChar.h"
#import "VT100CSIParser.h"
#import "VT100GraphicRendition.h"
#import "VT100Grid.h"
#import "VT100Output.h"
#import "VT100TerminalDelegate.h"
#import "VT100Parser.h"

#define NUM_CHARSETS 4  // G0...G3. Values returned from -charset go from 0 to this.
#define NUM_MODIFIABLE_RESOURCES 5

// https://sw.kovidgoyal.net/kitty/keyboard-protocol/
typedef NS_OPTIONS(int, VT100TerminalKeyReportingFlags) {
    VT100TerminalKeyReportingFlagsNone = 0,
    VT100TerminalKeyReportingFlagsDisambiguateEscape = (1 << 0),
    VT100TerminalKeyReportingFlagsReportAllEventTypes = (1 << 1),
    VT100TerminalKeyReportingFlagsReportAlternateKeys = (1 << 2),
    VT100TerminalKeyReportingFlagsReportAllKeysAsEscapeCodes = (1 << 3),
    VT100TerminalKeyReportingFlagsReportAssociatedText = (1 << 4)
};

@interface VT100Terminal : NSObject

@property(nonatomic, readonly) VT100Parser *parser;

@property(nonatomic, weak) id<VT100TerminalDelegate> delegate;
@property(nonatomic, copy) NSString *termType;
@property(nonatomic, copy) NSString *answerBackString;
// The current encoding. May be changed by ISO2022_* code.
@property(nonatomic, assign) NSStringEncoding encoding;
// The "canonical" encoding, which is changed by user preference and never
// escape code. On reset, we restore to this.
@property(nonatomic, assign) NSStringEncoding canonicalEncoding;
@property(nonatomic, assign) BOOL reportFocus;

@property(nonatomic, readonly) BOOL reverseVideo;
@property(nonatomic, readonly) BOOL originMode;
@property(nonatomic, readonly) BOOL moreFix;
@property(nonatomic, assign) BOOL wraparoundMode;
@property(nonatomic, assign) BOOL reverseWraparoundMode;
@property(nonatomic, readonly) BOOL isAnsi;
@property(nonatomic, readonly) BOOL autorepeatMode;
@property(nonatomic, assign) BOOL insertMode;
@property(nonatomic, assign) BOOL sendReceiveMode;  // TODO: This is not actually used. It is a write-only variable. I guess I should add support for it but I doubt it's used much.
@property(nonatomic, readonly) int charset;  // G0 through G3
@property(nonatomic, assign) MouseMode mouseMode;
@property(nonatomic, readonly) MouseMode previousMouseMode;  // will never equal NONE
@property(nonatomic, assign) MouseFormat mouseFormat;
@property(nonatomic, assign) BOOL reportKeyUp;
// -1: not set (fall back to profile settings)
// Only index 4 is used to control CSI u (1=on, 0=off, -1=use profile setting)
// Will always have at least 5 values.
@property(nonatomic, readonly) NSMutableArray<NSNumber *> *sendModifiers;

// The current foreground/background color to display (they're swapped when reverseVideo is on).
@property(nonatomic, readonly) screen_char_t foregroundColorCode;
@property(nonatomic, readonly) screen_char_t backgroundColorCode;

// The "real" foreground/background color, which doesn't change with reverseVideo.
@property(nonatomic, readonly) screen_char_t foregroundColorCodeReal;
@property(nonatomic, readonly) screen_char_t backgroundColorCodeReal;

@property(nonatomic, readonly) iTermExternalAttribute *externalAttributes;

@property(nonatomic, assign) BOOL cursorMode;
@property(nonatomic, assign) BOOL keypadMode;  // YES=application, NO=numeric
- (void)forceSetKeypadMode:(BOOL)mode;  // ignores allowKeypadMode
@property(nonatomic, assign) BOOL allowKeypadMode;
@property(nonatomic, assign) BOOL allowPasteBracketing;
@property(nonatomic, assign) BOOL sixelDisplayMode;

// http://www.xfree86.org/current/ctlseqs.html#Bracketed%20Paste%20Mode
@property(nonatomic, assign) BOOL bracketedPasteMode;
@property(nonatomic, readonly) VT100Output *output;

@property(nonatomic, readonly) NSDictionary *stateDictionary;

// True if receiving a file in multitoken mode, or if between BeginFile and
// EndFile codes (which are deprecated).
@property(nonatomic, readonly) BOOL receivingFile;

// If nonnil then we're currently in a hypertext link.
@property(nonatomic, readonly) NSURL *url;
@property(nonatomic, readonly) NSString *urlParams;

// Records whether the remote side thinks we're in alternate screen mode.
@property(nonatomic, readonly) BOOL softAlternateScreenMode;
@property(nonatomic) VT100GraphicRendition graphicRendition;

// If YES, overrides the delegate's -terminalTmuxMode.
@property(nonatomic) BOOL tmuxMode;

// DECSET 1036. This can be overridden by modifyOtherKeys, CSI u mode, and raw key reporting.
@property(nonatomic) BOOL metaSendsEscape;

// Convert input to printable characters.
@property(nonatomic) BOOL literalMode;

@property(nonatomic, readonly) VT100TerminalKeyReportingFlags keyReportingFlags;
@property(nonatomic) BOOL sendResizeNotifications;
@property(nonatomic, readonly) BOOL synchronizedUpdates;
@property(nonatomic, readonly) BOOL preserveScreenOnDECCOLM;
@property(nonatomic, readonly) BOOL alternateScrollMode;
@property(nonatomic, readonly) BOOL decsaceRectangleMode;
@property(nonatomic, readonly) VT100TerminalProtectedMode protectedMode;
@property(nonatomic, strong, readonly) VT100Token *lastToken;

// Values are string, number, or NSNull
@property(nonatomic, copy) NSDictionary<NSString *, id> *terminfoValues;
@property(nonatomic) BOOL wantsDidExecuteCallback;
@property(nonatomic, copy) NSString *currentBlockIDList;
@property(nonatomic, readonly) screen_char_t defaultChar;
@property(nonatomic, readonly) screen_char_t processedDefaultChar;

@property(atomic) BOOL dirty;
typedef NS_ENUM(NSUInteger, VT100TerminalFramerRecoveryMode) {
    VT100TerminalFramerRecoveryModeNone,
    VT100TerminalFramerRecoveryModeRecovering,
    VT100TerminalFramerRecoveryModeSyncing  // between when recovery begins and when the parser starts producing normal tokens
};

@property(nonatomic) VT100TerminalFramerRecoveryMode framerRecoveryMode;
@property(nonatomic) NSInteger framerBoundaryNumber;
@property(nonatomic, readonly) BOOL isExecutingToken;

+ (NSOrderedSet<NSString *> *)sgrCodesForCharacter:(screen_char_t)c
                                externalAttributes:(iTermExternalAttribute *)ea;

- (void)setStateFromDictionary:(NSDictionary *)dict;

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem;
- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem;

- (void)setForeground24BitColor:(NSColor *)color;

- (void)resetCharset;
typedef NS_ENUM(NSUInteger, VT100TerminalResetReason) {
    VT100TerminalResetReasonUserRequest,
    VT100TerminalResetReasonControlSequence,
    VT100TerminalResetReasonBrokenPipe
};
- (void)resetForReason:(VT100TerminalResetReason)reason;
- (void)resetForTmuxUnpause;
// Use this when restarting the login shell. Some features like paste bracketing should be turned
// off for a newly launched program. It differs from resetByUserRequest: by not modifying screen
// contents.
- (void)resetForRelaunch;

// Initialize terminal state for fresh host.
- (void)resetForSSH;

- (void)setDisableSmcupRmcup:(BOOL)value;

// Calls appropriate delegate methods to handle a token.
- (void)executeToken:(VT100Token *)token;

- (void)stopReceivingFile;

// Change saved cursor positions to the origin.
- (void)resetSavedCursorPositions;

// Ensure the saved cursor positions are valid for a new screen size.
- (void)clampSavedCursorToScreenSize:(VT100GridSize)newSize;

// Set the saved cursor position.
- (void)setSavedCursorPosition:(VT100GridCoord)position;

// Returns the saved cursor position.
- (VT100GridCoord)savedCursorPosition;

// Save the cursor position, graphic rendition, and various flags.
- (void)saveCursor;

// Restores values saved in -saveCursor.
- (void)restoreCursor;

// Reset colors, etc. Anything affected by SGR.
- (void)resetGraphicRendition;

- (void)gentleReset;

- (void)resetSendModifiersWithSideEffects:(BOOL)sideEffects;
- (void)toggleAlternateScreen;
- (void)toggleKeyReportingFlag:(VT100TerminalKeyReportingFlags)flag;

// Call this after changing the graphic rendition externally;
- (void)updateDefaultChar;

@property (nonatomic) iTermEmulationLevel emulationLevel;

@end
