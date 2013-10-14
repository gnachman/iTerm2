//
//  VT100GridTest.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "LineBuffer.h"
#import "VT100GridTest.h"
#import "VT100Grid.h"

#define ASSERT_STRUCTS_EQUAL(type, a, b) \
do { \
  type tempA = a; \
  type tempB = b; \
  assert(!memcmp(&tempA, &tempB, sizeof(type))); \
} while (0)

@interface VT100GridTest () <VT100GridDelegate>
@end

@implementation VT100GridTest {
    BOOL wraparoundMode_;
    BOOL insertMode_;
    BOOL isAnsi_;
    screen_char_t foregroundColor_;
    screen_char_t backgroundColor_;
}

- (id)init {
    self = [super init];
    if (self) {
        wraparoundMode_ = YES;
        foregroundColor_.foregroundColor = ALTSEM_FG_DEFAULT;
        foregroundColor_.foregroundColorMode = ColorModeAlternate;
        backgroundColor_.backgroundColor = ALTSEM_BG_DEFAULT;
        backgroundColor_.backgroundColorMode = ColorModeAlternate;
    }
    return self;
}

- (BOOL)wraparoundMode {
    return wraparoundMode_;
}

- (BOOL)insertMode {
    return insertMode_;
}

- (BOOL)isAnsi {
    return isAnsi_;
}

- (screen_char_t)foregroundColorCodeReal {
    return foregroundColor_;
}

- (screen_char_t)backgroundColorCodeReal {
    return backgroundColor_;
}

- (void)testTypeFunctions {
    VT100GridCoord coord = VT100GridCoordMake(1, 2);
    VT100GridSize size = VT100GridSizeMake(3, 4);
    VT100GridRange range = VT100GridRangeMake(5, 6);
    VT100GridRect rect = VT100GridRectMake(7, 8, 9, 10);
    VT100GridRun run = VT100GridRunMake(11, 12, 13);

    assert(coord.x == 1);
    assert(coord.y == 2);
    assert(size.width == 3);
    assert(size.height == 4);
    assert(range.location = 5);
    assert(range.length = 6);
    assert(rect.origin.x == 7);
    assert(rect.origin.y == 8);
    assert(rect.size.width == 9);
    assert(rect.size.height == 10);
    assert(run.origin.x == 11);
    assert(run.origin.y == 12);
    assert(run.length == 13);

    assert(VT100GridRangeMax(range) == 10);
    VT100GridCoord runMax = VT100GridRunMax(run, 100);
    assert(runMax.x == 11 + 13);
    assert(runMax.y == 12);
    runMax = VT100GridRunMax(run, 12);
    assert(runMax.x == 0);
    assert(runMax.y == 14);

    VT100GridCoord rectMax = VT100GridRectMax(rect);
    assert(rectMax.x == 7 + 9 - 1);
    assert(rectMax.y == 8 + 10 - 1);

    VT100GridRun runFromCoords = VT100GridRunFromCoords(VT100GridCoordMake(1, 2),
                                                        VT100GridCoordMake(2, 4),
                                                        5);
    // .....
    // .....
    // .xxxx
    // xxxxx
    // xx...
    assert(runFromCoords.length == 11);
    assert(runFromCoords.origin.x == 1);
    assert(runFromCoords.origin.y == 2);
}

- (void)testTypeValues {
    VT100GridCoord coord = VT100GridCoordMake(1, 2);
    VT100GridSize size = VT100GridSizeMake(3, 4);
    VT100GridRange range = VT100GridRangeMake(5, 6);
    VT100GridRect rect = VT100GridRectMake(7, 8, 9, 10);
    VT100GridRun run = VT100GridRunMake(11, 12, 13);

    NSValue *coordValue = [NSValue valueWithGridCoord:coord];
    NSValue *sizeValue = [NSValue valueWithGridSize:size];
    NSValue *rangeValue = [NSValue valueWithGridRange:range];
    NSValue *rectValue = [NSValue valueWithGridRect:rect];
    NSValue *runValue = [NSValue valueWithGridRun:run];

    ASSERT_STRUCTS_EQUAL(VT100GridCoord, coord, coordValue.gridCoordValue);
    ASSERT_STRUCTS_EQUAL(VT100GridSize, size, sizeValue.gridSizeValue);
    ASSERT_STRUCTS_EQUAL(VT100GridRange, range, rangeValue.gridRangeValue);
    ASSERT_STRUCTS_EQUAL(VT100GridRect, rect, rectValue.gridRectValue);
    ASSERT_STRUCTS_EQUAL(VT100GridRun, run, runValue.gridRunValue);
}

