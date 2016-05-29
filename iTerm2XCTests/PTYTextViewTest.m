#import "iTermColorMap.h"
#import "iTermSelection.h"
#import "iTermTextDrawingHelper.h"
#import "NSColor+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "SessionView.h"
#import "VT100LineInfo.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermPreferences.h"
#import "iTermSelectorSwizzler.h"
#import <objc/runtime.h>
#import <XCTest/XCTest.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#define NUM_DIFF_BUCKETS 10
typedef struct {
    CGFloat variance;
    CGFloat maxDiff;
    int buckets[NUM_DIFF_BUCKETS];
} iTermDiffStats;

@interface PTYTextViewTest : XCTestCase
@end

@interface iTermFakeSessionForPTYTextViewTest : PTYSession
@end

@implementation iTermFakeSessionForPTYTextViewTest

- (BOOL)textViewWindowUsesTransparency {
    return YES;
}

@end

@interface PTYTextViewTest ()<PTYTextViewDelegate, PTYTextViewDataSource>
@end

@interface PTYTextView (Internal)
- (void)paste:(id)sender;
- (void)pasteOptions:(id)sender;
- (void)pasteSelection:(id)sender;
- (void)pasteBase64Encoded:(id)sender;
@end

@implementation PTYTextViewTest {
    PTYTextView *_textView;
    iTermColorMap *_colorMap;
    NSString *_pasteboardString;
    NSMutableDictionary *_methodsCalled;
    screen_char_t _buffer[4];
}

- (void)setUp {
    _colorMap = [[iTermColorMap alloc] init];
    _textView = [[PTYTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) colorMap:_colorMap];
    _textView.delegate = self;
    _textView.dataSource = self;
    _methodsCalled = [[NSMutableDictionary alloc] init];
}

- (void)tearDown {
    [_textView release];
    [_colorMap release];
    [_methodsCalled release];
}

- (void)setLineDirtyAtY:(int)y {
}

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    return nil;
}

- (BOOL)isRestartable {
    return NO;
}

- (void)setRangeOfCharsAnimated:(NSRange)range onLine:(int)line {
}

- (NSIndexSet *)animatedLines {
    return nil;
}

- (void)resetAnimatedLines {
}

- (void)resetDirty {
}

- (void)textViewSelectPreviousTab {
}

- (void)selectPaneRightInCurrentTerminal {
}

- (void)textViewSelectPreviousPane {
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    return VT100GridRangeMake(0, 0);
}

- (PTYScroller *)textViewVerticalScroller {
    return nil;
}

- (BOOL)textViewHasCoprocess {
    return NO;
}

- (void)textViewWillNeedUpdateForBlink {
}

- (BOOL)textViewWindowUsesTransparency {
    return NO;
}

- (BOOL)textViewShouldShowMarkIndicators {
    return YES;
}

- (int)optionKey {
    return 2;
}

- (void)textViewSwapPane {
}

- (BOOL)textViewIsMaximized {
    return NO;
}

- (void)textViewMovePane {
}

- (NSStringEncoding)textViewEncoding {
    return NSUTF8StringEncoding;
}

- (void)selectPaneLeftInCurrentTerminal {
}

- (NSDictionary *)textViewVariables {
    return nil;
}

- (void)setCharDirtyAtCursorX:(int)x Y:(int)y {
}

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line {
    return nil;
}

- (void)launchProfileInCurrentTerminal:(NSDictionary *)profile withURL:(NSString *)url {
}

- (void)textViewSplitVertically:(BOOL)vertically withProfileGuid:(NSString *)guid {
}

- (BOOL)isPasting {
    return NO;
}

- (void)launchCoprocessWithCommand:(NSString *)command {
}

- (BOOL)textViewDelegateHandlesAllKeystrokes {
    return NO;
}

- (screen_char_t *)getLineAtScreenIndex:(int)theIndex {
    return nil;
}

- (BOOL)setUseSavedGridIfAvailable:(BOOL)use {
    return NO;
}

- (void)textViewInvalidateRestorableState {
}

- (BOOL)textViewIsZoomedIn {
    return NO;
}

- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(VT100ScreenMark *)mark {
    return VT100GridCoordRangeMake(0, 0, 0, 0);
}

- (void)textViewToggleBroadcastingInput {
}

- (void)textViewDrawBackgroundImageInView:(NSView *)view viewRect:(NSRect)rect blendDefaultBackground:(BOOL)blendDefaultBackground {
}

- (BOOL)textViewAmbiguousWidthCharsAreDoubleWidth {
    return NO;
}

- (void)insertText:(NSString *)string {
}

- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event {
    return NO;
}

- (void)sendEscapeSequence:(NSString *)text {
}

- (VT100Terminal *)terminal {
    return nil;
}

- (void)textViewSelectNextPane {
}

- (void)textViewPostTabContentsChangedNotification {
}

- (NSString *)textViewCurrentWorkingDirectory {
    return nil;
}

- (BOOL)textViewCanSelectOutputOfLastCommand {
    return NO;
}

- (BOOL)textViewCanSelectCurrentCommand {
    return NO;
}

- (void)textViewCloseWithConfirmation {
}

- (BOOL)textViewTabHasMaximizedPanel {
    return NO;
}

- (BOOL)textViewSessionIsBroadcastingInput {
    return NO;
}

- (VT100GridCoordRange)coordRangeOfNote:(PTYNoteViewController *)note {
    return VT100GridCoordRangeMake(0, 0, 0, 0);
}

- (BOOL)showingAlternateScreen {
    return NO;
}

- (BOOL)textViewShouldPlaceCursorAt:(VT100GridCoord)coord verticalOk:(BOOL *)verticalOk {
    return YES;
}

- (NSColor *)textViewBadgeColor {
    return nil;
}

- (BOOL)textViewReportMouseEvent:(NSEventType)eventType
                       modifiers:(NSUInteger)modifiers
                          button:(MouseButtonNumber)button
                      coordinate:(VT100GridCoord)coord
                          deltaY:(CGFloat)deltaY {
    return NO;
}

- (BOOL)textViewShouldDrawFilledInCursor {
    return YES;
}

- (void)pasteString:(NSString *)aString {
}

- (int)scrollbackOverflow {
    return 0;
}

- (void)textViewEditSession {
}

