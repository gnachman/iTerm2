#import "iTermTests.h"
#import "iTermColorMap.h"
#import "iTermSelection.h"
#import "iTermTextDrawingHelper.h"
#import "NSColor+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "PTYTextViewTest.h"
#import "SessionView.h"
#import <objc/runtime.h>

static const BOOL gCreateGoldens = YES;

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
    BOOL _canPasteFile;
    screen_char_t _buffer[4];
}

- (void)setLineDirtyAtY:(int)y {
}

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    return nil;
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

- (BOOL)textViewInSameTabAsTextView:(PTYTextView *)other {
    return YES;
}

- (void)removeInaccessibleNotes {
}

- (VT100GridAbsCoordRange)textViewRangeOfLastCommandOutput {
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

- (void)textViewSizeDidChange {
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

- (BOOL)continueFindAllResults:(NSMutableArray *)results inContext:(FindContext *)context {
    return NO;
}

- (BOOL)isAllDirty {
    return NO;
}
- (BOOL)isDirtyAtX:(int)x Y:(int)y {
    return NO;
}


- (void)setup {
    _colorMap = [[iTermColorMap alloc] init];
    _textView = [[PTYTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) colorMap:_colorMap];
    _textView.delegate = self;
    _textView.dataSource = self;
    _methodsCalled = [[NSMutableDictionary alloc] init];
    _canPasteFile = NO;
}

- (void)teardown {
    [_textView release];
    [_colorMap release];
    [_methodsCalled release];
}

- (void)invokeMenuItemWithSelector:(SEL)selector {
    [self invokeMenuItemWithSelector:selector tag:0];
}

- (void)invokeMenuItemWithSelector:(SEL)selector tag:(NSInteger)tag {
    NSMenuItem *fakeMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Fake Menu Item"
                                                           action:selector
                                                    keyEquivalent:@""] autorelease];
    [fakeMenuItem setTag:tag];
    assert([_textView validateMenuItem:fakeMenuItem]);
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
    [self invokeMenuItemWithSelector:@selector(paste:)];
    assert([_methodsCalled[@"paste:"] intValue] == 1);
}

- (void)testPasteOptions {
    [self invokeMenuItemWithSelector:@selector(pasteOptions:)];
    assert([_methodsCalled[@"pasteOptions:"] intValue] == 1);
}

- (void)testPasteSelection {
    [_textView selectAll:nil];
    [self invokeMenuItemWithSelector:@selector(pasteSelection:) tag:1];
    assert([_methodsCalled[@"textViewPasteFromSessionWithMostRecentSelection:1"] intValue] == 1);
}

- (void)testPasteBase64Encoded {
    _canPasteFile = YES;
    [self invokeMenuItemWithSelector:@selector(pasteBase64Encoded:)];
    assert([_methodsCalled[@"textViewPasteFileWithBase64Encoding"] intValue] == 1);
}

- (NSImage *)imageForInput:(NSString *)input
                        hook:(void (^)(PTYTextView *))hook
          profileOverrides:(NSDictionary *)profileOverrides
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

    assert([session setScreenSize:NSMakeRect(0, 0, 200, 200) parent:nil]);
    [session setPreferencesFromAddressBookEntry:profile];
    [session setWidth:size.width height:size.height];
    NSRect theFrame = NSMakeRect(0,
                                 0,
                                 size.width * session.textview.charWidth + MARGIN * 2,
                                 size.height * session.textview.lineHeight + VMARGIN * 2);
    session.view.frame = theFrame;
    [session loadInitialColorTable];
    [session setBookmarkName:profile[KEY_NAME]];
    [session setName:profile[KEY_NAME]];
    [session setDefaultName:profile[KEY_NAME]];

    [session synchronousReadTask:input];
    if (hook) {
        hook(session.textview);
    }
    return [session.view snapshot];
}

- (NSString *)pathForGoldenWithName:(NSString *)name {
    NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *filename = [NSString stringWithFormat:@"PTYTextViewTest-golden-%@.png", name];
    return [resourcePath stringByAppendingPathComponent:filename];
}

