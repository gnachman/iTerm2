//
//  VT100ScreenTest.m
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import "iTermTests.h"
#import "SearchResult.h"
#import "VT100ScreenTest.h"
#import "VT100Screen.h"
#import "DVR.h"
#import "DVRDecoder.h"
#import "TmuxStateParser.h"

@interface VT100Screen (Testing)
// It's only safe to use this on a newly created screen.
- (void)setLineBuffer:(LineBuffer *)lineBuffer;
@end

@implementation VT100Screen (Testing)
- (void)setLineBuffer:(LineBuffer *)lineBuffer {
    [linebuffer_ release];
    linebuffer_ = [lineBuffer retain];
}
@end

@implementation VT100ScreenTest {
    VT100Terminal *terminal_;
    int startX_, endX_, startY_, endY_;
    int needsRedraw_;
    int sizeDidChange_;
    BOOL cursorVisible_;
    int triggers_;
    BOOL highlightsCleared_;
    BOOL ambiguousIsDoubleWidth_;
}

- (void)setup {
    terminal_ = [[[VT100Terminal alloc] init] autorelease];
    startX_ = endX_ = startY_ = endY_ = -1;
    needsRedraw_ = 0;
    sizeDidChange_ = 0;
    cursorVisible_ = YES;
    triggers_ = 0;
    highlightsCleared_ = NO;
    ambiguousIsDoubleWidth_ = NO;
}

- (VT100Screen *)screen {
    return [[[VT100Screen alloc] initWithTerminal:terminal_] autorelease];
}

- (void)testInit {
    VT100Screen *screen = [self screen];

    // Make sure the screen is initialized to a positive size with the cursor at the origin
    assert([screen width] > 0);
    assert([screen height] > 0);
    assert(screen.maxScrollbackLines > 0);
    assert([screen cursorX] == 1);
    assert([screen cursorY] == 1);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Append some stuff to it to make sure we can retreive it.
    for (int i = 0; i < [screen height] - 1; i++) {
        [screen terminalAppendString:[NSString stringWithFormat:@"Line %d", i] isAscii:YES];
        [screen terminalLineFeed];
        [screen terminalCarriageReturn];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);
    assert([screen numberOfLines] == [screen height]);

    // Make sure it has a functioning line buffer.
    [screen terminalLineFeed];
    assert([screen numberOfLines] == [screen height] + 1);
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);

    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);

    // Make sure the DVR is there and works.
    [screen saveToDvr];
    DVRDecoder *decoder = [screen.dvr getDecoder];
    [decoder seek:0];
    screen_char_t *frame = (screen_char_t *)[decoder decodedFrame];

    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);
    [self assertInitialTabStopsAreSetInScreen:screen];
}

- (void)assertInitialTabStopsAreSetInScreen:(VT100Screen *)screen {
    // Make sure tab stops are set up properly.
    [screen terminalCarriageReturn];
    int expected = 9;
    while (expected < [screen width]) {
        [screen terminalAppendTabAtCursor];
        assert([screen cursorX] == expected);
        assert([screen cursorY] == [screen height]);
        expected += 8;
    }
}

- (void)testDestructivelySetScreenWidthHeight {
    VT100Screen *screen = [self screen];
    [screen terminalShowTestPattern];
    // Make sure it's full.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == [screen width]);
    }

    int w = [screen width] + 1;
    int h = [screen height] + 1;
    [screen destructivelySetScreenWidth:w height:h];
    assert([screen width] == w);
    assert([screen height] == h);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Make sure it is as large as it claims to be
    [screen terminalMoveCursorToX:1 y:1];
    char letters[] = "123456";
    int n = 6;
    NSMutableString *expected = [NSMutableString string];
    for (int i = 0; i < w; i++) {
        NSString *toAppend = [NSString stringWithFormat:@"%c", letters[i % n]];
        [expected appendString:toAppend];
        [screen appendStringAtCursor:toAppend ascii:YES];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:expected]);
}

- (VT100Screen *)screenWithWidth:(int)width height:(int)height {
    VT100Screen *screen = [self screen];
    [screen destructivelySetScreenWidth:width height:height];
    return screen;
}

- (void)appendLines:(NSArray *)lines toScreen:(VT100Screen *)screen {
    for (NSString *line in lines) {
        [screen appendStringAtCursor:line ascii:YES];
        [screen terminalCarriageReturn];
        [screen terminalLineFeed];
    }
}
// abcde+
// fgh..!
// ijkl.!
// .....!
// Cursor at first col of last row.
- (VT100Screen *)fiveByFourScreenWithThreeLinesOneWrapped {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    return screen;
}

// abcdefgh
//
// ijkl.!
// mnopq+
// rst..!
// .....!
// Cursor at first col of last row

- (VT100Screen *)fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @"mnopq\n"
            @"rst..\n"
            @"....."]);
    return screen;
}

- (void)showAltAndUppercase:(VT100Screen *)screen {
    [screen terminalShowAltBuffer];
    for (int y = 0; y < screen.height; y++) {
        screen_char_t *line = [screen getLineAtScreenIndex:y];
        for (int x = 0; x < screen.width; x++) {
            unichar c = line[x].code;
            if (isalpha(c)) {
                c -= 'a' - 'A';
            }
            line[x].code = c;
        }
    }
}