- (screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer {
    return nil;
}

- (void)clearBuffer {
}

- (void)textViewDidBecomeFirstResponder {
}

- (NSString *)debugString {
    return nil;
}

- (BOOL)shouldSendContentsChangedNotification {
    return NO;
}

- (void)sendHexCode:(NSString *)codes {
}

- (BOOL)textViewIsActiveSession {
    return YES;
}

- (NSArray *)charactersWithNotesOnLine:(int)line {
    return nil;
}

- (void)textViewFontDidChange {
}

- (VT100RemoteHost *)remoteHostOnLine:(int)line {
    return nil;
}

- (int)rightOptionKey {
    return 1;
}

- (NSArray *)notesInRange:(VT100GridCoordRange)range {
    return nil;
}

- (void)saveFindContextAbsPos {
}

- (void)textViewSelectPreviousWindow {
}

- (void)resetAllDirty {
}

- (void)textViewCreateTabWithProfileGuid:(NSString *)guid {
}

- (int)lineNumberOfMarkAfterLine:(int)line {
    return line + 1;
}

- (int)lineNumberOfMarkBeforeLine:(int)line {
    return line - 1;
}

- (VT100ScreenMark *)markOnLine:(int)line {
    return nil;
}

- (PTYScrollView *)scrollview {
    return nil;
}

- (void)addNote:(PTYNoteViewController *)note inRange:(VT100GridCoordRange)range {
}

- (void)startDownloadOverSCP:(SCPPath *)path {
}

- (void)selectPaneAboveInCurrentTerminal {
}

- (void)saveToDvr {
}

- (void)removeInaccessibleNotes {
}

- (VT100GridAbsCoordRange)textViewRangeOfLastCommandOutput {
    return VT100GridAbsCoordRangeMake(0, 0, 0, 0);
}

- (VT100GridAbsCoordRange)textViewRangeOfCurrentCommand {
    return VT100GridAbsCoordRangeMake(0, 0, 0, 0);
}

- (void)textViewCreateWindowWithProfileGuid:(NSString *)guid {
}

- (BOOL)textViewSuppressingAllOutput {
    return NO;
}

- (void)textViewRestartWithConfirmation {
}

- (void)setFindString:(NSString *)aString forwardDirection:(BOOL)direction ignoringCase:(BOOL)ignoreCase regex:(BOOL)regex startingAtX:(int)x startingAtY:(int)y withOffset:(int)offsetof inContext:(FindContext *)context multipleResults:(BOOL)multipleResults {
}

- (PTYTask *)shell {
    return nil;
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu {
}

- (void)resetScrollbackOverflow {
}

- (void)selectPaneBelowInCurrentTerminal {
}

- (void)writeTask:(NSData *)data {
}

- (void)textViewSelectNextWindow {
}

- (void)keyDown:(NSEvent *)event {
}

- (long long)totalScrollbackOverflow {
    return 0;
}

- (int)cursorX {
    return 1;
}

- (int)cursorY {
    return 1;
}

- (FindContext *)findContext {
    return nil;
}

- (long long)absoluteLineNumberOfCursor {
    return 0;
}

- (BOOL)textViewHasBackgroundImage {
    return NO;
}

- (void)textViewSelectNextTab {
}

- (BOOL)textViewUseHFSPlusMapping {
    return NO;
}

- (BOOL)xtermMouseReporting {
    return NO;
}

- (void)textViewBeginDrag {
}

- (NSMenu *)menuForEvent:event {
    return nil;
}

- (NSString *)workingDirectoryOnLine:(int)line {
    return nil;
}

- (void)queueKeyDown:(NSEvent *)event {
}

- (void)uploadFiles:(NSArray *)localFilenames toPath:(SCPPath *)destinationPath {
}

- (void)sendText:(NSString *)text {
}

- (BOOL)alertOnNextMark {
    return NO;
}

- (NSDate *)timestampForLine:(int)y {
    return nil;
}

- (int)numberOfScrollbackLines {
    return 0;
}

- (NSColor *)textViewCursorGuideColor {
    return nil;
}

- (void)textViewToggleAnnotations {
}

- (BOOL)textViewShouldAcceptKeyDownEvent:(NSEvent *)event {
    return YES;
}

- (void)textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:(BOOL)trying {
}

- (void)textViewResizeFrameIfNeeded {
}

- (BOOL)continueFindAllResults:(NSMutableArray *)results inContext:(FindContext *)context {
    return NO;
}

- (BOOL)isAllDirty {
    return NO;
}
- (BOOL)isDirtyAtX:(int)x Y:(int)y {
    return NO;
}


- (void)invokeMenuItemWithSelector:(SEL)selector {
    [self invokeMenuItemWithSelector:selector tag:0];
}

- (void)invokeMenuItemWithSelector:(SEL)selector tag:(NSInteger)tag {
    NSMenuItem *fakeMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Fake Menu Item"
                                                           action:selector
                                                    keyEquivalent:@""] autorelease];
    [fakeMenuItem setTag:tag];
    XCTAssert([_textView validateMenuItem:fakeMenuItem]);
    [_textView performSelector:selector withObject:fakeMenuItem];
}

- (void)registerCall:(SEL)selector {
    [self registerCall:selector argument:nil];
}

- (void)registerCall:(SEL)selector argument:(NSObject *)argument {
    NSString *name = NSStringFromSelector(selector);
    if (argument) {
        name = [name stringByAppendingString:[argument description]];
    }
    NSNumber *number = _methodsCalled[name];
    if (!number) {
        number = @0;
    }
    _methodsCalled[name] = @(number.intValue + 1);
}

- (void)testPaste {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:@"test" forType:NSPasteboardTypeString];
    [self invokeMenuItemWithSelector:@selector(paste:)];
    XCTAssert([_methodsCalled[@"paste:"] intValue] == 1);
}

- (void)testPasteOptions {
    [self invokeMenuItemWithSelector:@selector(pasteOptions:)];
    XCTAssert([_methodsCalled[@"pasteOptions:"] intValue] == 1);
}

- (void)testPasteSelection {
    [_textView selectAll:nil];
    [self invokeMenuItemWithSelector:@selector(pasteSelection:) tag:1];
    XCTAssert([_methodsCalled[@"textViewPasteFromSessionWithMostRecentSelection:1"] intValue] == 1);
}

- (PTYSession *)sessionWithProfileOverrides:(NSDictionary *)profileOverrides
                                       size:(VT100GridSize)size {
    PTYSession *session = [[[PTYSession alloc] init] autorelease];
    NSString* plistFile = [[NSBundle bundleForClass:[self class]]
                           pathForResource:@"DefaultBookmark"
                           ofType:@"plist"];
    NSMutableDictionary* profile = [NSMutableDictionary dictionaryWithContentsOfFile:plistFile];
    for (NSString *key in profileOverrides) {
        profile[key] = profileOverrides[key];
    }

    [session setProfile:profile];

    XCTAssert([session setScreenSize:NSMakeRect(0, 0, 200, 200) parent:nil]);
    [session setPreferencesFromAddressBookEntry:profile];
    [session setSize:size];
    NSRect theFrame = NSMakeRect(0,
                                 0,
                                 size.width * session.textview.charWidth + MARGIN * 2,
                                 size.height * session.textview.lineHeight + VMARGIN * 2);
    session.view.frame = theFrame;
    [session loadInitialColorTable];
    [session setBookmarkName:profile[KEY_NAME]];
    [session setName:profile[KEY_NAME]];
    [session setDefaultName:profile[KEY_NAME]];
    return session;
}

- (NSImage *)imageForInput:(NSString *)input
                        hook:(void (^)(PTYTextView *))hook
          profileOverrides:(NSDictionary *)profileOverrides
                      size:(VT100GridSize)size {
    PTYSession *session = [self sessionWithProfileOverrides:profileOverrides size:size];

    [session synchronousReadTask:input];
    if (hook) {
        hook(session.textview);
    }
    return [session.view snapshot];
}

- (NSString *)pathForGoldenWithName:(NSString *)name {
    return [self pathForTestResourceNamed:[self shortNameForGolden:name]];
}

- (NSString *)shortNameForGolden:(NSString *)name {
    NSString *domain = @"";
    if ([[[iTermApplication sharedApplication] delegate] isRunningOnTravis]) {
        // Travis runs in a VM that renders text a little differently than a retina device running
        // the app in low-res mode.
        domain = @"travis-";
    } else if ([[NSScreen mainScreen] backingScaleFactor] == 1.0) {
        domain = @"nonretina-";
    }
    return [NSString stringWithFormat:@"PTYTextViewTest-golden-%@%@.png", domain, name];
}

- (NSString *)pathForTestResourceNamed:(NSString *)name {
    NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    return [resourcePath stringByAppendingPathComponent:name];
}

