//
//  VT100ScreenTest.m
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import <XCTest/XCTest.h>
#import "DVR.h"
#import "DVRDecoder.h"
#import "LineBuffer.h"
#import "PTYNoteViewController.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100Screen.h"
#import "iTermSelection.h"

// This macro can be used in tests to document a known bug. The first expression would evaluate to
// true if the bug were fixed. Until then, the second expression unfortunately does evaluate to true.
#define ITERM_TEST_KNOWN_BUG(expressionThatShouldBeTrue, expressionThatIsTrue) \
do { \
XCTAssert(!(expressionThatShouldBeTrue)); \
XCTAssert((expressionThatIsTrue)); \
NSLog(@"Known bug: %s should be true, but %s is.", #expressionThatShouldBeTrue, #expressionThatIsTrue); \
} while(0)

@interface VT100ScreenTest : XCTestCase <iTermSelectionDelegate, VT100ScreenDelegate>
@end

@interface VT100Screen (UnitTest)
// It's only safe to use this on a newly created screen.
- (void)setLineBuffer:(LineBuffer *)lineBuffer;
@end

@implementation VT100Screen (UnitTest)
- (void)setLineBuffer:(LineBuffer *)lineBuffer {
    [linebuffer_ release];
    linebuffer_ = [lineBuffer retain];
}
@end

@implementation VT100ScreenTest {
    VT100Terminal *terminal_;
    iTermSelection *selection_;
    int needsRedraw_;
    int sizeDidChange_;
    BOOL cursorVisible_;
    int triggers_;
    BOOL highlightsCleared_;
    BOOL ambiguousIsDoubleWidth_;
    int updates_;
    BOOL shouldSendContentsChangedNotification_;
    BOOL printingAllowed_;
    NSMutableString *printed_;
    NSMutableString *triggerLine_;
    BOOL canResize_;
    BOOL isFullscreen_;
    VT100GridSize newSize_;
    BOOL syncTitle_;
    NSString *windowTitle_;
    NSString *name_;
    NSMutableArray *dirlog_;
    NSSize newPixelSize_;
    NSString *pasteboard_;
    NSMutableData *pbData_;
    BOOL pasted_;
    NSMutableData *write_;
}

- (void)setUp {
    terminal_ = [[[VT100Terminal alloc] init] autorelease];
    selection_ = [[[iTermSelection alloc] init] autorelease];
    selection_.delegate = self;
    needsRedraw_ = 0;
    sizeDidChange_ = 0;
    cursorVisible_ = YES;
    triggers_ = 0;
    highlightsCleared_ = NO;
    ambiguousIsDoubleWidth_ = NO;
    updates_ = 0;
    shouldSendContentsChangedNotification_ = NO;
    printingAllowed_ = YES;
    triggerLine_ = [NSMutableString string];
    canResize_ = YES;
    isFullscreen_ = NO;
    newSize_ = VT100GridSizeMake(0, 0);
    syncTitle_ = YES;
    windowTitle_ = nil;
    name_ = nil;
    dirlog_ = [NSMutableArray array];
    newPixelSize_ = NSMakeSize(0, 0);
    pasteboard_ = nil;
    pbData_ = [NSMutableData data];
    pasted_ = NO;
    write_ = [NSMutableData data];
}

#pragma mark - Convenience methods

- (VT100Screen *)screen {
    VT100Screen *screen = [[[VT100Screen alloc] initWithTerminal:terminal_] autorelease];
    terminal_.delegate = screen;
    return screen;
}

- (void)testInit {
    VT100Screen *screen = [self screen];

    // Make sure the screen is initialized to a positive size with the cursor at the origin
    XCTAssert([screen width] > 0);
    XCTAssert([screen height] > 0);
    XCTAssert(screen.maxScrollbackLines > 0);
    XCTAssert([screen cursorX] == 1);
    XCTAssert([screen cursorY] == 1);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        XCTAssert([s length] == 0);
    }

    // Append some stuff to it to make sure we can retreive it.
    for (int i = 0; i < [screen height] - 1; i++) {
        [screen terminalAppendString:[NSString stringWithFormat:@"Line %d", i]];
        [screen terminalLineFeed];
        [screen terminalCarriageReturn];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"Line 0"]);
    XCTAssert([screen numberOfLines] == [screen height]);

    // Make sure it has a functioning line buffer.
    [screen terminalLineFeed];
    XCTAssert([screen numberOfLines] == [screen height] + 1);
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"Line 1"]);

    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"Line 0"]);

    XCTAssert(screen.dvr);
    [self assertInitialTabStopsAreSetInScreen:screen];
}

- (void)assertInitialTabStopsAreSetInScreen:(VT100Screen *)screen {
    // Make sure tab stops are set up properly.
    [screen terminalCarriageReturn];
    int expected = 9;
    while (expected < [screen width]) {
        [screen terminalAppendTabAtCursor];
        XCTAssert([screen cursorX] == expected);
        XCTAssert([screen cursorY] == [screen height]);
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
        XCTAssert([s length] == [screen width]);
    }

    int w = [screen width] + 1;
    int h = [screen height] + 1;
    [screen destructivelySetScreenWidth:w height:h];
    XCTAssert([screen width] == w);
    XCTAssert([screen height] == h);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        XCTAssert([s length] == 0);
    }

    // Make sure it is as large as it claims to be
    [screen terminalMoveCursorToX:1 y:1];
    char letters[] = "123456";
    int n = 6;
    NSMutableString *expected = [NSMutableString string];
    for (int i = 0; i < w; i++) {
        NSString *toAppend = [NSString stringWithFormat:@"%c", letters[i % n]];
        [expected appendString:toAppend];
        [screen appendStringAtCursor:toAppend];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:expected]);
}

- (VT100Screen *)screenWithWidth:(int)width height:(int)height {
    VT100Screen *screen = [self screen];
    [screen destructivelySetScreenWidth:width height:height];
    return screen;
}

- (void)appendLines:(NSArray *)lines toScreen:(VT100Screen *)screen {
    for (NSString *line in lines) {
        [screen appendStringAtCursor:line];
        [screen terminalCarriageReturn];
        [screen terminalLineFeed];
    }
}

- (void)appendLinesNoNewline:(NSArray *)lines toScreen:(VT100Screen *)screen {
    for (int i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        [screen appendStringAtCursor:line];
        if (i + 1 != lines.count) {
            [screen terminalCarriageReturn];
            [screen terminalLineFeed];
        }
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
    XCTAssert([[screen compactLineDump] isEqualToString:
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
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijkl.\n"
               @"mnopq\n"
               @"rst..\n"
               @"....."]);
    return screen;
}

- (void)showAltAndUppercase:(VT100Screen *)screen {
    VT100Grid *temp = [[[screen currentGrid] copy] autorelease];
    [screen terminalShowAltBuffer];
    for (int y = 0; y < screen.height; y++) {
        screen_char_t *lineIn = [temp screenCharsAtLineNumber:y];
        screen_char_t *lineOut = [screen getLineAtScreenIndex:y];
        for (int x = 0; x < screen.width; x++) {
            lineOut[x] = lineIn[x];
            unichar c = lineIn[x].code;
            if (isalpha(c)) {
                c -= 'a' - 'A';
            }
            lineOut[x].code = c;
        }
        lineOut[screen.width] = lineIn[screen.width];
    }
}

- (void)setSelectionRange:(VT100GridCoordRange)range {
    [selection_ clearSelection];
    VT100GridWindowedRange theRange =
    VT100GridWindowedRangeMake(range, 0, 0);
    iTermSubSelection *theSub =
    [iTermSubSelection subSelectionWithRange:theRange
                                        mode:kiTermSelectionModeCharacter];
    [selection_ addSubSelection:theSub];
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
            if (c == '-') {
                c = DWC_RIGHT;
                [screen setMayHaveDoubleWidthCharacters:YES];
            }
            if (j == [line length] - 1) {
                if (c == '>') {
                    [screen setMayHaveDoubleWidthCharacters:YES];
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
                [screen setMayHaveDoubleWidthCharacters:YES];
                s[j].code = EOL_DWC;
                break;

            default:
                XCTAssert(false);  // bogus continution mark
        }
    }
    return screen;
}

- (NSString *)selectedStringInScreen:(VT100Screen *)screen {
    if (![selection_ hasSelection]) {
        return nil;
    }
    NSMutableString *s = [NSMutableString string];
    [selection_ enumerateSelectedRanges:^(VT100GridWindowedRange range, BOOL *stop, BOOL eol) {
        int sx = range.coordRange.start.x;
        for (int y = range.coordRange.start.y; y <= range.coordRange.end.y; y++) {
            screen_char_t *line = [screen getLineAtIndex:y];
            int x;
            int ex = y == range.coordRange.end.y ? range.coordRange.end.x : [screen width];
            BOOL newline = NO;
            for (x = sx; x < ex; x++) {
                if (line[x].code) {
                    [s appendString:ScreenCharArrayToStringDebug(line + x, 1)];
                } else {
                    newline = YES;
                    [s appendString:@"\n"];
                    break;
                }
            }
            if (line[x].code == EOL_HARD && !newline && y != range.coordRange.end.y) {
                [s appendString:@"\n"];
            }
            sx = 0;
        }
        if (eol) {
            [s appendString:@"\n"];
        }
    }];
    return s;
}

- (void)sendDataToTerminal:(NSData *)data {
    [terminal_.parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 1);
    [terminal_.parser addParsedTokensToVector:&vector];
    XCTAssert(CVectorCount(&vector) == 1);
    [terminal_ executeToken:CVectorGetObject(&vector, 0)];
    CVectorDestroy(&vector);
}

- (void)sendEscapeCodes:(NSString *)codes {
    NSString *esc = [NSString stringWithFormat:@"%c", 27];
    NSString *bel = [NSString stringWithFormat:@"%c", 7];
    codes = [codes stringByReplacingOccurrencesOfString:@"^[" withString:esc];
    codes = [codes stringByReplacingOccurrencesOfString:@"^G" withString:bel];
    NSData *data = [codes dataUsingEncoding:NSUTF8StringEncoding];
    [terminal_.parser putStreamData:data.bytes length:data.length];

    CVector vector;
    CVectorCreate(&vector, 1);
    [terminal_.parser addParsedTokensToVector:&vector];
    for (int i = 0; i < CVectorCount(&vector); i++) {
        VT100Token *token = CVectorGetObject(&vector, i);
        [terminal_ executeToken:token];
    }
    CVectorDestroy(&vector);
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
                        NULL,
                        NULL,
                        NO);
    return data;
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
                XCTAssert(line[j].foregroundColor == hfg &&
                          line[j].foregroundColorMode ==  hfm&&
                          line[j].backgroundColor == hbg &&
                          line[j].backgroundColorMode == hbm);
            } else {
                XCTAssert(line[j].foregroundColor == defaultFg &&
                          line[j].foregroundColorMode == ColorModeAlternate &&
                          line[j].backgroundColor == defaultBg &&
                          line[j].backgroundColorMode == ColorModeAlternate);
            }
        }
    }

}

- (void)sendStringToTerminalWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [self sendDataToTerminal:data];
}

