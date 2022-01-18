// DataSource for PTYTextView.
#import "iTermColorMap.h"
#import "iTermCursor.h"
#import "iTermFindDriver.h"
#import "iTermLogicalMovementHelper.h"
#import "ScreenChar.h"
#import "LineBuffer.h"
#import "VT100Grid.h"
#import "VT100Terminal.h"

@class iTermColorMap;
@class iTermExternalAttributeIndex;
@class PTYAnnotation;
@class PTYNoteViewController;
@class PTYSession;
@class PTYTask;
@class SCPPath;
@class VT100Grid;
@class VT100RemoteHost;
@class VT100ScreenMark;
@class VT100Terminal;

@protocol PTYTextViewSynchronousUpdateStateReading<NSObject>
@property (nonatomic, strong, readonly) id<VT100GridReading> grid;
@property (nonatomic, readonly) BOOL cursorVisible;
@property (nonatomic, strong, readonly) id<iTermColorMapReading> colorMap;
@end

@interface PTYTextViewSynchronousUpdateState : NSObject<PTYTextViewSynchronousUpdateStateReading, NSCopying>
@property (nonatomic, strong) VT100Grid *grid;
@property (nonatomic) BOOL cursorVisible;
@property (nonatomic, strong) iTermColorMap *colorMap;
@end

@protocol iTermTextDataSource <NSObject>

- (int)width;
- (int)numberOfLines;
// Deprecated - use fetchLine:block: instead because it manages the lifetime of the ScreenCharArray safely.
- (ScreenCharArray *)screenCharArrayForLine:(int)line;
- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index;
- (long long)totalScrollbackOverflow;
- (iTermExternalAttributeIndex *)externalAttributeIndexForLine:(int)y;
- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *sct))block;

@end


@protocol PTYTextViewDataSource <iTermLogicalMovementHelperDelegate, iTermTextDataSource>

- (BOOL)terminalReverseVideo;
- (MouseMode)terminalMouseMode;
- (VT100Output *)terminalOutput;
- (BOOL)terminalAlternateScrollMode;
- (BOOL)terminalSoftAlternateScreenMode;
- (BOOL)terminalAutorepeatMode;
- (int)height;

// Cursor position is 1-based (the top left is at 1,1).
- (int)cursorX;
- (int)cursorY;

// Provide a buffer as large as sizeof(screen_char_t*) * ([SCREEN width] + 1)
- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer;
- (NSArray<ScreenCharArray *> *)linesInRange:(NSRange)range;
- (int)numberOfScrollbackLines;
- (int)scrollbackOverflow;
- (long long)absoluteLineNumberOfCursor;
- (BOOL)continueFindAllResults:(NSMutableArray*)results
                     inContext:(FindContext*)context;
- (FindContext*)findContext;

// Initialize the find context.
- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
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
- (void)setRangeOfCharsAnimated:(NSRange)range onLine:(int)line;
- (NSIndexSet *)animatedLines;
- (void)resetAnimatedLines;

// Check if any the character at x,y has been marked dirty.
- (BOOL)isDirtyAtX:(int)x Y:(int)y;
- (NSIndexSet *)dirtyIndexesOnLine:(int)line;
#warning TODO: Delete this after making a copy of the state in sync
- (void)resetDirty;

// Save the current state to a new frame in the dvr.
- (void)saveToDvr:(NSIndexSet *)cleanLines;

// If this returns true then the textview will broadcast iTermTabContentsChanged
// when a dirty char is found.
- (BOOL)shouldSendContentsChangedNotification;

// Smallest range that contains all dirty chars for a line at a screen location.
// NOTE: y is a grid index and cannot refer to scrollback history.
- (VT100GridRange)dirtyRangeForLine:(int)y;

// Returns the last modified date for a given line.
- (NSDate *)timestampForLine:(int)y;

- (void)addNote:(PTYAnnotation *)note inRange:(VT100GridCoordRange)range focus:(BOOL)focus;

// Returns all notes in a range of cells.
- (NSArray<PTYAnnotation *> *)annotationsInRange:(VT100GridCoordRange)range;

- (VT100GridCoordRange)coordRangeOfAnnotation:(PTYAnnotation *)note;
- (NSArray *)charactersWithNotesOnLine:(int)line;
- (VT100ScreenMark *)markOnLine:(int)line;

- (NSString *)workingDirectoryOnLine:(int)line;

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line;
- (VT100RemoteHost *)remoteHostOnLine:(int)line;
- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(VT100ScreenMark *)mark;

// Indicates if we're in alternate screen mode.
- (BOOL)showingAlternateScreen;

- (void)clearBuffer;

// When the cursor is about to be hidden, a copy of the grid is saved. This
// method is used to temporarily swap in the saved grid if one is available. It
// calls `block` with a nonnil state if the saved grid was swapped in.
- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> state))block;

- (NSString *)compactLineDumpWithContinuationMarks;
- (NSSet<NSString *> *)sgrCodesForChar:(screen_char_t)c
                    externalAttributes:(iTermExternalAttribute *)ea;

- (void)setColor:(NSColor *)color forKey:(int)key;
- (id<iTermColorMapReading>)colorMap;
- (void)removeAnnotation:(PTYAnnotation *)annotation;

@end