// Minor differences in anti-aliasing on different machines (even running the same version of the
// OS) cause false failures with golden images, so we'll ignore tiny differences in brightness.
- (BOOL)image:(NSData *)image1 approximatelyEqualToImage:(NSData *)image2 stats:(iTermDiffStats *)stats {
    if (image1.length != image2.length) {
        return NO;
    }
    unsigned char *bytes1 = (unsigned char *)image1.bytes;
    unsigned char *bytes2 = (unsigned char *)image2.bytes;
    const CGFloat threshold = 0.1;
    CGFloat sumOfSquares = 0;
    CGFloat maxDiff = 0;
    CGFloat sum = 0;
    for (int j = 0; j < NUM_DIFF_BUCKETS; j++) {
        stats->buckets[j] = 0;
    }
    for (int i = 0; i < image1.length; i+= 4) {
        CGFloat brightness1 = PerceivedBrightness(bytes1[i + 0] / 255.0, bytes1[i + 1] / 255.0, bytes1[i + 2] / 255.0);
        CGFloat brightness2 = PerceivedBrightness(bytes2[i + 0] / 255.0, bytes2[i + 1] / 255.0, bytes2[i + 2] / 255.0);
        CGFloat diff = fabs(brightness1 - brightness2);
        sumOfSquares += diff*diff;
        sum += diff;
        maxDiff = MAX(maxDiff, diff);
        if (diff > 0) {
            int bucket = MIN((NUM_DIFF_BUCKETS - 1), MAX(0, diff * NUM_DIFF_BUCKETS));
            stats->buckets[bucket]++;
        }
    }
    CGFloat N = image1.length / 4;
    stats->variance = sumOfSquares/N - (sum/N)*(sum/N);
    stats->maxDiff = maxDiff;
    return maxDiff < threshold;
}

- (NSString *)decilesInStats:(iTermDiffStats)stats {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < NUM_DIFF_BUCKETS; i++) {
        [array addObject:[@(stats.buckets[i]) description]];
    }
    return [array componentsJoinedByString:@", "];
}

- (void)doGoldenTestForInput:(NSString *)input
                        name:(NSString *)name
                        hook:(void (^)(PTYTextView *))hook
            profileOverrides:(NSDictionary *)profileOverrides
                createGolden:(BOOL)createGolden
                        size:(VT100GridSize)size {
    NSImage *actual = [self imageForInput:input
                                     hook:^(PTYTextView *textView) {
                                         textView.thinStrokes = iTermThinStrokesSettingNever;
                                         if (hook) {
                                             hook(textView);
                                         }
                                     }
                         profileOverrides:profileOverrides
                                     size:size];
    NSString *goldenName = [self pathForGoldenWithName:name];
    if (createGolden) {
        NSData *pngData = [actual dataForFileOfType:NSPNGFileType];
        [pngData writeToFile:goldenName atomically:NO];
        NSLog(@"Wrote to golden file at %@", goldenName);
    } else {
        NSImage *golden = [[NSImage alloc] initWithContentsOfFile:goldenName];
        if (!golden) {
            golden = [NSImage imageNamed:[self shortNameForGolden:name]];
        }
        XCTAssertNotNil(golden, @"Failed to load golden image with name %@, short name %@", goldenName, [self shortNameForGolden:name]);
        NSData *goldenData = [golden rawPixelsInRGBColorSpace];
        XCTAssertNotNil(goldenData, @"Failed to extract pixels from golden image");
        NSData *actualData = [actual rawPixelsInRGBColorSpace];
        XCTAssertEqual(goldenData.length, actualData.length, @"Different number of pixels between %@ and %@", golden, actual);
        iTermDiffStats stats = { 0 };
        BOOL ok = [self image:goldenData approximatelyEqualToImage:actualData stats:&stats];
        if (ok) {
            NSLog(@"Tests “%@” ok with variance: %f. Max diff: %f", name, stats.variance, stats.maxDiff);
        } else {
            NSString *failPath = [NSString stringWithFormat:@"/tmp/failed-%@.png", name];
            [[actual dataForFileOfType:NSPNGFileType] writeToFile:failPath atomically:NO];
            NSLog(@"Test “%@” about to fail.\nActual output in %@.\nExpected output in %@",
                  name, failPath, goldenName);
        }
        XCTAssert(ok, @"variance=%f maxdiff=%f deciles=%@", stats.variance, stats.maxDiff, [self decilesInStats:stats]);
    }
}

- (NSString *)sgrSequence:(int)n {
    return [NSString stringWithFormat:@"%c[%dm", VT100CC_ESC, n];
}

- (NSString *)sgrSequenceWithSubparams:(NSArray *)values {
    return [NSString stringWithFormat:@"%c[%@m",
               VT100CC_ESC, [values componentsJoinedByString:@":"]];
}

#pragma mark - Drawing Tests

// Background color should be selected but grayed because window is not focused.
- (void)testCharacterSelection {
    [self doGoldenTestForInput:@"abcd"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100GridWindowedRange range =
                                  VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 0, 3, 0),
                                                             0, 0);
                              iTermSubSelection *subSelection =
                                  [iTermSubSelection subSelectionWithRange:range
                                                                      mode:kiTermSelectionModeCharacter];
                              [textView.selection addSubSelection:subSelection];
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 2)];
}

// A 2x2 box should be selected. The selection color is grayed because the window is unfocused.
- (void)testBoxSelection {
    [self doGoldenTestForInput:@"abcd\r\nefgh\r\nijkl\r\nmnop"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100GridWindowedRange range =
                                  VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 1, 3, 2),
                                                             0, 0);
                              iTermSubSelection *subSelection =
                              [iTermSubSelection subSelectionWithRange:range
                                                                  mode:kiTermSelectionModeBox];
                              [textView.selection addSubSelection:subSelection];
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// ab, fg, and jk should be selected. The selection color is grayed because the window is
// unfocused.
- (void)testMultipleDiscontinuousSelection {
    [self doGoldenTestForInput:@"abcd\r\nefgh\r\nijkl\r\nmnop"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100GridWindowedRange range =
                                  VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 1, 3, 2),
                                                             0, 0);
                              iTermSubSelection *subSelection =
                                  [iTermSubSelection subSelectionWithRange:range
                                                                      mode:kiTermSelectionModeBox];
                              [textView.selection addSubSelection:subSelection];

                              range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 2, 0),
                                                                 0, 0);
                              subSelection = [iTermSubSelection subSelectionWithRange:range
                                                                                 mode:kiTermSelectionModeCharacter];
                              [textView.selection addSubSelection:subSelection];

                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// The middle two letters should be selected. The selection color is grayed because the window is
// unfocused.
- (void)testWindowedCharacterSelection {
    [self doGoldenTestForInput:@"abcd\r\nefgh\r\nijkl\r\nmnop"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100GridWindowedRange range =
                                  VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 0, 3, 3),
                                                             1, 2);
                              iTermSubSelection *subSelection =
                              [iTermSubSelection subSelectionWithRange:range
                                                                  mode:kiTermSelectionModeBox];
                              [textView.selection addSubSelection:subSelection];
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// A cell cells after the a are selected. The selection color is grayed because the window is
// unfocused.
- (void)testSelectedTabOrphan {
    [self doGoldenTestForInput:@"a\t\x08q"
                              name:NSStringFromSelector(_cmd)
                              hook:^(PTYTextView *textView) {
                                  VT100GridWindowedRange range =
                                      VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 0, 3, 0),
                                                                 0, 0);
                                  iTermSubSelection *subSelection =
                                      [iTermSubSelection subSelectionWithRange:range
                                                                          mode:kiTermSelectionModeCharacter];
                                  [textView.selection addSubSelection:subSelection];
                              }
                  profileOverrides:nil
                      createGolden:NO
                              size:VT100GridSizeMake(9, 2)];
}

// The area between a and b is selected, and so is b. The selection color is grayed because the window is
// unfocused.
- (void)testSelectedTab {
    [self doGoldenTestForInput:@"a\tb"
                              name:NSStringFromSelector(_cmd)
                              hook:^(PTYTextView *textView) {
                                  VT100GridWindowedRange range =
                                      VT100GridWindowedRangeMake(VT100GridCoordRangeMake(7, 0, 9, 0),
                                                                 0, 0);
                                  iTermSubSelection *subSelection =
                                      [iTermSubSelection subSelectionWithRange:range
                                                                          mode:kiTermSelectionModeCharacter];
                                  [textView.selection addSubSelection:subSelection];
                              }
                  profileOverrides:nil
                      createGolden:NO
                              size:VT100GridSizeMake(9, 2)];
}