#pragma mark - VT100ScreenDelegate

- (void)screenSetColor:(NSColor *)color forKey:(int)key {
}

- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath {
}

- (BOOL)screenShouldPlacePromptAtFirstColumn {
    return YES;
}

- (void)screenSetBackgroundImageFile:(NSString *)filename {
}

- (void)screenSetBadgeFormat:(NSString *)theFormat {
}

- (void)screenSetUserVar:(NSString *)kvp {
}

- (void)screenUpdateDisplay:(BOOL)redraw {
    ++updates_;
}

- (BOOL)screenHasView {
    return YES;
}

- (iTermSelection *)screenSelection {
    return selection_;
}

- (void)screenSetSelectionFromX:(int)startX
                          fromY:(int)startY
                            toX:(int)endX
                            toY:(int)endY {
    [selection_ clearSelection];
    VT100GridWindowedRange theRange =
    VT100GridWindowedRangeMake(VT100GridCoordRangeMake(startX, startY, endX, endY), 0, 0);
    iTermSubSelection *theSub =
    [iTermSubSelection subSelectionWithRange:theRange mode:kiTermSelectionModeCharacter];
    [selection_ addSubSelection:theSub];
}

- (void)screenRemoveSelection {
    [selection_ clearSelection];
}

- (void)screenNeedsRedraw {
    needsRedraw_++;
}

- (void)screenScheduleRedrawSoon {
    needsRedraw_++;
}

- (void)screenSizeDidChange {
    sizeDidChange_++;
}

- (void)screenResizeToWidth:(int)newWidth height:(int)newHeight {
    newSize_ = VT100GridSizeMake(newWidth, newHeight);
}

- (void)screenResizeToPixelWidth:(int)newWidth height:(int)newHeight {
    newPixelSize_ = NSMakeSize(newWidth, newHeight);
}

- (BOOL)screenShouldInitiateWindowResize {
    return canResize_;
}

- (BOOL)screenWindowIsFullscreen {
    return isFullscreen_;
}

- (void)screenTriggerableChangeDidOccur {
    ++triggers_;
    triggerLine_ = [NSMutableString string];
}

- (void)screenSetCursorVisible:(BOOL)visible {
    cursorVisible_ = visible;
}

- (void)screenSetWindowTitle:(NSString *)newTitle {
    windowTitle_ = [[newTitle copy] autorelease];
}

- (void)screenSetName:(NSString *)name {
    name_ = [[name copy] autorelease];
}

- (NSString *)screenNameExcludingJob {
    return @"joblessName";
}

- (NSString *)screenProfileName {
    return @"Default";
}

- (void)screenLogWorkingDirectoryAtLine:(int)line withDirectory:(NSString *)directory {
    [dirlog_ addObject:@[ @(line), directory ? directory : [NSNull null] ]];
}

- (NSRect)screenWindowFrame {
    return NSMakeRect(10, 20, 100, 200);
}

- (NSRect)screenWindowScreenFrame {
    return NSMakeRect(30, 40, 1000, 2000);
}

- (BOOL)screenAllowTitleSetting {
    return YES;
}

- (NSString *)screenCurrentWorkingDirectory {
    return nil;
}

- (void)screenClearHighlights {
    highlightsCleared_ = YES;
}

- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth {
    return ambiguousIsDoubleWidth_;
}

- (BOOL)screenShouldSendContentsChangedNotification {
    return shouldSendContentsChangedNotification_;
}

- (BOOL)screenShouldBeginPrinting {
    return printingAllowed_;
}

- (BOOL)screenShouldSyncTitle {
    return syncTitle_;
}

- (void)screenDidAppendStringToCurrentLine:(NSString *)string {
    [triggerLine_ appendString:string];
}

- (void)screenDidAppendAsciiDataToCurrentLine:(AsciiData *)asciiData {
    [self screenDidAppendStringToCurrentLine:[[[NSString alloc] initWithBytes:asciiData->buffer
                                                                       length:asciiData->length
                                                                     encoding:NSASCIIStringEncoding]
                                              autorelease]];
}

- (void)screenDidReset {
}

- (void)screenPrintString:(NSString *)s {
    if (!printed_) {
        printed_ = [NSMutableString string];
    }
    [printed_ appendString:s];
}

- (void)screenPrintVisibleArea {
    [self screenPrintString:@"(screen dump)"];
}

- (BOOL)screenIsAppendingToPasteboard {
    return pasteboard_ != nil && !pasted_;
}

- (void)screenSetPasteboard:(NSString *)pasteboard {
    pasteboard_ = [[pasteboard copy] autorelease];
}

- (void)screenAppendDataToPasteboard:(NSData *)data {
    [pbData_ appendData:data];
}

- (void)screenCopyBufferToPasteboard {
    pasted_ = YES;
}

- (BOOL)screenShouldSendReport {
    return YES;
}

- (void)screenWriteDataToTask:(NSData *)data {
    [write_ appendData:data];
}

- (void)screenDidChangeNumberOfScrollbackLines {
}

- (NSString *)screenSessionGuid {
    return @"fjdkslafjdsklfa";
}

- (void)screenSetCursorBlinking:(BOOL)blink {
}

- (void)screenSetCursorType:(ITermCursorType)type {
}

- (NSString *)screenWindowTitle {
    return windowTitle_;
}

- (NSString *)screenDefaultName {
    return @"Default name";
}

- (NSString *)screenName {
    return name_;
}

- (NSPoint)screenWindowTopLeftPixelCoordinate {
    return NSZeroPoint;
}

- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point {
}

- (void)screenMiniaturizeWindow:(BOOL)flag {
}

- (void)screenRaise:(BOOL)flag {
}

- (BOOL)screenWindowIsMiniaturized {
    return NO;
}

- (NSSize)screenSize {
    return NSMakeSize(100, 100);
}

- (void)screenPushCurrentTitleForWindow:(BOOL)flag {
}

- (void)screenPopCurrentTitleForWindow:(BOOL)flag {
}

- (int)screenNumber {
    return 0;
}

- (int)screenTabIndex {
    return 0;
}

- (int)screenViewIndex {
    return 0;
}

- (int)screenWindowIndex {
    return 0;
}

- (void)screenStartTmuxMode {
}

- (void)screenHandleTmuxInput:(VT100Token *)token {
}

- (void)screenShowBellIndicator {
}

- (void)screenSuggestShellIntegrationUpgrade {
}

- (NSSize)screenCellSize {
    return NSMakeSize(10, 10);
}

- (void)screenMouseModeDidChange {
}

- (void)screenFlashImage:(NSString *)identifier {
}

- (void)screenIncrementBadge {
}

- (void)screenSetHighlightCursorLine:(BOOL)highlight {
}

- (void)screenCursorDidMoveToLine:(int)line {
}

- (void)screenSaveScrollPosition {
}

- (VT100ScreenMark *)screenAddMarkOnLine:(int)line {
    return nil;
}

- (void)screenActivateWindow {
}

- (void)screenSetProfileToProfileNamed:(NSString *)value {
}

- (void)screenDidAddNote:(PTYNoteViewController *)note {
}

- (void)screenDidEndEditingNote {
}

- (void)screenWillReceiveFileNamed:(NSString *)name ofSize:(int)size {
}

- (void)screenDidFinishReceivingFile {
}

- (void)screenDidReceiveBase64FileData:(NSString *)data {
}

- (void)screenFileReceiptEndedUnexpectedly {
}

- (void)screenRequestAttention:(BOOL)request isCritical:(BOOL)isCritical {
}

- (iTermColorMap *)screenColorMap {
    return nil;
}

- (void)screenSetCurrentTabColor:(NSColor *)color {
}

- (void)screenSetTabColorGreenComponentTo:(CGFloat)color {
}

- (void)screenSetTabColorBlueComponentTo:(CGFloat)color {
}

- (void)screenSetTabColorRedComponentTo:(CGFloat)color {
}

- (void)screenCurrentHostDidChange:(VT100RemoteHost *)host {
}

- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range {
}

- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range {
}

- (int)selectionViewportWidth {
    return 80;
}

- (BOOL)screenShouldPostTerminalGeneratedAlert {
    return NO;
}

- (BOOL)screenShouldIgnoreBellWhichIsAudible:(BOOL)audible visible:(BOOL)visible {
    return NO;
}

- (void)screenPromptDidStartAtLine:(int)line {
}

- (BOOL)screenInTmuxMode {
    return NO;
}

- (NSIndexSet *)selectionIndexesOnLine:(int)line
                   containingCharacter:(unichar)c
                               inRange:(NSRange)range {
    return nil;
}

- (BOOL)screenShouldReduceFlicker {
    return NO;
}

#pragma mark - iTermSelectionDelegate

- (void)selectionDidChange:(iTermSelection *)selection {
}

- (VT100GridWindowedRange)selectionRangeForParentheticalAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForWordAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForSmartSelectionAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForWrappedLineAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForLineAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridRange)selectionRangeOfTerminalNullsOnLine:(int)lineNumber {
    return VT100GridRangeMake(INT_MAX, 0);
}

- (VT100GridCoord)selectionPredecessorOfCoord:(VT100GridCoord)coord {
    XCTAssert(false);
}

#pragma mark - Tests

- (void)testSetSizeRespectsContinuations {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:5];
    screen_char_t *line = [screen.currentGrid screenCharsAtLineNumber:0];
    line[5].backgroundColor = 5;
    [screen setSize:VT100GridSizeMake(6, 4)];
    line = [screen.currentGrid screenCharsAtLineNumber:0];
    XCTAssert(line[0].backgroundColor == 5);
}

- (void)testAppendingWithWraparoundOffSetsContinuation {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:5];
    [screen.terminal setWraparoundMode:NO];
    [screen.terminal setBackgroundColor:5 alternateSemantics:NO];
    [screen appendStringAtCursor:@"0123456789Z"];  // Should become 0123Z
    screen_char_t *line = [screen.currentGrid screenCharsAtLineNumber:0];
    XCTAssert(line[5].backgroundColor == 0);
}