// Returns a 2x2 grid.
- (VT100Grid *)smallGrid {
    VT100Grid *grid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(2, 2)
                                              delegate:self] autorelease];
    return grid;
}

// Returns a 4x4 grid.
- (VT100Grid *)mediumGrid {
    VT100Grid *grid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(4, 4)
                                              delegate:self] autorelease];
    return grid;
}

- (void)testInitialization {
    VT100Grid *grid = [self smallGrid];
    assert([[grid compactLineDump] isEqualToString:@"..\n.."]);
}

- (void)testLookUpScreenCharsByLineNumber {
    VT100Grid *grid = [self smallGrid];
    screen_char_t *line = [grid screenCharsAtLineNumber:0];
    line[0].code = 'a';
    line = [grid screenCharsAtLineNumber:1];
    line[0].code = 'b';
    line = [grid screenCharsAtLineNumber:0];
    assert(line[0].code == 'a');
    line = [grid screenCharsAtLineNumber:1];
    assert(line[0].code == 'b');
    assert([[grid compactLineDump] isEqualToString:@"a.\nb."]);
}

- (void)testSetCursor {
    VT100Grid *grid = [self smallGrid];
    [grid setCursor:VT100GridCoordMake(1, 1)];
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 1);
    [grid setCursor:VT100GridCoordMake(2, 1)];
    assert(grid.cursorX == 2);
    [grid setCursor:VT100GridCoordMake(3, 1)];
    assert(grid.cursorX == 2);
    [grid setCursor:VT100GridCoordMake(3, 2)];
    assert(grid.cursorY == 1);
    [grid setCursor:VT100GridCoordMake(-1, -1)];
    assert(grid.cursorX == 0 && grid.cursorY == 0);
}

- (void)testMarkCharDirty {
    VT100Grid *grid = [self smallGrid];
    VT100GridCoord coord = VT100GridCoordMake(1,1);
    assert(![grid isCharDirtyAt:coord]);
    assert(![grid isAnyCharDirty]);

    [grid markCharDirty:YES at:coord];
    assert([grid isCharDirtyAt:coord]);
    assert([grid isAnyCharDirty]);
    [grid markCharDirty:NO at:coord];

    assert(![grid isCharDirtyAt:coord]);
    assert(![grid isAnyCharDirty]);
}

- (void)testMarkCharsDirtyInRect {
    VT100Grid *grid = [self mediumGrid];

    assert([[grid compactDirtyDump] isEqualToString:@"cccc\ncccc\ncccc\ncccc"]);
    [grid markCharsDirty:YES inRectFrom:VT100GridCoordMake(1, 1) to:VT100GridCoordMake(2, 2)];
    assert([[grid compactDirtyDump] isEqualToString:@"cccc\ncddc\ncddc\ncccc"]);
    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(2, 1) to:VT100GridCoordMake(2, 2)];
    assert([[grid compactDirtyDump] isEqualToString:@"cccc\ncdcc\ncdcc\ncccc"]);
}

- (void)testMarkAllCharsDirty {
    VT100Grid *grid = [self smallGrid];
    assert([[grid compactDirtyDump] isEqualToString:@"cc\ncc"]);
    [grid markAllCharsDirty:YES];
    assert([[grid compactDirtyDump] isEqualToString:@"dd\ndd"]);
    [grid markAllCharsDirty:NO];
    assert([[grid compactDirtyDump] isEqualToString:@"cc\ncc"]);
}

- (VT100Grid *)gridFromCompactLines:(NSString *)compact {
    NSArray *lines = [compact componentsSeparatedByString:@"\n"];
    VT100Grid *grid = [[VT100Grid alloc] initWithSize:VT100GridSizeMake([[lines objectAtIndex:0] length],
                                                                        [lines count])
                                             delegate:self];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [grid screenCharsAtLineNumber:i++];
        for (int j = 0; j < [line length]; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            s[j].code = c;
        }
    }
    return grid;
}

