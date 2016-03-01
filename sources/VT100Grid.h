//
//  VT100Grid.h
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import <Foundation/Foundation.h>
#import "DVRIndexEntry.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"

@class LineBuffer;
@class VT100LineInfo;
@class VT100Terminal;

@protocol VT100GridDelegate <NSObject>
- (screen_char_t)gridForegroundColorCode;
- (screen_char_t)gridBackgroundColorCode;
- (BOOL)gridUseHFSPlusMapping;
- (void)gridCursorDidMove;
- (void)gridCursorDidChangeLine;
@end

@interface VT100Grid : NSObject<NSCopying>

// Changing the size erases grid contents.
@property(nonatomic, assign) VT100GridSize size;
@property(nonatomic, assign) int cursorX;
@property(nonatomic, assign) int cursorY;
@property(nonatomic, assign) VT100GridCoord cursor;
@property(nonatomic, assign) VT100GridRange scrollRegionRows;
@property(nonatomic, assign) VT100GridRange scrollRegionCols;
@property(nonatomic, assign) BOOL useScrollRegionCols;
@property(nonatomic, assign, getter=isAllDirty) BOOL allDirty;
@property(nonatomic, readonly) int leftMargin;
@property(nonatomic, readonly) int rightMargin;
@property(nonatomic, readonly) int topMargin;
@property(nonatomic, readonly) int bottomMargin;
@property(nonatomic, assign) screen_char_t savedDefaultChar;
@property(nonatomic, assign) id<VT100GridDelegate> delegate;

// Serialized state, but excludes screen contents.
@property(nonatomic, readonly) NSDictionary *dictionaryValue;

- (instancetype)initWithSize:(VT100GridSize)size delegate:(id<VT100GridDelegate>)delegate;

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber;

// Set both x and y coord of cursor at once. Cursor positions are clamped to legal values. The cursor
// may extend into the right edge (cursorX == size.width is allowed).
- (void)setCursor:(VT100GridCoord)coord;

// Mark a specific character dirty. If updateTimestamp is set, then the line's last-modified time is
// set to the current time.
- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord updateTimestamp:(BOOL)updateTimestamp;

// Mark chars dirty in a rectangle, inclusive of endpoints.
- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to;
- (void)markAllCharsDirty:(BOOL)dirty;
- (BOOL)isCharDirtyAt:(VT100GridCoord)coord;
- (BOOL)isAnyCharDirty;
- (VT100GridRange)dirtyRangeForLine:(int)y;
// Returns the set of dirty indexes on |line|.
- (NSIndexSet *)dirtyIndexesOnLine:(int)line;

// Returns the count of lines excluding totally empty lines at the bottom, and always including the
// line the cursor is on.
- (int)numberOfLinesUsed;

// Like numberOfLinesUsed, but it doesn't care about where the cursor is.
- (int)numberOfNonEmptyLines;

// Append the first numLines to the given line buffer. Returns the number of lines appended.
- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer;

// Number of used chars in line at lineNumber.
- (int)lengthOfLineNumber:(int)lineNumber;

// Advances the cursor down one line and scrolls the screen, or part of the screen, if necessary.
// Returns the number of lines dropped from lineBuffer. lineBuffer may be nil. If a scroll region is
// present, the lineBuffer is only added to if useScrollbackWithRegion is set. willScroll is called
// if the region will need to scroll up by one line.
- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                                         willScroll:(void (^)())willScroll;

// Move cursor to the left by n steps. Does not wrap around when it hits the left margin.
// If it starts left of the scroll region, clamp it to the left. If it starts right of the scroll
// region, don't move it.  TODO: This is probably wrong w/r/t scroll region logic.
- (void)moveCursorLeft:(int)n;

// Move cursor to the right by n steps. Does not wrap around when it hits the right margin. The
// cursor is not permitted to extend into the width'th column, which setCursorX: allows.
// It has a similar same logic oddity as moveCursorLeft:, but slightly different (if the cursor's
// moved position is inside the scroll region, then it can change).
- (void)moveCursorRight:(int)n;

// Move cursor up by n steps. If there is a scroll region, it won't go past the top.
// Also clamps the cursor's x position to be valid.
- (void)moveCursorUp:(int)n;

// Move cursor down by n steps. If there is a scroll region, it won't go past the bottom.
// Also clamps the cursor's x position to be valid.
- (void)moveCursorDown:(int)n;

// Move cursor up one line. 
// Scroll the screen or a region of the screen up by one line. If lineBuffer is set, a line scrolled
// off the top will be moved into the line buffer. If a scroll region is present, the lineBuffer is
// only added to if useScrollbackWithRegion is set.

// When scrolling vertically within a region, the |softBreak| flag is used.
// If |softBreak| is YES then the soft line break on the top line (when scrolling down) or bottom
// line (when scrolling up) is preserved. Otherwise it is made hard.
- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                    softBreak:(BOOL)softBreak;

// Scroll the whole screen into the line buffer by one line. Returns the number of lines dropped.
// Scroll regions are ignored.
- (int)scrollWholeScreenUpIntoLineBuffer:(LineBuffer *)lineBuffer
                     unlimitedScrollback:(BOOL)unlimitedScrollback;

// Scroll the scroll region down by one line.
- (void)scrollDown;