- (BOOL)screenHasView {
    return YES;
}

- (int)screenSelectionStartX {
    return startX_;
}

- (int)screenSelectionEndX {
    return endX_;
}

- (int)screenSelectionStartY {
    return startY_;
}

- (int)screenSelectionEndY {
    return endY_;
}

- (void)screenSetSelectionFromX:(int)startX
                          fromY:(int)startY
                            toX:(int)endX
                            toY:(int)endY {
    startX_ = startX;
    startY_ = startY;
    endX_ = endX;
    endY_ = endY;
}

- (void)screenRemoveSelection {
    startX_ = startY_ = endX_ = endY_ = -1;
}

- (void)screenNeedsRedraw {
    needsRedraw_++;
}

- (void)screenSizeDidChange {
    sizeDidChange_++;
}

- (BOOL)screenShouldAppendToScrollbackWithStatusBar {
    return YES;
}

- (void)screenTriggerableChangeDidOccur {
    ++triggers_;
}

- (void)screenSetCursorVisible:(BOOL)visible {
    cursorVisible_ = visible;
}

- (NSString *)selectedStringInScreen:(VT100Screen *)screen {
    if (startX_ < 0 ||
        startY_ < 0 ||
        endX_ < 0 ||
        endY_ < 0) {
        return nil;
    }
    NSMutableString *s = [NSMutableString string];
    int sx = startX_;
    for (int y = startY_; y <= endY_; y++) {
        screen_char_t *line = [screen getLineAtIndex:y];
        int x;
        int ex = y == endY_ ? endX_ : [screen width];
        for (x = sx; x < ex; x++) {
            if (line[x].code) {
                [s appendString:ScreenCharArrayToStringDebug(line + x, 1)];
            }
        }
        if ((y == endY_ &&
             endX_ == [screen width] &&
             line[x - 1].code == 0 &&
             line[x].code == EOL_HARD) ||  // Last line of selection gets a newline iff there's a null char at the end
            (y < endY_ && x == [screen width] && line[x].code == EOL_HARD)) {  // No null required for other lines
            [s appendString:@"\n"];
        }
        sx = 0;
    }
    return s;
}

- (void)screenClearHighlights {
    highlightsCleared_ = YES;
}

- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth {
    return ambiguousIsDoubleWidth_;
}

- (void)testResizeWidthHeight {
    VT100Screen *screen;

    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, pulling lines out of line buffer
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"gh....\n"
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 5);

    // Starting in primary, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);

    // Same tests as above, but in alt screen. -----------------------------------------------------
    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEFGH.\n"
            @"IJKL.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    // Starting in alt - grows, but we don't pull anything out of the line buffer.
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"IJKL..\n"
            @"MNOPQR\n"
            @"ST....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:1],
                                     [screen width]);
    assert([s isEqualToString:@"def"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:2],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:3],
                                     [screen width]);
    assert([s isEqualToString:@"ijk"]);

    // Starting in primary with selection, it shrinks, but selection stays on screen
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "jk"
    startX_ = 1;
    startY_ = 2;
    endX_ = 3;
    endY_ = 2;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jk"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top completely
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "abcd"
    startX_ = 0;
    startY_ = 0;
    endX_ = 4;
    endY_ = 0;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcd"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top partially
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen shrinks but selection stays on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top partially
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"IJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top completely
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "abc"
    startX_ = 0;
    startY_ = 0;
    endX_ = 3;
    endY_ = 0;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([self selectedStringInScreen:screen] == nil);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEF\n"
            @"GH....\n"
            @"IJKL..\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQ\n"
            @"RST..\n"
            @"UVWXY\n"
            @"Z....\n"
            @"....."]);
    // select everything
    // TODO There's a bug when the selection is at the very end (5,6). It is deselected.
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 6;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQR\n"
            @"ST....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid. Selection goes to very end of screen
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    // select everything
    startX_ = 0;
    startY_ = 0;
    endX_ = 5;
    endY_ = 6;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ\n"]);
    [screen resizeWidth:6 height:6];
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ\n"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // If lines get pushed into line buffer, excess are dropped
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:1];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);

    // Scroll regions are reset
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [self showAltAndUppercase:screen];
    [screen terminalSetScrollRegionTop:0 bottom:1];
    [screen terminalSetLeftMargin:0 rightMargin:1];
    [screen resizeWidth:3 height:3];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 3, 3)));

    // Selection ending at line with trailing nulls
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "efgh.."
    startX_ = 4;
    startY_ = 0;
    endX_ = 5;
    endY_ = 1;
    [screen resizeWidth:3 height:3];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"efgh\n"]);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Selection starting at beginning of line of all nulls
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalLineFeed];
     [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    // .....
    // abcde
    // fgh..
    // ijkl.
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"]);
    [screen resizeWidth:13 height:4];
    // TODO
    // This is kind of questionable. We strip nulls in -convertCurrentSelectionToWidth..., while it
    // would be better to preserve the selection.
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection has to move back because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijklm\n"
            @"nopqr\n" // top line of screen
            @"st...\n"
            @"uvwxy\n"
            @"z....\n"
            @"....."]);
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nij"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"NOPQRS\n"
            @"T.....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"gh....\n"
            @"ijklmn\n"
            @"opqrst\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // onscreen. The screen grows, moving lines from history into the primary screen. The start of the
    // selection has to move forward because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 1;
    startY_ = 2;
    endX_ = 2;
    endY_ = 3;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jklmNO"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"NO"]);

    // In alt screen with selection that begins and ends onscreen. The screen is grown and some history
    // is deleted.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 4;
    endX_ = 2;
    endY_ = 4;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // there too. The screen grows, moving lines from history into the primary screen. The
    // selection is lost because none of its characters still exist.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 2;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ij"]);
    [screen resizeWidth:6 height:6];
    assert([self selectedStringInScreen:screen] == nil);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection is exactly at the last character before those that are lost.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 1;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // End is one before previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 5;
    endY_ = 0;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);

    // End is two after previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 2;
    endY_ = 1;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefg"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
}

