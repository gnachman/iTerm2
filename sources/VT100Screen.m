
#import "VT100Screen.h"
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"
#import "VT100Screen+Resizing.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "DVR.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermColorMap.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermNotificationController.h"
#import "iTermImage.h"
#import "iTermImageInfo.h"
#import "iTermImageMark.h"
#import "iTermURLMark.h"
#import "iTermOrderEnforcer.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermShellHistoryController.h"
#import "iTermTextExtractor.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSImage+iTerm.h"
#import "PTYNoteViewController.h"
#import "PTYTextView.h"
#import "RegexKitLite.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100InlineImageHelper.h"
#import "VT100LineInfo.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "VT100WorkingDirectory.h"
#import "VT100DCSParser.h"
#import "VT100Screen+Mutation.h"
#import "VT100ScreenConfiguration.h"
#import "VT100Token.h"
#import "VT100ScreenState.h"

#import <apr-1/apr_base64.h>

NSString *const kScreenStateKey = @"Screen State";

NSString *const kScreenStateTabStopsKey = @"Tab Stops";
NSString *const kScreenStateTerminalKey = @"Terminal State";
NSString *const kScreenStateLineDrawingModeKey = @"Line Drawing Modes";
NSString *const kScreenStateNonCurrentGridKey = @"Non-current Grid";
NSString *const kScreenStateCurrentGridIsPrimaryKey = @"Showing Primary Grid";
NSString *const kScreenStateIntervalTreeKey = @"Interval Tree";
NSString *const kScreenStateSavedIntervalTreeKey = @"Saved Interval Tree";
NSString *const kScreenStateCommandStartXKey = @"Command Start X";
NSString *const kScreenStateCommandStartYKey = @"Command Start Y";
NSString *const kScreenStateNextCommandOutputStartKey = @"Output Start";
NSString *const kScreenStateCursorVisibleKey = @"Cursor Visible";
NSString *const kScreenStateTrackCursorLineMovementKey = @"Track Cursor Line";
NSString *const kScreenStateLastCommandOutputRangeKey = @"Last Command Output Range";
NSString *const kScreenStateShellIntegrationInstalledKey = @"Shell Integration Installed";
NSString *const kScreenStateLastCommandMarkKey = @"Last Command Mark";
NSString *const kScreenStatePrimaryGridStateKey = @"Primary Grid State";
NSString *const kScreenStateAlternateGridStateKey = @"Alternate Grid State";
NSString *const kScreenStateCursorCoord = @"Cursor Coord";
NSString *const kScreenStateProtectedMode = @"Protected Mode";

int kVT100ScreenMinColumns = 2;
int kVT100ScreenMinRows = 2;

static const int kDefaultScreenColumns = 80;
static const int kDefaultScreenRows = 25;

NSString * const kHighlightForegroundColor = @"kHighlightForegroundColor";
NSString * const kHighlightBackgroundColor = @"kHighlightBackgroundColor";

const NSInteger VT100ScreenBigFileDownloadThreshold = 1024 * 1024 * 1024;


@implementation VT100Screen {

    // Used for recording instant replay.
    // This is an inherently shared mutable data structure. I don't think it can be easily moved into
    // the VT100ScreenState model. Instad it will need lots of mutexes :(
    DVR* dvr_;
}

@synthesize dvr = dvr_;

- (instancetype)initWithTerminal:(VT100Terminal *)terminal
                        darkMode:(BOOL)darkMode
                   configuration:(id<VT100ScreenConfiguration>)config {
    self = [super init];
    if (self) {
        _mutableState = [[VT100ScreenMutableState alloc] init];
        _state = [_mutableState retain];
        _mutableState.colorMap.darkMode = darkMode;

        assert(terminal);
        [self setTerminal:terminal];
        _mutableState.primaryGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(kDefaultScreenColumns,
                                                                                       kDefaultScreenRows)
                                                            delegate:self] autorelease];
        _mutableState.currentGrid = _mutableState.primaryGrid;
        _mutableState.temporaryDoubleBuffer.delegate = self;

        [self mutSetInitialTabStops];

        [iTermNotificationController sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes] * 1024 * 1024];
        [self setConfig:config];
    }
    return self;
}

- (void)dealloc {
    [dvr_ release];
    [_state release];
    [_mutableState release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, _state.currentGrid];
}

#pragma mark - APIs

- (void)setDelegate:(id<VT100ScreenDelegate>)delegate {
    [self mutSetDelegate:delegate];
}

- (id<VT100ScreenDelegate>)delegate {
    return delegate_;
}

- (void)setTerminal:(VT100Terminal *)terminal {
    DLog(@"set terminal=%@", terminal);
    [self mutSetTerminal:terminal];
}

- (VT100Terminal *)terminal {
    return _state.terminal;
}

- (void)setSize:(VT100GridSize)size {
    [self mutSetSize:size];
}

- (VT100GridSize)size {
    return _state.currentGrid.size;
}

- (NSSize)viewSize {
    NSSize cellSize = [delegate_ screenCellSize];
    VT100GridSize gridSize = _state.currentGrid.size;
    return NSMakeSize(cellSize.width * gridSize.width, cellSize.height * gridSize.height);
}

- (BOOL)allCharacterSetPropertiesHaveDefaultValues {
    for (int i = 0; i < NUM_CHARSETS; i++) {
        if ([_state.charsetUsesLineDrawingMode containsObject:@(i)]) {
            return NO;
        }
    }
    if ([_state.terminal charset]) {
        return NO;
    }
    return YES;
}

- (void)showCursor:(BOOL)show
{
    [delegate_ screenSetCursorVisible:show];
}

- (BOOL)shouldQuellBell {
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    const NSTimeInterval interval = now - _state.lastBell;
    const BOOL result = interval < [iTermAdvancedSettingsModel bellRateLimit];
    if (!result) {
        _mutableState.lastBell = now;
    }
    return result;
}

- (void)activateBell {
    if ([delegate_ screenShouldIgnoreBellWhichIsAudible:_state.audibleBell visible:_state.flashBell]) {
        return;
    }
    if ([self shouldQuellBell]) {
        DLog(@"Quell bell");
    } else {
        if (_state.audibleBell) {
            DLog(@"Beep: ring audible bell");
            NSBeep();
        }
        if (_state.showBellIndicator) {
            [delegate_ screenShowBellIndicator];
        }
        if (_state.flashBell) {
            [delegate_ screenFlashImage:kiTermIndicatorBell];
        }
    }
    [delegate_ screenIncrementBadge];
}

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow - self.numberOfScrollbackLines;

    VT100GridRun gridRun = [_state.currentGrid gridRunFromRange:range relativeToRow:lineNumber];
    DLog(@"Highlight range %@ with colors %@ at lineNumber %@ giving grid run %@",
         NSStringFromRange(range),
         colors,
         @(lineNumber),
         VT100GridRunDescription(gridRun));

    if (gridRun.length > 0) {
        NSColor *foreground = colors[kHighlightForegroundColor];
        NSColor *background = colors[kHighlightBackgroundColor];
        [self mutHighlightRun:gridRun withForegroundColor:foreground backgroundColor:background];
    }
}

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                  URLCode:(unsigned int)code {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow - self.numberOfScrollbackLines;
    if (lineNumber < 0) {
        return;
    }
    VT100GridRun gridRun = [_state.currentGrid gridRunFromRange:range relativeToRow:lineNumber];
    if (gridRun.length > 0) {
        [self mutLinkRun:gridRun withURLCode:code];
    }
}

- (void)storeLastPositionInLineBufferAsFindContextSavedPosition {
    [self mutStoreLastPositionInLineBufferAsFindContextSavedPosition];
}

- (VT100GridAbsCoord)commandStartCoord {
    return _state.commandStartCoord;
}

