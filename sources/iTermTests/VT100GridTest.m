//
//  VT100GridTest.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Cocoa/Cocoa.h>
#import "DVRBuffer.h"
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

// This is run before each test.
- (void)setup {
    wraparoundMode_ = YES;
    foregroundColor_.foregroundColor = ALTSEM_DEFAULT;
    foregroundColor_.foregroundColorMode = ColorModeAlternate;
    backgroundColor_.backgroundColor = ALTSEM_DEFAULT;
    backgroundColor_.backgroundColorMode = ColorModeAlternate;
}

- (screen_char_t)gridForegroundColorCode {
    return foregroundColor_;
}

- (screen_char_t)gridBackgroundColorCode {
    return backgroundColor_;
}

- (void)gridCursorDidChangeLine {
}

- (BOOL)gridUseHFSPlusMapping {
    return NO;
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

    VT100GridRun trivialRun = VT100GridRunMake(1, 1, 1);
    VT100GridCoord runMax = VT100GridRunMax(trivialRun, 100);
    assert(runMax.x == 1);
    assert(runMax.y == 1);

    runMax = VT100GridRunMax(run, 100);
    assert(runMax.x == 11 + 13 - 1);
    assert(runMax.y == 12);
    runMax = VT100GridRunMax(run, 12);
    assert(runMax.x == 11);
    assert(runMax.y == 13);

    VT100GridCoord rectMax = VT100GridRectMax(rect);
    assert(rectMax.x == 7 + 9 - 1);
    assert(rectMax.y == 8 + 10 - 1);

    VT100GridRun runFromCoords = VT100GridRunFromCoords(VT100GridCoordMake(1, 2),
                                                        VT100GridCoordMake(2, 4),
                                                        5);
    // .....
    // .....
    // .1234
    // 56789
    // 0ab..
    assert(runFromCoords.length == 12);
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

// Returns a 8x8 grid.
- (VT100Grid *)largeGrid {
    VT100Grid *grid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(8, 8)
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

    [grid markCharDirty:YES at:coord updateTimestamp:NO];
    assert([grid isCharDirtyAt:coord]);
    assert([grid isAnyCharDirty]);
    [grid markCharDirty:NO at:coord updateTimestamp:YES];

    assert(![grid isCharDirtyAt:coord]);
    assert(![grid isAnyCharDirty]);
}

- (void)testMarkAndClearDirty {
    // This test assumes that underlying implementation of dirty chars is a range per line.
    VT100Grid *grid = [self largeGrid];
    [grid markCharDirty:YES at:VT100GridCoordMake(1,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    
    [grid markCharDirty:YES at:VT100GridCoordMake(3,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    
    [grid markCharDirty:NO at:VT100GridCoordMake(2,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);

    [grid markCharDirty:NO at:VT100GridCoordMake(1,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);

    [grid markCharDirty:NO at:VT100GridCoordMake(3,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    
    [grid markCharDirty:NO at:VT100GridCoordMake(2,1) updateTimestamp:NO];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    
    [grid markCharsDirty:YES inRectFrom:VT100GridCoordMake(1, 1) to:VT100GridCoordMake(5, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:YES inRectFrom:VT100GridCoordMake(0, 1) to:VT100GridCoordMake(5, 1)];
    assert([grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(2, 1) to:VT100GridCoordMake(4, 1)];
    assert([grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(0, 1) to:VT100GridCoordMake(2, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(0, 1) to:VT100GridCoordMake(2, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(0, 1) to:VT100GridCoordMake(3, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(0, 1) to:VT100GridCoordMake(8, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:YES inRectFrom:VT100GridCoordMake(1, 1) to:VT100GridCoordMake(5, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(3, 1) to:VT100GridCoordMake(8, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);

    [grid markCharsDirty:NO inRectFrom:VT100GridCoordMake(2, 1) to:VT100GridCoordMake(2, 1)];
    assert(![grid isCharDirtyAt:VT100GridCoordMake(0, 1)]);
    assert([grid isCharDirtyAt:VT100GridCoordMake(1, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(2, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(3, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(4, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(5, 1)]);
    assert(![grid isCharDirtyAt:VT100GridCoordMake(6, 1)]);
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

- (void)gridCursorDidMove {
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
            if (c == '-') c = DWC_RIGHT;
            if (j == [line length] - 1) {
                if (c == '>') {
                    c = DWC_SKIP;
                    s[j+1].code = EOL_DWC;
                } else {
                    s[j+1].code = EOL_HARD;
                }
            }
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
            unichar c = [line characterAtIndex:j];
            if (c == '.') c = 0;
            if (c == '-') c = DWC_RIGHT;
            if (c == '>' && j == [line length] - 2 && [line characterAtIndex:j+1] == '>') c = DWC_SKIP;
            s[j].code = c;
        }
        if ([line characterAtIndex:j] == '!') {
            s[j].code = EOL_HARD;
        } else if ([line characterAtIndex:j] == '+') {
            s[j].code = EOL_SOFT;
        } else if ([line characterAtIndex:j] == '>') {
            s[j].code = EOL_DWC;
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
                               useScrollbackWithRegion:NO
                                            willScroll:^{
                                                assert(false);
                                            }];
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
                               useScrollbackWithRegion:NO
                                            willScroll:nil];
    assert([[grid compactLineDump] isEqualToString:@"abcd\nefgh\nijkl\nmnop"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 2);

    // Test whole screen scrolling
    grid = [self gridFromCompactLines:@"abcd\nefgh\nijkl\nmnop"];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    grid.cursorX = 0;
    grid.cursorY = 3;
    __block BOOL scrolled = NO;
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:NO
                               useScrollbackWithRegion:NO
                                            willScroll:^{
                                                scrolled = YES;
                                            }];
    assert(scrolled);
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
                               useScrollbackWithRegion:NO
                                            willScroll:nil];
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
                               useScrollbackWithRegion:YES
                                            willScroll:nil];
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
                               useScrollbackWithRegion:NO
                                            willScroll:nil];
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
                                              useScrollbackWithRegion:NO
                                                           willScroll:nil];
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
                               useScrollbackWithRegion:YES
                                            willScroll:nil];
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
    assert(grid.cursorX == 2);
}

// Make sure that moveCursorLeft wraps around soft EOLs
- (void)testMoveCursorLeftWrappingAroundSoftEOL {
    VT100Grid *grid = [self mediumGrid]; // 4x4

    NSString *string = @"abcdef";
    screen_char_t *line = [self screenCharLineForString:string];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendCharsAtCursor:line
                       length:[string length]
      scrollingIntoLineBuffer:lineBuffer
          unlimitedScrollback:YES
      useScrollbackWithRegion:NO
                   wraparound:YES
                         ansi:NO
                       insert:NO];
    assert([[grid compactLineDump] isEqualToString:
            @"abcd\n"
            @"ef..\n"
            @"....\n"
            @"...."]);

    assert(grid.cursorX == 2);
    assert(grid.cursorY == 1);
    [grid moveCursorLeft:4];
    assert(grid.cursorX == 2);
    assert(grid.cursorY == 0);
}

// Make sure that moveCursorLeft wraps around soft EOLs
- (void)testMoveCursorLeftWrappingAroundDoubleWideCharEOL {
    VT100Grid *grid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(3, 3)
                                              delegate:self] autorelease];

    NSString *string = @"abc-";  // c is double-width
    screen_char_t *line = [self screenCharLineForString:string];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendCharsAtCursor:line
                       length:[string length]
      scrollingIntoLineBuffer:lineBuffer
          unlimitedScrollback:YES
      useScrollbackWithRegion:NO
                   wraparound:YES
                         ansi:NO
                       insert:NO];
    assert([[grid compactLineDump] isEqualToString:
            @"ab>\n"
            @"c-.\n"
            @"..."]);

    assert(grid.cursorX == 2);
    assert(grid.cursorY == 1);
    [grid moveCursorLeft:4];
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 0);
}

// Make sure that moveCursorLeft wraps around soft EOLs
- (void)testMoveCursorLeftNotWrappingAroundHardEOL {
    VT100Grid *grid = [self mediumGrid]; // 4x4

    NSString *string = @"abc";
    screen_char_t *line = [self screenCharLineForString:string];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [grid appendCharsAtCursor:line
                       length:[string length]
      scrollingIntoLineBuffer:lineBuffer
          unlimitedScrollback:YES
      useScrollbackWithRegion:NO
                   wraparound:YES
                         ansi:NO
                       insert:NO];
    [grid moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:YES
                               useScrollbackWithRegion:NO
                                            willScroll:nil];
    grid.cursorX = 0;

    string = @"d";
    line = [self screenCharLineForString:string];
    [grid appendCharsAtCursor:line
                       length:[string length]
      scrollingIntoLineBuffer:lineBuffer
          unlimitedScrollback:YES
      useScrollbackWithRegion:NO
                   wraparound:YES
                         ansi:NO
                       insert:NO];

    assert([[grid compactLineDump] isEqualToString:
            @"abc.\n"
            @"d...\n"
            @"....\n"
            @"...."]);

    assert(grid.cursorX == 1);
    assert(grid.cursorY == 1);
    [grid moveCursorLeft:4];
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 1);
}

- (void)testMoveCursorRight {
    VT100Grid *grid = [self mediumGrid];
    grid.cursorX = 2;
    grid.cursorY = 0;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 3 && grid.cursorY == 0);

    grid.scrollRegionCols = VT100GridRangeMake(2, 1);
    grid.useScrollRegionCols = YES;
    grid.cursorX = 0;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 1);

    grid.cursorX = 1;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 2);

    grid.cursorX = 2;
    [grid moveCursorRight:1];
    assert(grid.cursorX == 2);
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
    [grid markCharDirty:YES at:VT100GridCoordMake(2, 2) updateTimestamp:YES];
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

// Scrolls a 2x2 region in at (1,1)
- (NSString *)compactLineDumpForRectScrolledDownBy:(int)downBy
                                        scrollRect:(VT100GridRect)scrollRect
                                      initialValue:(NSString *)initialValue {
    VT100Grid *grid = [self gridFromCompactLines:initialValue];
    [grid scrollRect:scrollRect downBy:downBy];
    return [NSString stringWithFormat:@"%@\n\n%@", [grid compactLineDump], [grid compactDirtyDump]];
}

- (void)testScrollRectDownBy {
    NSString *s;
    NSString *basicValue =
        @"abcd\n"
        @"efgh\n"
        @"ijkl\n"
        @"mnop";
    NSString *largerValue =
        @"abcde\n"
        @"fghij\n"
        @"klmno\n"
        @"pqrst\n"
        @"uvwxy";

    // Test that downBy=0 does nothing
    s = [self compactLineDumpForRectScrolledDownBy:0
                                        scrollRect:VT100GridRectMake(1, 1, 2, 2)
                                      initialValue:basicValue];
    assert([s isEqualToString:@"abcd\nefgh\nijkl\nmnop\n\ncccc\ncccc\ncccc\ncccc"]);


    // Test that downBy:1 works
    s = [self compactLineDumpForRectScrolledDownBy:1
                                        scrollRect:VT100GridRectMake(1, 1, 2, 2)
                                      initialValue:basicValue];
    assert([s isEqualToString:
            @"abcd\n"
            @"e..h\n"
            @"ifgl\n"
            @"mnop\n"
            @"\n"
            @"cccc\n"
            @"cddc\n"
            @"cddc\n"
            @"cccc"]);

    // Test that downBy:-1 works
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(1, 1, 2, 2)
                                      initialValue:basicValue];
    assert([s isEqualToString:
            @"abcd\n"
            @"ejkh\n"
            @"i..l\n"
            @"mnop\n"
            @"\n"
            @"cccc\n"
            @"cddc\n"
            @"cddc\n"
            @"cccc"]);

    // Test that downBy:2 works
    s = [self compactLineDumpForRectScrolledDownBy:2
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"f...j\n"
            @"k...o\n"
            @"pghit\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);

    // Test that downBy:-2 works
    s = [self compactLineDumpForRectScrolledDownBy:-2
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"fqrsj\n"
            @"k...o\n"
            @"p...t\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);

    // Test that direction = height works
    s = [self compactLineDumpForRectScrolledDownBy:3
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"f...j\n"
            @"k...o\n"
            @"p...t\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);

    // Test that direction = -height works
    s = [self compactLineDumpForRectScrolledDownBy:-3
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"f...j\n"
            @"k...o\n"
            @"p...t\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);

    // Test that direction = height + 1 works
    s = [self compactLineDumpForRectScrolledDownBy:4
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"f...j\n"
            @"k...o\n"
            @"p...t\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);

    // Test that direction = -height - 1 works
    s = [self compactLineDumpForRectScrolledDownBy:-4
                                        scrollRect:VT100GridRectMake(1, 1, 3, 3)
                                      initialValue:largerValue];
    assert([s isEqualToString:
            @"abcde\n"
            @"f...j\n"
            @"k...o\n"
            @"p...t\n"
            @"uvwxy\n"
            @"\n"
            @"ccccc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"cdddc\n"
            @"ccccc"]);


    // Test that split-dwc's are cleaned up when broken
    NSString *multiSplitDwcValue =
        @"ab>\n"
        @"c-d\n"
        @"ef>\n"
        @"gh-";
    // Test that a split-dwc at bottom when separated from its dwc is handled correctly.
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 1, 3, 2)
                                      initialValue:multiSplitDwcValue];
    assert([s isEqualToString:
            @"ab.\n"
            @"ef.\n"
            @"...\n"
            @"gh-\n"
            @"\n"
            @"ccc\n"
            @"ddd\n"
            @"ddd\n"
            @"ccc"]);

    // Test that a split-dwc at top when separated from its dwc is handled correctly.
    NSString *singleSplitDwcOnTopValue =
        @"ab>\n"
        @"c-d\n"
        @"efg";
    s = [self compactLineDumpForRectScrolledDownBy:1
                                        scrollRect:VT100GridRectMake(0, 1, 3, 2)
                                      initialValue:singleSplitDwcOnTopValue];
    assert([s isEqualToString:
            @"ab.\n"
            @"...\n"
            @"c-d\n"
            @"\n"
            @"ccc\n"
            @"ddd\n"
            @"ddd"]);

    // Test that a split-dwc is scrolled correctly.
    NSString *singleSplitDwcOnBottomValue =
        @"abc\n"
        @"de>\n"
        @"f-g";
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 0, 3, 3)
                                      initialValue:singleSplitDwcOnBottomValue];
    assert([s isEqualToString:
            @"de>\n"
            @"f-g\n"
            @"...\n"
            @"\n"
            @"ddd\n"
            @"ddd\n"
            @"ddd"]);

    // Test that orphaned DWCs are cleaned up when scrolling a subset of columns
    NSString *orphansValue =
        @"abcde\n"
        @"f-gh-\n"  // f- and h- should be erased because they're split up
        @"ij-k>\n"  // j- can move up, but the split-dwc is broken since l- doesn't move as a whole
        @"l-mno\n"  // l- gets erased
        @"p-qr-\n"  // p- and r- get erased
        @"stuvw";
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(1, 0, 3, 6)
                                      initialValue:orphansValue];
    assert([s isEqualToString:
            @"a.g.e\n"
            @".j-k.\n"
            @"i.mn.\n"
            @"..q.o\n"
            @".tuv.\n"
            @"s...w\n"
            @"\n"
            @"cdddc\n"
            @"ddddd\n"
            @"cdddc\n"
            @"ddddc\n"
            @"ddddd\n"
            @"cdddc"]);

    // Test edge cases of split-dwc cleanup.
    NSString *edgeCaseyOrphans =
        @"abcd>\n"
        @"e-fgh\n"
        @"ijklm\n"
        @"nopq>\n"
        @"r-stu";
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 1, 5, 3)
                                      initialValue:edgeCaseyOrphans];
    assert([s isEqualToString:
            @"abcd.\n"
            @"ijklm\n"
            @"nopq.\n"
            @".....\n"
            @"r-stu\n"
            @"\n"
            @"ccccc\n"
            @"ddddd\n"
            @"ddddd\n"
            @"ddddd\n"
            @"ccccc"]);

    // Same, but scroll by so much it just clears the area out.
    s = [self compactLineDumpForRectScrolledDownBy:-10
                                        scrollRect:VT100GridRectMake(0, 1, 5, 3)
                                      initialValue:edgeCaseyOrphans];
    assert([s isEqualToString:
            @"abcd.\n"
            @".....\n"
            @".....\n"
            @".....\n"
            @"r-stu\n"
            @"\n"
            @"ccccc\n"
            @"ddddd\n"
            @"ddddd\n"
            @"ddddd\n"
            @"ccccc"]);

    // Test scrolling a region where scrollRight=right margin, scrollLeft=1, and there's a split-dwc
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(1, 0, 4, 5)
                                      initialValue:edgeCaseyOrphans];
    assert([s isEqualToString:
            @"a.fgh\n"
            @".jklm\n"
            @"iopq.\n"
            @"n.stu\n"
            @".....\n"
            @"\n"
            @"cdddd\n"
            @"ddddd\n"
            @"cdddd\n"
            @"cdddd\n"
            @"ddddd"]);

    // Test scrolling a region where scrollRight=right margin-1, scrollLeft=0, and there's a split-dwc
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 0, 4, 5)
                                      initialValue:edgeCaseyOrphans];
    assert([s isEqualToString:
            @"e-fg.\n"
            @"ijklh\n"
            @"nopqm\n"
            @"r-st.\n"
            @"....u\n"
            @"\n"
            @"ddddc\n"
            @"ddddc\n"
            @"ddddc\n"
            @"ddddc\n"
            @"ddddc"]);

    // empty rect is harmless
    s = [self compactLineDumpForRectScrolledDownBy:1
                                        scrollRect:VT100GridRectMake(1, 1, 0, 0)
                                      initialValue:basicValue];
    assert([s isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"mnop\n"
            @"\n"
            @"cccc\n"
            @"cccc\n"
            @"cccc\n"
            @"cccc"]);

    // Move one dwc to replace one that had been split
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 1, 3, 2)
                                      initialValue:@"ab>\nc-d\ne-f"];
    assert([s isEqualToString:
            @"ab.\n"
            @"e-f\n"
            @"...\n"
            @"\n"
            @"ccc\n"
            @"ddd\n"
            @"ddd"]);

    // Test moving continuation mark to edge of rect
    NSString *lotsOfDwcsValue =
        @"ab>\n"
        @"c->\n"
        @"d->\n"
        @"e-f";
    s = [self compactLineDumpForRectScrolledDownBy:1
                                        scrollRect:VT100GridRectMake(0, 1, 3, 3)
                                      initialValue:lotsOfDwcsValue];
    assert([s isEqualToString:
            @"ab.\n"
            @"...\n"
            @"c->\n"
            @"d-.\n"
            @"\n"
            @"ccc\n"
            @"ddd\n"
            @"ddd\n"
            @"ddd"]);


    // Same, but other direction
    s = [self compactLineDumpForRectScrolledDownBy:-1
                                        scrollRect:VT100GridRectMake(0, 1, 3, 2)
                                      initialValue:lotsOfDwcsValue];
    assert([s isEqualToString:
            @"ab.\n"
            @"d-.\n"
            @"...\n"
            @"e-f\n"
            @"\n"
            @"ccc\n"
            @"ddd\n"
            @"ddd\n"
            @"ccc"]);

    // Test that continuation marks are cleaned up before the scrolled region with
    // full width and scrolling down
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:
                       @"abcd+\n"
                       @"efgh+\n"
                       @"ijkl+\n"
                       @"mnop+\n"
                       @"qrst!"];
    [grid scrollRect:VT100GridRectMake(0, 1, 4, 3) downBy:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"....!\n"
            @"efgh+\n"
            @"ijkl!\n"
            @"qrst!"]);

    // Same but scroll by 2
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(0, 1, 4, 3) downBy:2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"....!\n"
            @"....!\n"
            @"efgh!\n"
            @"qrst!"]);

    // Test that continuation marks are cleaned up before the scrolled region with
    // full width and scrolling up
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(0, 1, 4, 3) downBy:-1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"ijkl+\n"
            @"mnop!\n"
            @"....!\n"
            @"qrst!"]);

    // Same but scroll by 2
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(0, 1, 4, 3) downBy:-2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"mnop!\n"
            @"....!\n"
            @"....!\n"
            @"qrst!"]);

    // Test that continuation marks are cleaned up before the scrolled region with
    // no first column and scrolling down
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"e...!\n"
            @"ifgh+\n"
            @"mjkl!\n"
            @"qrst!"]);

    // Same but scroll by 2
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"e...!\n"
            @"i...!\n"
            @"mfgh!\n"
            @"qrst!"]);

    // With DWC_SKIP
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijk>>\n"
            @"M-op+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"e...!\n"
            @"ifgh+\n"
            @".jk.!\n"
            @"qrst!"]);

    // Test that continuation marks are cleaned up before the scrolled region with
    // no first column and scrolling up
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:-1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"ejkl+\n"
            @"inop!\n"
            @"m...!\n"
            @"qrst!"]);

    // With DWC_SKIP
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abc>>\n"
            @"E-gh+\n"
            @"ijkl+\n"
            @"mno>>\n"
            @"Q-st!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:-1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abc.!\n"
            @".jkl+\n"
            @"ino.!\n"
            @"m...!\n"
            @"Q-st!"]);

    // Same but scroll by 2
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efgh+\n"
            @"ijkl+\n"
            @"mnop+\n"
            @"qrst!"];
    [grid scrollRect:VT100GridRectMake(1, 1, 3, 3) downBy:-2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"enop!\n"
            @"i...!\n"
            @"m...!\n"
            @"qrst!"]);

}