- (void)testSetSizeHeight {
    VT100Screen *screen;

    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setSize:VT100GridSizeMake(5, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"....."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in primary - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setSize:VT100GridSizeMake(4, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcd\n"
               @"efgh\n"
               @"ijkl\n"
               @"...."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in primary - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setSize:VT100GridSizeMake(9, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefgh.\n"
               @"ijkl.....\n"
               @".........\n"
               @"........."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setSize:VT100GridSizeMake(5, 5)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @".....\n"
               @"....."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in primary - grows, pulling lines out of line buffer
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [screen setSize:VT100GridSizeMake(6, 5)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"gh....\n"
               @"ijkl..\n"
               @"mnopqr\n"
               @"st....\n"
               @"......"]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 5);

    // Starting in primary, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijk\n"
               @"l..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"abc"]);

    // Same tests as above, but in alt screen. -----------------------------------------------------
    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(5, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCDE\n"
               @"FGH..\n"
               @"IJKL.\n"
               @"....."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"....."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in alt - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(4, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCD\n"
               @"EFGH\n"
               @"IJKL\n"
               @"...."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcd\n"
               @"efgh\n"
               @"ijkl\n"
               @"...."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in alt - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(9, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCDEFGH.\n"
               @"IJKL.....\n"
               @".........\n"
               @"........."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefgh.\n"
               @"ijkl.....\n"
               @".........\n"
               @"........."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(5, 5)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCDE\n"
               @"FGH..\n"
               @"IJKL.\n"
               @".....\n"
               @"....."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @".....\n"
               @"....."]);

    // Starting in alt - grows, but we don't pull anything out of the line buffer.
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(6, 5)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"IJKL..\n"
               @"MNOPQR\n"
               @"ST....\n"
               @"......\n"
               @"......"]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijkl..\n"
               @"mnopqr\n"
               @"st....\n"
               @"......\n"
               @"......"]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 4);

    // Starting in alt, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"IJK\n"
               @"L..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijk\n"
               @"l..\n"
               @"..."]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"abc"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:1],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"def"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:2],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"gh"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:3],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"ijk"]);

    // Starting in primary with selection, it shrinks, but selection stays on screen
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "jk"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 2, 3, 2)];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijk\n"
               @"l..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"jk"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
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
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 4, 0)];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijk\n"
               @"l..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcd"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
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
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijk\n"
               @"l..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen setSize:VT100GridSizeMake(9, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefgh.\n"
               @"ijkl.....\n"
               @".........\n"
               @"........."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen shrinks but selection stays on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\ij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen setSize:VT100GridSizeMake(4, 4)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCD\n"
               @"EFGH\n"
               @"IJKL\n"
               @"...."]);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top partially
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"IJK\n"
               @"L..\n"
               @"..."]);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"IJ"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top completely
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "abc"
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 3, 0)];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"IJK\n"
               @"L..\n"
               @"..."]);
    XCTAssert([self selectedStringInScreen:screen] == nil);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen setSize:VT100GridSizeMake(6, 5)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ABCDEF\n"
               @"GH....\n"
               @"IJKL..\n"
               @"......\n"
               @"......"]);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    XCTAssert(needsRedraw_ > 0);
    XCTAssert(sizeDidChange_ > 0);
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
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"MNOPQ\n"
               @"RST..\n"
               @"UVWXY\n"
               @"Z....\n"
               @"....."]);
    // select everything
    // TODO There's a bug when the selection is at the very end (5,6). It is deselected.
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"MNOPQR\n"
               @"ST....\n"
               @"UVWXYZ\n"
               @"......\n"
               @"......\n"
               @"......"]);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
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
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 5, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ\n"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ\n"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // If lines get pushed into line buffer, excess are dropped
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:1];
    [self showAltAndUppercase:screen];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"IJK\n"
               @"L..\n"
               @"..."]);
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 3);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    XCTAssert([s isEqualToString:@"gh"]);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
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
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                                  VT100GridRectMake(0, 0, 3, 3)));

    // Selection ending at line with trailing nulls
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "efgh.."
    [self setSelectionRange:VT100GridCoordRangeMake(4, 0, 5, 1)];
    [screen setSize:VT100GridSizeMake(3, 3)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"efgh\n"]);
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
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 2)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"]);
    [screen setSize:VT100GridSizeMake(13, 4)];
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
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijklm\n"
               @"nopqr\n" // top line of screen
               @"st...\n"
               @"uvwxy\n"
               @"z....\n"
               @"....."]);
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 2, 2)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nij"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcdef\n"
               @"NOPQRS\n"
               @"T.....\n"
               @"UVWXYZ\n"
               @"......\n"
               @"......\n"
               @"......"]);
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
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
    [self setSelectionRange:VT100GridCoordRangeMake(1, 2, 2, 3)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"jklmNO"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"NO"]);

    // In alt screen with selection that begins and ends onscreen. The screen is grown and some history
    // is deleted.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 4, 2, 4)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // there too. The screen grows, moving lines from history into the primary screen. The
    // selection is lost because none of its characters still exist.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 2, 2, 2)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"ij"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([self selectedStringInScreen:screen] == nil);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection is exactly at the last character before those that are lost.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 1)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // End is one before previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 5, 0)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);

    // End is two after previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 2, 1)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefg"]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // Starting in primary but with content on the alt screen. It is properly restored.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"nopqr\n"
               @"st...\n"
               @"uvwxy\n"
               @"z....\n"
               @"....."]);
    [self showAltAndUppercase:screen];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"NOPQR\n"
               @"ST...\n"
               @"UVWXY\n"
               @"Z....\n"
               @"....."]);
    [screen setSize:VT100GridSizeMake(6, 6)];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"NOPQRS\n"
               @"T.....\n"
               @"UVWXYZ\n"
               @"......\n"
               @"......\n"
               @"......"]);
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"gh....\n"
               @"ijklmn\n"
               @"opqrst\n"
               @"uvwxyz\n"
               @"......\n"
               @"......"]);
}

- (void)testRunByTrimmingNullsFromRun {
    // Basic test
    VT100Screen *screen = [self screenFromCompactLines:
                           @"..1234\n"
                           @"56789a\n"
                           @"bc...."];
    VT100GridRun run = VT100GridRunMake(1, 0, 16);
    VT100GridRun trimmed = [screen runByTrimmingNullsFromRun:run];
    XCTAssert(trimmed.origin.x == 2);
    XCTAssert(trimmed.origin.y == 0);
    XCTAssert(trimmed.length == 12);

    // Test wrapping nulls around
    screen = [self screenFromCompactLines:
              @"......\n"
              @".12345\n"
              @"67....\n"
              @"......\n"];
    run = VT100GridRunMake(0, 0, 24);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    XCTAssert(trimmed.origin.x == 1);
    XCTAssert(trimmed.origin.y == 1);
    XCTAssert(trimmed.length == 7);

    // Test all nulls
    screen = [self screenWithWidth:4 height:4];
    run = VT100GridRunMake(0, 0, 4);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    XCTAssert(trimmed.length == 0);

    // Test no nulls
    screen = [self screenFromCompactLines:
              @"1234\n"
              @"5678"];
    run = VT100GridRunMake(1, 0, 6);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    XCTAssert(trimmed.origin.x == 1);
    XCTAssert(trimmed.origin.y == 0);
    XCTAssert(trimmed.length == 6);
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
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:YES];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijkl.\n"
               @".....\n"
               @"....."]);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"fgh..\n"
               @"ijkl.\n"
               @".....\n"
               @"....."]);

    XCTAssert(screen.cursorX == 5);
    XCTAssert(screen.cursorY == 1);
    XCTAssert(cursorVisible_);
    XCTAssert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    XCTAssert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                                  VT100GridRectMake(0, 0, 5, 3)));
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Test with arg=no
    screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @".....\n"
               @".....\n"
               @"....."]);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"ijkl.\n"
               @".....\n"
               @".....\n"
               @"....."]);

    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 1);
    XCTAssert(cursorVisible_);
    XCTAssert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    XCTAssert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                                  VT100GridRectMake(0, 0, 5, 3)));
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testAllCharacterSetPropertiesHaveDefaultValues {
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    // Switch to charset 1
    char shiftOut = 14;
    char shiftIn = 15;
    NSData *data = [NSData dataWithBytes:&shiftOut length:1];
    [self sendDataToTerminal:data];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    [screen terminalResetPreservingPrompt:NO];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    data = [NSData dataWithBytes:&shiftIn length:1];
    [self sendDataToTerminal:data];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testClearBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;

    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [terminal_ setSavedCursorPosition:screen.currentGrid.cursor];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen clearBuffer];
    XCTAssert(updates_ == 1);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @".....\n"
               @".....\n"
               @".....\n"
               @"....."]);
    XCTAssert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                                  VT100GridRectMake(0, 0, 5, 4)));
    XCTAssert(terminal_.savedCursorPosition.x == 0);
    XCTAssert(terminal_.savedCursorPosition.y == 0);

    // Cursor on last nonempty line
    screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:3];
    [screen clearBuffer];
    XCTAssert(updates_ == 2);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"wxyz.\n"
               @".....\n"
               @".....\n"
               @"....."]);
    XCTAssert(screen.cursorX == 4);
    XCTAssert(screen.cursorY == 1);


    // Cursor in middle of content
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen clearBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"rstuv\n"
               @".....\n"
               @".....\n"
               @"....."]);
    XCTAssert(screen.cursorX == 4);
    XCTAssert(screen.cursorY == 1);
}

- (void)testClearScrollbackBuffer {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 1, 1)];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"mnopq\n"
               @"rstuv\n"
               @"wxyz.\n"
               @"....."]);
    [screen clearScrollbackBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"mnopq\n"
               @"rstuv\n"
               @"wxyz.\n"
               @"....."]);
    XCTAssert(highlightsCleared_);
    XCTAssert(![selection_ hasSelection]);
    XCTAssert([screen isAllDirty]);
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
    [screen appendStringAtCursor:@"Hello world"];

    XCTAssert([[screen compactLineDump] isEqualToString:
               @"Hello\n"
               @" worl\n"
               @"d....\n"
               @"....."]);
    screen_char_t *line = [screen getLineAtScreenIndex:0];
    XCTAssert(line[0].foregroundColor == 5);
    XCTAssert(line[0].foregroundColorMode == ColorModeNormal);
    XCTAssert(line[0].bold);
    XCTAssert(line[0].italic);
    XCTAssert(line[0].blink);
    XCTAssert(line[0].underline);
    XCTAssert(line[0].backgroundColor == 6);
    XCTAssert(line[0].backgroundColorMode == ColorModeNormal);
}