- (VT100Grid *)gridFromCompactLinesWithContinuationMarks:(NSString *)compact {
    NSArray *lines = [compact componentsSeparatedByString:@"\n"];
    VT100Grid *grid = [[VT100Grid alloc] initWithSize:VT100GridSizeMake([[lines objectAtIndex:0] length] - 1,
                                                                        [lines count])
                                             delegate:self];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [grid screenCharsAtLineNumber:i++];
        int j;
        for (j = 0; j < [line length] - 1; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            s[j].code = c;
        }
        if ([line characterAtIndex:j] == '!') {
            s[j].code = EOL_HARD;
        } else if ([line characterAtIndex:j] == '+') {
            s[j].code = EOL_SOFT;
        } else {
            assert(false);
        }
    }
    return grid;
}

- (void)testNumberOfLinesUsed {
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefgh\n....\n...."];
    assert([grid numberOfLinesUsed] == 2);
    grid.cursorY = 1;
    assert([grid numberOfLinesUsed] == 2);
    grid.cursorY = 2;
    assert([grid numberOfLinesUsed] == 3);

    grid = [self smallGrid];
    assert([grid numberOfLinesUsed] == 1);
}

- (void)testAppendLineToLineBuffer {
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefgh\n....\n...."];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendLines:2 toLineBuffer:lineBuffer];
    assert([[lineBuffer debugString] isEqualToString:@"abcd!\nefgh!"]);

    grid = [self gridFromCompactLinesWithContinuationMarks:@"abcd!\nefgh+\n....!\n....!"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendLines:2 toLineBuffer:lineBuffer];
    assert([[lineBuffer debugString] isEqualToString:@"abcd!\nefgh+"]);

    grid = [self gridFromCompactLinesWithContinuationMarks:@"abcd+\nefgh!\n....!\n....!"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendLines:2 toLineBuffer:lineBuffer];
    assert([[lineBuffer debugString] isEqualToString:@"abcdefgh!"]);

    grid = [self gridFromCompactLines:@"abcd\nefgh\n....\n...."];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 2;
    grid.cursorY = 1;
    [grid appendLines:2 toLineBuffer:lineBuffer];
    int x;
    assert([lineBuffer getCursorInLastLineWithWidth:4 atX:&x]);
    assert(x == 2);

    // Test that the cursor gets hoisted from the start of a blank line following a soft-eol to the
    // end of the preceding line.
    grid = [self gridFromCompactLinesWithContinuationMarks:@"abcd+\nefgh+\n....!\n....!"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 0;
    grid.cursorY = 2;
    [grid appendLines:2 toLineBuffer:lineBuffer];
    assert([lineBuffer getCursorInLastLineWithWidth:4 atX:&x]);
    assert(x == 4);
}

- (void)testLengthOfLineNumber {
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefg.\n....\n...."];
    assert([grid lengthOfLineNumber:0] == 4);
    assert([grid lengthOfLineNumber:1] == 3);
    assert([grid lengthOfLineNumber:2] == 0);
}

- (void)testMoveCursorDownOneLineNoScroll {
    // Test cursor in default scroll region
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 0;
    grid.cursorY = 0;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO];
    assert([[grid compactLineDump] isEqualToString:@"abcd\nefgh\nijkl\nmnop"]);
    assert([[lineBuffer debugString] isEqualToString:@""]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 1);

    // Test cursor below scrollBottom but above last line.
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.scrollRegionRows = VT100GridRangeMake(0, 1);
    grid.cursorX = 0;
    grid.cursorY = 1;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO];
    assert([[grid compactLineDump] isEqualToString:@"abcd\nefgh\nijkl\nmnop"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 2);

    // Test whole screen scrolling
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 0;
    grid.cursorY = 3;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO];
    assert([[grid compactLineDump] isEqualToString:@"efgh\nijkl\nmnop\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"abcd!"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 3);

    // Test whole screen scrolling, verify soft eol's are respected
    grid = [self gridFromCompactLinesWithContinuationMarks:@"abcd+\nefgh!\nijkl!\nmnop!"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 0;
    grid.cursorY = 3;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO];
    assert([[grid compactLineDump] isEqualToString:@"efgh\nijkl\nmnop\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"abcd+"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 3);

    // Test scrolling when there's a full-width region touching the top of the screen
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.scrollRegionRows = VT100GridRangeMake(0, 2);
    grid.cursorX = 0;
    grid.cursorY = 1;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:YES];
    assert([[grid compactLineDump] isEqualToString:@"efgh\n....\nijkl\nmnop"]);
    assert([[lineBuffer debugString] isEqualToString:@"abcd!"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 1);

    // Same, but with useScrollbackWithRegion = NO
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.scrollRegionRows = VT100GridRangeMake(0, 2);
    grid.cursorX = 0;
    grid.cursorY = 1;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO];
    assert([[grid compactLineDump] isEqualToString:@"efgh\n....\nijkl\nmnop"]);
    assert([[lineBuffer debugString] isEqualToString:@""]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 1);

    // Test that the dropped line count is correct.
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    grid.cursorX = 0;
    grid.cursorY = 3;
    int dropped = 0;
    for (int i = 0; i < 3; i++) {
        dropped += [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                  unlimitedScrollback:NO
                                              useScrollbackWithRegion:NO];
    }
    assert(dropped == 2);
    assert([[grid compactLineDump] isEqualToString:@"mnop\n....\n....\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"ijkl!"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 3);

    // Test with both vertical and horizontal scroll region
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(1, 2);
    grid.useScrollRegionCols = YES;
    grid.cursorX = 1;
    grid.cursorY = 2;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:YES];
    assert([[grid compactLineDump] isEqualToString:@"abcd\nejkh\ni..l\nmnop"]);
    assert([[lineBuffer debugString] isEqualToString:@""]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 2);
}

- (void)testMoveCursorLeft {
    VT100Grid *grid = [self mediumGrid];
    grid.cursorX = 1;
    grid.cursorY = 0;
    [grid moveCursorLeft:1];
    assert(grid.cursorX == 0 && grid.cursorY == 0);
    [grid moveCursorLeft:1];
    assert(grid.cursorX == 0 && grid.cursorY == 0);

    grid.scrollRegionCols = VT100GridRangeMake(1, 2);
    grid.useScrollRegionCols = YES;
    grid.cursorX = 1;
    [grid moveCursorLeft:1];
    assert(grid.cursorX == 1);

    grid.cursorX = 2;
    [grid moveCursorLeft:1];
    assert(grid.cursorX == 1);

    grid.cursorX = 3;
    [grid moveCursorLeft:1];
    assert(grid.cursorX == 3);  // I'm not persuaded this is sane. Check with saitoha.
}

- (void)testMoveCursorRight {
    VT100Grid *grid = [self mediumGrid];
    grid.cursorX = 2;
    grid.cursorY = 0;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 3 && grid.cursorY == 0);
    [grid moveCursorRight:1];
    assert(grid.cursorX == 3 && grid.cursorY == 0);

    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.useScrollRegionCols = YES;
    grid.cursorX = 0;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 0);  // I'm not persuaded this is sane. Check with saitoha.

    grid.cursorX = 1;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 2);

    grid.cursorX = 2;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 2);  // Pretty sure this is wrong too.
}