- (VT100Screen *)screenFromCompactLines:(NSString *)compactLines {
    NSArray *lines = [compactLines componentsSeparatedByString:@"\n"];
    VT100Screen *screen = [self screenWithWidth:[[lines objectAtIndex:0] length]
                                         height:[lines count]];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [screen getLineAtScreenIndex:i++];
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
    return screen;
}

- (VT100Screen *)screenFromCompactLinesWithContinuationMarks:(NSString *)compactLines {
    NSArray *lines = [compactLines componentsSeparatedByString:@"\n"];
    VT100Screen *screen = [self screenWithWidth:[[lines objectAtIndex:0] length] - 1
                                         height:[lines count]];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [screen getLineAtScreenIndex:i++];
        for (int j = 0; j < [line length] - 1; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            if (c == '-') c = DWC_RIGHT;
            if (j == [line length] - 1) {
                if (c == '>') {
                    c = DWC_SKIP;
                }
            }
            s[j].code = c;
        }
        int j = [line length] - 1;
        switch ([line characterAtIndex:j]) {
            case '!':
                s[j].code = EOL_HARD;
                break;
                
            case '+':
                s[j].code = EOL_SOFT;
                break;
                
            case '>':
                s[j].code = EOL_DWC;
                break;
                
            default:
                assert(false);  // bogus continution mark
        }
    }
    return screen;
}

- (void)testRunByTrimmingNullsFromRun {
    // Basic test
    VT100Screen *screen = [self screenFromCompactLines:
                           @"..1234\n"
                           @"56789a\n"
                           @"bc...."];
    VT100GridRun run = VT100GridRunMake(1, 0, 16);
    VT100GridRun trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 2);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 12);

    // Test wrapping nulls around
    screen = [self screenFromCompactLines:
              @"......\n"
              @".12345\n"
              @"67....\n"
              @"......\n"];
    run = VT100GridRunMake(0, 0, 24);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 1);
    assert(trimmed.length == 7);

    // Test all nulls
    screen = [self screenWithWidth:4 height:4];
    run = VT100GridRunMake(0, 0, 4);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.length == 0);

    // Test no nulls
    screen = [self screenFromCompactLines:
              @"1234\n"
              @"5678"];
    run = VT100GridRunMake(1, 0, 6);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 6);
}

- (void)testTerminalResetPreservingPrompt {
    // Test with arg=yes
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 5);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Test with arg=no
    screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:NO];
    assert([[screen compactLineDump] isEqualToString:
            @".....\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testAllCharacterSetPropertiesHaveDefaultValues {
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    // Switch to charset 1
    char shiftOut = 14;
    char shiftIn = 15;
    NSData *data = [NSData dataWithBytes:&shiftOut length:1];
    [terminal_ putStreamData:data];
    assert([terminal_ parseNextToken]);
    [terminal_ executeToken];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    [screen terminalResetPreservingPrompt:NO];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    data = [NSData dataWithBytes:&shiftIn length:1];
    [terminal_ putStreamData:data];
    assert([terminal_ parseNextToken]);
    [terminal_ executeToken];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testClearBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSaveCursorAndCharsetFlags];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @".....\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 4)));
    assert([[screen currentGrid] savedCursor].x == 0);
    assert([[screen currentGrid] savedCursor].y == 0);

    // Cursor on last nonempty line
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:3];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"wxyz.\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);


    // Cursor in middle of content
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"rstuv\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);
}

- (void)testClearScrollbackBuffer {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    startX_ = startY_ = 1;
    endX_ = endY_ = 1;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnopq\n"
            @"rstuv\n"
            @"wxyz.\n"
            @"....."]);
    [screen clearScrollbackBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"mnopq\n"
            @"rstuv\n"
            @"wxyz.\n"
            @"....."]);
    assert(highlightsCleared_);
    assert(startX_ == -1);
    assert(startY_ == -1);
    assert(endX_ == -1);
    assert(endY_ == -1);
    assert([screen isAllDirty]);
}