- (void)testAppendComposedCharactersPiecewise {
    struct {
        NSArray<NSNumber *> *codePoints;
        NSString *expected;
        BOOL doubleWidth;
    } tests[] = {
        {
            @[ @'a', @0x301 ],  // a + accent
            @"á",
            NO
        },
        {
            @[ @0xD800, @0xDD50 ],  // surrogate pair
            @"𐅐",
            NO
        },
        {
            @[ @0xff25, @0x301 ],  // double-width e + accent
            @"Ｅ́",
            YES
        },
        /*
         This test fails but you can't hit this case in real life, unless your terminal's encoding
         is UTF-16. In UTF-8, surrogate pairs are not used, so they'll always appear together.
        {
            @[ @0xD83D, @0xDD95, @0xD83C, @0xDFFE ],  // Middle finger + dark skin tone
            @"🖕🏾",
            NO
        },
         */
        {
            @[ @0xfeff, @0xd83c, @0xdffe ],  // Zero width space + dark skin tone
            @"🏾",
            NO
        }
    };
    for (size_t i = 0; i < sizeof(tests) / sizeof(*tests); i++) {
        VT100Screen *screen = [self screenWithWidth:20 height:2];
        screen.delegate = (id<VT100ScreenDelegate>)self;
        for (NSNumber *code in tests[i].codePoints) {
            unichar c = code.intValue;
            [screen appendStringAtCursor:[NSString stringWithCharacters:&c length:1]];
        }
        screen_char_t *line = [screen getLineAtScreenIndex:0];
        XCTAssertEqualObjects(ScreenCharToStr(line), tests[i].expected);

        if (tests[i].doubleWidth) {
            XCTAssertEqual(line[1].code, DWC_RIGHT);
        } else {
            XCTAssertEqual(line[1].code, 0);
        }
    }
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
        0xD83D,  // High surrogate for 1F595 (middle finger)
        0xDD95,  // Low surrogate for 1F595
        0xD83C,  // High surrogate for 1F3FE (dark skin tone)
        0xDFFE,  // Low surrogate for 1F3FE
        'g',
        0xD83C,  // High surrogate for 1F3FE (dark skin tone)
        0xDFFE,  // Low surrogate for 1F3FE
    };

    NSMutableString *s = [NSMutableString stringWithCharacters:chars
                                                        length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s];

    screen_char_t *line = [screen getLineAtScreenIndex:0];
    XCTAssert(line[0].foregroundColor == 5);
    XCTAssert(line[0].foregroundColorMode == ColorModeNormal);
    XCTAssert(line[0].bold);
    XCTAssert(line[0].italic);
    XCTAssert(line[0].blink);
    XCTAssert(line[0].underline);
    XCTAssert(line[0].backgroundColor == 6);
    XCTAssert(line[0].backgroundColorMode == ColorModeNormal);

    NSString *a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    NSString *e = [@"´" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 2) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);

    a = ScreenCharToStr(line + 3);
    e = @"𐅐";
    XCTAssert([a isEqualToString:e]);

    XCTAssert([ScreenCharToStr(line + 4) isEqualToString:@"Ｅ"]);
    XCTAssert(line[5].code == DWC_RIGHT);
    XCTAssert([ScreenCharToStr(line + 6) isEqualToString:@"�"]);
    XCTAssert([ScreenCharToStr(line + 7) isEqualToString:@"g"]);
    XCTAssert([ScreenCharToStr(line + 8) isEqualToString:@"ł"]);

    XCTAssert([ScreenCharToStr(line + 9) isEqualToString:@"🖕🏾"]);
    XCTAssert([ScreenCharToStr(line + 10) isEqualToString:@"g"]);
    XCTAssert([ScreenCharToStr(line + 11) isEqualToString:@"🏾"]);  // Skin tone modifier only combines with certain emoji
    XCTAssert(line[12].code == 0);
    // Toggle ambiguousIsDoubleWidth_ and see if it works.
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    ambiguousIsDoubleWidth_ = YES;
    s = [NSMutableString stringWithCharacters:chars
                                       length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s];

    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"´" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);
    XCTAssert(line[2].code == DWC_RIGHT);

    a = [ScreenCharToStr(line + 3) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);
    XCTAssert(line[4].code == DWC_RIGHT);

    a = ScreenCharToStr(line + 5);
    e = @"𐅐";
    XCTAssert([a isEqualToString:e]);

    XCTAssert([ScreenCharToStr(line + 6) isEqualToString:@"Ｅ"]);
    XCTAssert(line[7].code == DWC_RIGHT);
    XCTAssert([ScreenCharToStr(line + 8) isEqualToString:@"�"]);
    XCTAssert(line[9].code == DWC_RIGHT);
    XCTAssert([ScreenCharToStr(line + 10) isEqualToString:@"g"]);
    XCTAssert([ScreenCharToStr(line + 11) isEqualToString:@"ł"]);
    XCTAssert(line[12].code == DWC_RIGHT);
    XCTAssert([ScreenCharToStr(line + 13) isEqualToString:@"🖕🏾"]);
    XCTAssert([ScreenCharToStr(line + 14) isEqualToString:@"g"]);
    XCTAssert([ScreenCharToStr(line + 15) isEqualToString:@"🏾"]);  // Skin tone modifier only combines with certain emoji
    XCTAssert(line[16].code == 0);

    // Test modifying character already at cursor with combining mark
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"e"];
    unichar combiningAcuteAccent = 0x301;
    s = [NSMutableString stringWithCharacters:&combiningAcuteAccent length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"é" decomposedStringWithCompatibilityMapping];
    XCTAssert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    const unichar highSurrogate = 0xD800;
    const unichar lowSurrogate = 0xDD50;
    s = [NSMutableString stringWithCharacters:&highSurrogate length:1];
    [screen appendStringAtCursor:s];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"𐅐";
    XCTAssert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate, but it's not a high surrogate.
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"g"];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"g";
    XCTAssert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = @"�";
    XCTAssert([a isEqualToString:e]);

    // Test two high surrogates in a row.
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    s = [NSMutableString stringWithCharacters:&highSurrogate length:1];
    [screen appendStringAtCursor:s];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"�";
    XCTAssert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [NSString stringWithCharacters:&highSurrogate length:1];
    XCTAssert([a isEqualToString:e]);
}

- (void)testLinefeed {
    // The guts of linefeed is tested in VT100GridTest.
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"mnop.\n"
               @"....."]);
    [screen terminalSetScrollRegionTop:1 bottom:3];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:3];
    [screen terminalMoveCursorToX:4 y:4];
    [screen linefeed];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fjkl.\n"
               @"inop.\n"
               @"m....\n"
               @"....."]);
    XCTAssert([screen scrollbackOverflow] == 0);
    XCTAssert([screen totalScrollbackOverflow] == 0);
    XCTAssert([screen cursorX] == 4);

    // Now test scrollback
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"mnop.\n"
               @"....."]);
    [screen terminalMoveCursorToX:4 y:5];
    [screen linefeed];
    [screen linefeed];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"ijkl.\n"
               @"mnop.\n"
               @".....\n"
               @".....\n"
               @"....."]);
    XCTAssert([screen scrollbackOverflow] == 1);
    XCTAssert([screen totalScrollbackOverflow] == 1);
    XCTAssert([screen cursorX] == 4);
    [screen resetScrollbackOverflow];
    XCTAssert([screen scrollbackOverflow] == 0);
    XCTAssert([screen totalScrollbackOverflow] == 1);
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
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcdef+\n"
               @"ghijkl!\n"
               @"mnop..!\n"
               @"qrstuv+\n"
               @"wxyz..!\n"
               @"012345+\n"
               @"6.....!\n"
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
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
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

    XCTAssert(screen.cursorX == 5);
    XCTAssert(screen.cursorY == 6);
    [terminal_ restoreCursor];
    XCTAssert(screen.cursorX == 3);
    XCTAssert(screen.cursorY == 4);
    XCTAssert([[screen currentGrid] topMargin] == 6);
    XCTAssert([[screen currentGrid] bottomMargin] == 7);
    XCTAssert(!cursorVisible_);
    [screen terminalCarriageReturn];
    [screen terminalAppendTabAtCursor];
    XCTAssert(screen.cursorX == 5);
    [screen terminalAppendTabAtCursor];
    XCTAssert(screen.cursorX == 9);
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
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcde+\n"
               @"fgh..!\n"
               @"ijkl.!\n"
               @".....!"]);
    XCTAssert(screen.cursorX == 2);
    XCTAssert(screen.cursorY == 3);

    // Try a screen smaller than the frame
    screen = [self screenWithWidth:2 height:2];
    [screen setFromFrame:(screen_char_t *) data.mutableBytes
                     len:data.length
                    info:info];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"ij!\n"
               @"..!"]);
    XCTAssert(screen.cursorX == 2);
    XCTAssert(screen.cursorY == 1);
}

// Perform a search, append some stuff, and continue searching from the end of scrollback history
// prior to the appending, finding a match in the stuff that was appended. This is what PTYSession
// does for tail-find.
- (void)testAPIsUsedByTailFind {
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
    XCTAssert([screen continueFindAllResults:results
                                   inContext:ctx]);
    XCTAssert(results.count == 1);
    SearchResult *range = results[0];
    XCTAssert(range.startX == 0);
    XCTAssert(range.absStartY == 5);
    XCTAssert(range.endX == 3);
    XCTAssert(range.absEndY == 5);

    // Make sure there's nothing else to find
    [results removeAllObjects];
    XCTAssert(![screen continueFindAllResults:results
                                    inContext:ctx]);
    XCTAssert(results.count == 0);

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
    XCTAssert([screen continueFindAllResults:results
                                   inContext:ctx]);
    XCTAssert(results.count == 1);
    range = results[0];
    XCTAssert(range.startX == 0);
    XCTAssert(range.absStartY == 8);
    XCTAssert(range.endX == 3);
    XCTAssert(range.absEndY == 8);

    // Make sure there's nothing else to find
    [results removeAllObjects];
    XCTAssert(![screen continueFindAllResults:results
                                    inContext:ctx]);
    XCTAssert(results.count == 0);

    // Search backwards from the end. This is slower than searching
    // forwards, but most searches are reverse searches begun at the end,
    // so it will get a result sooner.
    FindContext *myFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"mnop"
         forwardDirection:NO
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:[screen numberOfLines] + 1 + [screen totalScrollbackOverflow]
               withOffset:0
                inContext:[screen findContext]
          multipleResults:YES];

    [myFindContext copyFromFindContext:[screen findContext]];
    myFindContext.results = nil;
    [screen saveFindContextAbsPos];

    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:[screen findContext]];
    XCTAssert(results.count == 1);
    SearchResult *actualResult = results[0];
    SearchResult *expectedResult = [SearchResult searchResultFromX:0 y:3 toX:3 y:3];
    XCTAssert([actualResult isEqualToSearchResult:expectedResult]);
    // TODO test the result range

    // Do a tail find from the saved position.
    FindContext *tailFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"rst"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:tailFindContext
          multipleResults:YES];

    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [screen restoreSavedPositionToFindContext:tailFindContext];
    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:tailFindContext];
    XCTAssert(results.count == 0);

    // Append a line and then do it again, this time finding the line.
    [screen saveFindContextAbsPos];
    [screen setMaxScrollbackLines:8];
    [self appendLines:@[ @"rst" ]  toScreen:screen];
    tailFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"rst"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:tailFindContext
          multipleResults:YES];

    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [screen restoreSavedPositionToFindContext:tailFindContext];
    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:tailFindContext];
    XCTAssert(results.count == 1);
    actualResult = results[0];
    expectedResult = [SearchResult searchResultFromX:0 y:9 toX:2 y:9];
    XCTAssert([actualResult isEqualToSearchResult:expectedResult]);
}

#pragma mark - Tests for PTYTextViewDataSource methods

- (void)testNumberOfLines {
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    XCTAssert([screen numberOfLines] == 2);
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
    XCTAssert([screen numberOfLines] == 8);
}

- (void)testCursorXY {
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    XCTAssert([screen cursorX] == 1);
    XCTAssert([screen cursorY] == 1);
    [screen terminalMoveCursorToX:2 y:3];
    XCTAssert([screen cursorX] == 2);
    XCTAssert([screen cursorY] == 3);
}