- (void)testSetContentsFromDVRFrame {
    NSString *compactLines = @"abcd\nefgh\nijkl\nmnop";
    VT100Grid *grid = [self gridFromCompactLines:compactLines];
    const int w = 5, h = 4;
    screen_char_t frame[(w + 1) * h];
    int o = 0;
    for (int y = 0; y < h; y++) {
        screen_char_t *line = [grid screenCharsAtLineNumber:y];
        memmove(frame + o, line, sizeof(screen_char_t) * (w + 1));
        o += w;
    }

    // Test basic functionality -- save and restore 4x4 into 4x4.
    VT100Grid *testGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(4, 4)
                                                  delegate:self] autorelease];
    DVRFrameInfo info = {
        .width = 4,
        .height = 4,
        .cursorX = 1,
        .cursorY = 2,
        .timestamp = 0,
        .frameType = DVRFrameTypeKeyFrame
    };
    [testGrid setContentsFromDVRFrame:frame info:info];
    assert([[testGrid compactLineDump] isEqualToString:compactLines]);
    assert(testGrid.cursorX == 1);
    assert(testGrid.cursorY == 2);

    // Put it into a smaller grid.
    testGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(3, 3)
                                       delegate:self] autorelease];
    [testGrid setContentsFromDVRFrame:frame info:info];
    NSString *truncatedCompactLines =
        @"efg\n"
        @"ijk\n"
        @"mno";
    assert([[testGrid compactLineDump] isEqualToString:truncatedCompactLines]);
    assert(testGrid.cursorX == 1);
    assert(testGrid.cursorY == 1);

    // Put it into a bigger grid
    testGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(5, 5)
                                       delegate:self] autorelease];
    [testGrid setContentsFromDVRFrame:frame info:info];
    NSString *paddedCompactLines =
        @"abcd.\n"
        @"efgh.\n"
        @"ijkl.\n"
        @"mnop.\n"
        @".....";
    assert([[testGrid compactLineDump] isEqualToString:paddedCompactLines]);
    assert(testGrid.cursorX == 1);
    assert(testGrid.cursorY == 2);
}