- (void)sendEscapeCodes:(NSString *)codes {
    NSString *esc = [NSString stringWithFormat:@"%c", 27];
    codes = [codes stringByReplacingOccurrencesOfString:@"^[" withString:esc];
    NSData *data = [codes dataUsingEncoding:NSUTF8StringEncoding];
    [terminal_ putStreamData:data];
    while ([terminal_ parseNextToken]) {
        [terminal_ executeToken];
    }
}

// Most of the work is done by VT100Grid's appendCharsAtCursor, which is heavily tested already.
// This only tests the extra work not included therein.
- (void)testAppendStringAtCursorAscii {
    // Make sure colors and attrs are set properly
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [terminal_ setForegroundColor:5 alternateSemantics:NO];
    [terminal_ setBackgroundColor:6 alternateSemantics:NO];
    [self sendEscapeCodes:@"^[[1m^[[3m^[[4m^[[5m"];  // Bold, italic, blink, underline
    [screen appendStringAtCursor:@"Hello world" ascii:YES];

    assert([[screen compactLineDump] isEqualToString:
            @"Hello\n"
            @" worl\n"
            @"d....\n"
            @"....."]);
    screen_char_t *line = [screen getLineAtScreenIndex:0];
    assert(line[0].foregroundColor == 5);
    assert(line[0].foregroundColorMode == ColorModeNormal);
    assert(line[0].bold);
    assert(line[0].italic);
    assert(line[0].blink);
    assert(line[0].underline);
    assert(line[0].backgroundColor == 6);
    assert(line[0].backgroundColorMode == ColorModeNormal);
}

- (void)testAppendStringAtCursorNonAscii {
    // Make sure colors and attrs are set properly
    VT100Screen *screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [terminal_ setForegroundColor:5 alternateSemantics:NO];
    [terminal_ setBackgroundColor:6 alternateSemantics:NO];
    [self sendEscapeCodes:@"^[[1m^[[3m^[[4m^[[5m"];  // Bold, italic, blink, underline

    unichar chars[] = {
        0x301, //  standalone
        'a',
        0x301, //  a+accent
        'a',
        0x301,
        0x327, //  a+accent+cedilla
        0xD800, //  surrogate pair giving 𐅐
        0xDD50,
        0xff25, //  dwc E
        0xf000, //  item private
        0xfeff, //  zw-spaces..
        0x200b,
        0x200c,
        0x200d,
        'g',
        0x142,  // ambiguous width
    };

    NSMutableString *s = [NSMutableString stringWithCharacters:chars
                                                        length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s ascii:NO];

    screen_char_t *line = [screen getLineAtScreenIndex:0];
    assert(line[0].foregroundColor == 5);
    assert(line[0].foregroundColorMode == ColorModeNormal);
    assert(line[0].bold);
    assert(line[0].italic);
    assert(line[0].blink);
    assert(line[0].underline);
    assert(line[0].backgroundColor == 6);
    assert(line[0].backgroundColorMode == ColorModeNormal);

    NSString *a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    NSString *e = [@"´" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 2) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = ScreenCharToStr(line + 3);
    e = @"𐅐";
    assert([a isEqualToString:e]);

    assert([ScreenCharToStr(line + 4) isEqualToString:@"Ｅ"]);
    assert(line[5].code == DWC_RIGHT);
    assert([ScreenCharToStr(line + 6) isEqualToString:@"?"]);
    assert([ScreenCharToStr(line + 7) isEqualToString:@"g"]);
    assert([ScreenCharToStr(line + 8) isEqualToString:@"ł"]);
    assert(line[9].code == 0);

    // Toggle ambiguousIsDoubleWidth_ and see if it works.
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    ambiguousIsDoubleWidth_ = YES;
    s = [NSMutableString stringWithCharacters:chars
                                       length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s ascii:NO];

    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"´" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);
    assert(line[2].code == DWC_RIGHT);

    a = [ScreenCharToStr(line + 3) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);
    assert(line[4].code == DWC_RIGHT);
    
    a = ScreenCharToStr(line + 5);
    e = @"𐅐";
    assert([a isEqualToString:e]);

    assert([ScreenCharToStr(line + 6) isEqualToString:@"Ｅ"]);
    assert(line[7].code == DWC_RIGHT);
    assert([ScreenCharToStr(line + 8) isEqualToString:@"?"]);
    assert([ScreenCharToStr(line + 9) isEqualToString:@"g"]);
    assert([ScreenCharToStr(line + 10) isEqualToString:@"ł"]);
    assert(line[11].code == DWC_RIGHT);
    assert(line[12].code == 0);

    // Test modifying character already at cursor with combining mark
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"e" ascii:NO];
    unichar combiningAcuteAccent = 0x301;
    s = [NSMutableString stringWithCharacters:&combiningAcuteAccent length:1];
    [screen appendStringAtCursor:s ascii:NO];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"é" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    unichar highSurrogate = 0xD800;
    unichar lowSurrogate = 0xDD50;
    s = [NSMutableString stringWithCharacters:&highSurrogate length:1];
    [screen appendStringAtCursor:s ascii:NO];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s ascii:NO];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"𐅐";
    assert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate, but it's not a high surrogate.
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"g" ascii:NO];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s ascii:NO];
    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"g";
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = @"�";
    assert([a isEqualToString:e]);
}