- (void)testGetLineAtIndex {
    VT100Screen *screen = [self screenFromCompactLines:
                           @"abcde>\n"
                           @"F-ghi.\n"];
    [screen terminalMoveCursorToX:6 y:2];
    screen_char_t *line = [screen getLineAtIndex:0];
    XCTAssert(line[0].code == 'a');
    XCTAssert(line[5].code == DWC_SKIP);
    XCTAssert(line[6].code == EOL_DWC);

    // Scroll the DWC_SPLIT off the screen. getLineAtIndex: will restore it, even though line buffers
    // don't store those.
    [self appendLines:@[@"jkl"] toScreen:screen];
    line = [screen getLineAtIndex:0];
    XCTAssert(line[0].code == 'a');
    XCTAssert(line[5].code == DWC_SKIP);
    XCTAssert(line[6].code == EOL_DWC);
}

- (void)testNumberOfScrollbackLines {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:2];
    XCTAssert([screen numberOfScrollbackLines] == 0);
    [screen terminalLineFeed];
    XCTAssert([screen numberOfScrollbackLines] == 1);
    [screen terminalLineFeed];
    XCTAssert([screen numberOfScrollbackLines] == 2);
    [screen terminalLineFeed];
    XCTAssert([screen numberOfScrollbackLines] == 2);
}

- (void)testScrollbackOverflow {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:0];
    XCTAssert([screen scrollbackOverflow] == 0);
    [screen terminalLineFeed];
    [screen terminalLineFeed];
    XCTAssert([screen scrollbackOverflow] == 2);
    XCTAssert([screen totalScrollbackOverflow] == 2);
    [screen resetScrollbackOverflow];
    XCTAssert([screen scrollbackOverflow] == 0);
    XCTAssert([screen totalScrollbackOverflow] == 2);
    [screen terminalLineFeed];
    XCTAssert([screen scrollbackOverflow] == 1);
    XCTAssert([screen totalScrollbackOverflow] == 3);
}

- (void)testAbsoluteLineNumberOfCursor {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    XCTAssert([screen cursorY] == 4);
    XCTAssert([screen absoluteLineNumberOfCursor] == 3);
    [screen setMaxScrollbackLines:1];
    [screen terminalLineFeed];
    XCTAssert([screen absoluteLineNumberOfCursor] == 4);
    [screen terminalLineFeed];
    XCTAssert([screen absoluteLineNumberOfCursor] == 5);
    [screen resetScrollbackOverflow];
    XCTAssert([screen absoluteLineNumberOfCursor] == 5);
    [screen clearScrollbackBuffer];
    XCTAssert([screen absoluteLineNumberOfCursor] == 4);
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
    [screen setSize:VT100GridSizeMake(screen.width, 2)];
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
    XCTAssert(results.count == expected.count);
    for (int i = 0; i < expected.count; i++) {
        XCTAssert([expected[i] isEqualToSearchResult:results[i]]);
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
        [self appendLines:@[ @"FOO" ] toScreen:screen];
    }];
}

- (void)testScrollingInAltScreen {
    // When in alt screen and scrolling and !saveToScrollbackInAlternateScreen_, then the whole
    // screen must be marked dirty.
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:3];
    [self appendLines:@[ @"0", @"1", @"2", @"3", @"4"] toScreen:screen];
    [self showAltAndUppercase:screen];
    screen.saveToScrollbackInAlternateScreen = YES;
    [screen resetDirty];
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen terminalLineFeed];
    XCTAssert([screen scrollbackOverflow] == 1);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"1.\n"
               @"2.\n"
               @"3.\n"
               @"4.\n"
               @"..\n"
               @".."]);
    XCTAssert([[[screen currentGrid] compactDirtyDump] isEqualToString:
               @"cc\n"
               @"dc\n"
               @"dd"]);
    [screen resetScrollbackOverflow];
    XCTAssert([selection_ firstRange].coordRange.start.x == 1);

    screen.saveToScrollbackInAlternateScreen = NO;
    // scrollback overflow should be 0 and selection shoudn't be insane
    [self setSelectionRange:VT100GridCoordRangeMake(1, 5, 2, 5)];
    [screen terminalLineFeed];
    XCTAssert([screen scrollbackOverflow] == 0);
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"1.\n"
               @"2.\n"
               @"3.\n"
               @"..\n"
               @"..\n"
               @".."]);
    XCTAssert([[[screen currentGrid] compactDirtyDump] isEqualToString:
               @"dd\n"
               @"dd\n"
               @"dd"]);
    VT100GridWindowedRange selectionRange = [selection_ firstRange];
    ITERM_TEST_KNOWN_BUG(selectionRange.coordRange.start.y == 4,
                         selectionRange.coordRange.start.y == -1);
    // See comment in -linefeed about why this happens
    // When this bug is fixed, also test truncation with and without scroll regions, as well
    // as deselection because the whole selection scrolled off the top of the scroll region.
}

- (void)testAllDirty {
    // This is not a great test.
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    XCTAssert([screen isAllDirty]);
    [screen resetAllDirty];
    XCTAssert(![screen isAllDirty]);
    [screen terminalLineFeed];
    XCTAssert(![screen isAllDirty]);
    [screen terminalNeedsRedraw];
    XCTAssert([screen isAllDirty]);
}

- (void)testSetCharDirtyAtCursor {
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resetDirty];
    // Test normal case
    [screen setCharDirtyAtCursorX:0 Y:0];
    XCTAssert([[[screen currentGrid] compactDirtyDump] isEqualToString:
               @"dd\n"
               @"cc\n"
               @"cc"]);

    // Test cursor in right margin
    [screen resetDirty];
    [screen setCharDirtyAtCursorX:2 Y:1];
    XCTAssert([[[screen currentGrid] compactDirtyDump] isEqualToString:
               @"cc\n"
               @"cc\n"
               @"dd"]);

    // Test cursor in last column
    [screen resetDirty];
    [screen setCharDirtyAtCursorX:1 Y:1];
    XCTAssert([[[screen currentGrid] compactDirtyDump] isEqualToString:
               @"cc\n"
               @"cd\n"
               @"cc"]);
}

- (void)testIsDirtyAt {
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resetDirty];
    XCTAssert(![screen isDirtyAtX:0 Y:0]);
    [screen appendStringAtCursor:@"x"];
    XCTAssert([screen isDirtyAtX:0 Y:0]);
    [screen clearBuffer];  // Marks everything dirty
    XCTAssert([screen isDirtyAtX:1 Y:1]);
}

- (void)testSaveToDvr {
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[ @"Line 1", @"Line 2"] toScreen:screen];
    [screen saveToDvr];

    [self appendLines:@[ @"Line 3"] toScreen:screen];
    [screen saveToDvr];

    DVRDecoder *decoder = [screen.dvr getDecoder];
    [decoder seek:0];
    screen_char_t *frame = (screen_char_t *)[decoder decodedFrame];
    NSString *s;
    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    XCTAssert([s isEqualToString:@"Line 1"]);

    [decoder next];
    frame = (screen_char_t *)[decoder decodedFrame];

    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    XCTAssert([s isEqualToString:@"Line 2"]);
}

- (void)testContentsChangedNotification {
    shouldSendContentsChangedNotification_ = NO;
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    XCTAssert(![screen shouldSendContentsChangedNotification]);
    shouldSendContentsChangedNotification_ = YES;
    XCTAssert([screen shouldSendContentsChangedNotification]);
}

#pragma mark - Test for VT100TerminalDelegate methods

- (void)testPrinting {
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    printingAllowed_ = YES;
    [screen terminalBeginRedirectingToPrintBuffer];
    [screen terminalAppendString:@"test"];
    [screen terminalLineFeed];
    [screen terminalPrintBuffer];
    XCTAssert([printed_ isEqualToString:@"test\n"]);
    printed_ = nil;

    printingAllowed_ = NO;
    [screen terminalBeginRedirectingToPrintBuffer];
    [screen terminalAppendString:@"test"];
    XCTAssert([triggerLine_ isEqualToString:@"test"]);
    [screen terminalLineFeed];
    XCTAssert([triggerLine_ isEqualToString:@""]);
    [screen terminalPrintBuffer];
    XCTAssert(!printed_);
    XCTAssert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                            screen.width) isEqualToString:@"test"]);

    printed_ = nil;
    printingAllowed_ = YES;
    [screen terminalPrintScreen];
    XCTAssert([printed_ isEqualToString:@"(screen dump)"]);
}

- (void)testBackspace {
    // Normal case
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"Hello"];
    [screen terminalMoveCursorToX:5 y:1];
    [screen terminalBackspace];
    XCTAssert(screen.cursorX == 4);
    XCTAssert(screen.cursorY == 1);

    // Wrap around soft eol
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"12345678901234567890Hello"];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    XCTAssert(screen.cursorX == 20);
    XCTAssert(screen.cursorY == 1);

    // No wraparound for hard eol
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 2);

    // With vsplit, no wrap.
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:10];
    [screen terminalMoveCursorToX:3 y:2];
    [screen terminalBackspace];
    XCTAssert(screen.cursorX == 3);
    XCTAssert(screen.cursorY == 2);

    // Cursor should be on DWC_SKIP
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"1234567890123456789Ｗ"];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    XCTAssert(screen.cursorX == 20);
    XCTAssert(screen.cursorY == 1);
}

- (NSArray *)tabStopsInScreen:(VT100Screen *)screen {
    NSMutableArray *actual = [NSMutableArray array];
    [screen terminalCarriageReturn];
    int lastX = screen.cursorX;
    while (1) {
        [screen terminalAppendTabAtCursor];
        if (screen.cursorX == lastX) {
            return actual;
        }
        [actual addObject:@(screen.cursorX - 1)];
        lastX = screen.cursorX;
    }
}

- (void)testTabStops {
    VT100Screen *screen = [self screenWithWidth:20 height:3];

    // Test default tab stops
    NSArray *expected = @[ @8, @16, @19];
    XCTAssert([expected isEqualToArray:[self tabStopsInScreen:screen]]);

    // Add a tab stop
    [screen terminalMoveCursorToX:10 y:1];
    [screen terminalSetTabStopAtCursor];
    expected = @[ @8, @9, @16, @19];
    XCTAssert([expected isEqualToArray:[self tabStopsInScreen:screen]]);

    // Remove a tab stop
    [screen terminalMoveCursorToX:9 y:1];
    [screen terminalRemoveTabStopAtCursor];
    expected = @[ @9, @16, @19];
    XCTAssert([expected isEqualToArray:[self tabStopsInScreen:screen]]);

    // Appending a tab should respect vsplits.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:0 rightMargin:7];
    [screen terminalAppendTabAtCursor];
    XCTAssert(screen.cursorX == 8);

    // Tabbing over text doesn't change it
    screen = [self screenWithWidth:20 height:3];
    [screen appendStringAtCursor:@"0123456789"];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalAppendTabAtCursor];
    XCTAssert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                            screen.width) isEqualToString:@"0123456789"]);

    // Tabbing over all nils replaces them with tab fillers and a tab character at the end
    screen = [self screenWithWidth:20 height:3];
    [screen terminalAppendTabAtCursor];
    screen_char_t *line = [screen getLineAtScreenIndex:0];
    for (int i = 0; i < 7; i++) {
        XCTAssert(line[i].code == TAB_FILLER);
    }
    XCTAssert(line[7].code == '\t');

    // If there is a single non-nil, then the cursor just moves.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:3 y:1];
    [screen appendStringAtCursor:@"x"];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalAppendTabAtCursor];
    XCTAssert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                            screen.width) isEqualToString:@"x"]);
    XCTAssert(screen.cursorX == 9);

    // No wrap-around
    screen = [self screenWithWidth:20 height:3];
    [screen terminalAppendTabAtCursor];  // 9
    [screen terminalAppendTabAtCursor];  // 15
    [screen terminalAppendTabAtCursor];  // 19
    XCTAssert(screen.cursorX == 20);
    XCTAssert(screen.cursorY == 1);

    // Test backtab (it's simple, no wraparound)
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalAppendTabAtCursor];
    [screen terminalAppendTabAtCursor];
    XCTAssert(screen.cursorX == 17);
    [screen terminalBackTab:1];
    XCTAssert(screen.cursorX == 9);
    [screen terminalBackTab:1];
    XCTAssert(screen.cursorX == 1);
    [screen terminalBackTab:1];
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 2);

    // backtab should (but doesn't yet) respect vsplits.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:10 rightMargin:19];
    [screen terminalMoveCursorToX:11 y:1];
    [screen terminalBackTab:1];
    ITERM_TEST_KNOWN_BUG(screen.cursorX == 11, screen.cursorX == 9);
}