- (void)doTestDefaultLine {
    VT100Grid *grid = [self smallGrid];
    const int w = 80;
    NSMutableData *data = [grid defaultLineOfWidth:80];
    screen_char_t *line = [data mutableBytes];
    assert(data.length == sizeof(screen_char_t) * (w + 1));  // w+1 because it adds one for continuation marker
    for (int i = 0; i < w; i++) {
        assert(ForegroundAttributesEqual(line[i], foregroundColor_));
        assert(BackgroundColorsEqual(line[i], backgroundColor_));
        assert(line[i].code == 0);
    }
    assert(line[w].code == EOL_HARD);
}

- (void)testDefaultLine {
    [self doTestDefaultLine];
    foregroundColor_.foregroundColor = ALTSEM_SELECTED;
    [self doTestDefaultLine];
}

- (void)testSetBgFgColorInRect {
    VT100Grid *grid = [self mediumGrid];  // 4x4
    screen_char_t redFg = { 0 };
    redFg.foregroundColor = 1;
    redFg.foregroundColorMode = ColorModeNormal;

    screen_char_t greenBg = { 0 };
    greenBg.backgroundColor = 2;
    greenBg.backgroundColorMode = ColorModeNormal;

    [grid setBackgroundColor:greenBg
             foregroundColor:redFg
                  inRectFrom:VT100GridCoordMake(1, 1)
                          to:VT100GridCoordMake(2, 2)];

    for (int y = 0; y < 4; y++) {
        screen_char_t *line = [grid screenCharsAtLineNumber:y];
        screen_char_t fg, bg;
        for (int x = 0; x < 4; x++) {
            if ((x == 1 || x == 2) && (y == 1 || y == 2)) {
                fg = redFg;
                bg = greenBg;
                assert([grid isCharDirtyAt:VT100GridCoordMake(x, y)]);
            } else {
                fg = foregroundColor_;
                bg = backgroundColor_;
                assert(![grid isCharDirtyAt:VT100GridCoordMake(x, y)]);
            }
            assert(ForegroundAttributesEqual(fg, line[x]));
            assert(BackgroundColorsEqual(bg, line[x]));
        }
    }

    // Test the setting an invalid fg results in to change to fg
    screen_char_t invalidFg = redFg;
    invalidFg.foregroundColorMode = ColorModeInvalid;
    [grid setBackgroundColor:greenBg
             foregroundColor:invalidFg
                  inRectFrom:VT100GridCoordMake(0, 0)
                          to:VT100GridCoordMake(3, 3)];
    // Now should be green bg everywhere, red fg in center square
    for (int y = 0; y < 4; y++) {
        screen_char_t *line = [grid screenCharsAtLineNumber:y];
        screen_char_t fg;
        for (int x = 0; x < 4; x++) {
            if ((x == 1 || x == 2) && (y == 1 || y == 2)) {
                fg = redFg;
            } else {
                fg = foregroundColor_;
            }
            assert(ForegroundAttributesEqual(fg, line[x]));
            assert(BackgroundColorsEqual(greenBg, line[x]));
        }
    }

    // Try an invalid bg now
    screen_char_t invalidBg = greenBg;
    invalidBg.backgroundColorMode = ColorModeInvalid;
    [grid setBackgroundColor:invalidBg
             foregroundColor:foregroundColor_
                  inRectFrom:VT100GridCoordMake(0, 0)
                          to:VT100GridCoordMake(3, 3)];
    // Now should be default on green everywhere
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            screen_char_t *line = [grid screenCharsAtLineNumber:y];
            assert(ForegroundAttributesEqual(foregroundColor_, line[x]));
            assert(BackgroundColorsEqual(greenBg, line[x]));
        }
    }
}