- (void)loadInitialColorTable {
    for (int i = 16; i < 256; i++) {
        NSColor *theColor = [NSColor colorForAnsi256ColorIndex:i];
        [self setColor:theColor forKey:kColorMap8bitBase + i];
    }
}

- (void)setColor:(NSColor *)color forKey:(int)key {
    [self mutSetColor:color forKey:key];
}

- (void)resetNonAnsiColorWithKey:(int)colorKey {
    NSColor *theColor = [NSColor colorForAnsi256ColorIndex:colorKey - kColorMap8bitBase];
    [self setColor:theColor forKey:colorKey];
}

- (void)setDimOnlyText:(BOOL)dimOnlyText {
    [self mutSetDimOnlyText:dimOnlyText];
}

- (void)setDarkMode:(BOOL)darkMode {
    [self mutSetDarkMode:darkMode];
}

- (void)setUseSeparateColorsForLightAndDarkMode:(BOOL)value {
    [self mutSetUseSeparateColorsForLightAndDarkMode:value];
}

- (void)setMinimumContrast:(float)value {
    [self mutSetMinimumContrast:value];
}

- (void)setMutingAmount:(double)value {
    [self mutSetMutingAmount:value];
}

- (void)setDimmingAmount:(double)value {
    [self mutSetDimmingAmount:value];
}

#pragma mark - PTYTextViewDataSource

- (BOOL)showingAlternateScreen {
    return _state.currentGrid == _state.altGrid;
}

- (NSSet<NSString *> *)sgrCodesForChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    return [_state.terminal sgrCodesForCharacter:c externalAttributes:ea];
}

- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord {
    [self commandDidStartAt:VT100GridAbsCoordMake(coord.x, coord.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow])];
}

- (void)commandDidStartAt:(VT100GridAbsCoord)coord {
    [self mutSetCommandStartCoord:coord];
}

- (BOOL)confirmBigDownloadWithBeforeSize:(NSInteger)sizeBefore
                               afterSize:(NSInteger)afterSize
                                    name:(NSString *)name {
    if (sizeBefore < VT100ScreenBigFileDownloadThreshold && afterSize > VT100ScreenBigFileDownloadThreshold) {
        if (![self.delegate screenConfirmDownloadNamed:name canExceedSize:VT100ScreenBigFileDownloadThreshold]) {
            DLog(@"Aborting big download");
            [self mutStopTerminalReceivingFile];
            return NO;
        }
    }
    return YES;
}

- (void)hideOnScreenNotesAndTruncateSpanners {
    int screenOrigin = [self numberOfScrollbackLines];
    VT100GridCoordRange screenRange =
        VT100GridCoordRangeMake(0,
                                screenOrigin,
                                [self width],
                                screenOrigin + self.height);
    Interval *screenInterval = [self intervalForGridCoordRange:screenRange];
    for (id<IntervalTreeObject> note in [_state.intervalTree objectsInInterval:screenInterval]) {
        if (note.entry.interval.location < screenInterval.location) {
            // Truncate note so that it ends just before screen.
            note.entry.interval.length = screenInterval.location - note.entry.interval.location;
        }
        if ([note isKindOfClass:[PTYNoteViewController class]]) {
            [(PTYNoteViewController *)note setNoteHidden:YES];
        }
    }
}

- (void)promptDidStartAt:(VT100GridAbsCoord)coord {
    [self mutPromptDidStartAt:coord];
}

// This is a wee hack until PTYTextView breaks its direct dependence on PTYSession
- (PTYSession *)session {
    return (PTYSession *)delegate_;
}

// Returns the number of lines in scrollback plus screen height.
- (int)numberOfLines {
    return [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width] + _state.currentGrid.size.height;
}

- (int)width {
    return _state.currentGrid.size.width;
}

- (int)height {
    return _state.currentGrid.size.height;
}

- (int)cursorX {
    return _state.currentGrid.cursorX + 1;
}

- (int)cursorY {
    return _state.currentGrid.cursorY + 1;
}

- (void)enumerateLinesInRange:(NSRange)range block:(void (^)(int, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block {
    NSInteger i = range.location;
    const NSInteger lastLine = NSMaxRange(range);
    const NSInteger numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    const int width = self.width;
    while (i < lastLine) {
        if (i < numLinesInLineBuffer) {
            [_state.linebuffer enumerateLinesInRange:NSMakeRange(i, lastLine - i)
                                               width:width
                                               block:block];
            i = numLinesInLineBuffer;
            continue;
        }
        BOOL stop = NO;
        const int screenIndex = i - numLinesInLineBuffer;
        block(i,
              [self screenCharArrayAtScreenIndex:screenIndex],
              [self metadataAtScreenIndex:screenIndex],
              &stop);
        if (stop) {
            return;
        }
        i += 1;
    }
}

- (ScreenCharArray *)screenCharArrayForLine:(int)line {
    const NSInteger numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    if (line < numLinesInLineBuffer) {
        const BOOL eligibleForDWC = (line == numLinesInLineBuffer - 1 &&
                                     [_state.currentGrid screenCharsAtLineNumber:0][1].code == DWC_RIGHT);
        return [[_state.linebuffer wrappedLineAtIndex:line width:self.width continuation:NULL] paddedToLength:self.width
                                                                                               eligibleForDWC:eligibleForDWC];
    }
    return [self screenCharArrayAtScreenIndex:line - numLinesInLineBuffer];
}

- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    const screen_char_t *line = [_state.currentGrid screenCharsAtLineNumber:index];
    const int width = self.width;
    ScreenCharArray *array = [[[ScreenCharArray alloc] initWithLine:line
                                                             length:width
                                                       continuation:line[width]] autorelease];
    return array;
}

- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber {
    ITBetaAssert(lineNumber >= 0, @"Negative index to getLineAtIndex");
    const int width = _state.currentGrid.size.width;
    int numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:width];
    if (lineNumber >= numLinesInLineBuffer) {
        return [_state.currentGrid immutableMetadataAtLineNumber:lineNumber - numLinesInLineBuffer];
    } else {
        return [_state.linebuffer metadataForLineNumber:lineNumber width:width];
    }
}

- (iTermImmutableMetadata)metadataAtScreenIndex:(int)index {
    return [_state.currentGrid immutableMetadataAtLineNumber:index];
}

- (id<iTermExternalAttributeIndexReading>)externalAttributeIndexForLine:(int)y {
    iTermImmutableMetadata metadata = [self metadataOnLine:y];
    return iTermImmutableMetadataGetExternalAttributesIndex(metadata);
}

// Like getLineAtIndex:withBuffer:, but uses dedicated storage for the result.
// This function is dangerous! It writes to an internal buffer and returns a
// pointer to it. Better to use getLineAtIndex:withBuffer:.
- (const screen_char_t *)getLineAtIndex:(int)theIndex {
    return [self getLineAtIndex:theIndex withBuffer:[_state.currentGrid resultLine]];
}

// theIndex = 0 for first line in history; for sufficiently large values, it pulls from the current
// grid.
- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer {
    ITBetaAssert(theIndex >= 0, @"Negative index to getLineAtIndex");
    int numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    if (theIndex >= numLinesInLineBuffer) {
        // Get a line from the circular screen buffer
        return [_state.currentGrid screenCharsAtLineNumber:(theIndex - numLinesInLineBuffer)];
    } else {
        // Get a line from the scrollback buffer.
        screen_char_t continuation;
        int cont = [_state.linebuffer copyLineToBuffer:buffer
                                                 width:_state.currentGrid.size.width
                                               lineNum:theIndex
                                          continuation:&continuation];
        if (cont == EOL_SOFT &&
            theIndex == numLinesInLineBuffer - 1 &&
            [_state.currentGrid screenCharsAtLineNumber:0][1].code == DWC_RIGHT &&
            buffer[_state.currentGrid.size.width - 1].code == 0) {
            // The last line in the scrollback buffer is actually a split DWC
            // if the first char on the screen is double-width and the buffer is soft-wrapped without
            // a last char.
            cont = EOL_DWC;
        }
        if (cont == EOL_DWC) {
            buffer[_state.currentGrid.size.width - 1].code = DWC_SKIP;
            buffer[_state.currentGrid.size.width - 1].complexChar = NO;
        }
        buffer[_state.currentGrid.size.width] = continuation;
        buffer[_state.currentGrid.size.width].code = cont;

        return buffer;
    }
}

