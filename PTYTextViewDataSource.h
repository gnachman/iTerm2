// DataSource for PTYTextView.
#import "iTermCursor.h"
#import "ScreenChar.h"
#import "LineBuffer.h"
#import "VT100GridTypes.h"

// Images that the view can flash.
typedef enum {
    FlashBell, FlashWrapToTop, FlashWrapToBottom
} FlashImage;

@class PTYNoteViewController;
@class PTYSession;
@class PTYTask;
@class SCPPath;
@class VT100RemoteHost;
@class VT100ScreenMark;
@class VT100Terminal;

@protocol PTYTextViewDataSource

- (VT100Terminal *)terminal;
- (int)numberOfLines;
- (int)width;
- (int)height;

// Cursor position is 1-based (the top left is at 1,1).
- (int)cursorX;
- (int)cursorY;

// This function is dangerous! It writes to an internal buffer and returns a
// pointer to it. Better to use getLineAtIndex:withBuffer:.
- (screen_char_t *)getLineAtIndex:(int)theIndex;

- (screen_char_t *)getLineAtScreenIndex:(int)theIndex;

// Provide a buffer as large as sizeof(screen_char_t*) * ([SCREEN width] + 1)
- (screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer;
- (int)numberOfScrollbackLines;
- (int)scrollbackOverflow;
- (void)resetScrollbackOverflow;
- (long long)totalScrollbackOverflow;
- (long long)absoluteLineNumberOfCursor;
- (BOOL)continueFindAllResults:(NSMutableArray*)results
                     inContext:(FindContext*)context;
- (FindContext*)findContext;

// Initialize the find context.
- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
         ignoringCase:(BOOL)ignoreCase
                regex:(BOOL)regex
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offsetof  // Offset in the direction of searching (offset=1 while searching backwards means start one char before x,y)
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults;

// Save the position of the current find context (with the screen appended).
- (void)saveFindContextAbsPos;

// Return a human-readable dump of the screen contents.
- (NSString*)debugString;
- (BOOL)isAllDirty;
- (void)resetAllDirty;

// Set the cursor dirty. Cursor coords are different because of how they handle
// being in the WIDTH'th column (it wraps to the start of the next line)
// whereas that wouldn't normally be a legal X value. If possible, the char to the right of the
// cursor is also set dirty to handle DWCs.
- (void)setCharDirtyAtCursorX:(int)x Y:(int)y;
- (void)setLineDirtyAtY:(int)y;

// Check if any the character at x,y has been marked dirty.
- (BOOL)isDirtyAtX:(int)x Y:(int)y;
- (NSIndexSet *)dirtyIndexesOnLine:(int)line;
- (void)resetDirty;

// Save the current state to a new frame in the dvr.
- (void)saveToDvr;

// If this returns true then the textview will broadcast iTermTabContentsChanged
// when a dirty char is found.
- (BOOL)shouldSendContentsChangedNotification;

// Smallest range that contains all dirty chars for a line at a screen location.
// NOTE: y is a grid index and cannot refer to scrollback history.
- (VT100GridRange)dirtyRangeForLine:(int)y;

// Returns the last modified date for a given line.
- (NSDate *)timestampForLine:(int)y;

- (void)addNote:(PTYNoteViewController *)note inRange:(VT100GridCoordRange)range;
- (void)removeInaccessibleNotes;

// Returns all notes in a range of cells.
- (NSArray *)notesInRange:(VT100GridCoordRange)range;

- (VT100GridCoordRange)coordRangeOfNote:(PTYNoteViewController *)note;
- (NSArray *)charactersWithNotesOnLine:(int)line;
- (VT100ScreenMark *)markOnLine:(int)line;
- (NSString *)workingDirectoryOnLine:(int)line;
- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line;
- (VT100RemoteHost *)remoteHostOnLine:(int)line;

// Check whether in alternate screen mode
- (BOOL)isAlternate;

- (void)clearBuffer;

@end