// Returns a grid the same size as 'grid' with 'x's where runs are present.
- (VT100Grid *)coverageForRuns:(NSArray *)runs inGrid:(VT100Grid *)grid {
    VT100Grid *coverage = [[[VT100Grid alloc] initWithSize:grid.size delegate:self] autorelease];
    for (NSValue *value in runs) {
        VT100GridRun run = [value gridRunValue];
        [coverage setCharsInRun:run toChar:'x'];
    }
    return coverage;
}

- (void)testRunsMatchingRegex {
    NSString *cl =
    //    0123456789ab
        @"george      !\n"  // 0
        @"         geo+\n"  // 1
        @"rge         !\n"  // 2
        @"         geo!\n"  // 3
        @"rge         !\n"  // 4
        @"georgegeorge!\n"  // 5
        @"     georgeo+\n"  // 6
        @"rge         !";   // 7
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:cl];
    NSArray *runs = [grid runsMatchingRegex:@"george"];

    NSString *expectedCoverage =
        @"xxxxxx......\n"  // 0
        @".........xxx\n"  // 1
        @"xxx.........\n"  // 2
        @"............\n"  // 3
        @"............\n"  // 4
        @"xxxxxxxxxxxx\n"  // 5
        @".....xxxxxx.\n"  // 6
        @"............";  // 7
    VT100Grid *coverage = [self coverageForRuns:runs inGrid:grid];
    assert([[coverage compactLineDump] isEqualToString:expectedCoverage]);

    // Now test with combining marks.
    screen_char_t *line = [grid screenCharsAtLineNumber:0];
    BeginComplexChar(line + 1, 0x20dd, NO);  // e + combining enclosing circle
    line[1].complexChar = YES;
    runs = [grid runsMatchingRegex:@"ge.?orge"];  // the regex lib doesn't handle combining marks well
    coverage = [self coverageForRuns:runs inGrid:grid];
    assert([[coverage compactLineDump] isEqualToString:expectedCoverage]);

    // Test with double-width char.
    line[1].code = 0xff25;  // fullwidth e
    line[1].complexChar = NO;
    runs = [grid runsMatchingRegex:@"g.orge"];
    coverage = [self coverageForRuns:runs inGrid:grid];
    assert([[coverage compactLineDump] isEqualToString:expectedCoverage]);
}

// - is a DWC_RIGHT
// . is null
// All other chars are taken literally
- (screen_char_t *)screenCharLineForString:(NSString *)string {
    NSMutableData *data = [NSMutableData dataWithLength:string.length * sizeof(screen_char_t)];
    screen_char_t *line = data.mutableBytes;
    for (int i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '-') {
            c = DWC_RIGHT;
        } else if (c == '.') {
            c = 0;
        }
        line[i].code = c;
    }
    return line;
}

// Put a * in a string to designate the char after it as the cursor's location. The * will not be
// added to the linebuffer.
- (LineBuffer *)lineBufferWithStrings:(NSString *)first, ...
{
    NSMutableArray *strings = [NSMutableArray array];
    va_list args;
    va_start(args, first);
    for (NSString *arg = first; arg != nil; arg = va_arg(args, NSString*)) {
        [strings addObject:arg];
    }

    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    int i = 0;
    for (NSString *string in strings) {
        NSRange range = [string rangeOfString:@"*"];  // gives cursor position
        if (range.location != NSNotFound) {
            string = [string stringByReplacingOccurrencesOfString:@"*" withString:@""];
            [lineBuffer setCursor:range.location];
        }
        if ([string rangeOfString:@"-"].location != NSNotFound) {
            lineBuffer.mayHaveDoubleWidthCharacter = YES;
        }
        screen_char_t continuation = { 0 };
        [lineBuffer appendLine:[self screenCharLineForString:string]
                        length:string.length
                       partial:i == strings.count - 1
                         width:80
                     timestamp:0
                  continuation:continuation];
        i++;
    }
    va_end(args);

    return lineBuffer;
}

- (void)testRestoreScreenFromLineBuffer {
    VT100Grid *grid = [self largeGrid];
    LineBuffer *lineBuffer = [self lineBufferWithStrings:@"test", @"hello wor*ld", nil];
    [grid restoreScreenFromLineBuffer:lineBuffer
                      withDefaultChar:[grid defaultChar]
                    maxLinesToRestore:1];
    assert([[grid compactLineDump] isEqualToString:
            @"rld.....\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........"]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 0);

    grid = [self largeGrid];
    lineBuffer = [self lineBufferWithStrings:@"test", @"hello wo*rld", nil];
    [grid restoreScreenFromLineBuffer:lineBuffer
                      withDefaultChar:[grid defaultChar]
                    maxLinesToRestore:100];
    assert([[grid compactLineDump] isEqualToString:
            @"test....\n"
            @"hello wo\n"
            @"rld.....\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........\n"
            @"........"]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 2);

    grid = [self smallGrid];
    lineBuffer = [self lineBufferWithStrings:@"test", @"hello wor*ld", nil];
    screen_char_t dc = { 0 };
    dc.backgroundColor = 1;
    dc.backgroundColorMode = ColorModeNormal;
    [grid restoreScreenFromLineBuffer:lineBuffer
                      withDefaultChar:dc
                    maxLinesToRestore:100];
    assert([[grid compactLineDump] isEqualToString:
            @"rl\n"
            @"d."]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 0);

    screen_char_t *line = [grid screenCharsAtLineNumber:1];
    assert(!BackgroundColorsEqual(dc, line[0]));
    assert(!BackgroundColorsEqual(dc, line[1]));

    // Handle DWC_SKIPs
    grid = [self mediumGrid];
    lineBuffer = [self lineBufferWithStrings:@"abc*W-xy", nil];
    [grid restoreScreenFromLineBuffer:lineBuffer
                      withDefaultChar:[grid defaultChar]
                    maxLinesToRestore:100];
    assert([[grid compactLineDump] isEqualToString:
            @"abc>\n"
            @"W-xy\n"
            @"....\n"
            @"...."]);
    assert(grid.cursorX == 0);
    assert(grid.cursorY == 1);
}