- (NSArray<ScreenCharArray *> *)gridLinesInRange:(const NSRange)range {
    const int width = _state.currentGrid.size.width;
    const int numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:width];
    NSMutableArray<ScreenCharArray *> *result = [NSMutableArray array];
    for (NSInteger i = range.location; i < NSMaxRange(range); i++) {
        const screen_char_t *line = [_state.currentGrid screenCharsAtLineNumber:i - numLinesInLineBuffer];
        ScreenCharArray *array = [[[ScreenCharArray alloc] initWithLine:line
                                                                 length:width
                                                           continuation:line[width]] autorelease];
        [result addObject:array];
    }
    return result;
}

- (NSArray<ScreenCharArray *> *)historyLinesInRange:(const NSRange)range {
    return [_state.linebuffer wrappedLinesFromIndex:range.location width:_state.currentGrid.size.width count:range.length];
}

- (NSArray<ScreenCharArray *> *)linesInRange:(NSRange)range {
    const int numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    const NSRange gridRange = NSMakeRange(numLinesInLineBuffer, _state.currentGrid.size.height);
    const NSRange historyRange = NSMakeRange(0, numLinesInLineBuffer);
    const NSRange rangeForGrid = NSIntersectionRange(range, gridRange);

    NSArray<ScreenCharArray *> *gridLines = nil;
    if (rangeForGrid.length > 0) {
        gridLines = [self gridLinesInRange:rangeForGrid];
    } else {
        gridLines = @[];
    }
    const NSRange rangeForHistory = NSIntersectionRange(range, historyRange);
    NSArray<ScreenCharArray *> *historyLines = nil;
    if (rangeForHistory.length > 0) {
        historyLines = [self historyLinesInRange:rangeForHistory];
    } else {
        historyLines = @[];
    }

    return [historyLines arrayByAddingObjectsFromArray:gridLines];
}

