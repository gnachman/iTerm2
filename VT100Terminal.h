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
@property(nonatomic, assign) NSStringEncoding encoding;
@property(nonatomic, readonly) BOOL reportFocus;

@property(nonatomic, readonly) BOOL reverseVideo;
@property(nonatomic, readonly) BOOL originMode;
@property(nonatomic, assign) BOOL wraparoundMode;
@property(nonatomic, readonly) BOOL isAnsi;
@property(nonatomic, readonly) BOOL autorepeatMode;
@property(nonatomic, assign) BOOL insertMode;
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
@property(nonatomic, readonly) BOOL bracketedPasteMode;
@property(nonatomic, readonly) VT100Output *output;

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem;
- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem;

- (void)resetCharset;
- (void)resetPreservingPrompt:(BOOL)preservePrompt;


- (void)setDisableSmcupRmcup:(BOOL)value;

// Calls appropriate delegate methods to handle a token.
- (void)executeToken:(VT100Token *)token;

// If you just want to handle low level codes, you can use these methods instead of -executeToken:.
- (void)executeModeUpdates:(VT100Token *)token;
- (void)executeSGR:(VT100Token *)token;

@end