- (void)testClampCursorPositionToValid {
    // It's hard to test this method because the grid class keeps the cursor position valid.
    // However, it will allow the cursor to be in the width'th column, while clamp... keeps it
    // < width.
    VT100Grid *grid = [self smallGrid];
    grid.cursorX = 2;
    assert(grid.cursorX == 2);
    [grid clampCursorPositionToValid];
    assert(grid.cursorX == 1);
}

- (void)testRectsForRun {
    VT100Grid *grid = [self largeGrid];  // 8x8
    VT100GridRun run = VT100GridRunMake(3, 2, 20);
    screen_char_t x = [grid defaultChar];
    x.code = 'x';
    for (NSValue *value in [grid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [grid setCharsFrom:rect.origin to:VT100GridRectMax(rect) toChar:x];
    }

    assert([[grid compactLineDump] isEqualToString:
            @"........\n"
            @"........\n"
            @"...xxxxx\n"
            @"xxxxxxxx\n"
            @"xxxxxxx.\n"
            @"........\n"
            @"........\n"
            @"........"]);

    // Test empty run
    assert([[grid rectsForRun:VT100GridRunMake(3, 2, 0)] count] == 0);

    // Test one-line run
    NSArray *rects = [grid rectsForRun:VT100GridRunMake(3, 2, 2)];
    assert(rects.count == 1);
    VT100GridRect rect = [[rects objectAtIndex:0] gridRectValue];
    assert(rect.origin.x == 3);
    assert(rect.origin.y == 2);
    assert(rect.size.width == 2);
    assert(rect.size.height == 1);
}

- (void)testResetScrollRegions {
    VT100Grid *grid = [self largeGrid];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 3);
    grid.useScrollRegionCols = YES;
    [grid resetScrollRegions];
    assert(grid.scrollRegionRows.location == 0);
    assert(grid.scrollRegionRows.length == 8);
    assert(grid.scrollRegionCols.location == 0);
    assert(grid.scrollRegionCols.length == 8);
}

- (void)testScrollRegionRect {
    VT100Grid *grid = [self largeGrid];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 3);
    grid.useScrollRegionCols = YES;

    VT100GridRect rect = [grid scrollRegionRect];
    assert(rect.origin.x == 2);
    assert(rect.origin.y == 1);
    assert(rect.size.width == 3);
    assert(rect.size.height == 2);

    grid.useScrollRegionCols = NO;
    rect = [grid scrollRegionRect];
    assert(rect.origin.x == 0);
    assert(rect.origin.y == 1);
    assert(rect.size.width == 8);
    assert(rect.size.height == 2);
}

- (void)testEraseDwc {
    // Erase a DWC
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:@"ab-!"];
    screen_char_t dc = [grid defaultChar];
    assert([grid erasePossibleDoubleWidthCharInLineNumber:0
                                         startingAtOffset:1
                                                 withChar:dc]);
    assert([[grid compactLineDump] isEqualToString:@"a.."]);
    assert([[grid compactDirtyDump] isEqualToString:@"cdd"]);

    // Do nothing
    grid = [self gridFromCompactLinesWithContinuationMarks:@"ab-!"];
    assert(![grid erasePossibleDoubleWidthCharInLineNumber:0
                                          startingAtOffset:0
                                                  withChar:dc]);
    assert([[grid compactLineDump] isEqualToString:@"ab-"]);
    assert([[grid compactDirtyDump] isEqualToString:@"ccc"]);

    // Erase DWC-skip on prior line
    grid = [self gridFromCompactLinesWithContinuationMarks:@"ab>>\nc-.!"];
    assert([grid erasePossibleDoubleWidthCharInLineNumber:1
                                         startingAtOffset:0
                                                 withChar:dc]);
    assert([[grid compactLineDump] isEqualToString:@"ab.\n..."]);
    assert([[grid compactDirtyDump] isEqualToString:@"ccc\nddc"]);  // Don't need to set DWC_SKIP->NULL char to dirty
}

- (void)testMoveCursorToLeftMargin {
    VT100Grid *grid = [self mediumGrid];

    // Test without scroll region
    grid.cursorX = 2;
    assert(grid.cursorX == 2);
    [grid moveCursorToLeftMargin];
    assert(grid.cursorX == 0);

    // Scroll region defined but not used
    grid.scrollRegionCols = VT100GridRangeMake(1,2);
    grid.cursorX = 2;
    assert(grid.cursorX == 2);
    [grid moveCursorToLeftMargin];
    assert(grid.cursorX == 0);

    // Scroll region defined & used
    grid.useScrollRegionCols = YES;
    grid.cursorX = 2;
    assert(grid.cursorX == 2);
    [grid moveCursorToLeftMargin];
    assert(grid.cursorX == 1);

}

- (void)testResetWithLineBufferLeavingBehindZero {
    VT100Grid *grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.cursorX = 2;
    grid.cursorY = 3;

    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    int dropped = [grid resetWithLineBuffer:lineBuffer
                        unlimitedScrollback:NO
                         preserveCursorLine:NO];
    assert(dropped == 2);
    assert([[grid compactLineDump] isEqualToString:
            @"....\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"efgh!"]);
    assert(grid.scrollRegionRows.location == 0);
    assert(grid.scrollRegionRows.length == 4);
    assert(grid.scrollRegionCols.location == 0);
    assert(grid.scrollRegionCols.length == 4);
    assert(grid.cursor.x == 0);
    assert(grid.cursor.y == 0);

    // Test unlimited scrollback --------------------------------------------------------------------
    grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:YES
                     preserveCursorLine:NO];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:
            @"....\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"0123!\nabcd!\nefgh!"]);

    // Test on empty screen ------------------------------------------------------------------------
    grid = [self smallGrid];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:YES
                     preserveCursorLine:NO];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:
            @"..\n"
            @".."]);
    assert([lineBuffer numLinesWithWidth:grid.size.width] == 0);
}

