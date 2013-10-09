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

static inline VT100GridCoord VT100GridCoordMake(int x, int y) {
    VT100GridCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

static inline VT100GridSize VT100GridSizeMake(int width, int height) {
    VT100GridSize size;
    size.width = width;
    size.height = height;
    return size;
}

static inline VT100GridRange VT100GridRangeMake(int location, int length) {
    VT100GridRange range;
    range.location = location;
    range.length = length;
    return range;
}

static inline int VT100GridRangeMax(VT100GridRange range) {
    return range.location + range.length;
}

@interface VT100Grid : NSObject {
    VT100GridSize size_;
    int screenTop_;  // Index into lines_ and dirty_ of first line visible in the grid.
    NSMutableArray *lines_;  // Array of NSMutableData. Each data has size_.width+1 screen_char_t's.
    NSMutableArray *dirty_;  // Array of NSMutableData. Each data has size_.width char's.
    VT100Terminal *terminal_;
    VT100GridCoord cursor_;
    VT100GridRange scrollRegionRows_;
    VT100GridRange scrollRegionCols_;
    BOOL useScrollRegionCols_;

    NSMutableData *cachedDefaultLine_;
    screen_char_t cachedDefaultLineForeground_;
    screen_char_t cachedDefaultLineBackground_;
}

@property(nonatomic, readonly) VT100GridSize size;
@property(nonatomic, assign) int cursorX;
@property(nonatomic, assign) int cursorY;
@property(nonatomic, assign) VT100GridRange scrollRegionRows;
@property(nonatomic, assign) VT100GridRange scrollRegionCols;
@property(nonatomic, assign) BOOL useScrollRegionCols;

- (id)initWithSize:(VT100GridSize)size terminal:(VT100Terminal *)terminal;

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber;

// from and to are inclusive
- (void)markCharDirtyAt:(VT100GridCoord)coord;
- (void)markCharsDirtyFrom:(VT100GridCoord)from to:(VT100GridCoord)to;

// Returns the count of lines excluding totally empty lines at the bottom, and always including the
// line the cursor is on and its successor.
- (int)numberOfLinesUsed;

// Append the first numLines to the given line buffer. Returns the number of lines appended.
- (void)appendLines:(int)numLines toLineBuffer:(LineBuffer *)lineBuffer;

// Number of used chars in line at lineNumber.
- (int)lengthOfLineNumber:(int)lineNumber;

// Pull up to maxLines lines from line buffer and into grid.
- (void)restoreUpTo:(int)maxLines linesFromLineBuffer:(LineBuffer *)lineBuffer;

// Advances the cursor down one line and scrolls the screen, or part of the screen, if necessary.
- (void)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer;

@end