- (void)testMoveCursorUp {
    VT100Grid *grid = [self mediumGrid];
    grid.cursorX = 0;
    grid.cursorY = 2;
    [grid moveCursorUp:1];
    assert(grid.cursorY == 1);
    [grid moveCursorUp:1];
    assert(grid.cursorY == 0);
    [grid moveCursorUp:1];
    assert(grid.cursorY == 0);

    // If starting at or below scrollTop, clamp to scrollTop
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.cursorY = 2;
    [grid moveCursorUp:1];
    assert(grid.cursorY == 1);
    [grid moveCursorUp:1];
    assert(grid.cursorY == 1);

    // If starting above scrollTop, don't clamp
    grid.scrollRegionRows = VT100GridRangeMake(2, 2);
    grid.cursorY = 1;
    [grid moveCursorUp:1];
    assert(grid.cursorY == 0);
}

- (void)testMoveCursorDown {
    VT100Grid *grid = [self mediumGrid];
    grid.cursorX = 0;
    grid.cursorY = 2;
    [grid moveCursorDown:1];
    assert(grid.cursorY == 3);
    [grid moveCursorDown:1];
    assert(grid.cursorY == 3);

    // If starting at or above scrollBottom, clamp to scrollBottom
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.cursorY = 1;
    [grid moveCursorDown:1];
    assert(grid.cursorY == 2);
    [grid moveCursorDown:1];
    assert(grid.cursorY == 2);

    // If starting below scrollBottom, don't clamp
    grid.scrollRegionRows = VT100GridRangeMake(0, 2);
    grid.cursorY = 2;
    [grid moveCursorDown:1];
    assert(grid.cursorY == 3);
    [grid moveCursorDown:1];
    assert(grid.cursorY == 3);
}

