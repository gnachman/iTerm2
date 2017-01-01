// Parses input into escape codes, text, etc. Although it's called VT100Terminal, it's more of an
// xterm emulator. The real work of acting on escape codes is handled by the delegate.

#import <Cocoa/Cocoa.h>
#import "iTermCursor.h"
#import "ScreenChar.h"
#import "VT100CSIParser.h"
#import "VT100Grid.h"
#import "VT100Output.h"
#import "VT100TerminalDelegate.h"
#import "VT100Parser.h"

#define NUM_CHARSETS 4  // G0...G3. Values returned from -charset go from 0 to this.
#define NUM_MODIFIABLE_RESOURCES 5

@interface VT100Terminal : NSObject

@property(nonatomic, readonly) VT100Parser *parser;

@property(nonatomic, assign) id<VT100TerminalDelegate> delegate;
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
@property(nonatomic, assign) BOOL sendReceiveMode;
@property(nonatomic, readonly) int charset;  // G0 through G3
@property(nonatomic, assign) MouseMode mouseMode;
@property(nonatomic, assign) MouseFormat mouseFormat;

// The current foreground/background color to display (they're swapped when reverseVideo is on).
@property(nonatomic, readonly) screen_char_t foregroundColorCode;
@property(nonatomic, readonly) screen_char_t backgroundColorCode;

// The "real" foreground/background color, which doesn't change with reverseVideo.
@property(nonatomic, readonly) screen_char_t foregroundColorCodeReal;
@property(nonatomic, readonly) screen_char_t backgroundColorCodeReal;

@property(nonatomic, assign) BOOL cursorMode;
@property(nonatomic, assign) BOOL keypadMode;  // YES=application, NO=numeric
@property(nonatomic, assign) BOOL allowKeypadMode;

// http://www.xfree86.org/current/ctlseqs.html#Bracketed%20Paste%20Mode
@property(nonatomic, assign) BOOL bracketedPasteMode;
@property(nonatomic, readonly) VT100Output *output;

@property(nonatomic, readonly) NSDictionary *stateDictionary;

// True if receiving a file in multitoken mode, or if between BeginFile and
// EndFile codes (which are deprecated).
@property(nonatomic, readonly) BOOL receivingFile;
@property(nonatomic, readonly) BOOL copyingToPasteboard;

- (void)setStateFromDictionary:(NSDictionary *)dict;

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem;
- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem;

- (void)setForeground24BitColor:(NSColor *)color;

- (void)resetCharset;
- (void)resetByUserRequest:(BOOL)preservePrompt;


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

@end