- (int)numberOfScrollbackLines {
    return [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
}

- (int)scrollbackOverflow {
    return _state.scrollbackOverflow;
}

- (void)resetScrollbackOverflow {
    [self mutResetScrollbackOverflow];
}

- (long long)totalScrollbackOverflow {
    return _state.cumulativeScrollbackOverflow;
}

- (long long)absoluteLineNumberOfCursor
{
    return [self totalScrollbackOverflow] + [self numberOfLines] - [self height] + _state.currentGrid.cursorY;
}

- (int)lineNumberOfCursor
{
    return [self numberOfLines] - [self height] + _state.currentGrid.cursorY;
}

- (BOOL)continueFindAllResults:(NSMutableArray<SearchResult *> *)results
                     inContext:(FindContext*)context {
    context.hasWrapped = YES;
    NSDate* start = [NSDate date];
    BOOL keepSearching;
    do {
        keepSearching = [self mutContinueFindResultsInContext:context
                                                      toArray:results];
    } while (keepSearching &&
             [[NSDate date] timeIntervalSinceDate:start] < context.maxTime);
    if (results.count > 0) {
        [self.delegate screenRefreshFindOnPageView];
    }
    return keepSearching;
}

- (FindContext *)findContext {
    return _state.findContext;
}

- (NSString *)debugString {
    return [_state.currentGrid debugString];
}

- (NSString *)compactLineDumpWithHistory {
    NSMutableString *string = [NSMutableString stringWithString:[_state.linebuffer compactLineDumpWithWidth:[self width]
                                                                                       andContinuationMarks:NO]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[_state.currentGrid compactLineDump]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarks {
    NSMutableString *string = [NSMutableString stringWithString:[_state.linebuffer compactLineDumpWithWidth:[self width]
                                                                                       andContinuationMarks:YES]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[_state.currentGrid compactLineDumpWithContinuationMarks]];
    return string;
}

- (NSString *)compactLineDumpWithContinuationMarks {
    return [_state.currentGrid compactLineDumpWithContinuationMarks];
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers {
    NSMutableString *string =
        [NSMutableString stringWithString:[_state.linebuffer compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
    NSMutableArray *lines = [[[string componentsSeparatedByString:@"\n"] mutableCopy] autorelease];
    long long absoluteLineNumber = self.totalScrollbackOverflow;
    for (int i = 0; i < lines.count; i++) {
        lines[i] = [NSString stringWithFormat:@"%8lld:        %@", absoluteLineNumber++, lines[i]];
    }

    if ([string length]) {
        [lines addObject:@"- end of history -"];
    }
    NSString *gridDump = [_state.currentGrid compactLineDumpWithContinuationMarks];
    NSArray *gridLines = [gridDump componentsSeparatedByString:@"\n"];
    for (int i = 0; i < gridLines.count; i++) {
        [lines addObject:[NSString stringWithFormat:@"%8lld (%04d): %@", absoluteLineNumber++, i, gridLines[i]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)compactLineDump {
    return [_state.currentGrid compactLineDump];
}

- (id<VT100GridReading>)currentGrid {
    return _state.currentGrid;
}

- (BOOL)isAllDirty {
    return _state.currentGrid.isAllDirty;
}

- (void)setRangeOfCharsAnimated:(NSRange)range onLine:(int)line {
    // TODO: Store range
    [_mutableState.animatedLines addIndex:line];
}

- (void)resetAnimatedLines {
    [_mutableState.animatedLines removeAllIndexes];
}

- (BOOL)isDirtyAtX:(int)x Y:(int)y {
    return [_state.currentGrid isCharDirtyAt:VT100GridCoordMake(x, y)];
}

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    return [_state.currentGrid dirtyIndexesOnLine:line];
}

- (void)saveToDvr:(NSIndexSet *)cleanLines {
    if (!dvr_) {
        return;
    }

    DVRFrameInfo info;
    info.cursorX = _state.currentGrid.cursorX;
    info.cursorY = _state.currentGrid.cursorY;
    info.height = _state.currentGrid.size.height;
    info.width = _state.currentGrid.size.width;

    [dvr_ appendFrame:[_state.currentGrid orderedLines]
               length:sizeof(screen_char_t) * (_state.currentGrid.size.width + 1) * (_state.currentGrid.size.height)
             metadata:[_state.currentGrid metadataArray]
           cleanLines:cleanLines
                 info:&info];
}

- (BOOL)shouldSendContentsChangedNotification {
    return [delegate_ screenShouldSendContentsChangedNotification];
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    return [_state.currentGrid dirtyRangeForLine:y];
}

- (BOOL)textViewGetAndResetHasScrolled {
    return [self mutGetAndResetHasScrolled];
}

- (NSDate *)timestampForLine:(int)y {
    int numLinesInLineBuffer = [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    NSTimeInterval interval;
    if (y >= numLinesInLineBuffer) {
        interval = [_state.currentGrid timestampForLine:y - numLinesInLineBuffer];
    } else {
        interval = [_state.linebuffer metadataForLineNumber:y width:_state.currentGrid.size.width].timestamp;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:interval];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range
                                  width:(int)width
                            linesOffset:(long long)linesOffset {
    VT100GridCoord start = range.start;
    VT100GridCoord end = range.end;
    long long si = start.y;
    si += linesOffset;
    si *= (width + 1);
    si += start.x;
    long long ei = end.y;
    ei += linesOffset;
    ei *= (width + 1);
    ei += end.x;
    if (ei < si) {
        long long temp = ei;
        ei = si;
        si = temp;
    }
    return [Interval intervalWithLocation:si length:ei - si];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range {
    return [self intervalForGridCoordRange:range
                                     width:self.width
                               linesOffset:[self totalScrollbackOverflow]];
}

- (VT100GridCoordRange)coordRangeForInterval:(Interval *)interval {
    VT100GridCoordRange result;
    const int w = self.width + 1;
    result.start.y = interval.location / w - [self totalScrollbackOverflow];
    result.start.x = interval.location % w;
    result.end.y = interval.limit / w - [self totalScrollbackOverflow];
    result.end.x = interval.limit % w;

    if (result.start.y < 0) {
        result.start.y = 0;
        result.start.x = 0;
    }
    if (result.start.x == self.width) {
        result.start.y += 1;
        result.start.x = 0;
    }
    return result;
}

- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord {
    coord.x--;
    while (coord.x < 0) {
        coord.x += self.width;
        coord.y--;
        if (coord.y < 0) {
            coord.y = 0;
            return coord;
        }
    }
    return coord;
}

- (void)setWorkingDirectory:(NSString *)workingDirectory onLine:(int)line pushed:(BOOL)pushed {
    [self mutSetWorkingDirectory:workingDirectory
                          onLine:line
                          pushed:pushed
                           token:[[_mutableState.setWorkingDirectoryOrderEnforcer newToken] autorelease]];
}

- (id)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    long long pos = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                            line + 1,
                                                                            0,
                                                                            line + 1)].location;
    if (pos < 0) {
        return nil;
    }
    NSEnumerator *enumerator = [_state.intervalTree reverseEnumeratorAt:pos];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ cls ]];
    } while (objects && !objects.count);
    if (objects.count) {
        // We want the last object because they are sorted chronologically.
        return [objects lastObject];
    } else {
        return nil;
    }
}

- (VT100RemoteHost *)remoteHostOnLine:(int)line {
    return (VT100RemoteHost *)[self objectOnOrBeforeLine:line ofClass:[VT100RemoteHost class]];
}

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line {
    DLog(@"Figuring out path for %@ on line %d", filename, line);
    VT100RemoteHost *remoteHost = [self remoteHostOnLine:line];
    if (!remoteHost.username || !remoteHost.hostname) {
        DLog(@"nil username or hostname; return nil");
        return nil;
    }
    if (remoteHost.isLocalhost) {
        DLog(@"Is localhost; return nil");
        return nil;
    }
    NSString *workingDirectory = [self workingDirectoryOnLine:line];
    if (!workingDirectory) {
        DLog(@"No working directory; return nil");
        return nil;
    }
    NSString *path;
    if ([filename hasPrefix:@"/"]) {
        DLog(@"Filename is absolute path, so that's easy");
        path = filename;
    } else {
        DLog(@"Use working directory of %@", workingDirectory);
        path = [workingDirectory stringByAppendingPathComponent:filename];
    }
    SCPPath *scpPath = [[[SCPPath alloc] init] autorelease];
    scpPath.path = path;
    scpPath.hostname = remoteHost.hostname;
    scpPath.username = remoteHost.username;
    return scpPath;
}

- (NSString *)workingDirectoryOnLine:(int)line {
    VT100WorkingDirectory *workingDirectory =
        [self objectOnOrBeforeLine:line ofClass:[VT100WorkingDirectory class]];
    return workingDirectory.workingDirectory;
}

- (iTermIntervalTreeObjectType)intervalTreeObserverTypeForObject:(id<IntervalTreeObject>)object {
    if ([object isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *mark = (VT100ScreenMark *)object;
        if (!mark.hasCode) {
            return iTermIntervalTreeObjectTypeManualMark;
        }
        if (mark.code == 0) {
            return iTermIntervalTreeObjectTypeSuccessMark;
        }
        if (mark.code >= 128 && mark.code <= 128 + 32) {
            return iTermIntervalTreeObjectTypeOtherMark;
        }
        return iTermIntervalTreeObjectTypeErrorMark;
    }

    if ([object isKindOfClass:[PTYNoteViewController class]]) {
        return iTermIntervalTreeObjectTypeAnnotation;
    }
    return iTermIntervalTreeObjectTypeUnknown;
}

- (void)removeInaccessibleNotes {
    long long lastDeadLocation = [self totalScrollbackOverflow] * (self.width + 1);
    if (lastDeadLocation > 0) {
        Interval *deadInterval = [Interval intervalWithLocation:0 length:lastDeadLocation + 1];
        for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:deadInterval]) {
            if ([obj.entry.interval limit] <= lastDeadLocation) {
                [self mutRemoveObjectFromIntervalTree:obj];
            }
        }
    }
}

- (BOOL)markIsValid:(iTermMark *)mark {
    return [_state.intervalTree containsObject:mark];
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass {
    return [self mutAddMarkStartingAtAbsoluteLine:line oneLine:oneLine ofClass:markClass];
}

- (VT100GridCoordRange)coordRangeOfNote:(PTYNoteViewController *)note {
    return [self coordRangeForInterval:note.entry.interval];
}

- (NSArray *)charactersWithNotesOnLine:(int)line {
    NSMutableArray *result = [NSMutableArray array];
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                                 line,
                                                                                 0,
                                                                                 line + 1)];
    NSArray *objects = [_state.intervalTree objectsInInterval:interval];
    for (id<IntervalTreeObject> note in objects) {
        if ([note isKindOfClass:[PTYNoteViewController class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:note.entry.interval];
            VT100GridRange gridRange;
            if (range.start.y < line) {
                gridRange.location = 0;
            } else {
                gridRange.location = range.start.x;
            }
            if (range.end.y > line) {
                gridRange.length = self.width + 1 - gridRange.location;
            } else {
                gridRange.length = range.end.x - gridRange.location;
            }
            [result addObject:[NSValue valueWithGridRange:gridRange]];
        }
    }
    return result;
}

- (NSArray *)notesInRange:(VT100GridCoordRange)range {
    Interval *interval = [self intervalForGridCoordRange:range];
    NSArray *objects = [_state.intervalTree objectsInInterval:interval];
    NSMutableArray *notes = [NSMutableArray array];
    for (id<IntervalTreeObject> o in objects) {
        if ([o isKindOfClass:[PTYNoteViewController class]]) {
            [notes addObject:o];
        }
    }
    return notes;
}

- (VT100ScreenMark *)lastPromptMark {
    return [self lastMarkMustBePrompt:YES class:[VT100ScreenMark class]];
}

- (VT100ScreenMark *)promptMarkWithGUID:(NSString *)guid {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:obj];
            if (!screenMark) {
                continue;
            }
            if (!screenMark.isPrompt) {
                continue;
            }
            if ([screenMark.guid isEqualToString:guid]) {
                return screenMark;
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (void)enumerateObservableMarks:(void (^ NS_NOESCAPE)(iTermIntervalTreeObjectType, NSInteger))block {
    const NSInteger overflow = [self totalScrollbackOverflow];
    for (NSArray *objects in _state.intervalTree.forwardLimitEnumerator) {
        for (id<IntervalTreeObject> obj in objects) {
            const iTermIntervalTreeObjectType type = [self intervalTreeObserverTypeForObject:obj];
            if (type == iTermIntervalTreeObjectTypeUnknown) {
                continue;
            }
            NSInteger line = [self coordRangeForInterval:obj.entry.interval].start.y + overflow;
            block(type, line);
        }
    }
}

- (void)enumeratePromptsFrom:(NSString *)maybeFirst
                          to:(NSString *)maybeLast
                       block:(void (^ NS_NOESCAPE)(VT100ScreenMark *mark))block {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    BOOL foundFirst = (maybeFirst == nil);
    while (objects) {
        for (id obj in objects) {
            VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:obj];
            if (!screenMark) {
                continue;
            }
            if (!screenMark.isPrompt) {
                continue;
            }
            if (!foundFirst) {
                if (![screenMark.guid isEqualToString:maybeFirst]) {
                    continue;
                }
                foundFirst = YES;
            }
            block(screenMark);
            if (maybeLast && [screenMark.guid isEqualToString:maybeLast]) {
                return;
            }
        }
        objects = [enumerator nextObject];
    }
}

- (void)clearToLastMark {
    const long long overflow = self.totalScrollbackOverflow;
    const int cursorLine = self.currentGrid.cursor.y + self.numberOfScrollbackLines;
    VT100ScreenMark *lastMark = [self lastMarkPassingTest:^BOOL(__kindof id<IntervalTreeObject> obj) {
        if (![obj isKindOfClass:[VT100ScreenMark class]]) {
            return NO;
        }
        VT100ScreenMark *mark = obj;
        const VT100GridCoord intervalStart = [self coordRangeForInterval:mark.entry.interval].start;
        if (intervalStart.y >= self.numberOfScrollbackLines + self.currentGrid.cursor.y) {
            return NO;
        }
        // Found a screen mark above the cursor.
        return YES;
    }];
    long long line = overflow;
    if (lastMark) {
        const VT100GridCoordRange range = [self coordRangeForInterval:lastMark.entry.interval];
        line = overflow + range.end.y;
        if (range.end.y != cursorLine - 1) {
            // Unless we're erasing exactly the line above the cursor, preserve the line with the mark.
            line += 1;
        }
    }
    [self clearFromAbsoluteLineToEnd:line];
}

- (VT100ScreenMark *)lastMark {
    return [self lastMarkMustBePrompt:NO class:[VT100ScreenMark class]];
}

- (VT100RemoteHost *)lastRemoteHost {
    return [self lastMarkMustBePrompt:NO class:[VT100RemoteHost class]];
}

- (id)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            if ([obj isKindOfClass:theClass]) {
                if (wantPrompt && [obj isPrompt]) {
                    return obj;
                } else if (!wantPrompt) {
                    return obj;
                }
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (__kindof id<IntervalTreeObject>)lastMarkPassingTest:(BOOL (^)(__kindof id<IntervalTreeObject>))block {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            if (block(obj)) {
                return obj;
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (VT100ScreenMark *)markOnLine:(int)line {
    return _state.markCache[@([self totalScrollbackOverflow] + line)];
}

- (NSArray *)lastMarksOrNotes {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYNoteViewController class],
                                                   [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)firstMarksOrNotes {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYNoteViewController class],
                                                   [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)lastMarks {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)firstMarks {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)lastAnnotations {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYNoteViewController class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)firstAnnotations {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYNoteViewController class] ]
                                usingEnumerator:enumerator];
}

- (NSArray *)firstMarkBelongingToAnyClassIn:(NSArray<Class> *)allowedClasses
                            usingEnumerator:(NSEnumerator *)enumerator {
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:allowedClasses];
    } while (objects && !objects.count);
    return objects;
}

- (long long)lineNumberOfMarkBeforeAbsLine:(long long)absLine {
    const long long overflow = self.totalScrollbackOverflow;
    const long long line = absLine - overflow;
    if (line < 0 || line > INT_MAX) {
        return -1;
    }
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, line, 0, line)];
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return overflow + [self coordRangeForInterval:mark.entry.interval].start.y;
            }
        }
        objects = [enumerator nextObject];
    }
    return -1;
}

