//
//  VT100Grid.h
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import <Foundation/Foundation.h>

typedef struct {
    int x;
    int y;
} VT100GridCoord;

typedef struct {
    int width;
    int height;
} VT100GridSize;

typedef struct {
    int location;
    int length;
} VT100GridRange;

typedef struct {
    VT100GridCoord origin;
    VT100GridSize size;
} VT100GridRect;

typedef struct {
    VT100GridCoord origin;
    int length;
} VT100GridRun;

@interface NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord;
+ (NSValue *)valueWithGridSize:(VT100GridSize)size;
+ (NSValue *)valueWithGridRange:(VT100GridRange)range;
+ (NSValue *)valueWithGridRect:(VT100GridRect)rect;
+ (NSValue *)valueWithGridRun:(VT100GridRun)run;

- (VT100GridCoord)gridCoordValue;
- (VT100GridSize)gridSizeValue;
- (VT100GridRange)gridRangeValue;
- (VT100GridRect)gridRectValue;
- (VT100GridRun)gridRunValue;

@end

NS_INLINE VT100GridCoord VT100GridCoordMake(int x, int y) {
    VT100GridCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

NS_INLINE VT100GridSize VT100GridSizeMake(int width, int height) {
    VT100GridSize size;
    size.width = width;
    size.height = height;
    return size;
}

NS_INLINE VT100GridRange VT100GridRangeMake(int location, int length) {
    VT100GridRange range;
    range.location = location;
    range.length = length;
    return range;
}

NS_INLINE int VT100GridRangeMax(VT100GridRange range) {
    return range.location + range.length - 1;
}

NS_INLINE void VT100GridRectMake(int x, int y, int width, int height) {
    VT100GridRect rect;
    rect.origin = VT100GridCoordMake(x, y);
    rect.size = VT100GridSizeMake(width, height);
    return rect;
}

NS_INLINE VT100GridCoord VT100GridRunMax(VT100GridRun run, int width) {
    VT100GridCoord coord = run.origin;
    coord.y += (coord.x + run.length) / width;
    coord.x = (coord.x + run.length) % width;
    return coord;
}

// Creates a run between two coords, not inclusive of end.
VT100GridRun VT100GridRunFromCoords(VT100GridCoord start,
                                    VT100GridCoord end,
                                    int width);

@interface VT100Grid : NSObject <NSCopying> {
    VT100GridSize size_;
    int screenTop_;  // Index into lines_ and dirty_ of first line visible in the grid.
    NSMutableArray *lines_;  // Array of NSMutableData. Each data has size_.width+1 screen_char_t's.
    NSMutableArray *dirty_;  // Array of NSMutableData. Each data has size_.width char's.
    VT100Terminal *terminal_;
    VT100GridCoord cursor_;
    VT100GridCoord savedCursor_;
    VT100GridRange scrollRegionRows_;
    VT100GridRange scrollRegionCols_;
    BOOL useScrollRegionCols_;

    NSMutableData *cachedDefaultLine_;
    NSMutableData *resultLine_;
    screen_char_t savedDefaultChar_;
}

// Changing the size erases grid contents.
@property(nonatomic, readonly) VT100GridSize size;
@property(nonatomic, assign) int cursorX;
@property(nonatomic, assign) int cursorY;
@property(nonatomic, assign) VT100GridRange scrollRegionRows;
@property(nonatomic, assign) VT100GridRange scrollRegionCols;
@property(nonatomic, assign) BOOL useScrollRegionCols;
@property(nonatomic, assign) VT100GridCoord savedCursor;
@property(nonatomic, assign, getter=isAllDirty) BOOL allDirty;
@property(nonatomic, readonly) int leftMargin;
@property(nonatomic, readonly) int rightMargin;
@property(nonatomic, readonly) int topMargin;
@property(nonatomic, readonly) int bottomMargin;
@property(nonatomic, readonly) NSArray *lines;
@property(nonatomic, assign) screen_char_t savedDefaultChar;

- (id)initWithSize:(VT100GridSize)size terminal:(VT100Terminal *)terminal;

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber;

// Set both x and y coord of cursor at once.
- (void)setCursor:(VT100GridCoord)coord;

- (void)markCharDirtyAt:(VT100GridCoord)coord;

// Mark chars dirty in a rectangle, inclusive of endpoints.
- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to;
- (void)markAllCharsDirty:(BOOL)dirty;
- (BOOL)isCharDirtyAt:(VT100GridCoord)coord;
- (BOOL)isAnyCharDirty;

// Returns the count of lines excluding totally empty lines at the bottom, and always including the
// line the cursor is on and its successor.
- (int)numberOfLinesUsed;

// Append the first numLines to the given line buffer. Returns the number of lines appended.
- (int)appendLines:(int)numLines toLineBuffer:(LineBuffer *)lineBuffer;

// Number of used chars in line at lineNumber.
- (int)lengthOfLineNumber:(int)lineNumber;

// Advances the cursor down one line and scrolls the screen, or part of the screen, if necessary.
// Returns the number of lines dropped from lineBuffer. lineBuffer may be nil. If a scroll region is
// present, the lineBuffer is only added to if useScrollbackWithRegion is set.
- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion;

// Move cursor to the left by n steps. Does not wrap around when it hits the left margin.
// If it begins outside the scroll region, it is moved into it.
- (void)moveCursorLeft:(int)n;

// Move cursor to the right by n steps. Does not wrap around when it hits the right margin.
// If it begins outside the scroll region, it is moved into it.
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
- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion;

// Scroll the whole screen into the line buffer by one line. Returns the number of lines dropped.
// Scroll regions are ignored.
- (int)scrollWholeScreenUpIntoLineBuffer:(LineBuffer *)lineBuffer
                     unlimitedScrollback:(BOOL)unlimitedScrollback;

// Clear scroll region, clear screen, move cursor to origin, leaving only the last non-empty line
// at the top of the screen if preservingLastLine is set, or clearing the whole screen otherwise.
- (int)resetWithLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
        preservingLastLine:(BOOL)preservingLastLine;

// Move the grid contents up, leaving only the whole wrapped line the cursor is on at the top.
- (void)moveWrappedCursorLineToTopOfGrid;

// Set chars in a rectangle, inclusive of from and to. The character is assumed non-complex and the
// foreground and background colors are reset to the terminals's current default values.
// It will clean up orphaned DWCs.
- (void)setCharsFrom:(VT100GridCoord)from to:(VT100GridCoord)to toChar:(unichar)c;

// Same as above, but for runs.
- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)c;