- (void)testScrollUpIntoLineBuffer {
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid scrollUpIntoLineBuffer:lineBuffer
             unlimitedScrollback:NO
         useScrollbackWithRegion:YES];
    assert([[grid compactLineDump] isEqualToString:@"efgh\nijkl\nmnop\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"abcd!"]);

    // Check that dropped lines is accurate
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    int dropped = [grid scrollUpIntoLineBuffer:lineBuffer
                           unlimitedScrollback:NO
                       useScrollbackWithRegion:YES];
    assert(dropped == 0);
    dropped = [grid scrollUpIntoLineBuffer:lineBuffer
                       unlimitedScrollback:NO
                   useScrollbackWithRegion:YES];
    assert(dropped == 1);
    assert([[grid compactLineDump] isEqualToString:@"ijkl\nmnop\n....\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"efgh!"]);

    // Scroll a horizontal region. Shouldn't append to linebuffer.
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.scrollRegionCols = VT100GridRangeMake(1, 2);
    grid.useScrollRegionCols = YES;
    dropped = [grid scrollUpIntoLineBuffer:lineBuffer
                       unlimitedScrollback:NO
                   useScrollbackWithRegion:YES];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:@"afgd\nejkh\ninol\nm..p"]);
    assert([[lineBuffer debugString] isEqualToString:@""]);
}

- (void)setLine:(int)lineNumber ofGrid:(VT100Grid *)grid toString:(NSString *)string {
    assert(grid.size.width == string.length);
    VT100Grid *temp = [self gridFromCompactLines:string];
    screen_char_t *src = [temp screenCharsAtLineNumber:0];
    screen_char_t *dst = [grid screenCharsAtLineNumber:lineNumber];
    memmove(dst, src, sizeof(screen_char_t) * grid.size.width);
}

- (void)testScrollWholeScreenUpIntoLineBuffer {
    VT100Grid *grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    [grid markCharDirty:YES at:VT100GridCoordMake(2, 2)];
    assert([[grid compactDirtyDump] isEqualToString:@"cccc\ncccc\nccdc\ncccc"]);
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    assert([grid scrollWholeScreenUpIntoLineBuffer:lineBuffer unlimitedScrollback:NO] == 0);
    assert([[grid compactLineDump] isEqualToString:@"efgh\nijkl\nmnop\n...."]);
    assert([[grid compactDirtyDump] isEqualToString:@"cccc\nccdc\ncccc\ndddd"]);
    [self setLine:3 ofGrid:grid toString:@"qrst"];
    assert([grid scrollWholeScreenUpIntoLineBuffer:lineBuffer unlimitedScrollback:NO] == 1);
    assert([[grid compactLineDump] isEqualToString:@"ijkl\nmnop\nqrst\n...."]);
    assert([[lineBuffer debugString] isEqualToString:@"efgh!"]);
    assert([[grid compactDirtyDump] isEqualToString:@"ccdc\ncccc\ndddd\ndddd"]);
}

// No test for scrollDown because it's just a wafer thin wrapper around scrollRect:downBy:.

// TODO: Write more tests.
@end

int main(int argc, const char * argv[])
{
    VT100GridTest *test = [VT100GridTest new];

    unsigned int methodCount;
    Method *methods = class_copyMethodList([test class], &methodCount);
    for (int i = 0; i < methodCount; i++) {
        SEL name = method_getName(methods[i]);
        NSString *stringName = NSStringFromSelector(name);
        if ([stringName hasPrefix:@"test"]) {
            NSLog(@"Running %@", stringName);
            [test performSelector:name];
            NSLog(@"Success!");
        }
    }
    free(methods);

    NSLog(@"All tests passed");
    return 0;
}