- (void)testMoveCursor {
    // When not in origin mode, scroll regions are ignored
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:5 rightMargin:15];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    [screen terminalMoveCursorToX:1 y:1];
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 1);
    [screen terminalMoveCursorToX:100 y:100];
    XCTAssert(screen.cursorX == 21);
    XCTAssert(screen.cursorY == 20);

    // In origin mode, coord is relative to origin and cursor is forced inside scroll region
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalMoveCursorToX:1 y:1];
    XCTAssert(screen.cursorX == 6);
    XCTAssert(screen.cursorY == 6);

    [screen terminalMoveCursorToX:100 y:100];
    XCTAssert(screen.cursorX == 16);
    XCTAssert(screen.cursorY == 16);
}

- (void)testSaveAndRestoreCursorAndCharset {
    // Save then restore
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalMoveCursorToX:4 y:5];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [terminal_ saveCursor];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    [screen terminalSetCharset:3 toLineDrawingMode:NO];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);

    [terminal_ restoreCursor];

    XCTAssert(screen.cursorX == 4);
    XCTAssert(screen.cursorY == 5);
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:3 toLineDrawingMode:NO];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Restore without saving. Should use default charsets and move cursor to origin.
    // Terminal doesn't do anything in this case, but xterm does what we do.
    screen = [self screenWithWidth:20 height:20];
    for (int i = 0; i < 4; i++) {
        [screen terminalSetCharset:i toLineDrawingMode:NO];
    }
    [screen terminalMoveCursorToX:5 y:5];
    [terminal_ restoreCursor];

    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 1);
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:3 toLineDrawingMode:NO];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testSetTopBottomScrollRegion {
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 1);
    [screen terminalMoveCursorToX:5 y:16];
    [screen terminalAppendString:@"Hello"];
    XCTAssert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:15],
                                            screen.width) isEqualToString:@"Hello"]);
    [screen terminalLineFeed];
    XCTAssert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:14],
                                            screen.width) isEqualToString:@"Hello"]);

    // When origin mode is on, cursor should move to top left of scroll region.
    screen = [self screenWithWidth:20 height:20];
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalSetScrollRegionTop:5 bottom:15];
    XCTAssert(screen.cursorX == 1);
    XCTAssert(screen.cursorY == 6);
    [screen terminalMoveCursorToX:2 y:2];
    XCTAssert(screen.cursorX == 2);
    XCTAssert(screen.cursorY == 7);

    // Now try with a vsplit, too.
    screen = [self screenWithWidth:20 height:20];
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:5 rightMargin:15];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    XCTAssert(screen.cursorX == 6);
    XCTAssert(screen.cursorY == 6);
    [screen terminalMoveCursorToX:2 y:2];
    XCTAssert(screen.cursorX == 7);
    XCTAssert(screen.cursorY == 7);
}

- (VT100Screen *)screenForEraseInDisplay {
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789\n"
               @".........."]);
    [screen terminalMoveCursorToX:5 y:2];  // over the 'o'
    return screen;
}

- (void)testEraseInDisplay {
    // NOTE: The char the cursor is on always gets erased

    // Before and after should clear screen and move all nonempty lines into history
    VT100Screen *screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789\n"
               @"..........\n"
               @"..........\n"
               @"..........\n"
               @".........."]);

    // Before only should erase from origin to cursor, inclusive.
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"..........\n"
               @".....pqrst\n"
               @"0123456789\n"
               @".........."]);

    // Same but with curosr in the right margin
    screen = [self screenForEraseInDisplay];
    [screen terminalMoveCursorToX:11 y:2];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"..........\n"
               @"..........\n"
               @"0123456789\n"
               @".........."]);

    // After only erases from cursor position inclusive to end of display
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmn......\n"
               @"..........\n"
               @".........."]);

    // Neither before nor after does nothing
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:NO afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789\n"
               @".........."]);
}

- (void)testEraseLine {
    // NOTE: The char the cursor is on always gets erased

    // Before and after should clear the whole line
    VT100Screen *screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:YES];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"..........\n"
               @"0123456789\n"
               @".........."]);

    // Before only should erase from start of line to cursor, inclusive.
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @".....pqrst\n"
               @"0123456789\n"
               @".........."]);

    // Same but with curosr in the right margin
    screen = [self screenForEraseInDisplay];
    [screen terminalMoveCursorToX:11 y:2];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"..........\n"
               @"0123456789\n"
               @".........."]);

    // After only erases from cursor position inclusive to end of line
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:NO afterCursor:YES];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmn......\n"
               @"0123456789\n"
               @".........."]);

    // Neither before nor after does nothing
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:NO afterCursor:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789\n"
               @".........."]);
}

- (void)testIndex {
    // We don't implement index separately from linefeed. As far as I can tell they are the same.
    // Both respect vsplits.

    // Test simple indexing
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalMoveCursorToX:1 y:3];
    [screen terminalLineFeed];
    [screen terminalLineFeed];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"klmnopqrst\n"
               @"0123456789\n"
               @"..........\n"
               @".........."]);


    // With vsplit and hsplit
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:5];
    [screen terminalMoveCursorToX:3 y:2];
    XCTAssert(screen.cursorY == 2);
    // top-left is c, bottom-right is p
    [screen terminalLineFeed];
    XCTAssert(screen.cursorY == 3);
    [screen terminalLineFeed];
    XCTAssert(screen.cursorY == 3);
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"kl2345qrst\n"
               @"01....6789\n"
               @".........."]);

    // Test simple reverse indexing
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalReverseIndex];
    XCTAssert(screen.cursorY == 1);
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789\n"
               @".........."]);

    [screen terminalReverseIndex];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"..........\n"
               @"abcdefghij\n"
               @"klmnopqrst\n"
               @"0123456789"]);


    // Reverse index with vsplit and hsplit
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:5];
    [screen terminalMoveCursorToX:3 y:3];
    // top-left is c, bottom-right is p
    XCTAssert(screen.cursorY == 3);
    [screen terminalReverseIndex];
    XCTAssert(screen.cursorY == 2);
    [screen terminalReverseIndex];
    XCTAssert(screen.cursorY == 2);
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcdefghij\n"
               @"kl....qrst\n"
               @"01mnop6789\n"
               @".........."]);
}

- (void)testResetPreservingPrompt {
    // Preserve prompt
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen terminalResetPreservingPrompt:YES];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"klm.......\n"
               @"..........\n"
               @"..........\n"
               @".........."]);

    // Don't preserve prompt
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen terminalResetPreservingPrompt:NO];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"..........\n"
               @"..........\n"
               @"..........\n"
               @".........."]);

    // Tab stops get reset
    screen = [self screenWithWidth:20 height:4];
    NSArray *defaultTabstops = @[ @8, @16, @19 ];
    NSArray *augmentedTabstops = @[ @3, @8, @16, @19 ];
    XCTAssert([[self tabStopsInScreen:screen] isEqualToArray:defaultTabstops]);

    [screen terminalMoveCursorToX:4 y:1];
    [screen terminalSetTabStopAtCursor];

    XCTAssert([[self tabStopsInScreen:screen] isEqualToArray:augmentedTabstops]);
    [screen terminalResetPreservingPrompt:YES];
    XCTAssert([[self tabStopsInScreen:screen] isEqualToArray:defaultTabstops]);

    // Saved cursor gets reset to origin
    screen = [self screenWithWidth:10 height:4];
    [terminal_ saveCursor];

    [screen terminalResetPreservingPrompt:YES];

    [terminal_ restoreCursor];

    // Charset flags get reset
    screen = [self screenWithWidth:10 height:4];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:2 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [screen terminalResetPreservingPrompt:YES];
    XCTAssert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Saved charset flags get restored, not reset blindly
    screen = [self screenWithWidth:10 height:4];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:2 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [terminal_ saveCursor];

    [screen terminalResetPreservingPrompt:YES];
    [terminal_ restoreCursor];

    XCTAssert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    // Cursor is made visible
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetCursorVisible:NO];
    XCTAssert(!cursorVisible_);
    [screen terminalResetPreservingPrompt:YES];
    XCTAssert(cursorVisible_);
}

- (void)testSetWidth {
    canResize_ = YES;
    isFullscreen_ = NO;
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    XCTAssert(newSize_.width == 6);
    XCTAssert(newSize_.height == 4);

    newSize_ = VT100GridSizeMake(0, 0);
    canResize_ = NO;
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    XCTAssert(newSize_.width == 0);
    XCTAssert(newSize_.height == 0);

    newSize_ = VT100GridSizeMake(0, 0);
    canResize_ = YES;
    isFullscreen_ = YES;
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    XCTAssert(newSize_.width == 0);
    XCTAssert(newSize_.height == 0);
}

- (void)testEraseCharactersAfterCursor {
    // Delete 0 chars, should do nothing
    VT100Screen *screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalEraseCharactersAfterCursor:0];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcdefghij+\n"
               @"klm.......!\n"
               @"..........!"]);

    // Delete 2 chars
    [screen terminalEraseCharactersAfterCursor:2];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd..ghij+\n"
               @"klm.......!\n"
               @"..........!"]);

    // Delete just to end of line, change eol hard to eol soft.
    [screen terminalEraseCharactersAfterCursor:6];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd......!\n"
               @"klm.......!\n"
               @"..........!"]);

    // Delete way more than fits on line
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalEraseCharactersAfterCursor:100];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd......!\n"
               @"klm.......!\n"
               @"..........!"]);

    // Break dwc before cursor
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcD-fghij+\n"
              @"klm.......!"];
    [screen terminalMoveCursorToX:5 y:1];  // '-'
    [screen terminalEraseCharactersAfterCursor:2];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abc...ghij+\n"
               @"klm.......!"]);

    // Break dwc after cursor
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdeF-hij+\n"
              @"klm.......!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalEraseCharactersAfterCursor:2];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd...hij+\n"
               @"klm.......!"]);

    // Break split dwc
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdefghi>>\n"
              @"J-klm.....!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalEraseCharactersAfterCursor:6];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd......!\n"
               @"J-klm.....!"]);
}