// Copy chars and size from another grid.
- (void)copyCharsFromGrid:(VT100Grid *)otherGrid;

// Append a string starting from the cursor's current position.
// Returns number of scrollback lines dropped from lineBuffer.
- (int)appendCharsAtCursor:(screen_char_t *)buffer
                    length:(int)len
                isAllAscii:(BOOL)ascii
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion;

// Delete some number of chars starting at a given location, moving chars to the right of them back.
- (void)deleteChars:(int)num
         startingAt:(VT100GridCoord)startCoord;

// Scroll a rectangular area of the screen down (positive direction) or up (negative direction).
// Clears the left-over region.
- (void)scrollRect:(VT100GridRect)rect downBy:(int)direction;

// Load contents from a DVR frame.
- (void)setContentsFromDVRFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

// Returns a grid-owned empty line.
- (NSMutableData *)defaultLineOfWidth:(int)width;
- (screen_char_t)defaultChar;

// Set background/foreground colors in a range.
- (void)setBackgroundColor:(screen_char_t)bg
           foregroundColor:(screen_char_t)fg
                inRectFrom:(VT100GridCoord)from
                        to:(VT100GridCoord)to;

// Returns runs (as NSValue*s with gridRunValue) on screen that match a regex.
- (NSArray *)runsMatchingRegex:(NSString *)regex;

// Pop lines out of the line buffer and on to the screen. Up to maxLines will be restored. Before
// popping, lines to be modified will first be filled with defaultChar.
- (void)restoreScreenFromLineBuffer:(LineBuffer *)lineBuffer
                    withDefaultChar:(screen_char_t)defaultChar
                  maxLinesToRestore:(int)maxLines;

// Modify a run by removing nulls from both ends.
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run;

// Ensure the cursor and savedCursor positions are valid.
- (void)clampCursorPositionToValid;

// Returns temp storage for one line.
- (screen_char_t *)resultLine;

// Returns a human-readable string with the screen contents and dirty lines interspersed.
- (NSString *)debugString;

// Converts a run into one or more VT100GridRect NSValues.
- (NSArray *)rectsForRun:(VT100GridRun)run;

// Reset scroll regions to whole screen.
- (void)resetScrollRegions;

// Returns a 2-d array of screen_char_t's giving the whole screen contents. It has (width + 1)*height
// elements.
- (screen_char_t *)dvrFormattedFrame;

- (VT100GridRect)scrollRegionRect;

- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber startingAtOffset:(int)offset;

@end