- (long long)lineNumberOfMarkAfterAbsLine:(long long)absLine {
    const long long overflow = self.totalScrollbackOverflow;
    const long long line = absLine - overflow;
    if (line < 0 || line > INT_MAX) {
        return -1;
    }
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, line + 1, 0, line + 1)];
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return overflow + [self coordRangeForInterval:mark.entry.interval].end.y;
            }
        }
        objects = [enumerator nextObject];
    }
    return -1;
}

- (NSArray *)marksOfAnyClassIn:(NSArray<Class> *)allowedClasses
                        before:(Interval *)location {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumeratorAt:location.limit];
    return [self firstObjectsFoundWithEnumerator:enumerator
                                    ofAnyClassIn:allowedClasses];
}

- (NSArray *)marksOfAnyClassIn:(NSArray<Class> *)allowedClasses
                         after:(Interval *)location {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumeratorAt:location.limit];
    return [self firstObjectsFoundWithEnumerator:enumerator
                                    ofAnyClassIn:allowedClasses];
}

- (NSArray *)firstObjectsFoundWithEnumerator:(NSEnumerator *)enumerator
                                ofAnyClassIn:(NSArray<Class> *)allowedClasses {
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:allowedClasses];
    } while (objects && !objects.count);
    return objects;
}

- (NSArray *)marksOrNotesBefore:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYNoteViewController class],
                                 [VT100ScreenMark class] ];
    return [self marksOfAnyClassIn:classes before:location];
}

- (NSArray *)marksOrNotesAfter:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYNoteViewController class],
                                 [VT100ScreenMark class] ];
    return [self marksOfAnyClassIn:classes after:location];
}

- (NSArray *)marksBefore:(Interval *)location {
    NSArray<Class> *classes = @[ [VT100ScreenMark class] ];
    return [self marksOfAnyClassIn:classes before:location];
}

- (NSArray *)marksAfter:(Interval *)location {
    NSArray<Class> *classes = @[ [VT100ScreenMark class] ];
    return [self marksOfAnyClassIn:classes after:location];
}

- (NSArray *)annotationsBefore:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYNoteViewController class] ];
    return [self marksOfAnyClassIn:classes before:location];
}

- (NSArray *)annotationsAfter:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYNoteViewController class] ];
    return [self marksOfAnyClassIn:classes after:location];
}

- (BOOL)containsMark:(id<iTermMark>)mark {
    for (id obj in [_state.intervalTree objectsInInterval:mark.entry.interval]) {
        if (obj == mark) {
            return YES;
        }
    }
    return NO;
}

- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval {
    VT100GridCoordRange range = [self coordRangeForInterval:interval];
    return VT100GridRangeMake(range.start.y, range.end.y - range.start.y + 1);
}

- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(VT100ScreenMark *)mark {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumeratorAt:mark.entry.interval.limit];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [VT100ScreenMark class] ]];
        for (VT100ScreenMark *nextMark in objects) {
            if (nextMark.isPrompt) {
                VT100GridCoordRange range;
                range.start = [self coordRangeForInterval:mark.entry.interval].end;
                range.start.x = 0;
                range.start.y++;
                range.end = [self coordRangeForInterval:nextMark.entry.interval].start;
                return range;
            }
        }
    } while (objects && !objects.count);

    // Command must still be running with no subsequent prompt.
    VT100GridCoordRange range;
    range.start = [self coordRangeForInterval:mark.entry.interval].end;
    range.start.x = 0;
    range.start.y++;
    range.end.x = 0;
    range.end.y = self.numberOfLines - self.height + [_state.currentGrid numberOfLinesUsed];
    return range;
}