- (void)testLinefeed {
    // The guts of linefeed is tested in VT100GridTest.
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnop.\n"
            @"....."]);
    [screen terminalSetScrollRegionTop:1 bottom:3];
    [screen terminalSetLeftMargin:1 rightMargin:3];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalMoveCursorToX:4 y:4];
    [screen linefeed];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fjkl.\n"
            @"inop.\n"
            @"m....\n"
            @"....."]);
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 0);
    assert([screen cursorX] == 4);

    // Now test scrollback
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnop.\n"
            @"....."]);
    [screen terminalMoveCursorToX:4 y:5];
    [screen linefeed];
    [screen linefeed];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @"mnop.\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert([screen scrollbackOverflow] == 1);
    assert([screen totalScrollbackOverflow] == 1);
    assert([screen cursorX] == 4);
    [screen resetScrollbackOverflow];
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 1);
}

- (NSData *)screenCharLineForString:(NSString *)s {
    NSMutableData *data = [NSMutableData dataWithLength:s.length * sizeof(screen_char_t)];
    int len;
    StringToScreenChars(s,
                        (screen_char_t *)[data mutableBytes],
                        [terminal_ foregroundColorCode],
                        [terminal_ backgroundColorCode],
                        &len,
                        NO,
                        NULL);
    return data;
}

- (void)testSetHistory {
    NSArray *lines = @[[self screenCharLineForString:@"abcdefghijkl"],
                       [self screenCharLineForString:@"mnop"],
                       [self screenCharLineForString:@"qrstuvwxyz"],
                       [self screenCharLineForString:@"0123456  "],
                       [self screenCharLineForString:@"ABC   "],
                       [self screenCharLineForString:@"DEFGHIJKL   "],
                       [self screenCharLineForString:@"MNOP  "]];
    VT100Screen *screen = [self screenWithWidth:6 height:4];
    [screen setHistory:lines];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcdef\n"
            @"ghijkl\n"
            @"mnop..\n"
            @"qrstuv\n"
            @"wxyz..\n"
            @"012345\n"
            @"6.....\n"
            @"ABC...!\n"
            @"DEFGHI+\n"
            @"JKL...!\n"
            @"MNOP..!"]);
}

- (void)testSetAltScreen {
    NSArray *lines = @[[self screenCharLineForString:@"abcdefghijkl"],
                       [self screenCharLineForString:@"mnop"],
                       [self screenCharLineForString:@"qrstuvwxyz"],
                       [self screenCharLineForString:@"0123456  "],
                       [self screenCharLineForString:@"ABC   "],
                       [self screenCharLineForString:@"DEFGHIJKL   "],
                       [self screenCharLineForString:@"MNOP  "]];
    VT100Screen *screen = [self screenWithWidth:6 height:4];
    [screen terminalShowAltBuffer];
    [screen setAltScreen:lines];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcdef+\n"
            @"ghijkl!\n"
            @"mnop..!\n"
            @"qrstuv+"]);
}

- (void)testSetTmuxState {
    NSDictionary *stateDict =
      @{
        kStateDictSavedCX: @(2),
        kStateDictSavedCY: @(3),
        kStateDictCursorX: @(4),
        kStateDictCursorY: @(5),
        kStateDictScrollRegionUpper: @(6),
        kStateDictScrollRegionLower: @(7),
        kStateDictCursorMode: @(NO),
        kStateDictTabstops: @[@(4), @(8)]
       };
    VT100Screen *screen = [self screenWithWidth:10 height:10];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    cursorVisible_ = YES;
    [screen setTmuxState:stateDict];
    
    assert(screen.cursorX == 5);
    assert(screen.cursorY == 6);
    [screen terminalRestoreCursorAndCharsetFlags];
    assert(screen.cursorX == 3);
    assert(screen.cursorY == 4);
    assert([[screen currentGrid] topMargin] == 6);
    assert([[screen currentGrid] bottomMargin] == 7);
    assert(!cursorVisible_);
    [screen terminalCarriageReturn];
    [screen terminalAppendTabAtCursor];
    assert(screen.cursorX == 5);
    [screen terminalAppendTabAtCursor];
    assert(screen.cursorX == 9);
}

- (void)assertScreen:(VT100Screen *)screen
   matchesHighlights:(NSArray *)expectedHighlights
         highlightFg:(int)hfg
     highlightFgMode:(ColorMode)hfm
         highlightBg:(int)hbg
     highlightBgMode:(ColorMode)hbm {
    int defaultFg = [terminal_ foregroundColorCode].foregroundColor;
    int defaultBg = [terminal_ foregroundColorCode].backgroundColor;
    for (int i = 0; i < screen.height; i++) {
        screen_char_t *line = [screen getLineAtScreenIndex:i];
        NSString *expected = expectedHighlights[i];
        for (int j = 0; j < screen.width; j++) {
            if ([expected characterAtIndex:j] == 'h') {
                assert(line[j].foregroundColor == hfg &&
                       line[j].foregroundColorMode ==  hfm&&
                       line[j].backgroundColor == hbg &&
                       line[j].backgroundColorMode == hbm);
            } else {
                assert(line[j].foregroundColor == defaultFg &&
                       line[j].foregroundColorMode == ColorModeAlternate &&
                       line[j].backgroundColor == defaultBg &&
                       line[j].backgroundColorMode == ColorModeAlternate);
            }
        }
    }
    
}