// Although one of the tab fillers after a is selected, only a should appear selected.
// The selection color is grayed because the window is unfocused.
- (void)testSelectedTabFillerWithoutTab {
    [self doGoldenTestForInput:@"a\tb"
                              name:NSStringFromSelector(_cmd)
                              hook:^(PTYTextView *textView) {
                                  VT100GridWindowedRange range =
                                      VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 3, 0),
                                                                 0, 0);
                                  iTermSubSelection *subSelection =
                                      [iTermSubSelection subSelectionWithRange:range
                                                                          mode:kiTermSelectionModeCharacter];
                                  [textView.selection addSubSelection:subSelection];
                              }
                  profileOverrides:nil
                      createGolden:NO
                              size:VT100GridSizeMake(9, 2)];
}

// By default, the text view is not the first responder. Ensure the color is correct when it is FR.
- (void)testCharacterSelectionTextviewIsFirstResponder {
    [self doGoldenTestForInput:@"abcd"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100GridWindowedRange range =
                                  VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 0, 3, 0),
                                                             0, 0);
                              iTermSubSelection *subSelection =
                                  [iTermSubSelection subSelectionWithRange:range
                                                                      mode:kiTermSelectionModeCharacter];
                              [textView.selection addSubSelection:subSelection];
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.isFrontTextView = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 2)];
}

// Draws a cursor guide on the line with b.
- (void)testCursorGuide {
    [self doGoldenTestForInput:@"a\r\nb\r\nc\r\nd\x1b[2A"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                                  helper.highlightCursorLine = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// Draws a badge which blends with nondefault background colors.
- (void)testBadge {
    [self doGoldenTestForInput:@"\n\n\n\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\x1b[42mabc"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setBadgeLabel:@"Badge"];
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// Test various combinations of the basic 256 colors
- (void)test256Colors {
    // Tests a few combos of fg and bg colors in the set of 256 indexed colors.
    NSMutableString *input = [NSMutableString string];
    // 16 + r*36 + g*6 + b
    // RGB values are in 0 to 5 incl.
    NSNumber *black = @(16 + 0*36 + 0*6 + 0);
    NSNumber *gray = @(16 + 3*36 + 3*6 + 3);
    NSNumber *red = @(16 + 5*36 + 0*6 + 0);
    NSNumber *green = @(16 + 0*36 + 5*6 + 0);
    NSNumber *blue = @(16 + 0*36 + 0*6 + 5);
    NSNumber *purple = @(16 + 5*36 + 0*6 + 5);
    NSNumber *muddy = @(16 + 4*36 + 3*6 + 1);
    NSArray *colors = @[ black, gray, red, green, blue, purple, muddy ];
    NSArray *names = @[ @"black", @"gray", @"red", @"green", @"blue", @"purple", @"muddy" ];
    [input appendString:@"        "];
    for (NSNumber *fg in colors) {
        [input appendFormat:@"%-7d ", fg.intValue];
    }
    [input appendString:@"\r\n        "];
    for (NSString *name in names) {
        [input appendFormat:@"%-7s ", name.UTF8String];
    }
    [input appendString:@"\r\n"];
    int i = 0;
    for (NSNumber *bg in colors) {
        [input appendFormat:@"\e[m%-7s ", [names[i++] UTF8String]];
        for (NSNumber *fg in colors) {
            [input appendFormat:@"%@%@x       ",
             [self sgrSequenceWithSubparams:@[ @38, @5, fg ]],
             [self sgrSequenceWithSubparams:@[ @48, @5, bg ]] ];
        }
        [input appendFormat:@"\r\n"];
    }
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(70, 9)];
}

- (NSString *)sequenceForForegroundColorWithRed:(CGFloat)red
                                          green:(CGFloat)green
                                           blue:(CGFloat)blue {
    return [NSString stringWithFormat:@"\e[38:2:%d:%d:%dm",
               (int)(red * 255), (int)(green * 255), (int)(blue * 255)];
}

- (NSString *)sequenceForBackgroundColorWithRed:(CGFloat)red
                                          green:(CGFloat)green
                                           blue:(CGFloat)blue {
    return [NSString stringWithFormat:@"\e[48:2:%d:%d:%dm",
            (int)(red * 255), (int)(green * 255), (int)(blue * 255)];
}

// Test a couple 24-bit colors.
// Bluish foreground and orangish background
- (void)test24BitColor {
    [self doGoldenTestForInput:@"\x1b[38:2:17:133:177mFg\x1b[48:2:177:133:17mBg"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 2)];
}

// There should be ample horizontal spacing
- (void)testHorizontalSpacing {
    [self doGoldenTestForInput:@"abc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_HORIZONTAL_SPACING: @2.0 }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// There should be ample vertical spacing and a very tall cursor indeed.
- (void)testVerticalSpacing {
    [self doGoldenTestForInput:@"abc\r\ndef"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_VERTICAL_SPACING: @2.0 }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 3)];
}

// Red diagonal stripes should fill the background including side margins, top, and excess. It should
// be visible over the badge and nondefault background colors.
- (void)testBackgroundStripes {
    [self doGoldenTestForInput:@"abc\r\ndef\r\n\e[42mBlahblahblah"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setBadgeLabel:@"Badge"];
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.showStripes = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// Should render non-anti-aliased text.
- (void)testNoAntiAlias {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @NO,
                                  KEY_NONASCII_ANTI_ALIASED: @NO,
                                  KEY_USE_NONASCII_FONT: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// a should be anti-aliased and é should not be.
- (void)testAsciiAntiAliasOnly {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @YES,
                                  KEY_NONASCII_ANTI_ALIASED: @NO,
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// a should not be anti-aliased and é should be.
- (void)testNonAsciiAntiAliasOnly {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @NO,
                                  KEY_NONASCII_ANTI_ALIASED: @YES,
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// The é should be tiny, a should be regular.
- (void)testUseNonAsciiFont {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_NON_ASCII_FONT: [[NSFont fontWithName:@"Courier" size:8] stringValue],
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// Both a and é should have the same size.
- (void)testDontUseNonAsciiFont {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_NON_ASCII_FONT: [[NSFont fontWithName:@"Courier" size:8] stringValue],
                                  KEY_USE_NONASCII_FONT: @NO  }
                  createGolden:NO
                          size:VT100GridSizeMake(80, 25)];
}

// b should be invisible
- (void)testBlinkingTextHidden {
    [self doGoldenTestForInput:@"a\x1b[5mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = NO;
                              };
                          }
              profileOverrides:@{ KEY_BLINK_ALLOWED: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 2)];
}

// Should say "ab"
- (void)testBlinkingTextVisible {
    [self doGoldenTestForInput:@"a\x1b[5mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = YES;
                              };
                          }
              profileOverrides:@{ KEY_BLINK_ALLOWED: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 2)];
}