- (PTYTextViewSynchronousUpdateState *)setUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    return [self mutSetUseSavedGridIfAvailable:useSavedGrid];
}

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow;
    if (lineNumber < 0) {
        return nil;
    }
    if (lineNumber >= self.numberOfLines) {
        return nil;
    }
    // Search backward for start of line
    int i;
    NSMutableData *data = [NSMutableData data];
    *startAbsLineNumber = self.totalScrollbackOverflow;

    // Max radius of lines to search above and below absoluteLineNumber
    const int kMaxRadius = [iTermAdvancedSettingsModel triggerRadius];
    BOOL foundStart = NO;
    for (i = lineNumber - 1; i >= 0 && i >= lineNumber - kMaxRadius; i--) {
        const screen_char_t *line = [self getLineAtIndex:i];
        if (line[self.width].code == EOL_HARD) {
            *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
            foundStart = YES;
            break;
        }
        [data replaceBytesInRange:NSMakeRange(0, 0)
                        withBytes:line
                           length:self.width * sizeof(screen_char_t)];
    }
    if (!foundStart) {
        *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
    }
    BOOL done = NO;
    for (i = lineNumber; !done && i < self.numberOfLines && i < lineNumber + kMaxRadius; i++) {
        const screen_char_t *line = [self getLineAtIndex:i];
        int length = self.width;
        done = line[length].code == EOL_HARD;
        if (done) {
            // Remove trailing newlines
            while (length > 0 && line[length - 1].code == 0 && !line[length - 1].complexChar) {
                --length;
            }
        }
        [data appendBytes:line length:length * sizeof(screen_char_t)];
    }

    return [[[iTermStringLine alloc] initWithScreenChars:data.mutableBytes
                                                  length:data.length / sizeof(screen_char_t)] autorelease];
}

- (BOOL)commandDidEndAtAbsCoord:(VT100GridAbsCoord)coord {
    return [self mutCommandDidEndAtAbsCoord:coord];
}

- (void)appendNativeImageAtCursorWithName:(NSString *)name width:(int)width {
    [self mutAppendNativeImageAtCursorWithName:name width:width];
}

#pragma mark - Private

- (VT100GridCoordRange)commandRange {
    long long offset = [self totalScrollbackOverflow];
    if (_state.commandStartCoord.x < 0) {
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    } else {
        return VT100GridCoordRangeMake(_state.commandStartCoord.x,
                                       MAX(0, _state.commandStartCoord.y - offset),
                                       _state.currentGrid.cursorX,
                                       _state.currentGrid.cursorY + [self numberOfScrollbackLines]);
    }
}

- (BOOL)isAnyCharDirty {
    return [_state.currentGrid isAnyCharDirty];
}

// It's kind of wrong to use VT100GridRun here, but I think it's harmless enough.
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run {
    VT100GridRun result = run;
    int x = result.origin.x;
    int y = result.origin.y;
    ITBetaAssert(y >= 0, @"Negative y to runByTrimmingNullsFromRun");
    const screen_char_t *line = [self getLineAtIndex:y];
    int numberOfLines = [self numberOfLines];
    int width = [self width];
    if (x > 0) {
        while (result.length > 0 && line[x].code == 0 && y < numberOfLines) {
            x++;
            result.length--;
            if (x == width) {
                x = 0;
                y++;
                if (y == numberOfLines) {
                    // Run is all nulls
                    result.length = 0;
                    return result;
                }
                break;
            }
        }
    }
    result.origin = VT100GridCoordMake(x, y);

    VT100GridCoord end = VT100GridRunMax(run, width);
    x = end.x;
    y = end.y;
    ITBetaAssert(y >= 0, @"Negative y to from max of run %@", VT100GridRunDescription(run));
    line = [self getLineAtIndex:y];
    if (x < width - 1) {
        while (result.length > 0 && line[x].code == 0 && y < numberOfLines) {
            x--;
            result.length--;
            if (x == -1) {
                break;
            }
        }
    }
    return result;
}

// NSLog the screen contents for debugging.
- (void)dumpScreen {
    NSLog(@"%@", [self debugString]);
}

- (BOOL)useColumnScrollRegion {
    return _state.currentGrid.useScrollRegionCols;
}

- (void)setUseColumnScrollRegion:(BOOL)mode {
    [self mutSetUseColumnScrollRegion:mode];
}

- (void)blink {
    if ([_state.currentGrid isAnyCharDirty]) {
        [delegate_ screenNeedsRedraw];
    }
}

- (VT100ScreenMark *)lastCommandMark {
    DLog(@"Searching for last command mark...");
    if (_state.lastCommandMark) {
        DLog(@"Return cached mark %@", _state.lastCommandMark);
        return _state.lastCommandMark;
    }
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    int numChecked = 0;
    while (objects && numChecked < 500) {
        for (id<IntervalTreeObject> obj in objects) {
            if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = (VT100ScreenMark *)obj;
                if (mark.command) {
                    DLog(@"Found mark %@ in line number range %@", mark,
                         VT100GridRangeDescription([self lineNumberRangeOfInterval:obj.entry.interval]));
                    [self mutSetLastCommandMark:mark];
                    return mark;
                }
            }
            ++numChecked;
        }
        objects = [enumerator nextObject];
    }

    DLog(@"No last command mark found");
    return nil;
}

- (void)saveFindContextAbsPos {
    [self mutSaveFindContextAbsPos];
}

- (iTermAsyncFilter *)newAsyncFilterWithDestination:(id<iTermFilterDestination>)destination
                                              query:(NSString *)query
                                           refining:(iTermAsyncFilter *)refining
                                           progress:(void (^)(double))progress {
    return [[iTermAsyncFilter alloc] initWithQuery:query
                                        lineBuffer:_state.linebuffer
                                              grid:self.currentGrid
                                              mode:iTermFindModeSmartCaseSensitivity
                                       destination:destination
                                           cadence:1.0 / 60.0
                                          refining:refining
                                          progress:progress];
}


#pragma mark - PTYNoteViewControllerDelegate

- (void)noteDidRequestRemoval:(PTYNoteViewController *)note {
    [self mutRemoveNote:note];
}

- (void)noteDidEndEditing:(PTYNoteViewController *)note {
    [delegate_ screenDidEndEditingNote];
}

#pragma mark - VT100GridDelegate

- (screen_char_t)gridForegroundColorCode {
    return [_state.terminal foregroundColorCodeReal];
}

- (screen_char_t)gridBackgroundColorCode {
    return [_state.terminal backgroundColorCodeReal];
}

- (void)gridCursorDidChangeLine {
    if (_state.trackCursorLineMovement) {
        [delegate_ screenCursorDidMoveToLine:_state.currentGrid.cursorY + [self numberOfScrollbackLines]];
    }
}

- (iTermUnicodeNormalization)gridUnicodeNormalizationForm {
    return self.normalization;
}

- (void)gridCursorDidMove {
}

- (void)gridDidResize {
    [self.delegate screenDidResize];
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        [self mutSetLastCommandMark:mark];
    }
}

// Deprecated
- (int)numberOfLinesDroppedWhenEncodingLegacyFormatWithEncoder:(id<iTermEncoderAdapter>)encoder
                                                intervalOffset:(long long *)intervalOffsetPtr {
    if (gDebugLogging) {
        DLog(@"Saving state with width=%@", @(self.width));
        for (PTYNoteViewController *note in _state.intervalTree.allObjects) {
            if (![note isKindOfClass:[PTYNoteViewController class]]) {
                continue;
            }
            DLog(@"Save note with coord range %@", VT100GridCoordRangeDescription([self coordRangeForInterval:note.entry.interval]));
        }
    }
    return [self mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:YES
                                                                  encoder:encoder
                                                           intervalOffset:intervalOffsetPtr];
}

