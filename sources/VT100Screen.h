#import <Cocoa/Cocoa.h>
#import "PTYNoteViewController.h"
#import "PTYTextViewDataSource.h"
#import "SCPPath.h"
#import "VT100ScreenDelegate.h"
#import "VT100Terminal.h"
#import "VT100Token.h"

@class DVR;
@class iTermGrowlDelegate;
@class iTermMark;
@class iTermStringLine;
@class LineBuffer;
@class IntervalTree;
@class PTYTask;
@class VT100Grid;
@class VT100RemoteHost;
@class VT100ScreenMark;
@protocol iTermMark;
@class VT100Terminal;

// Dictionary keys for -highlightTextInRange:basedAtAbsoluteLineNumber:absoluteLineNumber:color:
extern NSString * const kHighlightForegroundColor;
extern NSString * const kHighlightBackgroundColor;

// Key into dictionaryValue to get screen state.
extern NSString *const kScreenStateKey;

// Key into dictionaryValue[kScreenStateKey] for the number of lines of scrollback history not saved.
// Useful for converting row numbers into the context of the saved contents.
extern NSString *const kScreenStateNumberOfLinesDroppedKey;

extern int kVT100ScreenMinColumns;
extern int kVT100ScreenMinRows;

@interface VT100Screen : NSObject <
    PTYNoteViewControllerDelegate,
    PTYTextViewDataSource,
    VT100GridDelegate,
    VT100TerminalDelegate> {
@private
    // This is here because the unit test needs to manipulate it.
    // Scrollback buffer
    LineBuffer* linebuffer_;
}

@property(nonatomic, retain) VT100Terminal *terminal;
@property(nonatomic, assign) BOOL audibleBell;
@property(nonatomic, assign) BOOL showBellIndicator;
@property(nonatomic, assign) BOOL flashBell;
@property(nonatomic, assign) id<VT100ScreenDelegate> delegate;
@property(nonatomic, assign) BOOL postGrowlNotifications;
@property(nonatomic, assign) BOOL cursorBlinks;
@property(nonatomic, assign) BOOL allowTitleReporting;
@property(nonatomic, assign) unsigned int maxScrollbackLines;
@property(nonatomic, assign) BOOL unlimitedScrollback;
@property(nonatomic, assign) BOOL useColumnScrollRegion;
@property(nonatomic, assign) BOOL saveToScrollbackInAlternateScreen;
@property(nonatomic, retain) DVR *dvr;
@property(nonatomic, assign) BOOL trackCursorLineMovement;
@property(nonatomic, assign) BOOL appendToScrollbackWithStatusBar;
@property(nonatomic, readonly) VT100GridAbsCoordRange lastCommandOutputRange;
@property(nonatomic, assign) BOOL useHFSPlusMapping;
@property(nonatomic, readonly) BOOL shellIntegrationInstalled;  // Just a guess.
@property(nonatomic, readonly) NSIndexSet *animatedLines;

// Assigning to `size` resizes the session and tty. Its contents are reflowed. The alternate grid's
// contents are reflowed, and the selection is updated. It is a little slow so be judicious.
@property(nonatomic, assign) VT100GridSize size;

// Designated initializer.
- (instancetype)initWithTerminal:(VT100Terminal *)terminal;

// Destructively sets the screen size.
- (void)destructivelySetScreenWidth:(int)width height:(int)height;

// Convert a run to one without nulls on either end.
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run;

// Indicates if line drawing mode is enabled for any character set, or if the current character set
// is not G0.
- (BOOL)allCharacterSetPropertiesHaveDefaultValues;

- (void)showCursor:(BOOL)show;

// Preserves the prompt, but erases screen and scrollback buffer.
- (void)clearBuffer;

// Clears the scrollback buffer, leaving screen contents alone.
- (void)clearScrollbackBuffer;

- (void)appendScreenChars:(screen_char_t *)line
                   length:(int)length
             continuation:(screen_char_t)continuation;

// Append a string to the screen at the current cursor position. The terminal's insert and wrap-
// around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
// buffer may change.
- (void)appendStringAtCursor:(NSString *)string;
- (void)appendAsciiDataAtCursor:(AsciiData *)asciiData;

// This is a hacky thing that moves the cursor to the next line, not respecting scroll regions.
// It's used for the tmux status screen.
- (void)crlf;

// Move the cursor down one position, scrolling if needed. Scroll regions are respected.
- (void)linefeed;

// Sets the primary grid's contents and scrollback history. |history| is an array of NSData
// containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
- (void)setHistory:(NSArray *)history;

// Sets the alt grid's contents. |lines| is NSData with screen_char_t's.
- (void)setAltScreen:(NSArray *)lines;

// Load state from tmux. The |state| dictionary has keys from the kStateDictXxx values.
- (void)setTmuxState:(NSDictionary *)state;

// Set the colors in the range relative to the start of the given line number.
// See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors;

// Load a frame from a dvr decoder.
- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

// Save the position of the end of the scrollback buffer without the screen appeneded.
- (void)storeLastPositionInLineBufferAsFindContextSavedPosition;

// Restore the saved position into a passed-in find context (see saveFindContextAbsPos and
// storeLastPositionInLineBufferAsFindContextSavedPosition).
- (void)restoreSavedPositionToFindContext:(FindContext *)context;

- (NSString *)compactLineDump;
- (NSString *)compactLineDumpWithHistory;
- (NSString *)compactLineDumpWithHistoryAndContinuationMarks;

// This is provided for testing only.
- (VT100Grid *)currentGrid;

// Called when a bell is to be run. Applies rate limiting and kicks off the bell indicators
// (notifications, flashing lights, sounds) per user preference.
- (void)activateBell;

// Show an inline image.
- (void)appendImageAtCursorWithName:(NSString *)name
                              width:(int)width
                              units:(VT100TerminalUnits)widthUnits
                             height:(int)height
                              units:(VT100TerminalUnits)heightUnits
                preserveAspectRatio:(BOOL)preserveAspectRatio
                              inset:(NSEdgeInsets)inset
                              image:(NSImage *)image
                               data:(NSData *)data;  // data is optional and only used by animated GIFs

- (void)resetAnimatedLines;

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber;

#pragma mark - Marks and notes

- (VT100ScreenMark *)lastMark;
- (VT100ScreenMark *)lastPromptMark;
- (VT100RemoteHost *)lastRemoteHost;
- (BOOL)markIsValid:(iTermMark *)mark;
- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;
- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval;

// These methods normally only return one object, but if there is a tie, all of the equally-positioned marks/notes are returned.
- (NSArray *)lastMarksOrNotes;
- (NSArray *)firstMarksOrNotes;
- (NSArray *)marksOrNotesBefore:(Interval *)location;
- (NSArray *)marksOrNotesAfter:(Interval *)location;
- (BOOL)containsMark:(id<iTermMark>)mark;

- (void)setWorkingDirectory:(NSString *)workingDirectory onLine:(int)line;
- (NSString *)workingDirectoryOnLine:(int)line;
- (VT100RemoteHost *)remoteHostOnLine:(int)line;
- (VT100ScreenMark *)lastCommandMark;  // last mark representing a command

- (NSDictionary *)contentsDictionary;
- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                knownTriggers:(NSArray *)triggers
                   reattached:(BOOL)reattached;

// Zero-based (as VT100GridCoord always is), unlike -cursorX and -cursorY.
- (void)setCursorPosition:(VT100GridCoord)coord;

@end

@interface VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value;

@end