- (void)testHighlightTextMatchingRegex {
    NSArray *lines = @[@"rerex", @"xrere", @"xxrerexxxx", @"xxrererere"];
    VT100Screen *screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightForegroundColor: [NSColor blueColor],
                                                       kHighlightBackgroundColor: [NSColor redColor] }];
    NSArray *expectedHighlights =
        @[ @"hhhh.",
           @".hhhh",
           @"..hhh",
           @"h....",
           @"..hhh",
           @"hhhhh",
           @"....." ];
    int blue = 16 + 5;
    int red = 16 + 5 * 36;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:blue
      highlightFgMode:ColorModeNormal
           highlightBg:red
       highlightBgMode:ColorModeNormal];
    
    // Leave fg unaffected
    screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightBackgroundColor: [NSColor redColor] }];
    int defaultFg = [terminal_ foregroundColorCode].foregroundColor;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:defaultFg
      highlightFgMode:ColorModeAlternate
           highlightBg:red
       highlightBgMode:ColorModeNormal];
    
    // Leave bg unaffected
    screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightForegroundColor: [NSColor blueColor] }];
    int defaultBg = [terminal_ foregroundColorCode].backgroundColor;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:blue
      highlightFgMode:ColorModeNormal
           highlightBg:defaultBg
       highlightBgMode:ColorModeAlternate];
}

- (void)testSetFromFrame {
    VT100Screen *source = [self fiveByFourScreenWithThreeLinesOneWrapped];
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < source.height; i++) {
        screen_char_t *line = [source getLineAtScreenIndex:i];
        [data appendBytes:line length:(sizeof(screen_char_t) * (source.width + 1))];
    }
    
    DVRFrameInfo info = {
        .width = 5,
        .height = 4,
        .cursorX = 1,  // zero based
        .cursorY = 2,
        .timestamp = 0,
        .frameType = DVRFrameTypeKeyFrame
    };
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    [screen setFromFrame:(screen_char_t *) data.mutableBytes
                     len:data.length
                    info:info];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcde+\n"
            @"fgh..!\n"
            @"ijkl.!\n"
            @".....!"]);
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 3);

    // Try a screen smaller than the frame
    screen = [self screenWithWidth:2 height:2];
    [screen setFromFrame:(screen_char_t *) data.mutableBytes
                     len:data.length
                    info:info];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"ij!\n"
            @"..!"]);
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 1);
}

// Perform a search, append some stuff, and continue searching from the end of scrollback history
// prior to the appending, finding a match in the stuff that was appended.
- (void)testStoreLastPositionInLineBufferAsFindContextSavedPositionAndRestoreSavedPositionToFindContext {
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz", @"012"] toScreen:screen];
    /* abcde
       fgh..
       ijkl.
       mnopq
       rstuv
       wxyz.
       012..
       .....
     */
    FindContext *ctx = [[[FindContext alloc] init] autorelease];
    ctx.maxTime = 0;
    [screen setFindString:@"wxyz"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:ctx
          multipleResults:YES];
    NSMutableArray *results = [NSMutableArray array];
    assert([screen continueFindAllResults:results
                                inContext:ctx]);
    assert(results.count == 1);
    SearchResult *range = results[0];
    assert(range->startX == 0);
    assert(range->absStartY == 5);
    assert(range->endX == 3);
    assert(range->absEndY == 5);
    
    // Make sure there's nothing else to find
    [results removeAllObjects];
    assert(![screen continueFindAllResults:results
                                 inContext:ctx]);
    assert(results.count == 0);
    
    [screen storeLastPositionInLineBufferAsFindContextSavedPosition];

    // Now add some stuff to the bottom and search again from where we previously stopped.
    [self appendLines:@[@"0123", @"wxyz"] toScreen:screen];
    [screen setFindString:@"wxyz"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:7  // Past bottom of screen
               withOffset:0
                inContext:ctx
          multipleResults:YES];
    [screen restoreSavedPositionToFindContext:ctx];
    results = [NSMutableArray array];
    assert([screen continueFindAllResults:results
                                inContext:ctx]);
    assert(results.count == 1);
    range = results[0];
    assert(range->startX == 0);
    assert(range->absStartY == 8);
    assert(range->endX == 3);
    assert(range->absEndY == 8);

    // Make sure there's nothing else to find
    [results removeAllObjects];
    assert(![screen continueFindAllResults:results
                                 inContext:ctx]);
    assert(results.count == 0);
}

#pragma mark - Tests for PTYTextViewDataSource methods

- (void)testNumberOfLines {
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    assert([screen numberOfLines] == 2);
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz", @"012"] toScreen:screen];
    /*
     abcde
     fgh..
     ijkl.
     mnopq
     rstuv
     wxyz.
     012..
     .....
     */
    assert([screen numberOfLines] == 8);
}