// Clear scroll region, clear screen, move cursor and saved cursor to origin, leaving only the last
// non-empty line at the top of the screen. Some lines may be left behind by giving a positive value
// for |leave|.
- (int)resetWithLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
        preserveCursorLine:(BOOL)preserveCursorLine;

// Move the grid contents up, leaving only the whole wrapped line the cursor is on at the top.
- (void)moveWrappedCursorLineToTopOfGrid;

// Set chars in a rectangle, inclusive of from and to. It will clean up orphaned DWCs.
- (void)setCharsFrom:(VT100GridCoord)from to:(VT100GridCoord)to toChar:(screen_char_t)c;

// Same as above, but for runs.
- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)c;

// Copy chars and size from another grid.
- (void)copyCharsFromGrid:(VT100Grid *)otherGrid;

// Append a string starting from the cursor's current position.
// Returns number of scrollback lines dropped from lineBuffer.
- (int)appendCharsAtCursor:(screen_char_t *)buffer
                    length:(int)len
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                wraparound:(BOOL)wraparound
                      ansi:(BOOL)ansi
                    insert:(BOOL)insert;

// Delete some number of chars starting at a given location, moving chars to the right of them back.
- (void)deleteChars:(int)num
         startingAt:(VT100GridCoord)startCoord;

// Scroll a rectangular area of the screen down (positive direction) or up (negative direction).
// Clears the left-over region.
// If |softBreak| is YES then the soft line break on the top line (when scrolling down) or bottom
// line (when scrolling up) is preserved. Otherwise it is made hard.
- (void)scrollRect:(VT100GridRect)rect downBy:(int)direction softBreak:(BOOL)softBreak;

// Load contents from a DVR frame.
- (void)setContentsFromDVRFrame:(screen_char_t*)s info:(DVRFrameInfo)info;

// Returns a grid-owned empty line.
- (NSMutableData *)defaultLineOfWidth:(int)width;
- (screen_char_t)defaultChar;

// Set background/foreground colors in a range.
- (void)setBackgroundColor:(screen_char_t)bg
           foregroundColor:(screen_char_t)fg
                inRectFrom:(VT100GridCoord)from
                        to:(VT100GridCoord)to;

// Converts a range relative to the start of a row into a grid run. If row is negative, a smaller-
// than-range.length (but valid!) grid run will be returned.
- (VT100GridRun)gridRunFromRange:(NSRange)range relativeToRow:(int)row;

// Pop lines out of the line buffer and on to the screen. Up to maxLines will be restored. Before
// popping, lines to be modified will first be filled with defaultChar.
- (void)restoreScreenFromLineBuffer:(LineBuffer *)lineBuffer
                    withDefaultChar:(screen_char_t)defaultChar
                  maxLinesToRestore:(int)maxLines;

// Ensure the cursor and savedCursor positions are valid.
- (void)clampCursorPositionToValid;

// Returns temp storage for one line.
- (screen_char_t *)resultLine;

// Returns a human-readable string with the screen contents and dirty lines interspersed.
- (NSString *)debugString;

// Returns a string for the character at |coord|.
- (NSString *)stringForCharacterAt:(VT100GridCoord)coord;

// Converts a run into one or more VT100GridRect NSValues.
- (NSArray *)rectsForRun:(VT100GridRun)run;

// Reset scroll regions to whole screen. NOTE: It does not reset useScrollRegionCols.
- (void)resetScrollRegions;

// Returns a rect describing the current scroll region. Takes useScrollRegionCols into account.
- (VT100GridRect)scrollRegionRect;

// If a DWC is presetn at (offset, lineNumber), then both its cells are erased. They're replaced
// with c (normally -defaultChar). If there's a DWC_SKIP + EOL_DWC on the preceding line
// when offset==0 then those are converted to a null and EOL_HARD. Returns true if a DWC was erased.
- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber
                                startingAtOffset:(int)offset
                                        withChar:(screen_char_t)c;

// Moves the cursor to the left margin (either 0 or scrollRegionCols.location, depending on
// useScrollRegionCols).
- (void)moveCursorToLeftMargin;

// Returns the timestamp of a given line.
- (NSTimeInterval)timestampForLine:(int)y;

- (NSString *)compactLineDump;
- (NSString *)compactLineDumpWithTimestamps;
- (NSString *)compactLineDumpWithContinuationMarks;
- (NSString *)compactDirtyDump;

// Returns the coordinate of the cell before this one. It respects scroll regions and double-width
// characters.
// Returns (-1,-1) if there is no previous cell.
- (VT100GridCoord)coordinateBefore:(VT100GridCoord)coord movedBackOverDoubleWidth:(BOOL *)dwc;

- (BOOL)addCombiningChar:(unichar)combiningChar toCoord:(VT100GridCoord)coord;

// TODO: write a test for this
- (void)insertChar:(screen_char_t)c at:(VT100GridCoord)pos times:(int)num;

// Returns an array of NSData for lines in order (corresponding with lines on screen).
- (NSArray *)orderedLines;

// Restore saved state excluding screen contents.
- (void)setStateFromDictionary:(NSDictionary *)dict;

#pragma mark - Testing use only

- (VT100LineInfo *)lineInfoAtLineNumber:(int)lineNumber;

@end