- (int)numberOfLinesDroppedWhenEncodingModernFormatWithEncoder:(id<iTermEncoderAdapter>)encoder
                                                intervalOffset:(long long *)intervalOffsetPtr {
    __block int linesDropped = 0;
    [encoder encodeDictionaryWithKey:@"LineBuffer"
                          generation:iTermGenerationAlwaysEncode
                               block:^BOOL(id<iTermEncoderAdapter>  _Nonnull subencoder) {
        linesDropped = [self mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:NO
                                                                              encoder:subencoder
                                                                       intervalOffset:intervalOffsetPtr];
        return YES;
    }];
    [encoder encodeDictionaryWithKey:@"PrimaryGrid"
                          generation:iTermGenerationAlwaysEncode
                               block:^BOOL(id<iTermEncoderAdapter>  _Nonnull subencoder) {
        [_state.primaryGrid encode:subencoder];
        return YES;
    }];
    if (_state.altGrid) {
        [encoder encodeDictionaryWithKey:@"AltGrid"
                              generation:iTermGenerationAlwaysEncode
                                   block:^BOOL(id<iTermEncoderAdapter>  _Nonnull subencoder) {
            [_state.altGrid encode:subencoder];
            return YES;
        }];
    }
    return linesDropped;
}

- (BOOL)encodeContents:(id<iTermEncoderAdapter>)encoder
          linesDropped:(int *)linesDroppedOut {
    NSDictionary *extra;

    // Interval tree
    if ([iTermAdvancedSettingsModel useNewContentFormat]) {
        long long intervalOffset = 0;
        const int linesDroppedForBrevity = [self numberOfLinesDroppedWhenEncodingModernFormatWithEncoder:encoder
                                                                                          intervalOffset:&intervalOffset];
        extra = @{
            kScreenStateIntervalTreeKey: [_state.intervalTree dictionaryValueWithOffset:intervalOffset] ?: @{},
        };
        if (linesDroppedOut) {
            *linesDroppedOut = linesDroppedForBrevity;
        }
    } else {
        long long intervalOffset = 0;
        const int linesDroppedForBrevity = [self numberOfLinesDroppedWhenEncodingLegacyFormatWithEncoder:encoder
                                                                                          intervalOffset:&intervalOffset];
        extra = @{
            kScreenStateIntervalTreeKey: [_state.intervalTree dictionaryValueWithOffset:intervalOffset] ?: @{},
            kScreenStateCursorCoord: VT100GridCoordToDictionary(_state.primaryGrid.cursor),
        };
        if (linesDroppedOut) {
            *linesDroppedOut = linesDroppedForBrevity;
        }
    }

    [encoder encodeDictionaryWithKey:kScreenStateKey
                          generation:iTermGenerationAlwaysEncode
                               block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
        [encoder mergeDictionary:extra];
        NSDictionary *dict =
        @{ kScreenStateTabStopsKey: [_state.tabStops allObjects] ?: @[],
           kScreenStateTerminalKey: [_state.terminal stateDictionary] ?: @{},
           kScreenStateLineDrawingModeKey: @[ @([_state.charsetUsesLineDrawingMode containsObject:@0]),
                                              @([_state.charsetUsesLineDrawingMode containsObject:@1]),
                                              @([_state.charsetUsesLineDrawingMode containsObject:@2]),
                                              @([_state.charsetUsesLineDrawingMode containsObject:@3]) ],
           kScreenStateNonCurrentGridKey: [self contentsOfNonCurrentGrid] ?: @{},
           kScreenStateCurrentGridIsPrimaryKey: @(_state.primaryGrid == _state.currentGrid),
           kScreenStateSavedIntervalTreeKey: [_state.savedIntervalTree dictionaryValueWithOffset:0] ?: [NSNull null],
           kScreenStateCommandStartXKey: @(_state.commandStartCoord.x),
           kScreenStateCommandStartYKey: @(_state.commandStartCoord.y),
           kScreenStateNextCommandOutputStartKey: [NSDictionary dictionaryWithGridAbsCoord:_state.startOfRunningCommandOutput],
           kScreenStateCursorVisibleKey: @(_state.cursorVisible),
           kScreenStateTrackCursorLineMovementKey: @(_state.trackCursorLineMovement),
           kScreenStateLastCommandOutputRangeKey: [NSDictionary dictionaryWithGridAbsCoordRange:_state.lastCommandOutputRange],
           kScreenStateShellIntegrationInstalledKey: @(_state.shellIntegrationInstalled),
           kScreenStateLastCommandMarkKey: _state.lastCommandMark.guid ?: [NSNull null],
           kScreenStatePrimaryGridStateKey: _state.primaryGrid.dictionaryValue ?: @{},
           kScreenStateAlternateGridStateKey: _state.altGrid.dictionaryValue ?: [NSNull null],
           kScreenStateProtectedMode: @(_state.protectedMode),
        };
        dict = [dict dictionaryByRemovingNullValues];
        [encoder mergeDictionary:dict];
        return YES;
    }];
    return YES;
}

// Deprecated - old format
- (NSDictionary *)contentsOfNonCurrentGrid {
    LineBuffer *temp = [[[LineBuffer alloc] initWithBlockSize:4096] autorelease];
    VT100Grid *grid;
    if (_state.currentGrid == _state.primaryGrid) {
        grid = _state.altGrid;
    } else {
        grid = _state.primaryGrid;
    }
    if (!grid) {
        return @{};
    }
    [grid appendLines:grid.size.height toLineBuffer:temp];
    iTermMutableDictionaryEncoderAdapter *encoder = [[[iTermMutableDictionaryEncoderAdapter alloc] init] autorelease];
    [temp encode:encoder maxLines:10000];
    return encoder.mutableDictionary;
}

- (void)restoreInitialSize {
    [self mutRestoreInitialSize];
}

- (id<iTermTemporaryDoubleBufferedGridControllerReading>)temporaryDoubleBuffer {
    if ([delegate_ screenShouldReduceFlicker] || _state.temporaryDoubleBuffer.explicit) {
        return _state.temporaryDoubleBuffer;
    } else {
        return nil;
    }
}

#pragma mark - iTermFullScreenUpdateDetectorDelegate

- (VT100Grid *)temporaryDoubleBufferedGridCopy {
    VT100Grid *copy = [[_state.currentGrid copy] autorelease];
    copy.delegate = nil;
    return copy;
}

- (PTYTextViewSynchronousUpdateState *)temporaryDoubleBufferedGridSavedState {
    PTYTextViewSynchronousUpdateState *state = [[[PTYTextViewSynchronousUpdateState alloc] init] autorelease];

    state.grid = [_state.currentGrid.copy autorelease];
    state.grid.delegate = nil;

    state.colorMap = [self.colorMap.copy autorelease];
    state.cursorVisible = self.temporaryDoubleBuffer.explicit ? _state.cursorVisible : YES;

    return state;

}

- (void)temporaryDoubleBufferedGridDidExpire {
    [self mutRedrawGrid];
}

#pragma mark - iTermLineBufferDelegate

- (void)lineBufferDidDropLines:(LineBuffer *)lineBuffer {
    if (lineBuffer == _state.linebuffer) {
        [delegate_ screenRefreshFindOnPageView];
    }
}

#pragma mark - VT100InlineImageHelperDelegate

- (void)inlineImageConfirmBigDownloadWithBeforeSize:(NSInteger)lengthBefore
                                          afterSize:(NSInteger)lengthAfter
                                               name:(NSString *)name {
    [self confirmBigDownloadWithBeforeSize:lengthBefore
                                 afterSize:lengthAfter
                                      name:name];
}

- (NSSize)inlineImageCellSize {
    return [delegate_ screenCellSize];
}

- (void)inlineImageAppendLinefeed {
    [self linefeed];
}

- (void)inlineImageSetMarkOnScreenLine:(NSInteger)line
                                  code:(unichar)code {
    long long absLine = (self.totalScrollbackOverflow +
                         [self numberOfScrollbackLines] +
                         line);
    iTermImageMark *mark = [self addMarkStartingAtAbsoluteLine:absLine
                                                       oneLine:YES
                                                       ofClass:[iTermImageMark class]];
    mark.imageCode = @(code);
    [delegate_ screenNeedsRedraw];
}