- (void)testCursorXY {
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    assert([screen cursorX] == 1);
    assert([screen cursorY] == 1);
    [screen terminalMoveCursorToX:2 y:3];
    assert([screen cursorX] == 2);
    assert([screen cursorY] == 3);
}

- (void)testGetLineAtIndex {
    VT100Screen *screen = [self screenFromCompactLines:
                           @"abcde>\n"
                           @"F-ghi.\n"];
    [screen terminalMoveCursorToX:6 y:2];
    screen_char_t *line = [screen getLineAtIndex:0];
    assert(line[0].code == 'a');
    assert(line[5].code == DWC_SKIP);
    assert(line[6].code == EOL_DWC);

    // Scroll the DWC_SPLIT off the screen. getLineAtIndex: will restore it, even though line buffers
    // don't store those.
    [self appendLines:@[@"jkl"] toScreen:screen];
    line = [screen getLineAtIndex:0];
    assert(line[0].code == 'a');
    assert(line[5].code == DWC_SKIP);
    assert(line[6].code == EOL_DWC);
}

- (void)testNumberOfScrollbackLines {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:2];
    assert([screen numberOfScrollbackLines] == 0);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 1);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 2);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 2);
}

- (void)testScrollbackOverflow {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:0];
    assert([screen scrollbackOverflow] == 0);
    [screen terminalLineFeed];
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 2);
    assert([screen totalScrollbackOverflow] == 2);
    [screen resetScrollbackOverflow];
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 2);
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 1);
    assert([screen totalScrollbackOverflow] == 3);
}

- (void)testAbsoluteLineNumberOfCursor {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    assert([screen cursorY] == 4);
    assert([screen absoluteLineNumberOfCursor] == 3);
    [screen setMaxScrollbackLines:1];
    [screen terminalLineFeed];
    assert([screen absoluteLineNumberOfCursor] == 4);
    [screen terminalLineFeed];
    assert([screen absoluteLineNumberOfCursor] == 5);
    [screen resetScrollbackOverflow];
    assert([screen absoluteLineNumberOfCursor] == 5);
    [screen clearScrollbackBuffer];
    assert([screen absoluteLineNumberOfCursor] == 4);
}

- (void)assertSearchInScreen:(VT100Screen *)screen
                  forPattern:(NSString *)pattern
            forwardDirection:(BOOL)forward
                ignoringCase:(BOOL)ignoreCase
                       regex:(BOOL)regex
                 startingAtX:(int)startX
                 startingAtY:(int)startY
                  withOffset:(int)offset
              matchesResults:(NSArray *)expected
  callBlockBetweenIterations:(void (^)(VT100Screen *))block {
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resizeWidth:screen.width height:2];
    [[screen findContext] setMaxTime:0];
    [screen setFindString:pattern
         forwardDirection:forward
             ignoringCase:ignoreCase
                    regex:regex
              startingAtX:startX
              startingAtY:startY
               withOffset:offset
                inContext:[screen findContext]
          multipleResults:YES];
    NSMutableArray *results = [NSMutableArray array];
    while ([screen continueFindAllResults:results inContext:[screen findContext]]) {
        if (block) {
            block(screen);
        }
    }
    assert(results.count == expected.count);
    for (int i = 0; i < expected.count; i++) {
        assert([expected[i] isEqualToSearchResult:results[i]]);
    }
}

- (void)assertSearchInScreenLines:(NSString *)compactLines
                       forPattern:(NSString *)pattern
                 forwardDirection:(BOOL)forward
                     ignoringCase:(BOOL)ignoreCase
                            regex:(BOOL)regex
                      startingAtX:(int)startX
                      startingAtY:(int)startY
                       withOffset:(int)offset
                   matchesResults:(NSArray *)expected {
    VT100Screen *screen = [self screenFromCompactLinesWithContinuationMarks:compactLines];
    [self assertSearchInScreen:screen
                    forPattern:pattern
              forwardDirection:forward
                  ignoringCase:ignoreCase
                         regex:regex
                   startingAtX:startX
                   startingAtY:startY
                    withOffset:offset
                matchesResults:expected
    callBlockBetweenIterations:NULL];
}