- (void)doGoldenTestForInput:(NSString *)input
                        name:(NSString *)name
                        hook:(void (^)(PTYTextView *))hook
            profileOverrides:(NSDictionary *)profileOverrides
                createGolden:(BOOL)createGolden
                        size:(VT100GridSize)size {
    NSImage *actual = [self imageForInput:input hook:hook profileOverrides:profileOverrides size:size];
    NSString *goldenName = [self pathForGoldenWithName:name];
    if (createGolden) {
        NSData *pngData = [actual dataForFileOfType:NSPNGFileType];
        [pngData writeToFile:goldenName atomically:NO];
        NSLog(@"Wrote to golden file at %@", goldenName);
    } else {
        NSImage *golden = [[NSImage alloc] initWithContentsOfFile:goldenName];
        NSData *goldenData = [golden rawPixelsInRGBColorSpace];
        NSData *actualData = [actual rawPixelsInRGBColorSpace];
        BOOL ok = [goldenData isEqual:actualData];
        if (!ok) {
            NSString *failPath = @"/tmp/failed-test.png";
            [[actual dataForFileOfType:NSPNGFileType] writeToFile:failPath atomically:NO];
            NSLog(@"Test “%@” about to fail.\nActual output in %@.\nExpected output in %@",
                  name, failPath, goldenName);
        }
        assert(ok);
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

// Character selection
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 2)];
}

// Box selection
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 5)];
}

// Multiple discontinuous selection
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 5)];
}

// Windowed character selection
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 5)];
}

// Selected tab orphan
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
                      createGolden:gCreateGoldens
                              size:VT100GridSizeMake(9, 2)];
}

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
                      createGolden:gCreateGoldens
                              size:VT100GridSizeMake(9, 2)];
}

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
                      createGolden:gCreateGoldens
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 2)];
}

// Cursor guide
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 5)];
}

// Badge
- (void)testBadge {
    [self doGoldenTestForInput:@"\n\n\n\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\x1b[42mabc"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setBadgeLabel:@"Badge"];
                          }
              profileOverrides:nil
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

// This test is really slow
#if 0
// 256 colors in color map
- (void)test256Colors {
    // Tests every combo of fg and bg colors in the set of 256 indexed colors.
    NSMutableString *input = [NSMutableString string];
    for (int fg = 16; fg < 256; fg++) {
        for (int bg = 16; bg < 256; bg++) {
            [input appendFormat:@"%@%@x",
             [self sgrSequenceWithSubparams:@[ @38, @5, @(fg) ]],
             [self sgrSequenceWithSubparams:@[ @48, @5, @(bg) ]] ];
        }
        [input appendFormat:@"\r\n"];
    }
    [self doGoldenTestForInput:input
                          name:@"256-colors"
                          hook:nil
              profileOverrides:nil
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(257, 257)];
}
#endif

- (void)test24BitColor {
    [self doGoldenTestForInput:@"\x1b[38:2:17:133:177mFg\x1b[48:2:177:133:17mBg"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:nil
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(5, 2)];
}

// Horizontal spacing
- (void)testHorizontalSpacing {
    [self doGoldenTestForInput:@"abc"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_HORIZONTAL_SPACING: @2.0 }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(4, 2)];
}

// Vertical spacing
- (void)testVerticalSpacing {
    [self doGoldenTestForInput:@"abc\r\ndef"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_VERTICAL_SPACING: @2.0 }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(4, 3)];
}

// Background stripes
- (void)testBackgroundStripes {
    [self doGoldenTestForInput:@"abc\r\ndef\r\n"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setBadgeLabel:@"Badge"];
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.showStripes = YES;
                              };
                          }
              profileOverrides:nil
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

- (void)testNoAntiAlias {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @NO,
                                  KEY_NONASCII_ANTI_ALIASED: @NO,
                                  KEY_USE_NONASCII_FONT: @YES }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