- (void)inlineImageDidFinishWithImageData:(NSData *)imageData {
    [delegate_ screenDidAppendImageData:imageData];
}

#pragma mark - Mutation Wrappers

- (void)clearBuffer {
    [self mutClearBuffer];
}

- (void)clearBufferSavingPrompt:(BOOL)savePrompt {
    [self mutClearBufferSavingPrompt:savePrompt];
}

- (void)appendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation {
    [self mutAppendScreenChars:line
                       length:length
       externalAttributeIndex:externalAttributeIndex
                 continuation:continuation];
}

- (void)appendAsciiDataAtCursor:(AsciiData *)asciiData {
    [self mutAppendAsciiDataAtCursor:asciiData];
}

- (void)appendStringAtCursor:(NSString *)string {
    [self mutAppendStringAtCursor:string];
}

- (void)setContentsFromLineBuffer:(LineBuffer *)lineBuffer {
    [self mutSetContentsFromLineBuffer:lineBuffer];
}

- (void)setHistory:(NSArray *)history {
    [self mutSetHistory:history];
}

- (void)setAltScreen:(NSArray *)lines {
    [self mutSetAltScreen:lines];
}

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                knownTriggers:(NSArray *)triggers
                   reattached:(BOOL)reattached {
    [self mutRestoreFromDictionary:dictionary
     includeRestorationBanner:includeRestorationBanner
                knownTriggers:triggers
                   reattached:reattached];
}

- (void)setTmuxState:(NSDictionary *)state {
     [self mutSetTmuxState:state];
}

- (void)crlf {
    [self mutCrlf];
}

- (void)linefeed {
    [self mutLinefeed];
}

- (void)setFromFrame:(screen_char_t*)s
                 len:(int)len
            metadata:(NSArray<NSArray *> *)metadataArrays
                info:(DVRFrameInfo)info {
    [self mutSetFromFrame:s
                      len:len
                 metadata:metadataArrays
                     info:info];
}

- (void)restoreSavedPositionToFindContext:(FindContext *)context {
    [self mutRestoreSavedPositionToFindContext:context];
}

- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults {
    [self mutSetFindString:aString
         forwardDirection:direction
                     mode:mode
              startingAtX:x
              startingAtY:y
               withOffset:offset
                inContext:context
          multipleResults:multipleResults];
}

- (screen_char_t *)getLineAtScreenIndex:(int)theIndex {
    return [self mutGetLineAtScreenIndex:theIndex];
}

- (void)resetAllDirty {
    [self mutResetAllDirty];
}

- (void)setLineDirtyAtY:(int)y {
    [self mutSetLineDirtyAtY:y];
}

- (void)setCharDirtyAtCursorX:(int)x Y:(int)y {
    [self mutSetCharDirtyAtCursorX:x Y:y];
}

- (void)resetDirty {
    [self mutResetDirty];
}

- (void)addNote:(PTYNoteViewController *)note
        inRange:(VT100GridCoordRange)range {
    [self mutAddNote:note inRange:range];
}

- (void)clearScrollbackBuffer {
    [self mutClearScrollbackBuffer];
}

- (void)resetTimestamps {
    [self mutResetTimestamps];
}

- (void)removeLastLine {
    [self mutRemoveLastLine];
}

- (void)clearFromAbsoluteLineToEnd:(long long)absLine {
    [self mutClearFromAbsoluteLineToEnd:absLine];
}

- (void)setMaxScrollbackLines:(unsigned int)lines {
    [self mutSetMaxScrollbackLines:lines];
}

#pragma mark - Accessors

- (void)setConfig:(id<VT100ScreenConfiguration>)config {
    [_nextConfig autorelease];
    _nextConfig = [config copyWithZone:nil];
    // In the future, VT100Screen+Mutation will run on a different thread and updating the config
    // will need to be synchronized properly.
    [self mutUpdateConfig];
}

- (id<VT100ScreenConfiguration>)config {
    return _nextConfig;
}

- (VT100GridAbsCoord)startOfRunningCommandOutput {
    return _state.startOfRunningCommandOutput;
}

- (id<iTermColorMapReading>)colorMap {
    return _state.colorMap;
}

- (id<iTermIntervalTreeObserver>)intervalTreeObserver {
    return _state.intervalTreeObserver;
}

- (void)setIntervalTreeObserver:(id<iTermIntervalTreeObserver>)intervalTreeObserver {
    [self mutSetIntervalTreeObserver:intervalTreeObserver];
}

- (iTermUnicodeNormalization)normalization {
    return _state.normalization;
}

- (void)setNormalization:(iTermUnicodeNormalization)normalization {
    [self mutSetNormalization:normalization];
}

- (BOOL)shellIntegrationInstalled {
    return _state.shellIntegrationInstalled;
}

- (BOOL)appendToScrollbackWithStatusBar {
    return _state.appendToScrollbackWithStatusBar;
}

- (void)setAppendToScrollbackWithStatusBar:(BOOL)appendToScrollbackWithStatusBar {
    [self mutSetAppendToScrollbackWithStatusBar:appendToScrollbackWithStatusBar];
}

- (BOOL)trackCursorLineMovement {
    return _state.trackCursorLineMovement;
}

- (void)setTrackCursorLineMovement:(BOOL)trackCursorLineMovement {
    [self mutSetTrackCursorLineMovement:trackCursorLineMovement];
}

- (VT100GridAbsCoordRange)lastCommandOutputRange {
    return _state.lastCommandOutputRange;
}

- (void)setLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange {
    [self mutSetLastCommandOutputRange:lastCommandOutputRange];
}

- (BOOL)saveToScrollbackInAlternateScreen {
    return _state.saveToScrollbackInAlternateScreen;
}

- (void)setSaveToScrollbackInAlternateScreen:(BOOL)saveToScrollbackInAlternateScreen {
    [self mutSetSaveToScrollbackInAlternateScreen:saveToScrollbackInAlternateScreen];
}

- (unsigned int)maxScrollbackLines {
    return _state.maxScrollbackLines;
}

- (BOOL)unlimitedScrollback {
    return _state.unlimitedScrollback;
}

- (void)setUnlimitedScrollback:(BOOL)unlimitedScrollback {
    [self mutSetUnlimitedScrollback:unlimitedScrollback];
}

- (BOOL)audibleBell {
    return _state.audibleBell;
}

- (void)setAudibleBell:(BOOL)audibleBell {
    _mutableState.audibleBell = audibleBell;
}

- (BOOL)showBellIndicator {
    return _state.showBellIndicator;
}

- (void)setShowBellIndicator:(BOOL)showBellIndicator {
    _mutableState.showBellIndicator = showBellIndicator;
}

- (BOOL)flashBell {
    return _state.flashBell;
}

- (void)setFlashBell:(BOOL)flashBell {
    _mutableState.flashBell = flashBell;
}

- (BOOL)postUserNotifications {
    return _state.postUserNotifications;
}

- (void)setPostUserNotifications:(BOOL)postUserNotifications {
    _mutableState.postUserNotifications = postUserNotifications;
}

- (BOOL)cursorBlinks {
    return _state.cursorBlinks;
}

- (void)setCursorBlinks:(BOOL)cursorBlinks {
    _mutableState.cursorBlinks = cursorBlinks;
}

- (BOOL)collectInputForPrinting {
    return _state.collectInputForPrinting;
}

- (void)setCollectInputForPrinting:(BOOL)collectInputForPrinting {
    _mutableState.collectInputForPrinting = collectInputForPrinting;
}

- (BOOL)allowTitleReporting {
    return _state.allowTitleReporting;
}

- (void)setAllowTitleReporting:(BOOL)allowTitleReporting {
    _mutableState.allowTitleReporting = allowTitleReporting;
}

- (NSIndexSet *)animatedLines {
    return _state.animatedLines;
}

@end