- (void)testSetTitle {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:20];

    // Should come back as joblessName test
    syncTitle_ = YES;
    [screen terminalSetWindowTitle:@"test"];
    XCTAssert([windowTitle_ isEqualToString:@"joblessName: test"]);

    // Should come back as just test2
    syncTitle_ = NO;
    [screen terminalSetWindowTitle:@"test2"];
    XCTAssert([windowTitle_ isEqualToString:@"test2"]);

    // Absolute cursor line number should be updated with nil directory.
    [dirlog_ removeAllObjects];
    [screen destructivelySetScreenWidth:10 height:10];
    [screen terminalMoveCursorToX:1 y:5];
    [screen terminalSetWindowTitle:@"test"];
    XCTAssert(dirlog_.count == 1);
    NSArray *entry = dirlog_[0];
    XCTAssert([entry[0] intValue] == 4);
    XCTAssert([entry[1] isKindOfClass:[NSNull class]]);

    // Add some scrollback
    for (int i = 0; i < 10; i++) {
        [screen terminalLineFeed];
    }
    [dirlog_ removeAllObjects];
    [screen terminalSetWindowTitle:@"test"];
    XCTAssert(dirlog_.count == 1);
    entry = dirlog_[0];
    XCTAssert([entry[0] intValue] == 14);
    XCTAssert([entry[1] isKindOfClass:[NSNull class]]);

    // Make sure scrollback overflow is included.
    for (int i = 0; i < 100; i++) {
        [screen terminalLineFeed];
    }
    [dirlog_ removeAllObjects];
    [screen terminalSetWindowTitle:@"test"];
    XCTAssert(dirlog_.count == 1);
    entry = dirlog_[0];
    XCTAssert([entry[0] intValue] == 29);  // 20 lines of scrollback + 10th line of display
    XCTAssert([entry[1] isKindOfClass:[NSNull class]]);

    // Test icon title, which is the same, but does not log the pwd.
    syncTitle_ = YES;
    [screen terminalSetIconTitle:@"test3"];
    XCTAssert([name_ isEqualToString:@"joblessName: test3"]);

    syncTitle_ = NO;
    [screen terminalSetIconTitle:@"test4"];
    XCTAssert([name_ isEqualToString:@"test4"]);
}

- (void)testInsertEmptyCharsAtCursor {
    // Insert 0 should do nothing
    VT100Screen *screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:0];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcdefghij+\n"
               @"klm.......!\n"
               @"..........!"]);

    // Base case: insert 1
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd.efghi+\n"
               @"klm.......!\n"
               @"..........!"]);

    // Insert 2
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:2];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd..efgh+\n"
               @"klm.......!\n"
               @"..........!"]);

    // Insert to end of line, breaking EOL_SOFT
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:6];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd......!\n"
               @"klm.......!\n"
               @"..........!"]);

    // Insert more than fits
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:100];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd......!\n"
               @"klm.......!\n"
               @"..........!"]);

    // Insert 1, breaking DWC_SKIP
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdefghi>>\n"
              @"J-k.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd.efghi+\n"
               @"J-k.......!\n"
               @"..........!"]);

    // Insert breaking DWC that would end at end of line
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdefghI-+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd.efgh.!\n"
               @"jkl.......!\n"
               @"..........!"]);

    // Insert breaking DWC at cursor, which is on left half of dwc
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdE-fghi+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:6 y:1];  // 'E'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd...fgh+\n"
               @"jkl.......!\n"
               @"..........!"]);

    // Insert breaking DWC at cursor, which is on right half of dwc
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcD-efghi+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // '-'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abc...efgh+\n"
               @"jkl.......!\n"
               @"..........!"]);

    // With vsplit
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:8];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd.efghj+\n"
               @"klm.......!\n"
               @"..........!"]);

    // There are a few more tests of insertChar in VT100GridTest, no sense duplicating them all here.
}

- (void)testInsertBlankLinesAfterCursor {
    // 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalInsertBlankLinesAfterCursor:0];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // insert 1 blank line, breaking eol_soft
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalInsertBlankLinesAfterCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd!\n"
               @"....!\n"
               @"efg.!\n"
               @"hij.!"]);

    // Insert outside scroll region does nothing
    screen = [self screenWithWidth:4 height:4];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalInsertBlankLinesAfterCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // Same but with vsplit
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:3];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalInsertBlankLinesAfterCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
}

- (void)testDeleteLinesAtCursor {
    // Deleting 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:0];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // Deleting 1
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd!\n"
               @"hij.!\n"
               @"....!\n"
               @"....!"]);

    // Outside region does nothing
    screen = [self screenWithWidth:4 height:4];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalDeleteLinesAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // Same but with vsplit
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:3];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalDeleteLinesAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // Delete one inside scroll region
    screen = [self screenWithWidth:4 height:5];
    [self appendLines:@[ @"abcdefg", @"hij", @"klm" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"klm.!\n"
               @"....!"]);
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalMoveCursorToX:2 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd!\n"
               @"hij.!\n"
               @"....!\n"
               @"klm.!\n"
               @"....!"]);
}

- (void)testTerminalSetPixelSize {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetPixelWidth:-1 height:-1];
    XCTAssert(newPixelSize_.width == 100);
    XCTAssert(newPixelSize_.height == 200);

    [screen terminalSetPixelWidth:0 height:0];
    XCTAssert(newPixelSize_.width == 1000);
    XCTAssert(newPixelSize_.height == 2000);

    [screen terminalSetPixelWidth:50 height:60];
    XCTAssert(newPixelSize_.width == 50);
    XCTAssert(newPixelSize_.height == 60);
}

- (void)testScrollUp {
    // Scroll by 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalScrollUp:0];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);

    // Scroll by 1
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalScrollUp:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!\n"
               @"....!"]);

    // Scroll by 2
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalScrollUp:2];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!\n"
               @"....!\n"
               @"....!"]);

    // Scroll with region
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"efg.!\n"
               @"hij.!\n"
               @"....!"]);
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalScrollUp:1];
    XCTAssert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
               @"abcd+\n"
               @"eij.!\n"
               @"h...!\n"
               @"....!"]);
}

#pragma mark - Regression tests

- (void)testPasting {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self sendEscapeCodes:@"^[]50;CopyToClipboard=general^GHello world^[]50;EndCopy^G"];
    XCTAssert([pasteboard_ isEqualToString:@"general"]);
    XCTAssert(!memcmp(pbData_.mutableBytes, "Hello world", strlen("Hello world")));
    XCTAssert(pasted_);
}

- (void)testCursorReporting {
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalMoveCursorToX:2 y:3];
    [self sendEscapeCodes:@"^[[6n"];

    NSString *s = [[[NSString alloc] initWithData:write_ encoding:NSUTF8StringEncoding] autorelease];
    XCTAssert([s isEqualToString:@"\033[3;2R"]);
}

- (void)testReportWindowSize {
    VT100Screen *screen = [self screenWithWidth:30 height:20];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self sendEscapeCodes:@"^[[18t"];

    NSString *s = [[[NSString alloc] initWithData:write_ encoding:NSUTF8StringEncoding] autorelease];
    XCTAssert([s isEqualToString:@"\033[8;20;30t"]);
}

- (void)testResizeNotes {
    // Put a note on the primary grid, switch to alt, resize width, swap back to primary. Note should
    // still be there.
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"....."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 2, 1)];  // fg
    [screen terminalShowAltBuffer];
    [screen setSize:VT100GridSizeMake(4, 4)];
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcd\n"
               @"efgh\n"
               @"ijkl\n"
               @"...."]);
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 1);
    XCTAssert(range.start.y == 1);
    XCTAssert(range.end.x == 3);
    XCTAssert(range.end.y == 1);
}

- (void)testResizeWithNoteOnLineOfNulls {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    XCTAssert([[screen compactLineDump] isEqualToString:
               @"abcde\n"
               @"fgh..\n"
               @"ijkl.\n"
               @"....."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 3, 2, 3)];  // First two chars on last line
    [screen setSize:VT100GridSizeMake(4, 4)];
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
    XCTAssert(notes.count == 0);
}

- (void)testResizeWithSelectionOfJustNullsInAltScreen {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = self;
    [screen terminalShowAltBuffer];
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    XCTAssert([selection_ hasSelection]);
    [screen setSize:VT100GridSizeMake(4, 4)];
    XCTAssert(![selection_ hasSelection]);
}

- (void)testResizeWithSelectionOfJustNullsInMainScreen {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = self;
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    XCTAssert([selection_ hasSelection]);
    [screen setSize:VT100GridSizeMake(4, 4)];
    XCTAssert(![selection_ hasSelection]);
}

- (void)testResizeNoteInPrimaryWhileInAltAndSomeHistory {
    // Put a note on the primary grid, switch to alt, resize width, swap back to primary. Note should
    // still be there.
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"   // history
               @"fgh..\n"   // history
               @"ijkl.\n"
               @"hello\n"
               @" worl\n"
               @"d...."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 2, 2)];  // ij
    [screen terminalShowAltBuffer];
    [screen setSize:VT100GridSizeMake(4, 4)];
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcd\n"  // history
               @"efgh\n"  // history
               @"ijkl\n"
               @"hell\n"
               @"o wo\n"
               @"rld."]);
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 0);
    XCTAssert(range.start.y == 2);
    XCTAssert(range.end.x == 2);
    XCTAssert(range.end.y == 2);
}

- (void)testResizeNoteInPrimaryWhileInAltAndPushingSomePrimaryIncludingWholeNoteIntoHistory {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"   // history
               @"fgh..\n"   // history
               @"ijkl.\n"
               @"hello\n"
               @" worl\n"
               @"d...."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 2, 2)];  // ij
    [screen terminalShowAltBuffer];
    [screen setSize:VT100GridSizeMake(3, 4)];
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abc\n"
               @"def\n"
               @"gh.\n"
               @"ijk\n"
               @"l..\n"
               @"hel\n"
               @"lo \n"
               @"wor\n"
               @"ld."]);
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 0);
    XCTAssert(range.start.y == 3);
    XCTAssert(range.end.x == 2);
    XCTAssert(range.end.y == 3);
}

- (void)testResizeNoteInPrimaryWhileInAltAndPushingSomePrimaryIncludingPartOfNoteIntoHistory {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"   // history
               @"fgh..\n"   // history
               @"ijkl.\n"
               @"hello\n"
               @" worl\n"
               @"d...."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 5, 3)];  // ijkl\nhello
    [screen terminalShowAltBuffer];
    [screen setSize:VT100GridSizeMake(3, 4)];
    [screen terminalShowPrimaryBuffer];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abc\n"
               @"def\n"
               @"gh.\n"
               @"ijk\n"
               @"l..\n"
               @"hel\n"
               @"lo \n"
               @"wor\n"
               @"ld."]);
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 0);
    XCTAssert(range.start.y == 3);
    XCTAssert(range.end.x == 2);
    XCTAssert(range.end.y == 6);
}

