#import <Cocoa/Cocoa.h>
#import "PTYNoteViewController.h"
#import "PTYTextViewDataSource.h"
#import "SCPPath.h"
#import "VT100ScreenDelegate.h"
#import "VT100Terminal.h"
#import "VT100Token.h"

@class DVR;
@class iTermGrowlDelegate;
@class LineBuffer;
@class IntervalTree;
@class PTYTask;
@class VT100Grid;
@class VT100RemoteHost;
@class VT100ScreenMark;
@protocol iTermMark;
@class VT100Terminal;

// Dictionary keys for -highlightTextMatchingRegex:
extern NSString * const kHighlightForegroundColor;
extern NSString * const kHighlightBackgroundColor;
extern int kVT100ScreenMinColumns;
extern int kVT100ScreenMinRows;

@interface VT100Screen : NSObject <
    PTYNoteViewControllerDelegate,
    PTYTextViewDataSource,
    VT100GridDelegate,
    VT100TerminalDelegate> {
    NSMutableSet* tabStops_;
    VT100Terminal *terminal_;
    id<VT100ScreenDelegate> delegate_;  // PTYSession implements this

    // BOOLs indicating, for each of the characters sets, which ones are in line-drawing mode.
    BOOL charsetUsesLineDrawingMode_[4];
    BOOL audibleBell_;
    BOOL showBellIndicator_;
    BOOL flashBell_;
    BOOL postGrowlNotifications_;
    BOOL cursorBlinks_;
    VT100Grid *primaryGrid_;
    VT100Grid *altGrid_;  // may be nil
    VT100Grid *currentGrid_;  // Weak reference. Points to either primaryGrid or altGrid.

    // Max size of scrollback buffer
    unsigned int maxScrollbackLines_;
    // This flag overrides maxScrollbackLines_:
    BOOL unlimitedScrollback_;

    // How many scrollback lines have been lost due to overflow. Periodically reset with
    // -resetScrollbackOverflow.
    int scrollbackOverflow_;

    // A rarely reset count of the number of lines lost to scrollback overflow. Adding this to a
    // line number gives a unique line number that won't be reused when the linebuffer overflows.
    long long cumulativeScrollbackOverflow_;

    // When set, strings, newlines, and linefeeds are appened to printBuffer_. When ANSICSI_PRINT
    // with code 4 is received, it's sent for printing.
    BOOL collectInputForPrinting_;
    NSMutableString *printBuffer_;

    // Scrollback buffer
    LineBuffer* linebuffer_;

    // Current find context.
    FindContext *findContext_;

    // Where we left off searching.
    long long savedFindContextAbsPos_;

    // Used for recording instant replay.
    DVR* dvr_;
    BOOL saveToScrollbackInAlternateScreen_;

    // OK to report window title?
    BOOL allowTitleReporting_;

    // Holds notes on alt/primary grid (the one we're not in). The origin is the top-left of the
    // grid.
    IntervalTree *savedIntervalTree_;

    // All currently visible marks and notes. Maps an interval of
    //   (startx + absstarty * (width+1)) to (endx + absendy * (width+1))
    // to an id<IntervalTreeObject>, which is either PTYNoteViewController or VT100ScreenMark.
    IntervalTree *intervalTree_;

    NSMutableDictionary *markCache_;  // Maps an absolute line number to a VT100ScreenMark.
    VT100GridCoordRange markCacheRange_;

    // Location of the start of the current command, or -1 for none. Y is absolute.
    int commandStartX_;
    long long commandStartY_;

    // Cached copies of terminal attributes
    BOOL _wraparoundMode;
    BOOL _ansi;
    BOOL _insert;
    
    BOOL _shellIntegrationInstalled;
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

// Designated initializer.
- (id)initWithTerminal:(VT100Terminal *)terminal;

// Destructively sets the screen size.
- (void)destructivelySetScreenWidth:(int)width height:(int)height;

// Resize the screen, preserving its contents, alt-grid's contents, and selection.
- (void)resizeWidth:(int)new_width height:(int)height;

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

// Set the colors in the prototype char to all text on screen that matches the regex.
// See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
- (void)highlightTextMatchingRegex:(NSString *)regex
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
                              image:(NSImage *)image;

#pragma mark - Marks and notes

- (VT100ScreenMark *)lastMark;
- (BOOL)markIsValid:(VT100ScreenMark *)mark;
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
- (void)appendFromDictionary:(NSDictionary *)dictionary;

@end

@interface VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value;

@end