- (void)testAsciiAntiAliasOnly {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @YES,
                                  KEY_NONASCII_ANTI_ALIASED: @NO,
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

- (void)testNonAsciiAntiAliasOnly {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_ASCII_ANTI_ALIASED: @NO,
                                  KEY_NONASCII_ANTI_ALIASED: @YES,
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

- (void)testUseNonAsciiFont {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_NON_ASCII_FONT: [[NSFont fontWithName:@"Courier" size:8] stringValue],
                                  KEY_USE_NONASCII_FONT: @YES  }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}

- (void)testDontUseNonAsciiFont {
    [self doGoldenTestForInput:@"aé"
                          name:NSStringFromSelector(_cmd)
                          hook:nil
              profileOverrides:@{ KEY_NON_ASCII_FONT: [[NSFont fontWithName:@"Courier" size:8] stringValue],
                                  KEY_USE_NONASCII_FONT: @NO  }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(80, 25)];
}


- (void)testBlinkingTextHidden {
    [self doGoldenTestForInput:@"a\x1b[5mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = NO;
                              };
                          }
              profileOverrides:@{ KEY_BLINK_ALLOWED: @YES }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(3, 2)];
}

- (void)testBlinkingTextVisible {
    [self doGoldenTestForInput:@"a\x1b[5mb"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              textView.drawingHook = ^(iTermTextDrawingHelper *helper) {
                                  helper.blinkingItemsVisible = YES;
                              };
                          }
              profileOverrides:@{ KEY_BLINK_ALLOWED: @YES }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(3, 2)];
}

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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(2, 2)];
}

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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(2, 2)];
}

// Scrollback overflow
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(2, 2)];
}


// Transparency
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
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(2, 2)];
}

// IME with (without) Ambiguous is double width
- (void)testIME {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"abc"
                                        selectedRange:NSMakeRange(3, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5 }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(2, 2)];
}

- (void)testIMEWithAmbiguousIsDoubleWidth {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"Γ"  // U+0393 (hex), Greek capital gamma, is ambiguous width
                                        selectedRange:NSMakeRange(1, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5,
                                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @YES }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(3, 2)];
}

- (void)testIMEWithAmbiguousIsNotDoubleWidth {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              [textView setMarkedText:@"Γ"  // U+0393 (hex), Greek capital gamma, is ambiguous width
                                        selectedRange:NSMakeRange(1, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5,
                                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(3, 2)];
}

- (void)testIMEWrapsDoubleWidthAtEndOfLine {
    [self doGoldenTestForInput:@"x"
                          name:NSStringFromSelector(_cmd)
                          hook:^(PTYTextView *textView) {
                              // The DWC should be wrapped onto the second line
                              [textView setMarkedText:@"aᄀ"  // U+1100 (hex), HANGUL CHOSEONG KIYEOK, is double width.
                                        selectedRange:NSMakeRange(2, 0)
                                     replacementRange:NSMakeRange(0, 0)];
                          }
              profileOverrides:@{ KEY_TRANSPARENCY: @0.5,
                                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO }
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(3, 2)];
}

// Background image low blending
// Background image high blending
// Reverse video
// Find cursor
// Smart cursor color
// Non-filled in block cursor
// Force filled in cursor
// Organically filled in block cursor
// Bright bold
// Underlined host name
// transparency alpha, whatever that is
// hidden cursor
// Each cursor type
// Min contrast
// Non ascii font
// Timestamps
// Retina vs nonretina fake bold
// IME
// Multi line IME
// Mark
// Notes
// Dimming
// Cursor boost
// Dimming + cursor boost
// Find matches
// Oversize glyphs
// Emoji
// Emoji exclamation point
// Combining mark
// Surrogate pair
// DWC
// Line drawing

- (void)testBasicDraw {
    [self doGoldenTestForInput:@"abc"
                          name:@"basic"
                          hook:nil
              profileOverrides:nil
                  createGolden:gCreateGoldens
                          size:VT100GridSizeMake(4, 2)];
}

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
                          name:@"ansiColors"
                          hook:nil
              profileOverrides:nil
                  createGolden:gCreateGoldens
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

- (void)textViewPasteFileWithBase64Encoding {
    [self registerCall:_cmd];
}

- (BOOL)textViewCanPasteFile {
    return _canPasteFile;
}

- (void)refreshAndStartTimerIfNeeded {
    [self registerCall:_cmd];
}

@end