- (void)testFind {
    NSString *lines =
        @"abcd+\n"
        @"efgc!\n"
        @"de..!\n"
        @"fgx>>\n"
        @"Y-z.!";
    NSArray *cdeResults = @[ [SearchResult searchResultFromX:2 y:0 toX:0 y:1] ];
    // Search forward, wraps around a line, beginning from first char onscreen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];
    
    // Search backward
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:2
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];

    // Search from last char on screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:2
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];

    // Search from null after last char on screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];
    // Search from middle of screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:2
                         withOffset:0
                     matchesResults:cdeResults];

    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:1
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[]];

    // Search ignoring case
    [self assertSearchInScreenLines:lines
                         forPattern:@"CDE"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[]];

    [self assertSearchInScreenLines:lines
                         forPattern:@"CDE"
                   forwardDirection:YES
                       ignoringCase:YES
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];

    // Search with regex
    [self assertSearchInScreenLines:lines
                         forPattern:@"c.e"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:YES
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];

    [self assertSearchInScreenLines:lines
                         forPattern:@"C.E"
                   forwardDirection:YES
                       ignoringCase:YES
                              regex:YES
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];
    
    // Search with offset=1
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:3 y:0 toX:0 y:1],
                                       [SearchResult searchResultFromX:0 y:2 toX:1 y:2] ]];

    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:0
                         withOffset:1
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:2 toX:1 y:2] ]];

    // Search with offset=-1
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:2
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:2 toX:1 y:2],
                                       [SearchResult searchResultFromX:3 y:0 toX:0 y:1] ]];
    
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:2
                         withOffset:1
                     matchesResults:@[ [SearchResult searchResultFromX:3 y:0 toX:0 y:1] ]];

    // Search matching DWC
    [self assertSearchInScreenLines:lines
                         forPattern:@"Yz"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:4 toX:2 y:4] ]];

    // Search matching text before DWC_SKIP and after it
    [self assertSearchInScreenLines:lines
                         forPattern:@"xYz"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:2 y:3 toX:2 y:4] ]];

    // Search that searches multiple blocks
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    LineBuffer *smallBlockLineBuffer = [[[LineBuffer alloc] initWithBlockSize:10] autorelease];
    [screen setLineBuffer:smallBlockLineBuffer];
    [self appendLines:@[ @"abcdefghij",       // Block 0
                         @"spam",             // Block 1
                         @"bacon",
                         @"eggs",             // Block 2
                         @"spam",
                         @"0123def456789",    // Block 3
                         @"hello def world"]  // Block 4
             toScreen:screen];
    /*
     abcde  0
     fghij  1
     spam   2
     bacon  3
     eggs   4
     spam   5
     0123d  6
     ef456  7
     789    8
     hello  9
      def   10
     world  11
            12
     */
    [self assertSearchInScreen:screen
                    forPattern:@"def"
              forwardDirection:NO
                  ignoringCase:NO
                         regex:NO
                   startingAtX:0
                   startingAtY:12
                    withOffset:0
                matchesResults:@[ [SearchResult searchResultFromX:1 y:10 toX:3 y:10],
                                  [SearchResult searchResultFromX:4 y:6 toX:1 y:7],
                                  [SearchResult searchResultFromX:3 y:0 toX:0 y:1]]
    callBlockBetweenIterations:NULL];
    // Search multiple blocks with a drop between calls to continueFindAllResults
    screen = [self screenWithWidth:5 height:2];
    smallBlockLineBuffer = [[[LineBuffer alloc] initWithBlockSize:10] autorelease];
    [screen setLineBuffer:smallBlockLineBuffer];
    [screen setMaxScrollbackLines:11];
    [self appendLines:@[ @"abcdefghij",       // Block 0
                         @"spam",             // Block 1
                         @"bacon",
                         @"eggs",             // Block 2
                         @"spam",
                         @"0123def456789",    // Block 3
                         @"hello def world"]  // Block 4
             toScreen:screen];
    [self assertSearchInScreen:screen
                    forPattern:@"spam"
              forwardDirection:NO
                  ignoringCase:NO
                         regex:NO
                   startingAtX:0
                   startingAtY:12
                    withOffset:0
                matchesResults:@[ [SearchResult searchResultFromX:0 y:5 toX:3 y:5] ]
    callBlockBetweenIterations:^(VT100Screen *screen) {
        NSLog(@"Searched this:\n%@", [screen compactLineDumpWithHistory]);
        [self appendLines:@[ @"FOO" ] toScreen:screen];
        NSLog(@"After appending a line of foo:\n%@", [screen compactLineDumpWithHistory]);
    }];
}

/*
 METHODS LEFT TO TEST:
 
 // Search from middle of screen, wrapping around, going backwards
 // Search from middle of screen, wrapping around, going forwards
// Runs for a limited amount of time. Wraps around. Returns one result at a time.
 - (BOOL)continueFindResultAtStartX:(int*)startX
 atStartY:(int*)startY
 atEndX:(int*)endX
 atEndY:(int*)endY
 found:(BOOL*)found
 inContext:(FindContext*)context;
 - (void)saveFindContextAbsPos;

 // Save the position of the current find context (with the screen appended).
 - (PTYTask *)shell;
 
 // Return a human-readable dump of the screen contents.
 - (NSString*)debugString;
 - (BOOL)isAllDirty;
 - (void)resetAllDirty;
 
 // Set the cursor dirty. Cursor coords are different because of how they handle
 // being in the WIDTH'th column (it wraps to the start of the next line)
 // whereas that wouldn't normally be a legal X value.
 - (void)setCharDirtyAtCursorX:(int)x Y:(int)y;
 
 // Check if any the character at x,y has been marked dirty.
 - (BOOL)isDirtyAtX:(int)x Y:(int)y;
 - (void)resetDirty;
 
 // Save the current state to a new frame in the dvr.
 - (void)saveToDvr;
 
 // If this returns true then the textview will broadcast iTermTabContentsChanged
 // when a dirty char is found.
 - (BOOL)shouldSendContentsChangedNotification;

*/
@end