- (void)testResetWithLineBufferLeavingBehindCursorLine {
    // Cursor below content
    VT100Grid *grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.cursorX = 2;
    grid.cursorY = 3;

    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    int dropped = [grid resetWithLineBuffer:lineBuffer
                        unlimitedScrollback:NO
                         preserveCursorLine:YES];
    assert(dropped == 2);
    assert([[grid compactLineDump] isEqualToString:
            @"....\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"efgh!"]);
    assert(grid.scrollRegionRows.location == 0);
    assert(grid.scrollRegionRows.length == 4);
    assert(grid.scrollRegionCols.location == 0);
    assert(grid.scrollRegionCols.length == 4);
    assert(grid.cursor.x == 0);
    assert(grid.cursor.y == 0);

    // Cursor at end of content
    grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.cursorX = 2;
    grid.cursorY = 2;

    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:NO
                     preserveCursorLine:YES];
    assert(dropped == 1);
    assert([[grid compactLineDump] isEqualToString:
            @"efgh\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"abcd!"]);
    assert(grid.scrollRegionRows.location == 0);
    assert(grid.scrollRegionRows.length == 4);
    assert(grid.scrollRegionCols.location == 0);
    assert(grid.scrollRegionCols.length == 4);
    assert(grid.cursor.x == 0);
    assert(grid.cursor.y == 0);

    // Cursor within content
    grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.cursorX = 2;
    grid.cursorY = 1;

    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:NO
                     preserveCursorLine:YES];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:
            @"abcd\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"0123!"]);
    assert(grid.scrollRegionRows.location == 0);
    assert(grid.scrollRegionRows.length == 4);
    assert(grid.scrollRegionCols.location == 0);
    assert(grid.scrollRegionCols.length == 4);
    assert(grid.cursor.x == 0);
    assert(grid.cursor.y == 0);

    // Test unlimited scrollback --------------------------------------------------------------------
    grid = [self gridFromCompactLines:@"0123\nabcd\nefgh\n...."];
    grid.cursor = VT100GridCoordMake(0, 3);
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:YES
                     preserveCursorLine:YES];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:
            @"....\n"
            @"....\n"
            @"....\n"
            @"...."]);
    assert([[lineBuffer debugString] isEqualToString:@"0123!\nabcd!\nefgh!"]);

    // Test on empty screen ------------------------------------------------------------------------
    grid = [self smallGrid];
    lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    [lineBuffer setMaxLines:1];
    dropped = [grid resetWithLineBuffer:lineBuffer
                    unlimitedScrollback:YES
                     preserveCursorLine:YES];
    assert(dropped == 0);
    assert([[grid compactLineDump] isEqualToString:
            @"..\n"
            @".."]);
    assert([lineBuffer numLinesWithWidth:grid.size.width] == 0);
}


- (void)testMoveWrappedCursorLineToTopOfGrid {
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:
                       @"abcd+\n"
                       @"efg.!\n"
                       @"hijk+\n"
                       @"lmno+\n"
                       @"pq..!\n"
                       @"rstu+\n"
                       @"vwx.!"];
    grid.cursorX = 1;
    grid.cursorY = 4;
    [grid moveWrappedCursorLineToTopOfGrid];

    assert([[grid compactLineDump] isEqualToString:
            @"hijk\n"
            @"lmno\n"
            @"pq..\n"
            @"rstu\n"
            @"vwx.\n"
            @"....\n"
            @"...."]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 2);

    // Test empty screen
    grid = [self smallGrid];
    grid.cursorX = 1;
    grid.cursorY = 1;
    [grid moveWrappedCursorLineToTopOfGrid];

    assert([[grid compactLineDump] isEqualToString:@"..\n.."]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 0);

    // Test that scroll regions are ignored.
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!\n"
            @"hijk+\n"
            @"lmno+\n"
            @"pq..!\n"
            @"rstu+\n"
            @"vwx.!"];
    grid.scrollRegionRows = VT100GridRangeMake(1, 2);
    grid.scrollRegionCols = VT100GridRangeMake(2, 2);
    grid.useScrollRegionCols = YES;
    grid.cursorX = 1;
    grid.cursorY = 4;
    [grid moveWrappedCursorLineToTopOfGrid];

    assert([[grid compactLineDump] isEqualToString:
            @"hijk\n"
            @"lmno\n"
            @"pq..\n"
            @"rstu\n"
            @"vwx.\n"
            @"....\n"
            @"...."]);
    assert(grid.cursorX == 1);
    assert(grid.cursorY == 2);
}

- (void)doAppendCharsAtCursorTestWithInitialBuffer:(NSString *)initialBuffer
                                      scrollRegion:(VT100GridRect)scrollRect
                           useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                               unlimitedScrollback:(BOOL)unlimitedScrollback
                                         appending:(NSString *)stringToAppend
                                                at:(VT100GridCoord)initialCursor
                                            expect:(NSString *)expectedLines
                                      expectCursor:(VT100GridCoord)expectedCursor
                                  expectLineBuffer:(NSString *)expectedLineBuffer
                                     expectDropped:(int)expectedNumLinesDropped {
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:initialBuffer];
    LineBuffer *lineBuffer = [[[LineBuffer alloc] initWithBlockSize:1000] autorelease];
    if (scrollRect.size.width >= 0) {
        grid.scrollRegionCols = VT100GridRangeMake(scrollRect.origin.x, scrollRect.size.width);
        grid.useScrollRegionCols = YES;
    }
    if (scrollRect.size.height >= 0) {
        grid.scrollRegionRows = VT100GridRangeMake(scrollRect.origin.y, scrollRect.size.height);
    }
    screen_char_t *line = [self screenCharLineForString:stringToAppend];
    grid.cursor = initialCursor;
    int numLinesDropped = [grid appendCharsAtCursor:line
                                             length:[stringToAppend length]
                            scrollingIntoLineBuffer:lineBuffer
                                unlimitedScrollback:unlimitedScrollback
                            useScrollbackWithRegion:useScrollbackWithRegion
                                         wraparound:wraparoundMode_
                                               ansi:isAnsi_
                                             insert:insertMode_];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:expectedLines]);
    assert([[lineBuffer debugString] isEqualToString:expectedLineBuffer]);
    assert(numLinesDropped == expectedNumLinesDropped);
    assert(grid.cursorX == expectedCursor.x);
    assert(grid.cursorY == expectedCursor.y);
}