// Cursor should be invisible
- (void)testBlinkingCursorHidden {
    [self doGoldenTestForInput:@""
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = NO;
                                  helper.isInKeyWindow = YES;
                                  helper.textViewIsActiveSession = YES;
                                  helper.cursorBlinking = YES;  // PTYTextView sets this based on if the window is key
                              };
                          }
              profileOverrides:@{ KEY_BLINKING_CURSOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Cursor should be visible
- (void)testBlinkingCursorNotHidden {
    [self doGoldenTestForInput:@""
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = YES;
                                  helper.isInKeyWindow = YES;
                                  helper.textViewIsActiveSession = YES;
                                  helper.cursorBlinking = YES;  // PTYTextView sets this based on if the window is key
                              };
                          }
              profileOverrides:@{ KEY_BLINKING_CURSOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should render c and d.
- (void)testScrollbackOverflow {
    // Tests receiving input between -refresh (which calls setNeedsDisplay) and -drawRect.
    // The most up-to-date model should be drawn. This is a departure from how 2.0 worked,
    // which tried to draw how things "were" at the time refresh was called (but didn't really
    // succeed).
    [self doGoldenTestForInput:@"a\r\nb\r\n"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView refresh];
                              PTYSession *session = (PTYSession *)textView.delegate;
                              [session synchronousReadTask:@"c\r\nd"];
                          }
              profileOverrides:@{ KEY_SCROLLBACK_LINES: @1 }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}


// Red with 50% black should show through background and text should be normal gray..
- (void)testTransparency {
    [self doGoldenTestForInput:@"a\r\nb\r\n"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // Change the session's class to one that always returns YES for
                              // use transparency.
                              PTYSession *session = (PTYSession *)textView.delegate;
                              object_setClass(session, [iTermFakeSessionForPTYTextViewTest class]);
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  // Draw a red background to ensure transparency.
                                  [[NSColor redColor] set];
                                  NSRectFill(textView.bounds);
                              };
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// abc should be underlined with a yellow cursor after c.
- (void)testIME {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"abc"
                                        selectedRange:NSMakeRange(3, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Gamma should be double width
- (void)testIMEWithAmbiguousIsDoubleWidth {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"Γ"  // U+0393 (hex), Greek capital gamma, is ambiguous width
                                        selectedRange:NSMakeRange(1, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_AMBIGUOUS_DOUBLE_WIDTH: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 2)];
}

// Gamma should be single width
- (void)testIMEWithAmbiguousIsNotDoubleWidth {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"Γ"  // U+0393 (hex), Greek capital gamma, is ambiguous width
                                        selectedRange:NSMakeRange(1, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 2)];
}

// The squiggle should be on the second line
- (void)testIMEWrapsDoubleWidthAtEndOfLine {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // The DWC should be wrapped onto the second line
                              [textView setMarkedText:@"aᄀ"  // U+1100 (hex), HANGUL CHOSEONG KIYEOK, is double width.
                                        selectedRange:NSMakeRange(2, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 2)];
}

// Background image low blending - less of background shows through on default bg color
// Background noise should be subtle.
- (void)testBackgroundImageLowBlending {
    NSString *pathToImage = [self pathForTestResourceNamed:@"TestBackground.png"];
    [self doGoldenTestForInput:@"a\e[31mb\e[41mc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_BACKGROUND_IMAGE_LOCATION: pathToImage,
                                  KEY_BLEND: @0.3 }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 1)];
}

// Background image high blending - more of background shows through on default bg color
// Background noise should be quite visible (annoyingly so).
- (void)testBackgroundImageHighBlending {
    NSString *pathToImage = [self pathForTestResourceNamed:@"TestBackground.png"];
    [self doGoldenTestForInput:@"a\e[31mb\e[41mc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_BACKGROUND_IMAGE_LOCATION: pathToImage,
                                  KEY_BLEND: @0.9 }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 1)];
}