- (void)testNoteTruncatedOnSwitchingToAlt {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"   // history
               @"fgh..\n"   // history
               @"ijkl.\n"
               @"hello\n"
               @" worl\n"
               @"d...."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 5, 3)];  // fgh\nijkl\nhello
    [screen terminalShowAltBuffer];
    [screen terminalShowPrimaryBuffer];

    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 0);
    XCTAssert(range.start.y == 1);
    XCTAssert(range.end.x == 0);
    XCTAssert(range.end.y == 2);
}

- (void)testResizeNoteInAlternateThatGetsTruncatedByShrinkage {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abcde\n"   // history
               @"fgh..\n"   // history
               @"ijkl.\n"
               @"hello\n"
               @" worl\n"
               @"d...."]);
    [self showAltAndUppercase:screen];
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 5, 3)];  // fgh\nIJKL\nHELLO
    [screen setSize:VT100GridSizeMake(3, 4)];
    XCTAssert([[screen compactLineDumpWithHistory] isEqualToString:
               @"abc\n"
               @"def\n"
               @"gh.\n"
               @"ijk\n"
               @"l..\n"  // last line of history (all pulled from primary)
               @"HEL\n"
               @"LO \n"
               @"WOR\n"
               @"LD."]);
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 3, 6)];
    XCTAssert(notes.count == 1);
    XCTAssert(notes[0] == note);
    VT100GridCoordRange range = [screen coordRangeOfNote:note];
    XCTAssert(range.start.x == 2);  // fgh\nijkl\nHELLO
    XCTAssert(range.start.y == 1);
    XCTAssert(range.end.x == 2);
    XCTAssert(range.end.y == 6);
}

- (void)testEmptyLineRestoresBackgroundColor {
    LineBuffer *lineBuffer = [[[LineBuffer alloc] init] autorelease];
    screen_char_t line[1];
    screen_char_t continuation;
    continuation.backgroundColor = 5;
    [lineBuffer appendLine:line length:0 partial:NO width:80 timestamp:0 continuation:continuation];

    screen_char_t buffer[3];
    [lineBuffer copyLineToBuffer:buffer width:3 lineNum:0 continuation:&continuation];

    XCTAssert(buffer[0].backgroundColor == 5);
    XCTAssert(buffer[1].backgroundColor == 5);
    XCTAssert(buffer[2].backgroundColor == 5);
}

// Issue 4261
- (void)testRemoteHostOnTrailingEmptyLineNotLostDuringResize {
    // Append some text, then a newline, then set a remote host, then resize. Ensure the
    // remote host is still there.
    
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[ @"Hi" ] toScreen:screen];
    
    [screen terminalSetRemoteHost:@"example.com"];
    [screen setSize:VT100GridSizeMake(6, 4)];
    VT100RemoteHost *remoteHost = [screen remoteHostOnLine:2];
    
    XCTAssertEqualObjects([remoteHost hostname], @"example.com");
}

#pragma mark - CSI Tests

- (void)testCSI_CUD {
    // Cursor Down Ps Times (default = 1) (CUD)
    // This control function moves the cursor down a specified number of lines in the same column. The
    // cursor stops at the bottom margin. If the cursor is already below the bottom margin, then the
    // cursor stops at the bottom line.

    // Test basic usage, default parameter.
    VT100Screen *screen = [self screenWithWidth:3 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[B"];
    XCTAssert(screen.currentGrid.cursorX == 1);
    XCTAssert(screen.currentGrid.cursorY == 2);

    // Basic usage, explicit parameter.
    screen = [self screenWithWidth:3 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[2B"];
    XCTAssert(screen.currentGrid.cursorX == 1);
    XCTAssert(screen.currentGrid.cursorY == 3);

    // Start inside scroll region - should stop at bottom margin
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:2 bottom:4];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:2];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    XCTAssert(screen.currentGrid.cursorX == 1);
    XCTAssert(screen.currentGrid.cursorY == 4);

    // Start above scroll region - should stop at bottom margin
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:0];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    XCTAssert(screen.currentGrid.cursorX == 1);
    XCTAssert(screen.currentGrid.cursorY == 3);

    // Start below bottom margin - should stop at bottom of screen.
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:3];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    XCTAssert(screen.currentGrid.cursorX == 1);
    XCTAssert(screen.currentGrid.cursorY == 4);
}

- (void)testCSI_CUF {
    // Cursor Forward Ps Times (default = 1) (CUF)
    // This control function moves the cursor to the right by a specified number of columns. The
    // cursor stops at the right border of the page.

    // Test basic usage, default parameter.
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[C"];
    XCTAssert(screen.currentGrid.cursorX == 2);
    XCTAssert(screen.currentGrid.cursorY == 1);

    // Test basic usage, explicit parameter.
    screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[2C"];
    XCTAssert(screen.currentGrid.cursorX == 3);
    XCTAssert(screen.currentGrid.cursorY == 1);

    // Test stops on right border.
    screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    XCTAssert(screen.currentGrid.cursorX == 4);
    XCTAssert(screen.currentGrid.cursorY == 1);

    // Test respects region when starting inside it
    screen = [self screenWithWidth:5 height:5];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:3];
    [screen.currentGrid setCursorX:2];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    XCTAssert(screen.currentGrid.cursorX == 3);
    XCTAssert(screen.currentGrid.cursorY == 1);

    // Test does not respect region when starting outside it
    screen = [self screenWithWidth:5 height:5];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen.currentGrid setCursorX:3];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    XCTAssert(screen.currentGrid.cursorX == 4);
    XCTAssert(screen.currentGrid.cursorY == 1);
}

/*

 { 0, 0, 'C', VT100CSI_CUF, 1, -1 },
 { 0, 0, 'D', VT100CSI_CUB, 1, -1 },
 { 0, 0, 'E', VT100CSI_CNL, 1, -1 },
 { 0, 0, 'F', VT100CSI_CPL, 1, -1 },
 { 0, 0, 'G', ANSICSI_CHA, 1, -1 },
 { 0, 0, 'H', VT100CSI_CUP, 1, 1 },
 // I not supported (Cursor Forward Tabulation P s tab stops (default = 1) (CHT))
 { 0, 0, 'J', VT100CSI_ED, 0, -1 },
 // ?J not supported (Erase in Display (DECSED))
 { 0, 0, 'K', VT100CSI_EL, 0, -1 },
 // ?K not supported ((Erase in Line (DECSEL))
 { 0, 0, 'L', XTERMCC_INSLN, 1, -1 },
 { 0, 0, 'M', XTERMCC_DELLN, 1, -1 },
 { 0, 0, 'P', XTERMCC_DELCH, 1, -1 },
 { 0, 0, 'S', XTERMCC_SU, 1, -1 },
 // ?Pi;Pa;PvS not supported (Sixel/ReGIS)
 { 0, 0, 'T', XTERMCC_SD, 1, -1 },
 // Ps;Ps;Ps;Ps;PsT not supported (Initiate highlight mouse tracking)
 { 0, 0, 'X', ANSICSI_ECH, 1, -1 },
 { 0, 0, 'Z', ANSICSI_CBT, 1, -1 },
 // ` not supported (Character Position Absolute [column] (default = [row,1]) (HPA))
 // a not supported (Character Position Relative [columns] (default = [row,col+1]) (HPR))
 // b not supported (Repeat the preceding graphic character P s times (REP))
 { 0, 0, 'c', VT100CSI_DA, 0, -1 },
 { '>', 0, 'c', VT100CSI_DA2, 0, -1 },
 { 0, 0, 'd', ANSICSI_VPA, 1, -1 },
 { 0, 0, 'e', ANSICSI_VPR, 1, -1 },
 { 0, 0, 'f', VT100CSI_HVP, 1, 1 },
 { 0, 0, 'g', VT100CSI_TBC, 0, -1 },
 { 0, 0, 'h', VT100CSI_SM, -1, -1 },
 { '?', 0, 'h', VT100CSI_DECSET, -1, -1 },
 { 0, 0, 'i', ANSICSI_PRINT, 0, -1 },
 // ?i not supported (Media Copy (MC, DEC-specific))
 { 0, 0, 'l', VT100CSI_RM, -1, -1 },
 { '?', 0, 'l', VT100CSI_DECRST, -1, -1 },
 { 0, 0, 'm', VT100CSI_SGR, 0, -1 },
 { '>', 0, 'm', VT100CSI_SET_MODIFIERS, -1, -1 },
 { 0, 0, 'n', VT100CSI_DSR, 0, -1 },
 { '>', 0, 'n', VT100CSI_RESET_MODIFIERS, -1, -1 },
 { '?', 0, 'n', VT100CSI_DECDSR, 0, -1 },
 // >p not supported (Set resource value pointerMode. This is used by xterm to decide whether
 // to hide the pointer cursor as the user types.)
 { '!', 0, 'p', VT100CSI_DECSTR, -1, -1 },
 // $p not supported (Request ANSI mode (DECRQM))
 // ?$p not supported (Request DEC private mode (DECRQM))
 // "p not supported (Set conformance level (DECSCL))
 // q not supported (Load LEDs (DECLL))
 { 0, ' ', 'q', VT100CSI_DECSCUSR, 0, -1 },
 // "q not supported (Select character protection attribute (DECSCA))
 { 0, 0, 'r', VT100CSI_DECSTBM, -1, -1 },
 // $r not supported (Change Attributes in Rectangular Area (DECCARA))
 { 0, 0, 's', VT100CSI_DECSLRM_OR_ANSICSI_SCP, -1, -1 },
 // ?s not supported (Save DEC Private Mode Values)
 // t tested in -testWindowManipulationCodes
 // $t not supported (Reverse Attributes in Rectangular Area (DECRARA))
 // >t not supported (Set one or more features of the title modes)
 // SP t not supported (Set warning-bell volume (DECSWBV, VT520))
 { 0, 0, 'u', ANSICSI_RCP, -1, -1 },
 
 { 1, XTERMCC_DEICONIFY },
 { 2, XTERMCC_ICONIFY },
 { 3, XTERMCC_WINDOWPOS },
 { 4, XTERMCC_WINDOWSIZE_PIXEL },
 { 5, XTERMCC_RAISE },
 { 6, XTERMCC_LOWER },
 // 7 is not supported (Refresh the window)
 { 8, XTERMCC_WINDOWSIZE },
 // 9 is not supported (Various maximize window actions)
 // 10 is not supported (Various full-screen actions)
 { 11, XTERMCC_REPORT_WIN_STATE },
 // 12 is not defined
 { 13, XTERMCC_REPORT_WIN_POS },
 { 14, XTERMCC_REPORT_WIN_PIX_SIZE },
 // 15, 16, and 17 are not defined
 { 18, XTERMCC_REPORT_WIN_SIZE },
 { 19, XTERMCC_REPORT_SCREEN_SIZE },
 { 20, XTERMCC_REPORT_ICON_TITLE },
 { 21, XTERMCC_REPORT_WIN_TITLE },
 { 22, XTERMCC_PUSH_TITLE },
 { 23, XTERMCC_POP_TITLE },
 */

@end