- (void)testAppendCharsAtCursor {
    // append empty buffer
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"ab!\n"
                                                     @"cd!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@""
                                                  at:VT100GridCoordMake(0, 0)
                                              expect:@"ab!\n"
                                                     @"cd!"
                                        expectCursor:VT100GridCoordMake(0, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // scrolling into line buffer
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc!\n"
                                                     @"d..!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efgh"
                                                  at:VT100GridCoordMake(1, 1)
                                              expect:@"def+\n"
                                                     @"gh.!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@"abc!"
                                       expectDropped:0];

    // no scrolling into line buffer with vsplit
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc!\n"
                                                     @"d..!"
                                        scrollRegion:VT100GridRectMake(1, 0, 2, 2)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efgh"
                                                  at:VT100GridCoordMake(1, 1)
                                              expect:@"aef!\n"
                                                     @"dgh!"
                                        expectCursor:VT100GridCoordMake(3, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // scrolling into line buffer with scrollTop/Bottom + useScrollbackWithRegion
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc!\n"
                                                     @"d..!"
                                        scrollRegion:VT100GridRectMake(0, 0, 3, 1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efgh"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"h..!\n"
                                                     @"d..!"
                                        expectCursor:VT100GridCoordMake(1, 0)
                                    expectLineBuffer:@"abcefg+"
                                       expectDropped:0];

    // no scrolling into line buffer with scrollTop/Bottom + !useScrollbackWithRegion
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc!\n"
                                                     @"d..!"
                                        scrollRegion:VT100GridRectMake(0, 0, 3, 1)
                             useScrollbackWithRegion:NO
                                 unlimitedScrollback:NO
                                           appending:@"efgh"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"h..!\n"
                                                     @"d..!"
                                        expectCursor:VT100GridCoordMake(1, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // cursor starts outside scrollTop/Bottom region and scrolls (not sure what should happen!)
    // TODO

    // no scrolling into line buffer with h-region + v-region + useScrollbackWithRegion
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc!\n"
                                                     @"d..!"
                                        scrollRegion:VT100GridRectMake(1, 0, 2, 1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efgh"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"agh!\n"
                                                     @"d..!"
                                        expectCursor:VT100GridCoordMake(3, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];
    // unlimited scrollback
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"ab!\n"
                                                     @"cd!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:YES
                                           appending:@"efghijklmn"
                                                  at:VT100GridCoordMake(2, 1)
                                              expect:@"kl+\n"
                                                     @"mn!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@"ab!\ncdefghij+"
                                       expectDropped:0];
    // DWC
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"...!\n"
                                                     @"...!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"A-bcd"
                                                  at:VT100GridCoordMake(0, 0)
                                              expect:@"A-b+\n"
                                                     @"cd.!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // DWC that gets split to next line (wraparoundmode on)
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"...!\n"
                                                     @"...!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"abC-d"
                                                  at:VT100GridCoordMake(0, 0)
                                              expect:@"ab>>\n"
                                                     @"C-d!"
                                        expectCursor:VT100GridCoordMake(3, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // DWC that gets split to next line at vsplit (wraparoundmode on)
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"....!\n"
                                                     @"....!\n"
                                                     @"....!"
                                        scrollRegion:VT100GridRectMake(0, 0, 3, 3)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"abC-d"
                                                  at:VT100GridCoordMake(0, 0)
                                              expect:@"ab..!\n"
                                                     @"C-d.!\n"
                                                     @"....!"
                                        expectCursor:VT100GridCoordMake(3, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // plain text wraps around in wraparoundmode
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"a.!\n"
                                                     @"..!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"bcd"
                                                  at:VT100GridCoordMake(1, 0)
                                              expect:@"ab+\n"
                                                     @"cd!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // plain text wraps around in wraparoundmode in vsplit
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"a...!\n"
                                                     @"....!"
                                        scrollRegion:VT100GridRectMake(0, 0, 2, 2)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"bcde"
                                                  at:VT100GridCoordMake(1, 0)
                                              expect:@"cd..!\n"
                                                     @"e...!"
                                        expectCursor:VT100GridCoordMake(1, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // plain text truncated bc wraparoundmode is off (cont marker should go to hard)
    wraparoundMode_ = NO;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"zyxwv+\n"
                                                     @"u....!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"abcdefgh"
                                                  at:VT100GridCoordMake(1, 0)
                                              expect:@"zabch!\n"
                                                     @"u....!"
                                        expectCursor:VT100GridCoordMake(5, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // Appending long string ending in DWC with wraparound off
    wraparoundMode_ = NO;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"zyxwv+\n"
                                                     @"u....!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"abcdefghI-"
                                                  at:VT100GridCoordMake(1, 0)
                                              expect:@"zabI-!\n"
                                                     @"u....!"
                                        expectCursor:VT100GridCoordMake(5, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // Appending long string with wraparound off that orphans a dwc |abC-d| -> |abCxz|
    wraparoundMode_ = NO;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"zyxwv+\n"
                                                     @"u....!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"abC-defg"
                                                  at:VT100GridCoordMake(1, 0)
                                              expect:@"zab.g!\n"
                                                     @"u....!"
                                        expectCursor:VT100GridCoordMake(5, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    wraparoundMode_ = YES;

    // insert mode with plain text
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcdgh..!\n"
                                                     @"zy......!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"ef"
                                                  at:VT100GridCoordMake(4, 0)
                                              expect:@"abcdefgh!\n"
                                                     @"zy......!"
                                        expectCursor:VT100GridCoordMake(6, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // insert orphaning DWCs
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcdgH-.!\n"
                                                     @"zy......!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"ef"
                                                  at:VT100GridCoordMake(4, 0)
                                              expect:@"abcdefg.!\n"
                                                     @"zy......!"
                                        expectCursor:VT100GridCoordMake(6, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // insert stomping DWC_SKIP, causing lines to be joined normally
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcdfgh>>\n"
                                                     @"I-......!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"e"
                                                  at:VT100GridCoordMake(4, 0)
                                              expect:@"abcdefgh+\n"
                                                     @"I-......!"
                                        expectCursor:VT100GridCoordMake(5, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // insert really long string, causing truncation at end of line and of inserted string and
    // wraparound
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcdtuvw+\n"
                                                     @"xyz.....!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efghijklm"
                                                  at:VT100GridCoordMake(4, 0)
                                              expect:@"abcdefgh+\n"
                                                     @"ijklmxyz!"
                                        expectCursor:VT100GridCoordMake(5, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    //  insert long string without wrapraround
    insertMode_ = YES;
    wraparoundMode_ = NO;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcdtuvw+\n"
                                                     @"xyz.....!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"efghijklm"
                                                  at:VT100GridCoordMake(4, 0)
                                              expect:@"abcdefgm!\n"
                                                     @"xyz.....!"
                                        expectCursor:VT100GridCoordMake(8, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];
    wraparoundMode_ = YES;

    // insert mode with vsplit
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcde!\n"
                                                     @"xyz..!"
                                        scrollRegion:VT100GridRectMake(1, 0, 3, 2)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"m"
                                                  at:VT100GridCoordMake(2, 0)
                                              expect:@"abmce!\n"
                                                     @"xyz..!"
                                        expectCursor:VT100GridCoordMake(3, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // insert wrapping string with vsplit
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcde!\n"
                                                     @"xyz..!"
                                        scrollRegion:VT100GridRectMake(1, 0, 3, 2)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"mno"
                                                  at:VT100GridCoordMake(2, 0)
                                              expect:@"abmne!\n"
                                                     @"xoyz.!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // insert orphaning dwc and end of line with vsplit
    insertMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcD-e!\n"
                                                     @"xyz...!"
                                        scrollRegion:VT100GridRectMake(1, 0, 4, 2)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"m"
                                                  at:VT100GridCoordMake(2, 0)
                                              expect:@"abmc.e!\n"
                                                     @"xyz...!"
                                        expectCursor:VT100GridCoordMake(3, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    insertMode_ = NO;
    // with insert mode off, overwrite the left half of a DWC, leaving orphan
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abcD-e!\n"
                                                     @"xyz...!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"mn"
                                                  at:VT100GridCoordMake(2, 0)
                                              expect:@"abmn.e!\n"
                                                     @"xyz...!"
                                        expectCursor:VT100GridCoordMake(4, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // with ansi terminal, placing cursor at right margin wraps it around in wraparound mode
    // TODO: vsplits aren't treated the same way; should they be?
    isAnsi_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc.!\n"
                                                     @"xyz.!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"d"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"abcd+\n"
                                                     @"xyz.!"
                                        expectCursor:VT100GridCoordMake(0, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // with ansi terminal, placing cursor at right margin moves it back one space if wraparoundmode is off
    // TODO: vsplits aren't treated the same way; should they be?
    isAnsi_ = YES;
    wraparoundMode_ = NO;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc.!\n"
                                                     @"xyz.!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"d"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"abcd!\n"
                                                     @"xyz.!"
                                        expectCursor:VT100GridCoordMake(3, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    // Overwriting a DWC_SKIP converts EOL_DWC to EOL_SOFT
    isAnsi_ = NO;
    wraparoundMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc>>\n"
                                                     @"D-..!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"d"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"abcd+\n"
                                                     @"D-..!"
                                        expectCursor:VT100GridCoordMake(4, 0)
                                    expectLineBuffer:@""
                                       expectDropped:0];

    isAnsi_ = NO;
    wraparoundMode_ = YES;
    [self doAppendCharsAtCursorTestWithInitialBuffer:@"abc>>\n"
                                                     @"D-..!"
                                        scrollRegion:VT100GridRectMake(0, 0, -1, -1)
                             useScrollbackWithRegion:YES
                                 unlimitedScrollback:NO
                                           appending:@"def"
                                                  at:VT100GridCoordMake(3, 0)
                                              expect:@"abcd+\n"
                                                     @"ef..!"
                                        expectCursor:VT100GridCoordMake(2, 1)
                                    expectLineBuffer:@""
                                       expectDropped:0];
}

- (void)testCoordinateBefore {
    VT100Grid *grid = [self smallGrid];
    // Test basic case
    VT100GridCoord coord = [grid coordinateBefore:VT100GridCoordMake(1, 0)];
    assert(coord.x == 0);
    assert(coord.y == 0);

    // Test failure to move before grid
    coord = [grid coordinateBefore:VT100GridCoordMake(0, 0)];
    assert(coord.x == -1);
    assert(coord.y == -1);

    // Test simple wrap-back over EOL_SOFT
    grid = [self gridFromCompactLinesWithContinuationMarks:@"ab+\ncd!"];
    coord = [grid coordinateBefore:VT100GridCoordMake(0, 1)];
    assert(coord.x == 1);
    assert(coord.y == 0);

    // Test failure to wrap-back across EOL_HARD
    grid = [self gridFromCompactLinesWithContinuationMarks:@"ab!\ncd!"];
    coord = [grid coordinateBefore:VT100GridCoordMake(0, 1)];
    assert(coord.x == -1);
    assert(coord.y == -1);

    // Test wrap-back over EOL_DWC + DWC_SKIP
    grid = [self gridFromCompactLinesWithContinuationMarks:@"a>>\nC-!"];
    coord = [grid coordinateBefore:VT100GridCoordMake(0, 1)];
    assert(coord.x == 0);
    assert(coord.y == 0);

    // Test scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:@"abcd!\nefgh!"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 2);
    grid.useScrollRegionCols = YES;
    coord = [grid coordinateBefore:VT100GridCoordMake(1, 1)];
    assert(coord.x == 2);
    assert(coord.y == 0);

    // Test moving back over DWC_RIGHT
    grid = [self gridFromCompactLinesWithContinuationMarks:@"A-b!"];
    coord = [grid coordinateBefore:VT100GridCoordMake(2, 0)];
    assert(coord.x == 0);
    assert(coord.y == 0);

    // Test wrap + skip over dwc
    grid = [self gridFromCompactLinesWithContinuationMarks:@"aB-+\ncde!"];
    coord = [grid coordinateBefore:VT100GridCoordMake(0, 1)];
    assert(coord.x == 1);
    assert(coord.y == 0);
}

- (void)testAddCombiningCharToCoord {
    const unichar kCombiningAcuteAccent = 0x301;
    const unichar kCombiningCedilla = 0x327;
    const unichar kCombiningEnclosingCircle = 0x20dd;
    
    VT100Grid *grid = [self gridFromCompactLines:@"abcd"];
    assert([grid addCombiningChar:kCombiningEnclosingCircle
                          toCoord:VT100GridCoordMake(0, 0)]);
    screen_char_t *line = [grid screenCharsAtLineNumber:0];
    assert(line[0].complexChar);
    NSString *str = ScreenCharToStr(&line[0]);
    assert([[str decomposedStringWithCanonicalMapping] isEqualToString:[@"a⃝" decomposedStringWithCanonicalMapping]]);

    // Fail to modify null character
    grid = [self gridFromCompactLines:@".bcd"];
    assert(![grid addCombiningChar:kCombiningAcuteAccent
                           toCoord:VT100GridCoordMake(0, 0)]);

    // Add two combining marks
    grid = [self gridFromCompactLines:@"abcd"];
    assert([grid addCombiningChar:kCombiningAcuteAccent
                          toCoord:VT100GridCoordMake(0, 0)]);
    assert([grid addCombiningChar:kCombiningCedilla
                          toCoord:VT100GridCoordMake(0, 0)]);
    line = [grid screenCharsAtLineNumber:0];
    assert(line[0].complexChar);
    str = ScreenCharToStr(&line[0]);
    assert([[str decomposedStringWithCanonicalMapping] isEqualToString:[@"á̧" decomposedStringWithCanonicalMapping]]);
}

- (void)testDeleteChars {
    // Base case
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:
                       @"abcd!\n"
                       @"efg.!"];
    [grid deleteChars:1 startingAt:VT100GridCoordMake(1, 0)];
    assert([[grid compactLineDump] isEqualToString:
            @"acd.\n"
            @"efg."]);

    // Delete more chars than exist in line
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!"];
    [grid deleteChars:100 startingAt:VT100GridCoordMake(1, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a...!\n"
            @"efg.!"]);

    // Delete 0 chars
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!"];
    [grid deleteChars:0 startingAt:VT100GridCoordMake(1, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!"]);

    // Orphan dwc - deleting left half
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"aB-d!\n"
            @"efg.!"];
    [grid deleteChars:1 startingAt:VT100GridCoordMake(1, 0)];
    assert([[grid compactLineDump] isEqualToString:
            @"a.d.\n"
            @"efg."]);

    // Orphan dwc - deleting right half
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"aB-d!\n"
            @"efg.!"];
    [grid deleteChars:1 startingAt:VT100GridCoordMake(2, 0)];
    assert([[grid compactLineDump] isEqualToString:
            @"a.d.\n"
            @"efg."]);

    // Break DWC_SKIP
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abc>>\n"
            @"D-ef!"];
    [grid deleteChars:1 startingAt:VT100GridCoordMake(0, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"bc..!\n"
            @"D-ef!"]);

    // Scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcde+\n"
            @"fghi.!"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 3);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(2, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abd.e+\n"
            @"fghi.!"]);

    // Scroll region, deleting bignum
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcde+\n"
            @"fghi.!"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 3);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:100 startingAt:VT100GridCoordMake(2, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab..e+\n"
            @"fghi.!"]);

    // Scroll region, creating orphan dwc by deleting right half
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"aB-cd+\n"
            @"fghi.!"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 3);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(2, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a.c.d+\n"
            @"fghi.!"]);

    // Scroll region right boundary overlaps half a DWC, orphaning its right half
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abC-e+"];
    grid.scrollRegionCols = VT100GridRangeMake(0, 3);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(0, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"b...e+"]);

    // Scroll region right boundary overlaps half a DWC, orphaning its left half
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abC-efg+"];
    grid.scrollRegionCols = VT100GridRangeMake(3, 2);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(3, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab.e.fg+"]);

    // DWC skip survives with a scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abc>>\n"
            @"D-ef!"];
    grid.scrollRegionCols = VT100GridRangeMake(0, 3);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(0, 0)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"bc.>>\n"
            @"D-ef!"]);

    // Delete outside scroll region (should be a noop)
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abc!\n"
            @"def!"];
    grid.scrollRegionCols = VT100GridRangeMake(0, 1);
    grid.useScrollRegionCols = YES;
    [grid deleteChars:1 startingAt:VT100GridCoordMake(10, 10)];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abc!\n"
            @"def!"]);
}

- (void)testInsertChar {
    // Base case
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:
                       @"abcd+\n"
                       @"efg.!"];
    screen_char_t c = [grid defaultChar];
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a.bc+\n"
            @"efg.!"]);

    // Insert more chars than there is room for
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!"];
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:100];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a...!\n"
            @"efg.!"]);

    // Verify that continuation marks are preserved if inserted char is not null.
    c.code = 'x';
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!"];
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:100];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"axxx+\n"
            @"efg.!"]);
    c.code = 0;

    // Insert 0 chars
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd+\n"
            @"efg.!"];
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:0];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!"]);

    // Insert into middle of dwc, creating two orphans
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"aB-de+\n"
            @"fghi.!"];
    c.code = 'x';
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a.x.d+\n"
            @"fghi.!"]);
    c.code = 0;

    // Shift right one, removing DWC_SKIP, changing EOL_DWC into EOL_SOFT
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd>>\n"
            @"E-fgh!"];
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab.cd+\n"
            @"E-fgh!"]);

    // Break DWC_SKIP/EOL_DWC
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcd>>\n"
            @"E-fgh!"];
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab..c+\n"
            @"E-fgh!"]);

    // Break DWC_SKIP/EOL_DWC, leave null and hard-wrap
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abC->>\n"
            @"E-fgh!"];
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:2];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab...!\n"
            @"E-fgh!"]);

    // Scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcdef+"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 4);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab.cdf+"]);

    // Insert more than fits in scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcdef+"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 4);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(2, 0) times:100];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"ab...f+"]);

    // Make orphan by inserting into scroll region that overlaps left half of dwc
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abcD-f+"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 3);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"a.bc.f+"]);

    // Make orphan by inserting into scroll region that overlaps right half of dec
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"A-cdef+"];
    grid.scrollRegionCols = VT100GridRangeMake(1, 3);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(1, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"...cef+"]);

    // DWC skip survives with scroll region
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abC->>\n"
            @"E-fgh!"];
    grid.scrollRegionCols = VT100GridRangeMake(0, 2);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(0, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @".aC->>\n"
            @"E-fgh!"]);

    // Insert outside scroll region (noop)
    grid = [self gridFromCompactLinesWithContinuationMarks:
            @"abC->>\n"
            @"E-fgh!"];
    grid.scrollRegionCols = VT100GridRangeMake(0, 2);
    grid.useScrollRegionCols = YES;
    [grid insertChar:c at:VT100GridCoordMake(3, 0) times:1];
    assert([[grid compactLineDumpWithContinuationMarks] isEqualToString:
            @"abC->>\n"
            @"E-fgh!"]);
}

#pragma mark - Regression tests

- (void)moveCursorRightToMargin {
    VT100Grid *grid = [self gridFromCompactLinesWithContinuationMarks:
                       @"abcd+\n"
                       @"efg.!"];
    [grid setCursorX:1];
    [grid moveCursorRight:99];
    assert(grid.cursorX == grid.size.width - 1);
}

@end