// The first line is fg/bg swapped vs the second line. a and b on the second line should have
// transparent (default) backgrounds; all others should have opaque background colors.
- (void)testBackgroundImageWithReverseVideo {
    NSString *pathToImage = [self pathForTestResourceNamed:@"TestBackground.png"];
    [self doGoldenTestForInput:@"\e[7ma\e[31mb\e[42mc\r\n"
                               @"\e[0ma\e[31mb\e[42mc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_BACKGROUND_IMAGE_LOCATION: pathToImage,
                                  KEY_BLEND: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Default bg becomes gray. Default fg over default bg (a in second row) becomes black.
- (void)testBackgroundImageWithGloballyInvertedColors {
    NSString *pathToImage = [self pathForTestResourceNamed:@"TestBackground.png"];
    [self doGoldenTestForInput:@"\e[7ma\e[31mb\e[42mc\r\n"  // reversed
                               @"\e[0ma\e[31mb\e[42mc"  // regular
                               @"\e[?5h"  // invert colors globally (affects default bg and default fg when over default bg)
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_BACKGROUND_IMAGE_LOCATION: pathToImage,
                                  KEY_BLEND: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Default background color is transparent on a and b. Nondefault red background is opaque on c
// (which you can't see because it's also red).
- (void)testBackgroundImageWithTransparency {
    NSString *pathToImage = [self pathForTestResourceNamed:@"TestBackground.png"];
    [self doGoldenTestForInput:@"a\e[31mb\e[41mc"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // Change the session's class to one that always returns YES for
                              // use transparency.
                              PTYSession *session = (PTYSession *)textView.delegate;
                              object_setClass(session, [iTermFakeSessionForPTYTextViewTest class]);
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  // Draw a red background to ensure transparency.
                                  [[NSColor redColor] set];
                                  NSRectFill(textView.bounds);
                              };
                          }
              profileOverrides:@{ KEY_BACKGROUND_IMAGE_LOCATION: pathToImage,
                                  KEY_BLEND: @0.3,
                                  KEY_TRANSPARENCY: @0 }
                  createGolden:NO
                          size:VT100GridSizeMake(3, 1)];
}

// Smart cursor color
// All white neighbors->cursor will be black because text color is too close to white.
- (void)testSmartCursorColor_allWhite {
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       white, white, white,
                       white, white, white,
                       white, white, white];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Dark red is distant from the default cursor color so the center cell should be white on dark red.
- (void)testSmartCursorColor_allWhiteDarkRedFore {
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       [self sequenceForForegroundColorWithRed:0.5 green:0 blue:0],
                       white, white, white,
                       white, white, white,
                       white, white, white];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// All neighbors are black so cursor will be black on default foreground gray color.
- (void)testSmartCursorColor_allBlack {
    NSString *black = [self sequenceForBackgroundColorWithRed:0 green:0 blue:0];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       black, black, black,
                       black, black, black,
                       black, black, black];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// All neighbors are dark gray (close to text color) so cursor will be black on white.
- (void)testSmartCursorColor_allDarkGray {
    NSString *darkGray = [self sequenceForBackgroundColorWithRed:0.4 green:0.4 blue:0.4];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       darkGray, darkGray, darkGray,
                       darkGray, darkGray, darkGray,
                       darkGray, darkGray, darkGray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue]
                                }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Cursor should be visible when all text is default fg/bg with globally inverted colors.
- (void)testSmartCursorColor_reverseVideo {
    NSString *input = [NSString stringWithFormat:@"\e[?5hxxx\r\nxxx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Cursor should be visible when all text is non-default fg/default bg with globally inverted colors.
- (void)testSmartCursorColor_reverseVideoNondefaultForeground {
    NSString *input = [NSString stringWithFormat:@"\e[31m\e[?5hxxx\r\nxxx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Colors are globally inverted and the cursor is on text that is red on default bg (black). Without
// a cursor, it would render as red on gray. A naïve color swap for the cursor would give gray on red.
// Since that is terrible contrast, the cursor renders as white on red.
- (void)testSmartCursorColor_reverseVideoNondefaultForegroundOnlyUnderCursor {
    NSString *input = [NSString stringWithFormat:@"\e[?5hxxx\r\nx\e[31mx\e[mx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Without a cursor, the center character would be default fg (gray) on red. It should render the
// cursor as red on gray.
- (void)testSmartCursorColor_reverseVideoNondefaultBackground {
    NSString *input = [NSString stringWithFormat:@"\e[41m\e[?5hxxx\r\nxxx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// The char the cursor is on has a red background. It should render as white on default bg (black)
// because red on black wouldn't have enough contrast.
- (void)testSmartCursorColor_reverseVideoNondefaultBackgroundOnlyUnderCursor {
    NSString *input = [NSString stringWithFormat:@"\e[?5hxxx\r\nx\e[41mx\e[mx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// The char under the cursor is red over light gray. Global reverse video doesn't affect nondefault
// background colored chars. So the cursor renders as white on red (white for contrast).
- (void)testSmartCursorColor_reverseVideoNondefaultForegroundAndBackgroundUnderCursor {
    NSString *input = [NSString stringWithFormat:@"\e[?5hxxx\r\nx\e[47m\e[31mx\e[mx\r\nxxx\e[2;2H"];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}


// All neighbors are the same as the default text color. Cursor should be black on white or white on
// black (either is ok; one must be chosen arbitrarily).
- (void)testSmartCursorColor_allCursorColor {
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *input = [NSString stringWithFormat:@"%@%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       [self sequenceForForegroundColorWithRed:0.5 green:0.5 blue:0.5],
                       gray, gray, gray,
                       gray, gray, gray,
                       gray, gray, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// The frame is visible (light gray) but smart cursor color doesn't ensure text is visible when unfocused.
- (void)testSmartCursorColor_frameAllCursorColor {
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *input = [NSString stringWithFormat:@"%@%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       [self sequenceForForegroundColorWithRed:0.5 green:0.5 blue:0.5],
                       gray, gray, gray,
                       gray, gray, gray,
                       gray, gray, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Cursor should be white on black. The gray corners are ignored.
- (void)testSmartCursorColor_whiteCrossGrayCorners {
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       gray, white, gray,
                       white, white, white,
                       gray, white, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue]
                                  }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// With both gray and white neighbors the cursor should be white on black.
- (void)testSmartCursorColor_manyGrayOneWhite {
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       gray, gray, gray,
                       white, gray, gray,
                       gray, gray, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue]
                                  }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// With gray, white, and black neighbors, the cursor should be black on light gray.
- (void)testSmartCursorColor_manyGrayOneWhiteOneBlack {
    NSString *black = [self sequenceForBackgroundColorWithRed:0 green:0 blue:0];
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       gray, gray, gray,
                       white, gray, gray,
                       gray, black, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue]
                                  }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Cursor frame should be a medium gray, between the background color of the cell it's on and its
// white neighbor. Dark gray would also be ok (actually, would be better).
- (void)testSmartCursorColor_frameManyGrayOneWhiteOneBlack {
    NSString *black = [self sequenceForBackgroundColorWithRed:0 green:0 blue:0];
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       gray, gray, gray,
                       white, gray, gray,
                       gray, black, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue]
                                  }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// The center cell is gray on black. Inverted, it would be black on gray. With smart cursor color,
// it should become white on black. That's kind of confusing, but this is a weird edge case.
- (void)testSmartCursorColor_onIsland {
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *black = [self sequenceForBackgroundColorWithRed:0 green:0 blue:0];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       white, white, white,
                       white, black, white,
                       white, white, white];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Cursor boost should dim everything but the cursor as compared to testSmartCursorColor_manyGrayOneWhiteOneBlack
- (void)testSmartCursorColorWithCursorBoost {
    NSString *black = [self sequenceForBackgroundColorWithRed:0 green:0 blue:0];
    NSString *gray = [self sequenceForBackgroundColorWithRed:0.5 green:0.5 blue:0.5];
    NSString *white = [self sequenceForBackgroundColorWithRed:1 green:1 blue:1];
    NSString *input = [NSString stringWithFormat:@"%@x%@x%@x\r\n%@x%@x%@x\r\n%@x%@x%@x\e[2;2H",
                       gray, gray, gray,
                       white, gray, gray,
                       gray, black, gray];
    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_SMART_CURSOR_COLOR: @YES,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1] dictionaryValue],
                                  KEY_CURSOR_BOOST: @0.5,
                                }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// Should have a gray frame around b.
- (void)testFrameCursor {
    [self doGoldenTestForInput:@"abc\e[1;2H"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Should have a gray frame around b.
- (void)testFrameCursorWithNondefaultColors {
    [self doGoldenTestForInput:@"\e[41;32mabc\e[1;2H"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Should have a gray box.
- (void)testCursorFilledInBecauseKeyWindowAndActiveTextview {
    [self doGoldenTestForInput:@""
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.isInKeyWindow = YES;
                                  helper.textViewIsActiveSession = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Should have a gray box.
- (void)testCursorFilledInBecauseOfDelegateOverride {
    [self doGoldenTestForInput:@""
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.isInKeyWindow = NO;
                                  helper.textViewIsActiveSession = NO;
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Second x should be lighter color.
- (void)testBrightBoldOn {
    [self doGoldenTestForInput:@"x\e[1mx"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_USE_BRIGHT_BOLD: @YES }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Both x's the same color.
- (void)testBrightBoldOff {
    [self doGoldenTestForInput:@"x\e[1mx"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_USE_BRIGHT_BOLD: @NO }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// cdef should be blue and underlined.
- (void)testUnderlineHost {
    [self doGoldenTestForInput:@"abcdefg"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.underlineRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(2, 0, 2, 1), 0, 5);
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Nothing visible, just black.
- (void)testHiddenCursor {
    [self doGoldenTestForInput:@"\e[?25l"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Each cursor type
- (void)testBlockCursor {
    [self doGoldenTestForInput:@"\e[1 qa\x08"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should be just a gray box
- (void)testUnderlineCursor {
    [self doGoldenTestForInput:@"\e[4 qa\x08"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should be a gray vertical line left of an a.
- (void)testBarCursor {
    [self doGoldenTestForInput:@"\e[6 qa\x08"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Black a on white cursor; all other cells are gray.
- (void)testBlockCursorReverseVideo {
    [self doGoldenTestForInput:@"\e[1 qa\x08\e[?5h"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Black b on white cursor. All else is black on gray.
- (void)testBlockCursorDoublyReverseVideo {
    [self doGoldenTestForInput:@"x\e[1 q\e[7mab\x08\e[?5h"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// White underline cursor beneath a.
- (void)testUnderlineCursorReverseVideo {
    [self doGoldenTestForInput:@"\e[4 qa\x08\e[?5h"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Vertical white bar before black a.
- (void)testBarCursorReverseVideo {
    [self doGoldenTestForInput:@"\e[6 qa\x08\e[?5h"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Gray background, barely visible lighter gray and and b.
- (void)testDimmingTextAndBg {
    [self doGoldenTestForInput:@"a\e[41mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = NO;
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should be a very very dark ab on black.
- (void)testDimmingText {
    [self doGoldenTestForInput:@"a\e[41mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = YES;
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should render a black x on green background.
- (void)testMinimumContrast {
    NSString *input = [NSString stringWithFormat:@"%@%@x",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],  // Puke green (should render as same color)
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];  // Similar-brightness blue (should render black)

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Gray x on gray-green background.
- (void)testDimmingTextAndBgAndMinimumContrast {
    NSString *input = [NSString stringWithFormat:@"%@%@x",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = NO;
                          }
              profileOverrides:@{ KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Black x on very dark green background.
- (void)testDimmingTextAndMinimumContrast {
    NSString *input = [NSString stringWithFormat:@"%@%@x",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = YES;
                          }
              profileOverrides:@{ KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Everything dark except for lightish colored green cursor.
- (void)testCursorBoost {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{ KEY_CURSOR_BOOST: @0.5,
                                  KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                               green:.64
                                                                                blue:.39
                                                                               alpha:1] dictionaryValue] }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// Everything pretty washed out except lightish green cursor.
- (void)testDimmingTextAndBgAndCursorBoost {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = NO;
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{  KEY_CURSOR_BOOST: @0.5,
                                   KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                                green:.64
                                                                                 blue:.39
                                                                                alpha:1] dictionaryValue],
                                   KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// Almost invisibly dark text and a lightish green cursor.
- (void)testDimmingTextAndCursorBoost {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = YES;
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{  KEY_CURSOR_BOOST: @0.5,
                                   KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                                green:.64
                                                                                 blue:.39
                                                                                alpha:1] dictionaryValue],
                                   KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// Everything darkish, c is black on green, cursor is lightish green.
- (void)testMinimumContrastAndCursorBoost {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{  KEY_CURSOR_BOOST: @0.5,
                                   KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                                green:.64
                                                                                 blue:.39
                                                                                alpha:1] dictionaryValue],
                                   KEY_MINIMUM_CONTRAST: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// Everything is washed out. The c is as dark as can be, but still washed out. The cursor is
// lightish green.
- (void)testDimmingTextAndBgAndCursorBoostAndMinimumContrast {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = NO;
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{  KEY_CURSOR_BOOST: @0.5,
                                   KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                                green:.64
                                                                                 blue:.39
                                                                                alpha:1] dictionaryValue],
                                   KEY_MINIMUM_CONTRAST: @1 }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// Everything is very dark. The c is black. The cursor is lightish green.
- (void)testDimmingTextAndCursorBoostAndMinimumContrast {
    NSString *input = [NSString stringWithFormat:@"a%@b%@c\e[m ",
                       [self sequenceForForegroundColorWithRed:.51 green:.59 blue:.85],
                       [self sequenceForBackgroundColorWithRed:.45 green:.64 blue:.39]];

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.colorMap.dimmingAmount = 0.8;
                              textView.colorMap.dimOnlyText = YES;
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.shouldDrawFilledInCursor = YES;
                              };
                          }
              profileOverrides:@{  KEY_CURSOR_BOOST: @0.2,
                                   KEY_CURSOR_COLOR: [[NSColor colorWithCalibratedRed:.45
                                                                                green:.64
                                                                                 blue:.39
                                                                                alpha:1] dictionaryValue],
                                   KEY_MINIMUM_CONTRAST: @1 }
                  createGolden:NO
                          size:VT100GridSizeMake(6, 2)];
}

// For whatever reason, shadows don't render properly into a bitmap context.
// Various different date formats (as described in comments below) should be seen on the right.
- (void)testTimestamps {
    [self doGoldenTestForInput:@"\e[41mabcdefghijklmn"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100Screen *screen = (VT100Screen *)textView.dataSource;
                              NSTimeInterval now = 449711536;
                              const NSTimeInterval day = 86400;
                              int line = 0;
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - 1];  // HH:MM:SS
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - day - 1];  // DOW HH:MM:SS
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - 6 * day];  // DOW HH:MM:SS
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - 6 * day - 1];  // MM/DD HH:MM:SS
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - 180 * day];  // MM/DD HH:MM:SS
                              [[screen.currentGrid lineInfoAtLineNumber:line++] setTimestamp:now - 180 * day - 1];  // MM/DD/YYYY HH:MM:SS
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.showTimestamps = YES;
                                  helper.now = now;
                                  helper.useTestingTimezone = YES;  // Use GMT so test can pass anywhere.
                              };
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(20, 6)];
}

// Retina uses a shift because double-striking is imperceptible.
// The second 'i' should be a bit thicker.
- (void)testRetinaFakeBold {
    [self doGoldenTestForInput:@"i\e[1mi"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.antiAliasedShift = 0.5;
                              };
                          }
              profileOverrides:@{ KEY_USE_BRIGHT_BOLD: @NO }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// While the second i is double-struck, the effect is invisible.
- (void)testNonretinaFakeBold {
    [self doGoldenTestForInput:@"i\e[1mi"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.antiAliasedShift = 0;
                              };
                          }
              profileOverrides:@{ KEY_USE_BRIGHT_BOLD: @NO }
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// Should have a blue mark on the 2nd line and a red mark on the 3rd.
- (void)testMark {
    [self doGoldenTestForInput:@"abc\r\ndef\r\nghi"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              PTYSession *session = (PTYSession *)textView.delegate;
                              [session screenAddMarkOnLine:1];
                              VT100ScreenMark *mark = [session markAddedAtCursorOfClass:[VT100ScreenMark class]];
                              mark.code = 1;
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 4)];
}

// efg should have a yellow underline.
- (void)testNote {
    [self doGoldenTestForInput:@"abc\r\nd\e]1337;AddAnnotation=5|This is a note\x07 ef\r\nghi"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              for (NSView *view in textView.subviews) {
                                  view.hidden = YES;
                              }
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// The first two xx's should be black on yellow. The last xx should be selected.
- (void)testFindMatches {
    [self doGoldenTestForInput:@"abxxfghxxxxl"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // Need to call refresh to clear dirty flags, otherwise find matches
                              // get reset when refresh gets called.
                              [textView refresh];

                              [textView resetFindCursor];
                              [textView findString:@"xx"
                                  forwardDirection:NO
                                      ignoringCase:NO
                                             regex:NO
                                        withOffset:0];
                              double progress;
                              while ([textView findInProgress]) {
                                  [textView continueFind:&progress];
                              }
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 5)];
}

// Stacked acute accents and cedillas should draw over green backgrounds on line above and below
// the blue arrow, which also runs into the cell with the a. Nothing should be clipped.
- (void)testOversizeGlyphs {
    // Combining accents that draw into line above and line below. The arrow glyph is single-width
    // but occupies two cells. Although other text may draw over the out-of-range bits the background
    // should not obscure any of it.
    [self doGoldenTestForInput:@"\e[42mxyz\r\n\e[0;34m⏎\u0301\u0301\u0301\u0301\u0301\u0327\u0327\u0327\u0327\u0327\e[0;41mab\r\n\e[43m123"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 3)];
}

// Various emoji, as seen below should be drawn. The second row has a red background.
- (void)testEmoji {
    // The exclamation point tests the case where CTRunGetGlyphsPtr returns nil. It has a combining
    // mark that colors it.
    [self doGoldenTestForInput:@"😄 1️⃣ ❗ \r\n\e[41m🐶 🎅 🚀 "
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(10, 2)];
}

// The x should have three stacked acute accents.
- (void)testCombiningMark {
    [self doGoldenTestForInput:@"\r\nx\u0301\u0301\u0301"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Should render a symbol that looks like a "v" with a squiggly bit on the left.
- (void)testSurrogatePair {
    [self doGoldenTestForInput:@"\xf0\x90\x90\xb7"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// A squiggly v with two stacked acute accents.
- (void)testSurrogatePairWithCombiningMark {
    [self doGoldenTestForInput:@"\xf0\x90\x90\xb7\u0301\u0301"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(2, 2)];
}

// Double width lorem ipsum. e and m have yellow bg. i has green bg. m and i are red. Acute accent on p.
- (void)testDoubleWidthCharacter {
    [self doGoldenTestForInput:@"123456789Ｌｏｒ\e[43mｅ\e[31mｍ\e[42mｉ\e[mｐ\u0301ｓｕｍ"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(9, 3)];
}

// A box divided into four parts. The middle row is red on green. The row above is red on black.
// There's a frame cursor.
- (void)testBoxDrawing {
    [self doGoldenTestForInput:@"\e(0"
                               @"lqqwqqk\r\n"
                               @"\e[31m"
                               @"x  x  x\r\n"
                               @"\e[42m"
                               @"tqqnqqu\r\n"
                               @"\e[m"
                               @"x  x  x\r\n"
                               @"mqqvqqj"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(9, 5)];
}

// Faint regular text and faint bold text, as compared to their non-faint versions. The faint
// ones should be darker.
- (void)testFaintText {
    [self doGoldenTestForInput:@"Regular\r\n"
                               @"\e[2mFaint\e[m\r\n"
                               @"\e[1mBold\r\n"
                               @"\e[2mFaint bold"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(11, 5)];
}

// Faint regular text and faint bold text, as compared to their non-faint versions. The faint
// ones should be darker.
// The background is 50% red due to transparency.
- (void)testFaintTextWithTransparency {
    [self doGoldenTestForInput:@"Regular\r\n"
                               @"\e[2mFaint\e[m\r\n"
                               @"\e[1mBold\r\n"
                               @"\e[2mFaint bold"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // Change the session's class to one that always returns YES for
                              // use transparency.
                              PTYSession *session = (PTYSession *)textView.delegate;
                              object_setClass(session, [iTermFakeSessionForPTYTextViewTest class]);
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  // Draw a red background to ensure transparency.
                                  [[NSColor redColor] set];
                                  NSRectFill(textView.bounds);
                              };
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5 }
                  createGolden:NO
                          size:VT100GridSizeMake(11, 5)];
}

// abc in default colors.
- (void)testBasicDraw {
    [self doGoldenTestForInput:@"abc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(4, 2)];
}

// It can happen that a line like [double-width character][dwc-right]["a"] will be drawn starting
// with the dwc-right. There was a bug where no advance was given for the dwc-right because it was
// assumed that the DWC itself was always drawn. That ceased to be the case when the "draw an extra
// ring of glyphs" algorithm was implemented (it accommodates oversize glyphs outside the drawing
// rect).
//
// In this test, the first column should be empty and the second column should hold an "a".
- (void)testRegionStartingWithDWCRight {
    [self doGoldenTestForInput:@" a\r\n01"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              VT100Screen *screen = (VT100Screen *)textView.dataSource;
                              screen_char_t *line = [screen getLineAtScreenIndex:0];
                              line[0].code = DWC_RIGHT;
                          }
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(5, 3)];
}

// A 16x16 grid of the ansi colors with columns having similar bg's and rows having similar fg's.
- (void)testAnsiColors {
    // Test every combination of foreground and background.
    NSMutableString *input = [NSMutableString string];

    for (NSNumber *fgNumber in @[ @30, @31, @32, @33, @34, @35, @36, @37, @90, @91, @92, @93, @94,
                                  @95, @96, @97 ]) {
        for (NSNumber *bgNumber in @[ @40, @41, @42, @43, @44, @45, @46, @47, @100, @101, @102,
                                      @103, @104, @105, @106, @107 ]) {
            int fg = [fgNumber intValue];
            int bg = [bgNumber intValue];

            [input appendFormat:@"%@%@x", [self sgrSequence:fg], [self sgrSequence:bg]];
        }
        [input appendFormat:@"\r\n"];
    }

    [self doGoldenTestForInput:input
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:NO
                          size:VT100GridSizeMake(17, 17)];
}

- (int)width {
    return 4;
}

- (int)height {
    return 4;
}

- (int)numberOfLines {
    return 4;
}

- (screen_char_t *)getLineAtIndex:(int)theIndex {
    for (int i = 0; i < [self width]; i++) {
        memset(&_buffer[i], 0, sizeof(screen_char_t));
        _buffer[i].code = theIndex + '0';
    }
    return _buffer;
}

#pragma mark - Test selection

- (void)testSelectedTextVeryBasic {
    // Given
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"123456789";
    [session synchronousReadTask:text];
    NSUserDefaults *mockDefaults = MKTMock([NSUserDefaults class]);
    [MKTGiven([mockDefaults objectForKey:kPreferenceKeyCopyLastNewline]) willReturn:@YES];
    [MKTGiven([mockDefaults objectForKey:@"TrimWhitespaceOnCopy"]) willReturn:@YES];

    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return mockDefaults; }
                                  forBlock:^{
                                      // When
                                      [_textView selectAll:nil];
                                      NSString *selectedText = [_textView selectedText];

                                      // Then
                                      XCTAssertEqualObjects(@"123456789\n\n", selectedText);
                                  }];
}

- (void)testSelectedTextWrappedLine {
    // Given
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"123456789abc";
    [session synchronousReadTask:text];
    NSUserDefaults *mockDefaults = MKTMock([NSUserDefaults class]);
    [MKTGiven([mockDefaults objectForKey:kPreferenceKeyCopyLastNewline]) willReturn:@YES];
    [MKTGiven([mockDefaults objectForKey:@"TrimWhitespaceOnCopy"]) willReturn:@YES];

    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return mockDefaults; }
                                  forBlock:^{
                                      // When
                                      [_textView selectAll:nil];
                                      NSString *selectedText = [_textView selectedText];

                                      // Then
                                      XCTAssertEqualObjects([text stringByAppendingString:@"\n"], selectedText);
                                  }];
}

- (void)testSelectedTextWrappedAttributedLinesDontGetNewlinesInserted {
    // Given
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"123456789abcdefghi";
    [session synchronousReadTask:text];
    NSUserDefaults *mockDefaults = MKTMock([NSUserDefaults class]);
    [MKTGiven([mockDefaults objectForKey:kPreferenceKeyCopyLastNewline]) willReturn:@YES];
    [MKTGiven([mockDefaults objectForKey:@"TrimWhitespaceOnCopy"]) willReturn:@YES];

    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return mockDefaults; }
                                  forBlock:^{
                                      // When
                                      [_textView selectAll:nil];
                                      NSAttributedString *selectedAttributedText = [_textView selectedTextAttributed:YES
                                                                                                        cappedAtSize:0
                                                                                                   minimumLineNumber:0];

                                      // Then
                                      XCTAssertEqualObjects([text stringByAppendingString:@"\n"], selectedAttributedText.string);
                                  }];
}

- (void)testSelectedTextWithSizeCap {
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"123456789abc";
    [session synchronousReadTask:text];
    [_textView selectAll:nil];
    NSString *selectedText = [_textView selectedTextAttributed:NO cappedAtSize:5 minimumLineNumber:0];
    XCTAssertEqualObjects(@"12345", selectedText);
}

- (void)testSelectedTextWithMinimumLine {
    // Given
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"blah\r\n12345";
    [session synchronousReadTask:text];
    NSUserDefaults *mockDefaults = MKTMock([NSUserDefaults class]);
    [MKTGiven([mockDefaults objectForKey:kPreferenceKeyCopyLastNewline]) willReturn:@YES];
    [MKTGiven([mockDefaults objectForKey:@"TrimWhitespaceOnCopy"]) willReturn:@YES];

    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return mockDefaults; }
                                  forBlock:^{
                                      // When
                                      [_textView selectAll:nil];
                                      NSString *selectedText = [_textView selectedTextAttributed:NO cappedAtSize:0 minimumLineNumber:1];

                                      // Then
                                      XCTAssertEqualObjects(@"12345\n", selectedText);
                                  }];
}

- (void)testSelectedTextWithSizeCapAndMinimumLine {
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(10, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"blah\r\n12345";
    [session synchronousReadTask:text];
    [_textView selectAll:nil];
    NSString *selectedText = [_textView selectedTextAttributed:NO cappedAtSize:2 minimumLineNumber:1];
    XCTAssertEqualObjects(@"12", selectedText);
}

// TODO: Add more tests for every possible attribute.
- (void)testSelectedAttributedTextIncludesBoldAttribute {
    PTYSession *session = [self sessionWithProfileOverrides:@{} size:VT100GridSizeMake(20, 2)];
    _textView.dataSource = session.screen;
    NSString *text = @"regular\e[1mbold";
    [session synchronousReadTask:text];
    [_textView selectAll:nil];
    NSAttributedString *selectedAttributedText = [_textView selectedTextAttributed:YES
                                                                      cappedAtSize:11
                                                                 minimumLineNumber:0];
    XCTAssertEqualObjects(@"regularbold", selectedAttributedText.string);

    NSRange range;
    NSDictionary *regularAttributes = [selectedAttributedText attributesAtIndex:0
                                                                 effectiveRange:&range];
    XCTAssertEqual(range.location, 0);
    const int kRegularLength = [@"regular" length];
    XCTAssertEqual(range.length, kRegularLength);
    XCTAssertEqualObjects(regularAttributes[NSFontAttributeName],
                          [NSFont systemFontOfSize:[NSFont systemFontSize]]);

    NSDictionary *boldAttributes = [selectedAttributedText attributesAtIndex:kRegularLength
                                                                 effectiveRange:&range];
    const int kBoldLength = [@"bold" length];
    XCTAssertEqual(range.location, kRegularLength);
    XCTAssertEqual(range.length, kBoldLength);
    XCTAssertEqualObjects(boldAttributes[NSFontAttributeName],
                          [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]);
}

#pragma mark - PTYTextViewDelegate

- (void)paste:(id)sender {
    [self registerCall:_cmd];
}

- (void)pasteOptions:(id)sender {
    [self registerCall:_cmd];
}

- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags {
    [self registerCall:_cmd argument:@(flags)];
}

- (void)refresh {
    [self registerCall:_cmd];
}

@end
