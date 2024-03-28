// DataSource for PTYTextView.
#import "iTermColorMap.h"
#import "iTermCursor.h"
#import "iTermFindDriver.h"
#import "iTermLogicalMovementHelper.h"
#import "iTermTextDataSource.h"
#import "ScreenChar.h"
#import "LineBuffer.h"
#import "VT100Grid.h"
#import "VT100Terminal.h"

@class Interval;
@class iTermColorMap;
@class iTermExternalAttributeIndex;
@protocol iTermMark;
@class iTermOffscreenCommandLine;
@class iTermTerminalButtonPlace;
@protocol IntervalTreeImmutableObject;
@class PTYAnnotation;
@protocol PTYAnnotationReading;
@class PTYNoteViewController;
@class PTYSession;
@class PTYTask;
@protocol Porthole;
@class SCPPath;
@class VT100Grid;
@protocol VT100RemoteHostReading;
@protocol VT100ScreenMarkReading;
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
                      rangeOut:(NSRange *)rangePtr
                     inContext:(FindContext*)context
                  absLineRange:(NSRange)absLineRange
                 rangeSearched:(VT100GridAbsCoordRange *)VT100GridAbsCoordRange;
- (FindContext*)findContext;

// Initialize the find context.
- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offsetof  // Offset in the direction of searching (offset=1 while searching backwards means start one char before x,y)
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults
         absLineRange:(NSRange)absLineRange;

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
- (NSArray<id<PTYAnnotationReading>> *)annotationsInRange:(VT100GridCoordRange)range;

- (VT100GridCoordRange)coordRangeOfAnnotation:(id<IntervalTreeImmutableObject>)note;
- (NSArray *)charactersWithNotesOnLine:(int)line;
- (id<VT100ScreenMarkReading>)markOnLine:(int)line;
- (void)removeNamedMark:(id<VT100ScreenMarkReading>)mark;
- (id<VT100ScreenMarkReading>)commandMarkAt:(VT100GridCoord)coord
                                      range:(out VT100GridWindowedRange *)range;
- (VT100GridAbsCoordRange)absCoordRangeForInterval:(Interval *)interval;

- (NSString *)workingDirectoryOnLine:(int)line;

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line;
- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line;
- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark;

// Indicates if we're in alternate screen mode.
- (BOOL)showingAlternateScreen;

- (void)clearBuffer;

// When the cursor is about to be hidden, a copy of the grid is saved. This
// method is used to temporarily swap in the saved grid if one is available. It
// calls `block` with a nonnil state if the saved grid was swapped in.
- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> state))block;

- (NSString *)compactLineDumpWithContinuationMarks;
- (NSOrderedSet<NSString *> *)sgrCodesForChar:(screen_char_t)c
                           externalAttributes:(iTermExternalAttribute *)ea;

- (void)setColor:(NSColor *)color forKey:(int)key;
- (id<iTermColorMapReading>)colorMap;
- (void)removeAnnotation:(id<PTYAnnotationReading>)annotation;
- (void)setStringValueOfAnnotation:(id<PTYAnnotationReading>)annotation to:(NSString *)stringValue;

- (void)resetDirty;

- (id<iTermTextDataSource>)snapshotDataSource;

- (void)replaceRange:(VT100GridAbsCoordRange)range
        withPorthole:(id<Porthole>)porthole
            ofHeight:(int)numLines;
- (void)replaceMark:(id<iTermMark>)mark withLines:(NSArray<ScreenCharArray *> *)lines;
- (void)changeHeightOfMark:(id<iTermMark>)mark to:(int)newHeight;

- (VT100GridCoordRange)coordRangeOfPorthole:(id<Porthole>)porthole;
- (iTermOffscreenCommandLine *)offscreenCommandLineBefore:(int)line;
- (NSInteger)numberOfCellsUsedInRange:(VT100GridRange)range;
- (NSArray<iTermTerminalButtonPlace *> *)buttonsInRange:(VT100GridRange)range;
- (VT100GridCoordRange)rangeOfBlockWithID:(NSString *)blockID;

@end
