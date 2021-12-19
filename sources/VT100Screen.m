
#import "VT100Screen.h"
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"

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

@synthesize saveToScrollbackInAlternateScreen = saveToScrollbackInAlternateScreen_;
@synthesize dvr = dvr_;
@synthesize delegate = delegate_;

- (instancetype)initWithTerminal:(VT100Terminal *)terminal {
    self = [super init];
    if (self) {
        _mutableState = [[VT100ScreenMutableState alloc] init];
        _state = [_mutableState retain];

        assert(terminal);
        [self setTerminal:terminal];
        _mutableState.primaryGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(kDefaultScreenColumns,
                                                                                       kDefaultScreenRows)
                                                            delegate:self] autorelease];
        _mutableState.currentGrid = _mutableState.primaryGrid;
        _temporaryDoubleBuffer = [[iTermTemporaryDoubleBufferedGridController alloc] init];
        _temporaryDoubleBuffer.delegate = self;

        [self mutSetInitialTabStops];
        linebuffer_ = [[LineBuffer alloc] init];

        [iTermNotificationController sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes] * 1024 * 1024];

        _startOfRunningCommandOutput = VT100GridAbsCoordMake(-1, -1);
        _lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _cursorVisible = YES;
        _initialSize = VT100GridSizeMake(-1, -1);
    }
    return self;
}

- (void)dealloc {
    [linebuffer_ release];
    [dvr_ release];
    [_lastCommandMark release];
    _temporaryDoubleBuffer.delegate = nil;
    [_temporaryDoubleBuffer reset];
    [_temporaryDoubleBuffer release];
    [_state release];
    [_mutableState release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, _state.currentGrid];
}

#pragma mark - APIs

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

#pragma mark - PTYTextViewDataSource

// This is a wee hack until PTYTextView breaks its direct dependence on PTYSession
- (PTYSession *)session {
    return (PTYSession *)delegate_;
}

// Returns the number of lines in scrollback plus screen height.
- (int)numberOfLines {
    return [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width] + _state.currentGrid.size.height;
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
    const NSInteger numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
    const int width = self.width;
    while (i < lastLine) {
        if (i < numLinesInLineBuffer) {
            [linebuffer_ enumerateLinesInRange:NSMakeRange(i, lastLine - i)
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
    const NSInteger numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
    if (line < numLinesInLineBuffer) {
        const BOOL eligibleForDWC = (line == numLinesInLineBuffer - 1 &&
                                     [_state.currentGrid screenCharsAtLineNumber:0][1].code == DWC_RIGHT);
        return [[linebuffer_ wrappedLineAtIndex:line width:self.width continuation:NULL] paddedToLength:self.width
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
    int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:width];
    if (lineNumber >= numLinesInLineBuffer) {
        return [_state.currentGrid immutableMetadataAtLineNumber:lineNumber - numLinesInLineBuffer];
    } else {
        return [linebuffer_ metadataForLineNumber:lineNumber width:width];
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
    int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
    if (theIndex >= numLinesInLineBuffer) {
        // Get a line from the circular screen buffer
        return [_state.currentGrid screenCharsAtLineNumber:(theIndex - numLinesInLineBuffer)];
    } else {
        // Get a line from the scrollback buffer.
        screen_char_t continuation;
        int cont = [linebuffer_ copyLineToBuffer:buffer
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
    const int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:width];
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
    return [linebuffer_ wrappedLinesFromIndex:range.location width:_state.currentGrid.size.width count:range.length];
}

- (NSArray<ScreenCharArray *> *)linesInRange:(NSRange)range {
    const int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
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

- (int)numberOfScrollbackLines
{
    return [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
}

- (int)scrollbackOverflow {
    return _state.scrollbackOverflow;
}

- (void)resetScrollbackOverflow {
    [self mutResetScrollbackOverflow];
}

- (long long)totalScrollbackOverflow
{
    return cumulativeScrollbackOverflow_;
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
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]
                                                                                 andContinuationMarks:NO]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[_state.currentGrid compactLineDump]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarks {
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]
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
        [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
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
    int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
    NSTimeInterval interval;
    if (y >= numLinesInLineBuffer) {
        interval = [_state.currentGrid timestampForLine:y - numLinesInLineBuffer];
    } else {
        interval = [linebuffer_ metadataForLineNumber:y width:_state.currentGrid.size.width].timestamp;
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
    [self setWorkingDirectory:workingDirectory
                       onLine:line
                       pushed:pushed
                        token:[[_mutableState.setWorkingDirectoryOrderEnforcer newToken] autorelease]];
}

// Adds a working directory mark at the given line.
//
// nil token means not to fetch working directory asynchronously.
//
// pushed means it's a higher confidence update. The directory must be pushed to be remote, but
// that alone is not sufficient evidence that it is remote. Pushed directories will update the
// recently used directories and will change the current remote host to the remote host on `line`.
- (void)setWorkingDirectory:(NSString *)workingDirectory
                     onLine:(int)line
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken>)token {
    // If not timely, record the update but don't consider it the latest update.
    // Peek now so we can log but don't commit because we might recurse asynchronously.
    const BOOL timely = !token || [token peek];
    DLog(@"%p: setWorkingDirectory:%@ onLine:%d token:%@ (timely=%@)", self, workingDirectory, line, token, @(timely));
    VT100WorkingDirectory *workingDirectoryObj = [[[VT100WorkingDirectory alloc] init] autorelease];
    if (token && !workingDirectory) {
        __weak __typeof(self) weakSelf = self;
        DLog(@"%p: Performing async working directory fetch for token %@", self, token);
        [delegate_ screenGetWorkingDirectoryWithCompletion:^(NSString *path) {
            DLog(@"%p: Async update got %@ for token %@", self, path, token);
            if (path) {
                [weakSelf setWorkingDirectory:path onLine:line pushed:pushed token:token];
            }
        }];
        return;
    }
    // OK, now commit. It can't have changed since we peeked.
    const BOOL stillTimely = !token || [token commit];
    assert(timely == stillTimely);

    DLog(@"%p: Set finished working directory token to %@", self, token);
    if (workingDirectory.length) {
        DLog(@"Changing working directory to %@", workingDirectory);
        workingDirectoryObj.workingDirectory = workingDirectory;

        VT100WorkingDirectory *previousWorkingDirectory = [[[self objectOnOrBeforeLine:line
                                                                               ofClass:[VT100WorkingDirectory class]] retain] autorelease];
        DLog(@"The previous directory was %@", previousWorkingDirectory);
        if ([previousWorkingDirectory.workingDirectory isEqualTo:workingDirectory]) {
            // Extend the previous working directory. We used to add a new VT100WorkingDirectory
            // every time but if the window title gets changed a lot then they can pile up really
            // quickly and you spend all your time searching through VT001WorkingDirectory marks
            // just to find VT100RemoteHost or VT100ScreenMark objects.
            //
            // It's a little weird that a VT100WorkingDirectory can now represent the same path on
            // two different hosts (e.g., you ssh from /Users/georgen to another host and you're in
            // /Users/georgen over there, but you can share the same VT100WorkingDirectory between
            // the two hosts because the path is the same). I can't see the harm in it besides being
            // odd.
            //
            // Intervals aren't removed while part of them is on screen, so this works fine.
            VT100GridCoordRange range = [self coordRangeForInterval:previousWorkingDirectory.entry.interval];
            [_mutableState.intervalTree removeObject:previousWorkingDirectory];
            range.end = VT100GridCoordMake(self.width, line);
            DLog(@"Extending the previous directory to %@", VT100GridCoordRangeDescription(range));
            Interval *interval = [self intervalForGridCoordRange:range];
            [_mutableState.intervalTree addObject:previousWorkingDirectory withInterval:interval];
        } else {
            VT100GridCoordRange range;
            range = VT100GridCoordRangeMake(_state.currentGrid.cursorX, line, self.width, line);
            DLog(@"Set range of %@ to %@", workingDirectory, VT100GridCoordRangeDescription(range));
            [_mutableState.intervalTree addObject:workingDirectoryObj
                                     withInterval:[self intervalForGridCoordRange:range]];
        }
    }
    [delegate_ screenLogWorkingDirectoryAtLine:line
                                 withDirectory:workingDirectory
                                        pushed:pushed
                                        timely:timely];
}

- (VT100RemoteHost *)setRemoteHost:(NSString *)host user:(NSString *)user onLine:(int)line {
    VT100RemoteHost *remoteHostObj = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHostObj.hostname = host;
    remoteHostObj.username = user;
    VT100GridCoordRange range = VT100GridCoordRangeMake(0, line, self.width, line);
    [_mutableState.intervalTree addObject:remoteHostObj
                             withInterval:[self intervalForGridCoordRange:range]];
    return remoteHostObj;
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

#pragma mark - VT100TerminalDelegate

- (void)terminalAppendString:(NSString *)string {
    if (_state.collectInputForPrinting) {
        [_mutableState.printBuffer appendString:string];
    } else {
        // else display string on screen
        [self appendStringAtCursor:string];
    }
    [delegate_ screenDidAppendStringToCurrentLine:string
                                      isPlainText:YES];
}

- (void)terminalAppendAsciiData:(AsciiData *)asciiData {
    if (_state.collectInputForPrinting) {
        NSString *string = [[[NSString alloc] initWithBytes:asciiData->buffer
                                                     length:asciiData->length
                                                   encoding:NSASCIIStringEncoding] autorelease];
        [self terminalAppendString:string];
        return;
    } else {
        // else display string on screen
        [self appendAsciiDataAtCursor:asciiData];
    }
    [delegate_ screenDidAppendAsciiDataToCurrentLine:asciiData];
}

- (void)terminalRingBell {
    DLog(@"Terminal rang the bell");
    [delegate_ screenDidAppendStringToCurrentLine:@"\a" isPlainText:NO];
    [self activateBell];
}

- (void)terminalBackspace {
    int cursorX = _state.currentGrid.cursorX;
    int cursorY = _state.currentGrid.cursorY;

    [self mutDoBackspace];

    if (_state.commandStartCoord.x != -1 && (_state.currentGrid.cursorX != cursorX ||
                                             _state.currentGrid.cursorY != cursorY)) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)terminalAppendTabAtCursor:(BOOL)setBackgroundColors {
    [self mutAppendTabAtCursor:setBackgroundColors];
}

- (BOOL)cursorOutsideLeftRightMargin {
    return (_state.currentGrid.useScrollRegionCols && (_state.currentGrid.cursorX < _state.currentGrid.leftMargin ||
                                                 _state.currentGrid.cursorX > _state.currentGrid.rightMargin));
}

- (void)terminalLineFeed {
    if (_state.currentGrid.cursor.y == VT100GridRangeMax(_state.currentGrid.scrollRegionRows) &&
        [self cursorOutsideLeftRightMargin]) {
        DLog(@"Ignore linefeed/formfeed/index because cursor outside left-right margin.");
        return;
    }

    if (_state.collectInputForPrinting) {
        [_mutableState.printBuffer appendString:@"\n"];
    } else {
        [self linefeed];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    [delegate_ screenDidReceiveLineFeed];
}

- (void)terminalCursorLeft:(int)n {
    [self mutCursorLeft:n];
}

- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [self mutCursorDown:n andToStartOfLine:toStart];
}

- (void)terminalCursorRight:(int)n {
    [self mutCursorRight:n];
}

- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [self mutCursorUp:n andToStartOfLine:toStart];
}


- (void)terminalMoveCursorToX:(int)x y:(int)y {
    [self mutCursorToX:x Y:y];
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (BOOL)terminalShouldSendReport {
    return [delegate_ screenShouldSendReport];
}

- (BOOL)terminalShouldSendReportForVariable:(NSString *)variable {
    return [delegate_ screenShouldSendReportForVariable:variable];
}

- (void)terminalSendReport:(NSData *)report {
    if ([delegate_ screenShouldSendReport] && report) {
        DLog(@"report %@", [report stringWithEncoding:NSUTF8StringEncoding]);
        [delegate_ screenWriteDataToTask:report];
    }
}

- (NSString *)terminalValueOfVariableNamed:(NSString *)name {
    return [delegate_ screenValueOfVariableNamed:name];
}

- (void)terminalShowTestPattern {
    [self mutShowTestPattern];
}

- (int)terminalRelativeCursorX {
    return _state.currentGrid.cursorX - _state.currentGrid.leftMargin + 1;
}

- (int)terminalRelativeCursorY {
    return _state.currentGrid.cursorY - _state.currentGrid.topMargin + 1;
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom {
    [self mutSetScrollRegionTop:top bottom:bottom];
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [self mutEraseInDisplayBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [self mutEraseLineBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalSetTabStopAtCursor {
    [self mutSetTabStopAtCursor];
}

- (void)terminalCarriageReturn {
    [self mutCarriageReturn];
}

- (void)terminalReverseIndex {
    [self mutReverseIndex];
}

- (void)terminalForwardIndex {
    [self mutForwardIndex];
}

- (void)terminalBackIndex {
    [self mutBackIndex];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    [self mutResetPreservingPrompt:preservePrompt modifyContent:modifyContent];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    [delegate_ screenSetCursorType:cursorType];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    [delegate_ screenSetCursorBlinking:blinking];
}

- (BOOL)terminalCursorIsBlinking {
    return [delegate_ screenCursorIsBlinking];
}

- (void)terminalGetCursorType:(ITermCursorType *)cursorTypeOut
                     blinking:(BOOL *)blinking {
    [delegate_ screenGetCursorType:cursorTypeOut blinking:blinking];
}

- (void)terminalResetCursorTypeAndBlink {
    [delegate_ screenResetCursorTypeAndBlink];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    [self mutSetLeftMargin:scrollLeft rightMargin:scrollRight];
}

- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode {
    [self mutSetCharacterSet:charset usesLineDrawingMode:lineDrawingMode];
}

- (BOOL)terminalLineDrawingFlagForCharset:(int)charset {
    return [_state.charsetUsesLineDrawingMode containsObject:@(charset)];
}

- (void)terminalRemoveTabStops {
    [self mutRemoveAllTabStops];
}

- (void)terminalRemoveTabStopAtCursor {
    [self mutRemoveTabStopAtCursor];
}

- (void)terminalSetWidth:(int)width preserveScreen:(BOOL)preserveScreen {
    [self mutSetWidth:width preserveScreen:preserveScreen];
}

- (void)terminalBackTab:(int)n {
    [self mutBackTab:n];
}

- (void)terminalSetCursorX:(int)x {
    [self mutCursorToX:x];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalAdvanceCursorPastLastColumn {
    [self mutAdvanceCursorPastLastColumn];
}

- (void)terminalSetCursorY:(int)y {
    [self mutCursorToY:y];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalEraseCharactersAfterCursor:(int)j {
    [self mutEraseCharactersAfterCursor:j];
}

- (void)terminalPrintBuffer {
    if ([delegate_ screenShouldBeginPrinting] && [_state.printBuffer length] > 0) {
        [self doPrint];
    }
}

- (void)terminalBeginRedirectingToPrintBuffer {
    if ([delegate_ screenShouldBeginPrinting]) {
        // allocate a string for the stuff to be printed
        _mutableState.printBuffer = [[[NSMutableString alloc] init] autorelease];
        _mutableState.collectInputForPrinting = YES;
    }
}

- (void)terminalPrintScreen {
    if ([delegate_ screenShouldBeginPrinting]) {
        // Print out the whole screen
        _mutableState.printBuffer = nil;
        _mutableState.collectInputForPrinting = NO;
        [self doPrint];
    }
}

- (void)terminalSetWindowTitle:(NSString *)title {
    DLog(@"terminalSetWindowTitle:%@", title);
    
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenSetWindowTitle:title];
    }

    // If you know to use RemoteHost then assume you also use CurrentDirectory. Innocent window title
    // changes shouldn't override CurrentDirectory.
    if (![self remoteHostOnLine:[self numberOfScrollbackLines] + self.height]) {
        DLog(@"Don't have a remote host, so changing working directory");
        // TODO: There's a bug here where remote host can scroll off the end of history, causing the
        // working directory to come from PTYTask (which is what happens when nil is passed here).
        //
        // NOTE: Even though this is kind of a pull, it happens at a good
        // enough rate (not too common, not too rare when part of a prompt)
        // that I'm comfortable calling it a push. I want it to do things like
        // update the list of recently used directories.
        [self setWorkingDirectory:nil onLine:[self lineNumberOfCursor] pushed:YES];
    } else {
        DLog(@"Already have a remote host so not updating working directory because of title change");
    }
}

- (void)terminalSetIconTitle:(NSString *)title {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenSetIconName:title];
    }
}

- (void)terminalSetSubtitle:(NSString *)subtitle {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenSetSubtitle:subtitle];
    }
}

- (void)terminalPasteString:(NSString *)string {
    [delegate_ screenTerminalAttemptedPasteboardAccess];
    // check the configuration
    if (![iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        return;
    }

    // set the result to paste board.
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
    [thePasteboard setString:string forType:NSPasteboardTypeString];
}

- (void)terminalInsertEmptyCharsAtCursor:(int)n {
    [self mutInsertEmptyCharsAtCursor:n];
}

- (void)terminalShiftLeft:(int)n {
    [self mutShiftLeft:n];
}

- (void)terminalShiftRight:(int)n {
    [self mutShiftRight:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    [self mutInsertBlankLinesAfterCursor:n];
}

- (void)terminalDeleteCharactersAtCursor:(int)n {
    [self mutDeleteCharactersAtCursor:n];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    [self mutDeleteLinesAtCursor:n];
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    if (rows == -1) {
        rows = self.height;
    } else if (rows == 0) {
        rows = [self terminalScreenHeightInCells];
    }
    if (columns == -1) {
        columns = self.width;
    } else if (columns == 0) {
        columns = [self terminalScreenWidthInCells];
    }
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        [delegate_ screenResizeToWidth:columns
                                height:rows];

    }
}

- (void)terminalSetPixelWidth:(int)width height:(int)height {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        NSRect frame = [delegate_ screenWindowFrame];
        NSRect screenFrame = [delegate_ screenWindowScreenFrame];
        if (width < 0) {
            width = frame.size.width;
        } else if (width == 0) {
            width = screenFrame.size.width;
        }
        if (height < 0) {
            height = frame.size.height;
        } else if (height == 0) {
            height = screenFrame.size.height;
        }
        [delegate_ screenResizeToPixelWidth:width height:height];
    }
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        [delegate_ screenMoveWindowTopLeftPointTo:point];
    }
}

- (void)terminalMiniaturize:(BOOL)mini {
    // TODO: Only allow this if there is a single session in the tab.
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        [delegate_ screenMiniaturizeWindow:mini];
    }
}

- (void)terminalRaise:(BOOL)raise {
    if ([delegate_ screenShouldInitiateWindowResize]) {
        [delegate_ screenRaise:raise];
    }
}

- (void)terminalScrollDown:(int)n {
    [self mutScrollDown:n];
}

- (void)terminalScrollUp:(int)n {
    [self mutScrollUp:n];
}

- (BOOL)terminalWindowIsMiniaturized {
    return [delegate_ screenWindowIsMiniaturized];
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    return [delegate_ screenWindowTopLeftPixelCoordinate];
}

- (int)terminalWindowWidthInPixels {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.width;
}

- (int)terminalWindowHeightInPixels {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.height;
}

- (int)terminalScreenHeightInCells {
    //  TODO: WTF do we do with panes here?
    NSRect screenFrame = [delegate_ screenWindowScreenFrame];
    NSRect windowFrame = [delegate_ screenWindowFrame];
    float roomToGrow = screenFrame.size.height - windowFrame.size.height;
    NSSize cellSize = [delegate_ screenCellSize];
    return [self height] + roomToGrow / cellSize.height;
}

- (int)terminalScreenWidthInCells {
    //  TODO: WTF do we do with panes here?
    NSRect screenFrame = [delegate_ screenWindowScreenFrame];
    NSRect windowFrame = [delegate_ screenWindowFrame];
    float roomToGrow = screenFrame.size.width - windowFrame.size.width;
    NSSize cellSize = [delegate_ screenCellSize];
    return [self width] + roomToGrow / cellSize.width;
}

- (NSString *)terminalIconTitle {
    if (_state.allowTitleReporting && [self terminalIsTrusted]) {
        return [delegate_ screenIconTitle];
    } else {
        return @"";
    }
}

- (NSString *)terminalWindowTitle {
    if (_state.allowTitleReporting && [self terminalIsTrusted]) {
        return [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : @"";
    } else {
        return @"";
    }
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenPushCurrentTitleForWindow:isWindow];
    }
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenPopCurrentTitleForWindow:isWindow];
    }
}

- (BOOL)terminalPostUserNotification:(NSString *)message {
    if (_state.postUserNotifications && [delegate_ screenShouldPostTerminalGeneratedAlert]) {
        DLog(@"Terminal posting user notification %@", message);
        [delegate_ screenIncrementBadge];
        NSString *description = [NSString stringWithFormat:@"Session %@ #%d: %@",
                                 [[delegate_ screenName] removingHTMLFromTabTitleIfNeeded],
                                 [delegate_ screenNumber],
                                 message];
        BOOL sent = [[iTermNotificationController sharedInstance]
                                 notify:@"Alert"
                        withDescription:description
                            windowIndex:[delegate_ screenWindowIndex]
                               tabIndex:[delegate_ screenTabIndex]
                              viewIndex:[delegate_ screenViewIndex]];
        return sent;
    } else {
        DLog(@"Declining to allow terminal to post user notification %@", message);
        return NO;
    }
}

- (void)terminalStartTmuxModeWithDCSIdentifier:(NSString *)dcsID {
    [delegate_ screenStartTmuxModeWithDCSIdentifier:dcsID];
}

- (void)terminalHandleTmuxInput:(VT100Token *)token {
    [delegate_ screenHandleTmuxInput:token];
}

- (void)terminalSynchronizedUpdate:(BOOL)begin {
    if (begin) {
        [_temporaryDoubleBuffer startExplicitly];
    } else {
        [_temporaryDoubleBuffer resetExplicitly];
    }
}

- (int)terminalWidth {
    return [self width];
}

- (int)terminalHeight {
    return [self height];
}

- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode {
    [delegate_ screenMouseModeDidChange];
}

- (void)terminalNeedsRedraw {
    [self mutMarkWholeScreenDirty];
}

- (void)terminalSetUseColumnScrollRegion:(BOOL)use {
    self.useColumnScrollRegion = use;
}

- (BOOL)terminalUseColumnScrollRegion {
    return self.useColumnScrollRegion;
}

- (void)terminalShowAltBuffer {
    [self mutShowAltBuffer];
}

- (BOOL)terminalIsShowingAltBuffer {
    return [self showingAlternateScreen];
}

- (BOOL)showingAlternateScreen {
    return _state.currentGrid == _state.altGrid;
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

- (void)terminalShowPrimaryBuffer {
    [self mutShowPrimaryBuffer];
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    DLog(@"Set remote host to %@ %@", remoteHost, self);
    // Search backwards because Windows UPN format includes an @ in the user name. I don't think hostnames would ever have an @ sign.
    NSRange atRange = [remoteHost rangeOfString:@"@" options:NSBackwardsSearch];
    NSString *user = nil;
    NSString *host = nil;
    if (atRange.length == 1) {
        user = [remoteHost substringToIndex:atRange.location];
        host = [remoteHost substringFromIndex:atRange.location + 1];
        if (host.length == 0) {
            host = nil;
        }
    } else {
        host = remoteHost;
    }

    [self setHost:host user:user];
}

- (void)setHost:(NSString *)host user:(NSString *)user {
    DLog(@"setHost:%@ user:%@ %@", host, user, self);
    VT100RemoteHost *currentHost = [self remoteHostOnLine:[self numberOfLines]];
    if (!host || !user) {
        // A trigger can set the host and user alone. If remoteHost looks like example.com or
        // user@, then preserve the previous host/user. Also ensure neither value is nil; the
        // empty string will stand in for a real value if necessary.
        VT100RemoteHost *lastRemoteHost = [self lastRemoteHost];
        if (!host) {
            host = [[lastRemoteHost.hostname copy] autorelease] ?: @"";
        }
        if (!user) {
            user = [[lastRemoteHost.username copy] autorelease] ?: @"";
        }
    }

    int cursorLine = [self numberOfLines] - [self height] + _state.currentGrid.cursorY;
    VT100RemoteHost *remoteHostObj = [self setRemoteHost:host user:user onLine:cursorLine];

    if (![remoteHostObj isEqualToRemoteHost:currentHost]) {
        [delegate_ screenCurrentHostDidChange:remoteHostObj];
    }
}

- (void)terminalSetWorkingDirectoryURL:(NSString *)URLString {
    DLog(@"terminalSetWorkingDirectoryURL:%@", URLString);
    
    if (![iTermAdvancedSettingsModel acceptOSC7]) {
        return;
    }
    NSURL *URL = [NSURL URLWithString:URLString];
    if (!URL || URLString.length == 0) {
        return;
    }
    NSURLComponents *components = [[[NSURLComponents alloc] initWithURL:URL resolvingAgainstBaseURL:NO] autorelease];
    NSString *host = components.host;
    NSString *user = components.user;
    NSString *path = components.path;

    if (host || user) {
        [self setHost:host user:user];
    }
    [self terminalCurrentDirectoryDidChangeTo:path];
    [delegate_ screenPromptDidStartAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
}

- (void)terminalClearScreen {
    [self mutEraseScreenAndRemoveSelection];
}

- (void)terminalSaveScrollPositionWithArgument:(NSString *)argument {
    // The difference between an argument of saveScrollPosition and saveCursorLine (the default) is
    // subtle. When saving the scroll position, the entire region of visible lines is recorded and
    // will be restored exactly. When saving only the line the cursor is on, when restored, that
    // line will be made visible but no other aspect of the scroll position must be restored. This
    // is often preferable because when setting a mark as part of the prompt, we wouldn't want the
    // prompt to be the last line on the screen (such lines are scrolled to the center of
    // the screen).
    if ([argument isEqualToString:@"saveScrollPosition"]) {
        [delegate_ screenSaveScrollPosition];
    } else {  // implicitly "saveCursorLine"
        [delegate_ screenAddMarkOnLine:[self numberOfScrollbackLines] + self.cursorY - 1];
    }
}

- (void)terminalStealFocus {
    [delegate_ screenStealFocus];
}

- (void)terminalSetProxyIcon:(NSString *)value {
    NSString *path = [value length] ? value : nil;
    [delegate_ screenSetPreferredProxyIcon:path];
}

- (void)terminalClearScrollbackBuffer {
    if ([self.delegate screenShouldClearScrollbackBuffer]) {
        [self clearScrollbackBuffer];
    }
}

- (void)terminalClearBuffer {
    [self clearBuffer];
}

// Shell integration or equivalent.
- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)dir {
    DLog(@"%p: terminalCurrentDirectoryDidChangeTo:%@", self, dir);
    [delegate_ screenSetPreferredProxyIcon:nil]; // Clear current proxy icon if exists.

    int cursorLine = [self numberOfLines] - [self height] + _state.currentGrid.cursorY;
    if (dir.length) {
        [self currentDirectoryReallyDidChangeTo:dir onLine:cursorLine];
        return;
    }

    // Go fetch the working directory and then update it.
    __weak __typeof(self) weakSelf = self;
    id<iTermOrderedToken> token = [[_mutableState.currentDirectoryDidChangeOrderEnforcer newToken] autorelease];
    DLog(@"Fetching directory asynchronously with token %@", token);
    [delegate_ screenGetWorkingDirectoryWithCompletion:^(NSString *dir) {
        DLog(@"For token %@, the working directory is %@", token, dir);
        if ([token commit]) {
            [weakSelf currentDirectoryReallyDidChangeTo:dir onLine:cursorLine];
        }
    }];
}

- (void)currentDirectoryReallyDidChangeTo:(NSString *)dir
                                   onLine:(int)cursorLine {
    DLog(@"currentDirectoryReallyDidChangeTo:%@ onLine:%@", dir, @(cursorLine));
    BOOL willChange = ![dir isEqualToString:[self workingDirectoryOnLine:cursorLine]];
    [self setWorkingDirectory:dir onLine:cursorLine pushed:YES token:nil];
    if (willChange) {
        [delegate_ screenCurrentDirectoryDidChangeTo:dir];
    }
}

- (void)terminalProfileShouldChangeTo:(NSString *)value {
    [delegate_ screenSetProfileToProfileNamed:value];
}

- (void)terminalAddNote:(NSString *)value show:(BOOL)show {
    NSArray *parts = [value componentsSeparatedByString:@"|"];
    VT100GridCoord location = _state.currentGrid.cursor;
    NSString *message = nil;
    int length = _state.currentGrid.size.width - _state.currentGrid.cursorX - 1;
    if (parts.count == 1) {
        message = parts[0];
    } else if (parts.count == 2) {
        message = parts[1];
        length = [parts[0] intValue];
    } else if (parts.count >= 4) {
        message = parts[0];
        length = [parts[1] intValue];
        VT100GridCoord limit = {
            .x = self.width - 1,
            .y = self.height - 1
        };
        location.x = MIN(MAX(0, [parts[2] intValue]), limit.x);
        location.y = MIN(MAX(0, [parts[3] intValue]), limit.y);
    }
    VT100GridCoord end = location;
    end.x += length;
    end.y += end.x / self.width;
    end.x %= self.width;

    int endVal = end.x + end.y * self.width;
    int maxVal = self.width - 1 + (self.height - 1) * self.width;
    if (length > 0 &&
        message.length > 0 &&
        endVal <= maxVal) {
        PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
        [note setString:message];
        [note sizeToFit];
        [self addNote:note
              inRange:VT100GridCoordRangeMake(location.x,
                                              location.y + [self numberOfScrollbackLines],
                                              end.x,
                                              end.y + [self numberOfScrollbackLines])];
        if (!show) {
            [note setNoteHidden:YES];
        }
    }
}

- (void)terminalSetPasteboard:(NSString *)value {
    [delegate_ screenSetPasteboard:value];
}

- (BOOL)preconfirmDownloadOfSize:(NSInteger)size
                            name:(NSString *)name
                   displayInline:(BOOL)displayInline
                     promptIfBig:(BOOL *)promptIfBig {
    return [self.delegate screenConfirmDownloadAllowed:name
                                                  size:size
                                         displayInline:displayInline
                                           promptIfBig:promptIfBig];
}

- (BOOL)terminalWillReceiveFileNamed:(NSString *)name
                              ofSize:(NSInteger)size {
    BOOL promptIfBig = YES;
    if (![self preconfirmDownloadOfSize:size
                                   name:name
                          displayInline:NO
                            promptIfBig:&promptIfBig]) {
        return NO;
    }
    [delegate_ screenWillReceiveFileNamed:name ofSize:size preconfirmed:!promptIfBig];
    return YES;
}

- (BOOL)terminalWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(NSInteger)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset {
    BOOL promptIfBig = YES;
    if (![self preconfirmDownloadOfSize:size name:name displayInline:YES promptIfBig:&promptIfBig]) {
        return NO;
    }
    _mutableState.inlineImageHelper = [[[VT100InlineImageHelper alloc] initWithName:name
                                                                              width:width
                                                                         widthUnits:widthUnits
                                                                             height:height
                                                                        heightUnits:heightUnits
                                                                        scaleFactor:[delegate_ screenBackingScaleFactor]
                                                                preserveAspectRatio:preserveAspectRatio
                                                                              inset:inset
                                                                       preconfirmed:!promptIfBig] autorelease];
    _mutableState.inlineImageHelper.delegate = self;
    return YES;
}

- (void)appendNativeImageAtCursorWithName:(NSString *)name width:(int)width {
    VT100InlineImageHelper *helper = [[[VT100InlineImageHelper alloc] initWithNativeImageNamed:name
                                                                                 spanningWidth:width
                                                                                   scaleFactor:[delegate_ screenBackingScaleFactor]] autorelease];
    helper.delegate = self;
    [helper writeToGrid:_state.currentGrid];
}

- (void)addURLMarkAtLineAfterCursorWithCode:(unsigned int)code {
    long long absLine = (self.totalScrollbackOverflow +
                         [self numberOfScrollbackLines] +
                         _state.currentGrid.cursor.y + 1);
    iTermURLMark *mark = [self addMarkStartingAtAbsoluteLine:absLine
                                                     oneLine:YES
                                                     ofClass:[iTermURLMark class]];
    mark.code = code;
}

- (void)terminalWillStartLinkWithCode:(unsigned int)code {
    [self addURLMarkAtLineAfterCursorWithCode:code];
}

- (void)terminalWillEndLinkWithCode:(unsigned int)code {
    [self addURLMarkAtLineAfterCursorWithCode:code];
}

- (void)terminalAppendSixelData:(NSData *)data {
    VT100InlineImageHelper *helper = [[[VT100InlineImageHelper alloc] initWithSixelData:data
                                                                            scaleFactor:[delegate_ screenBackingScaleFactor]] autorelease];
    helper.delegate = self;
    [helper writeToGrid:_state.currentGrid];
    [self crlf];
}

- (void)terminalDidChangeSendModifiers {
    // CSI u is too different from xterm's modifyOtherKeys to allow the terminal to change it with
    // xterm's control sequences. Lots of strange problems appear with vim. For example, mailing
    // list thread with subject "Control Keys Failing After System Bell".
    // TODO: terminal_.sendModifiers[i] holds the settings. See xterm's modifyOtherKeys and friends.
    [self.delegate screenSendModifiersDidChange];
}

- (void)terminalKeyReportingFlagsDidChange {
    [self.delegate screenKeyReportingFlagsDidChange];
}

- (void)terminalDidFinishReceivingFile {
    if (_mutableState.inlineImageHelper) {
        [_mutableState.inlineImageHelper writeToGrid:_state.currentGrid];
        _mutableState.inlineImageHelper = nil;
        // TODO: Handle objects other than images.
        [delegate_ screenDidFinishReceivingInlineFile];
    } else {
        DLog(@"Download finished");
        [delegate_ screenDidFinishReceivingFile];
    }
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

- (void)terminalDidReceiveBase64FileData:(NSString *)data {
    if (_mutableState.inlineImageHelper) {
        [_mutableState.inlineImageHelper appendBase64EncodedData:data];
    } else {
        [delegate_ screenDidReceiveBase64FileData:data];
    }
}

- (void)terminalFileReceiptEndedUnexpectedly {
    [self mutFileReceiptEndedUnexpectedly];
}

- (void)terminalRequestUpload:(NSString *)args {
    [delegate_ screenRequestUpload:args];
}

- (void)terminalBeginCopyToPasteboard {
    [delegate_ screenTerminalAttemptedPasteboardAccess];
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        _mutableState.pasteboardString = [[[NSMutableString alloc] init] autorelease];
    }
}

- (void)terminalDidReceiveBase64PasteboardString:(NSString *)string {
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        [_mutableState.pasteboardString appendString:string];
    }
}

- (void)terminalDidFinishReceivingPasteboard {
    if (_state.pasteboardString && [iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        NSData *data = [NSData dataWithBase64EncodedString:_state.pasteboardString];
        if (data) {
            NSString *string = [[[NSString alloc] initWithData:data encoding:_state.terminal.encoding] autorelease];
            if (!string) {
                string = [[[NSString alloc] initWithData:data encoding:[NSString defaultCStringEncoding]] autorelease];
            }

            if (string) {
                NSPasteboard *pboard = [NSPasteboard generalPasteboard];
                [pboard clearContents];
                [pboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
                [pboard setString:string forType:NSPasteboardTypeString];
            }
        }
    }
    _mutableState.pasteboardString = nil;
}

- (void)terminalPasteboardReceiptEndedUnexpectedly {
    _mutableState.pasteboardString = nil;
}

- (void)terminalCopyBufferToPasteboard {
    [delegate_ screenCopyBufferToPasteboard];
}

- (BOOL)terminalIsAppendingToPasteboard {
    return [delegate_ screenIsAppendingToPasteboard];
}

- (void)terminalAppendDataToPasteboard:(NSData *)data {
    return [delegate_ screenAppendDataToPasteboard:data];
}

- (BOOL)terminalIsTrusted {
    const BOOL result = ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences];
    DLog(@"terminalIsTrusted returning %@", @(result));
    return result;
}

- (BOOL)terminalCanUseDECRQCRA {
    if (![iTermAdvancedSettingsModel disableDECRQCRA]) {
        return YES;
    }
    [delegate_ screenDidTryToUseDECRQCRA];
    return NO;
}

- (void)terminalRequestAttention:(VT100AttentionRequestType)request {
    [delegate_ screenRequestAttention:request];
}

- (void)terminalDisinterSession {
    [delegate_ screenDisinterSession];
}

- (void)terminalSetBackgroundImageFile:(NSString *)filename {
    [delegate_ screenSetBackgroundImageFile:filename];
}

- (void)terminalSetBadgeFormat:(NSString *)badge {
    [delegate_ screenSetBadgeFormat:badge];
}

- (void)terminalSetUserVar:(NSString *)kvp {
    [delegate_ screenSetUserVar:kvp];
}

- (void)terminalResetColor:(VT100TerminalColorIndex)n {
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }
    [delegate_ screenResetColorsWithColorMapKey:key];
}

- (void)terminalSetForegroundColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapForeground];
}

- (void)terminalSetBackgroundColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapBackground];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapBold];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapSelection];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapSelectedText];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapCursor];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapCursorText];
}

- (int)colorMapKeyForTerminalColorIndex:(VT100TerminalColorIndex)n {
    switch (n) {
        case VT100TerminalColorIndexText:
            return kColorMapForeground;
        case VT100TerminalColorIndexBackground:
            return kColorMapBackground;
        case VT100TerminalColorIndexCursor:
            return kColorMapCursor;
        case VT100TerminalColorIndexSelectionBackground:
            return kColorMapSelection;
        case VT100TerminalColorIndexSelectionForeground:
            return kColorMapSelectedText;
        case VT100TerminalColorIndexFirst8BitColorIndex:
        case VT100TerminalColorIndexLast8BitColorIndex:
            break;
    }
    if (n < 0 || n > 255) {
        return -1;
    } else {
        return kColorMap8bitBase + n;
    }
}
- (void)terminalSetColorTableEntryAtIndex:(VT100TerminalColorIndex)n color:(NSColor *)color {
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }
    [delegate_ screenSetColor:color forKey:key];
}

- (void)terminalSetCurrentTabColor:(NSColor *)color {
    [delegate_ screenSetCurrentTabColor:color];
}

- (void)terminalSetTabColorRedComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorRedComponentTo:color];
}

- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorGreenComponentTo:color];
}

- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorBlueComponentTo:color];
}

- (BOOL)terminalFocusReportingAllowed {
    return [iTermAdvancedSettingsModel focusReportingEnabled];
}

- (BOOL)terminalCursorVisible {
    return _cursorVisible;
}

- (NSColor *)terminalColorForIndex:(VT100TerminalColorIndex)index {
    const int key = [self colorMapKeyForTerminalColorIndex:index];
    if (key < 0) {
        return nil;
    }
    return [[delegate_ screenColorMap] colorForKey:key];
}

- (int)terminalCursorX {
    return MIN([self cursorX], [self width]);
}

- (int)terminalCursorY {
    return [self cursorY];
}

- (BOOL)terminalWillAutoWrap {
    return self.cursorX > self.width;
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    if (visible != _cursorVisible) {
        _cursorVisible = visible;
        if (visible) {
            [self.temporaryDoubleBuffer reset];
        } else {
            [self.temporaryDoubleBuffer start];
        }
    }
    [delegate_ screenSetCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    [delegate_ screenSetHighlightCursorLine:highlight];
}

- (void)terminalClearCapturedOutput {
    [delegate_ screenClearCapturedOutput];
}

- (void)terminalPromptDidStart {
    [self promptDidStartAt:VT100GridAbsCoordMake(_state.currentGrid.cursor.x,
                                                 _state.currentGrid.cursor.y + self.numberOfScrollbackLines + self.totalScrollbackOverflow)];
}

- (NSArray<NSNumber *> *)terminalTabStops {
    return [[_state.tabStops.allObjects sortedArrayUsingSelector:@selector(compare:)] mapWithBlock:^NSNumber *(NSNumber *ts) {
        return @(ts.intValue + 1);
    }];
}

- (void)terminalSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [self mutSetTabStops:tabStops];
}

- (void)promptDidStartAt:(VT100GridAbsCoord)coord {
    DLog(@"FinalTerm: terminalPromptDidStart");
    if (coord.x > 0 && [delegate_ screenShouldPlacePromptAtFirstColumn]) {
        [self crlf];
    }
    _shellIntegrationInstalled = YES;

    _lastCommandOutputRange.end = coord;
    _lastCommandOutputRange.start = _startOfRunningCommandOutput;

    _currentPromptRange.start = coord;
    _currentPromptRange.end = coord;

    // FinalTerm uses this to define the start of a collapsible region. That would be a nightmare
    // to add to iTerm, and our answer to this is marks, which already existed anyway.
    [delegate_ screenPromptDidStartAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
    if ([iTermAdvancedSettingsModel resetSGROnPrompt]) {
        [_mutableState.terminal resetGraphicRendition];
    }
}

- (void)terminalCommandDidStart {
    DLog(@"FinalTerm: terminalCommandDidStart");
    _currentPromptRange.end = VT100GridAbsCoordMake(_state.currentGrid.cursor.x,
                                                    _state.currentGrid.cursor.y + self.numberOfScrollbackLines + self.totalScrollbackOverflow);
    [self commandDidStartAtScreenCoord:_state.currentGrid.cursor];
    [delegate_ screenPromptDidEndAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
}

- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord {
    [self commandDidStartAt:VT100GridAbsCoordMake(coord.x, coord.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow])];
}

- (void)commandDidStartAt:(VT100GridAbsCoord)coord {
    [self mutSetCommandStartCoord:coord];
}

- (void)terminalCommandDidEnd {
    DLog(@"FinalTerm: terminalCommandDidEnd");
    _currentPromptRange.start = _currentPromptRange.end = VT100GridAbsCoordMake(0, 0);

    [self commandDidEndAtAbsCoord:VT100GridAbsCoordMake(_state.currentGrid.cursor.x, _state.currentGrid.cursor.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow])];
}

- (BOOL)commandDidEndAtAbsCoord:(VT100GridAbsCoord)coord {
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidEndWithRange:[self commandRange]];
        [self mutInvalidateCommandStartCoord];
        _startOfRunningCommandOutput = coord;
        return YES;
    }
    return NO;
}

- (void)terminalAbortCommand {
    DLog(@"FinalTerm: terminalAbortCommand");
    [self mutCommandWasAborted];
}

- (void)terminalSemanticTextDidStartOfType:(VT100TerminalSemanticTextType)type {
    // TODO
}

- (void)terminalSemanticTextDidEndOfType:(VT100TerminalSemanticTextType)type {
    // TODO
}

- (void)terminalProgressAt:(double)fraction label:(NSString *)label {
     // TODO
}

- (void)terminalProgressDidFinish {
    // TODO
}

- (VT100ScreenMark *)lastCommandMark {
    DLog(@"Searching for last command mark...");
    if (_lastCommandMark) {
        DLog(@"Return cached mark %@", _lastCommandMark);
        return _lastCommandMark;
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
                    self.lastCommandMark = mark;
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

- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode {
    DLog(@"FinalTerm: terminalReturnCodeOfLastCommandWas:%d", returnCode);
    VT100ScreenMark *mark = [[self.lastCommandMark retain] autorelease];
    if (mark) {
        DLog(@"FinalTerm: setting code on mark %@", mark);
        const NSInteger line = [self coordRangeForInterval:mark.entry.interval].start.y + self.totalScrollbackOverflow;
        [_intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:mark]
                                                          onLine:line];
        mark.code = returnCode;
        [_intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:mark]
                                                       onLine:line];
        VT100RemoteHost *remoteHost = [self remoteHostOnLine:[self numberOfLines]];
        [[iTermShellHistoryController sharedInstance] setStatusOfCommandAtMark:mark
                                                                        onHost:remoteHost
                                                                            to:returnCode];
        [delegate_ screenNeedsRedraw];
    } else {
        DLog(@"No last command mark found.");
    }
    [delegate_ screenCommandDidExitWithCode:returnCode mark:mark];
}

- (void)terminalFinalTermCommand:(NSArray *)argv {
    // TODO
    // Currently, FinalTerm supports these commands:
  /*
   QUIT_PROGRAM,
   SEND_TO_SHELL,
   CLEAR_SHELL_COMMAND,
   SET_SHELL_COMMAND,
   RUN_SHELL_COMMAND,
   TOGGLE_VISIBLE,
   TOGGLE_FULLSCREEN,
   TOGGLE_DROPDOWN,
   ADD_TAB,
   SPLIT,
   CLOSE,
   LOG,
   PRINT_METRICS,
   COPY_TO_CLIPBOARD,
   OPEN_URL
   */
}

// version is formatted as
// <version number>;<key>=<value>;<key>=<value>...
// Older scripts may have only a version number and no key-value pairs.
// The only defined key is "shell", and the value will be tcsh, bash, zsh, or fish.
- (void)terminalSetShellIntegrationVersion:(NSString *)version {
    NSArray *parts = [version componentsSeparatedByString:@";"];
    NSString *shell = nil;
    NSInteger versionNumber = [parts[0] integerValue];
    if (parts.count >= 2) {
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        for (NSString *kvp in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
            NSRange equalsRange = [kvp rangeOfString:@"="];
            if (equalsRange.location == NSNotFound) {
                continue;
            }
            NSString *key = [kvp substringToIndex:equalsRange.location];
            NSString *value = [kvp substringFromIndex:NSMaxRange(equalsRange)];
            params[key] = value;
        }
        shell = params[@"shell"];
    }

    NSDictionary<NSString *, NSNumber *> *lastVersionByShell =
        @{ @"tcsh": @2,
           @"bash": @5,
           @"zsh": @5,
           @"fish": @5 };
    NSInteger latestKnownVersion = [lastVersionByShell[shell ?: @""] integerValue];
    if (shell) {
        [delegate_ screenDidDetectShell:shell];
    }
    if (!shell || versionNumber < latestKnownVersion) {
        [delegate_ screenSuggestShellIntegrationUpgrade];
    }
}

- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue {
    [self mutSetWraparoundMode:newValue];
}

- (void)terminalTypeDidChange {
    [self mutUpdateTerminalType];
}

- (void)terminalInsertModeDidChangeTo:(BOOL)newValue {
    [self mutSetInsert:newValue];
}

- (NSString *)terminalProfileName {
    return [delegate_ screenProfileName];
}

- (VT100GridRect)terminalScrollRegion {
    return _state.currentGrid.scrollRegionRect;
}

- (int)terminalChecksumInRectangle:(VT100GridRect)rect {
    int result = 0;
    for (int y = rect.origin.y; y < rect.origin.y + rect.size.height; y++) {
        screen_char_t *theLine = [self getLineAtScreenIndex:y];
        for (int x = rect.origin.x; x < rect.origin.x + rect.size.width && x < self.width; x++) {
            unichar code = theLine[x].code;
            BOOL isPrivate = (code < ITERM2_PRIVATE_BEGIN &&
                              code > ITERM2_PRIVATE_END);
            if (code && !isPrivate) {
                NSString *s = ScreenCharToStr(&theLine[x]);
                for (int i = 0; i < s.length; i++) {
                    result += (int)[s characterAtIndex:i];
                }
            }
        }
    }
    return result;
}

- (NSSet<NSString *> *)sgrCodesForChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    return [_state.terminal sgrCodesForCharacter:c externalAttributes:ea];
}

- (NSArray<NSString *> *)terminalSGRCodesInRectangle:(VT100GridRect)screenRect {
    __block NSMutableSet<NSString *> *codes = nil;
    VT100GridRect rect = screenRect;
    rect.origin.y += [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
    [self enumerateLinesInRange:NSMakeRange(rect.origin.y, rect.size.height)
                          block:^(int y,
                                  ScreenCharArray *sca,
                                  iTermImmutableMetadata metadata,
                                  BOOL *stop) {
        const screen_char_t *theLine = sca.line;
        id<iTermExternalAttributeIndexReading> eaIndex = iTermImmutableMetadataGetExternalAttributesIndex(metadata);
        for (int x = rect.origin.x; x < rect.origin.x + rect.size.width && x < self.width; x++) {
            const screen_char_t c = theLine[x];
            if (c.code == 0 && !c.complexChar && !c.image) {
                continue;
            }
            NSSet<NSString *> *charCodes = [self sgrCodesForChar:c externalAttributes:eaIndex[x]];
            if (!codes) {
                codes = [[charCodes mutableCopy] autorelease];
            } else {
                [codes intersectSet:charCodes];
                if (!codes.count) {
                    *stop = YES;
                    return;
                }
            }
        }
    }];
    return codes.allObjects ?: @[];
}

- (NSSize)terminalCellSizeInPoints:(double *)scaleOut {
    *scaleOut = [delegate_ screenBackingScaleFactor];
    return [delegate_ screenCellSize];
}

- (void)terminalSetUnicodeVersion:(NSInteger)unicodeVersion {
    [delegate_ screenSetUnicodeVersion:unicodeVersion];
}

- (NSInteger)terminalUnicodeVersion {
    return [delegate_ screenUnicodeVersion];
}

- (void)terminalSetLabel:(NSString *)label forKey:(NSString *)keyName {
    [delegate_ screenSetLabel:label forKey:keyName];
}

- (void)terminalPushKeyLabels:(NSString *)value {
    [delegate_ screenPushKeyLabels:value];
}

- (void)terminalPopKeyLabels:(NSString *)value {
    [delegate_ screenPopKeyLabels:value];
}

// fg=ff0080,bg=srgb:808080
- (void)terminalSetColorNamed:(NSString *)name to:(NSString *)colorString {
    if ([name isEqualToString:@"preset"]) {
        [delegate_ screenSelectColorPresetNamed:colorString];
        return;
    }
    if ([colorString isEqualToString:@"default"] && [name isEqualToString:@"tab"]) {
        [delegate_ screenSetCurrentTabColor:nil];
        return;
    }

    NSInteger colon = [colorString rangeOfString:@":"].location;
    NSString *cs;
    NSString *hex;
    if (colon != NSNotFound && colon + 1 != colorString.length && colon != 0) {
        cs = [colorString substringToIndex:colon];
        hex = [colorString substringFromIndex:colon + 1];
    } else {
        if ([iTermAdvancedSettingsModel p3]) {
            cs = @"p3";
        } else {
            cs = @"srgb";
        }
        hex = colorString;
    }
    NSDictionary *colorSpaces = @{ @"srgb": @"sRGBColorSpace",
                                   @"rgb": @"genericRGBColorSpace",
                                   @"p3": @"displayP3ColorSpace" };
    NSColorSpace *colorSpace = [NSColorSpace it_defaultColorSpace];
    if (colorSpaces[cs]) {
        SEL selector = NSSelectorFromString(colorSpaces[cs]);
        if ([NSColorSpace respondsToSelector:selector]) {
            colorSpace = [[NSColorSpace class] performSelector:selector];
            if (!colorSpace) {
                colorSpace = [NSColorSpace it_defaultColorSpace];
            }
        }
    }
    if (!colorSpace) {
        return;
    }

    CGFloat r, g, b;
    if (hex.length == 6) {
        NSScanner *scanner = [NSScanner scannerWithString:hex];
        unsigned int rgb = 0;
        if (![scanner scanHexInt:&rgb]) {
            return;
        }
        r = ((rgb >> 16) & 0xff);
        g = ((rgb >> 8) & 0xff);
        b = ((rgb >> 0) & 0xff);
    } else if (hex.length == 3) {
        NSScanner *scanner = [NSScanner scannerWithString:hex];
        unsigned int rgb = 0;
        if (![scanner scanHexInt:&rgb]) {
            return;
        }
        r = ((rgb >> 8) & 0xf) | ((rgb >> 4) & 0xf0);
        g = ((rgb >> 4) & 0xf) | ((rgb >> 0) & 0xf0);
        b = ((rgb >> 0) & 0xf) | ((rgb << 4) & 0xf0);
    } else {
        return;
    }
    CGFloat components[4] = { r / 255.0, g / 255.0, b / 255.0, 1.0 };
    NSColor *color = [NSColor colorWithColorSpace:colorSpace
                                       components:components
                                            count:sizeof(components) / sizeof(*components)];
    if (!color) {
        return;
    }

    if ([name isEqualToString:@"tab"]) {
        [delegate_ screenSetCurrentTabColor:color];
        return;
    }

    NSDictionary *names = @{ @"fg": @(kColorMapForeground),
                             @"bg": @(kColorMapBackground),
                             @"bold": @(kColorMapBold),
                             @"link": @(kColorMapLink),
                             @"selbg": @(kColorMapSelection),
                             @"selfg": @(kColorMapSelectedText),
                             @"curbg": @(kColorMapCursor),
                             @"curfg": @(kColorMapCursorText),
                             @"underline": @(kColorMapUnderline),

                             @"black": @(kColorMapAnsiBlack),
                             @"red": @(kColorMapAnsiRed),
                             @"green": @(kColorMapAnsiGreen),
                             @"yellow": @(kColorMapAnsiYellow),
                             @"blue": @(kColorMapAnsiBlue),
                             @"magenta": @(kColorMapAnsiMagenta),
                             @"cyan": @(kColorMapAnsiCyan),
                             @"white": @(kColorMapAnsiWhite),

                             @"br_black": @(kColorMapAnsiBlack + kColorMapAnsiBrightModifier),
                             @"br_red": @(kColorMapAnsiRed + kColorMapAnsiBrightModifier),
                             @"br_green": @(kColorMapAnsiGreen + kColorMapAnsiBrightModifier),
                             @"br_yellow": @(kColorMapAnsiYellow + kColorMapAnsiBrightModifier),
                             @"br_blue": @(kColorMapAnsiBlue + kColorMapAnsiBrightModifier),
                             @"br_magenta": @(kColorMapAnsiMagenta + kColorMapAnsiBrightModifier),
                             @"br_cyan": @(kColorMapAnsiCyan + kColorMapAnsiBrightModifier),
                             @"br_white": @(kColorMapAnsiWhite + kColorMapAnsiBrightModifier) };

    NSNumber *keyNumber = names[name];
    if (!keyNumber) {
        return;
    }
    NSInteger key = [keyNumber integerValue];

    [delegate_ screenSetColor:color forKey:key];
}

- (void)terminalCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                                           payload:(NSString *)payload {
    [delegate_ screenDidReceiveCustomEscapeSequenceWithParameters:parameters
                                                          payload:payload];
}

- (void)terminalRepeatPreviousCharacter:(int)times {
    if (![iTermAdvancedSettingsModel supportREPCode]) {
        return;
    }
    if (_state.lastCharacter.code) {
        int length = 1;
        screen_char_t chars[2];
        chars[0] = _state.lastCharacter;
        if (_state.lastCharacterIsDoubleWidth) {
            length++;
            chars[1] = _state.lastCharacter;
            chars[1].code = DWC_RIGHT;
            chars[1].complexChar = NO;
        }

        NSString *string = ScreenCharToStr(chars);
        for (int i = 0; i < times; i++) {
            [self mutAppendScreenCharArrayAtCursor:chars
                                            length:length
                            externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:_state.lastExternalAttribute]];
            [delegate_ screenDidAppendStringToCurrentLine:string
                                              isPlainText:(_state.lastCharacter.complexChar ||
                                                           _state.lastCharacter.code >= ' ')];
        }
    }
}

- (void)terminalReportFocusWillChangeTo:(BOOL)reportFocus {
    [self.delegate screenReportFocusWillChangeTo:reportFocus];
}

- (void)terminalPasteBracketingWillChangeTo:(BOOL)bracket {
    [self.delegate screenReportPasteBracketingWillChangeTo:bracket];
}

- (void)terminalSoftAlternateScreenModeDidChange {
    [self.delegate screenSoftAlternateScreenModeDidChange];
}

- (void)terminalReportKeyUpDidChange:(BOOL)reportKeyUp {
    [self.delegate screenReportKeyUpDidChange:reportKeyUp];
}

- (BOOL)terminalIsInAlternateScreenMode {
    return [self showingAlternateScreen];
}

- (NSString *)terminalTopBottomRegionString {
    if (!_state.currentGrid.haveRowScrollRegion) {
        return @"";
    }
    return [NSString stringWithFormat:@"%d;%d", _state.currentGrid.topMargin + 1, _state.currentGrid.bottomMargin + 1];
}

- (NSString *)terminalLeftRightRegionString {
    if (!_state.currentGrid.haveColumnScrollRegion) {
        return @"";
    }
    return [NSString stringWithFormat:@"%d;%d", _state.currentGrid.leftMargin + 1, _state.currentGrid.rightMargin + 1];
}

- (NSString *)terminalStringForKeypressWithCode:(unsigned short)keyCode
                                          flags:(NSEventModifierFlags)flags
                                     characters:(NSString *)characters
                    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    return [self.delegate screenStringForKeypressWithCode:keyCode
                                                    flags:flags
                                               characters:characters
                              charactersIgnoringModifiers:charactersIgnoringModifiers];
}

- (void)terminalApplicationKeypadModeDidChange:(BOOL)mode {
    [self.delegate screenApplicationKeypadModeDidChange:mode];
}

- (VT100SavedColorsSlot *)terminalSavedColorsSlot {
    return [delegate_ screenSavedColorsSlot];
}

- (void)terminalRestoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    [delegate_ screenRestoreColorsFromSlot:slot];
}

- (int)terminalMaximumTheoreticalImageDimension {
    return [delegate_ screenMaximumTheoreticalImageDimension];
}

- (void)terminalInsertColumns:(int)n {
    [self mutInsertColumns:n];
}

- (void)terminalDeleteColumns:(int)n {
    [self mutDeleteColumns:n];
}

- (void)terminalSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    [self mutSetAttribute:sgrAttribute inRect:rect];
}

- (void)terminalToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    [self mutToggleAttribute:sgrAttribute inRect:rect];
}

- (void)terminalCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    [self mutCopyFrom:source to:dest];
}

- (void)terminalFillRectangle:(VT100GridRect)rect withCharacter:(unichar)inputChar {
    screen_char_t c = {
        .code = inputChar
    };
    if ([_state.charsetUsesLineDrawingMode containsObject:@(_state.terminal.charset)]) {
        ConvertCharsToGraphicsCharset(&c, 1);
    }
    CopyForegroundColor(&c, [_state.terminal foregroundColorCode]);
    CopyBackgroundColor(&c, [_state.terminal backgroundColorCode]);

    // Only preserve SGR attributes. image is OSC, not SGR.
    c.image = 0;

    [self mutFillRectangle:rect with:c externalAttributes:[_state.terminal externalAttributes]];
}

- (void)terminalEraseRectangle:(VT100GridRect)rect {
    screen_char_t c = [_state.currentGrid defaultChar];
    c.code = ' ';
    [self mutFillRectangle:rect with:c externalAttributes:nil];
}

- (void)terminalSelectiveEraseRectangle:(VT100GridRect)rect {
    [self mutSelectiveEraseRectangle:rect];
}

- (void)terminalSelectiveEraseInDisplay:(int)mode {
    BOOL before = NO;
    BOOL after = NO;
    switch (mode) {
        case 0:
            after = YES;
            break;
        case 1:
            before = YES;
            break;
        case 2:
            before = YES;
            after = YES;
            break;
    }
    // Unlike DECSERA, this does erase attributes.
    [self mutEraseInDisplayBeforeCursor:before afterCursor:after decProtect:YES];
}

- (void)terminalSelectiveEraseInLine:(int)mode {
    switch (mode) {
        case 0:
            [self mutSelectiveEraseRange:VT100GridCoordRangeMake(_state.currentGrid.cursorX,
                                                                 _state.currentGrid.cursorY,
                                                                 _state.currentGrid.size.width,
                                                                 _state.currentGrid.cursorY)
                         eraseAttributes:YES];
            return;
        case 1:
            [self mutSelectiveEraseRange:VT100GridCoordRangeMake(0,
                                                                 _state.currentGrid.cursorY,
                                                                 _state.currentGrid.cursorX + 1,
                                                                 _state.currentGrid.cursorY)
                         eraseAttributes:YES];
            return;
        case 2:
            [self mutSelectiveEraseRange:VT100GridCoordRangeMake(0,
                                                                 _state.currentGrid.cursorY,
                                                                 _state.currentGrid.size.width,
                                                                 _state.currentGrid.cursorY)
                         eraseAttributes:YES];
    }
}

- (void)terminalProtectedModeDidChangeTo:(VT100TerminalProtectedMode)mode {
    _protectedMode = mode;
}

- (VT100TerminalProtectedMode)terminalProtectedMode {
    return _protectedMode;
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

- (void)doPrint {
    if ([_state.printBuffer length] > 0) {
        [delegate_ screenPrintString:_state.printBuffer];
    } else {
        [delegate_ screenPrintVisibleArea];
    }
    _mutableState.printBuffer = nil;
    _mutableState.collectInputForPrinting = NO;
}

- (void)saveFindContextAbsPos {
    int linesPushed;
    linesPushed = [self.mutableCurrentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                                          toLineBuffer:linebuffer_];

    [self mutSaveFindContextPosition];
    [self mutPopScrollbackLines:linesPushed];
}

- (iTermAsyncFilter *)newAsyncFilterWithDestination:(id<iTermFilterDestination>)destination
                                              query:(NSString *)query
                                           refining:(iTermAsyncFilter *)refining
                                           progress:(void (^)(double))progress {
    return [[iTermAsyncFilter alloc] initWithQuery:query
                                        lineBuffer:linebuffer_
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
    if (_trackCursorLineMovement) {
        [delegate_ screenCursorDidMoveToLine:_state.currentGrid.cursorY + [self numberOfScrollbackLines]];
    }
}

- (iTermUnicodeNormalization)gridUnicodeNormalizationForm {
    return _normalization;
}

- (void)gridCursorDidMove {
}

- (void)gridDidResize {
    [self.delegate screenDidResize];
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        self.lastCommandMark = mark;
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
           kScreenStateNextCommandOutputStartKey: [NSDictionary dictionaryWithGridAbsCoord:_startOfRunningCommandOutput],
           kScreenStateCursorVisibleKey: @(_cursorVisible),
           kScreenStateTrackCursorLineMovementKey: @(_trackCursorLineMovement),
           kScreenStateLastCommandOutputRangeKey: [NSDictionary dictionaryWithGridAbsCoordRange:_lastCommandOutputRange],
           kScreenStateShellIntegrationInstalledKey: @(_shellIntegrationInstalled),
           kScreenStateLastCommandMarkKey: _lastCommandMark.guid ?: [NSNull null],
           kScreenStatePrimaryGridStateKey: _state.primaryGrid.dictionaryValue ?: @{},
           kScreenStateAlternateGridStateKey: _state.altGrid.dictionaryValue ?: [NSNull null],
           kScreenStateProtectedMode: @(_protectedMode),
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
    if (_initialSize.width > 0 && _initialSize.height > 0) {
        [self setSize:_initialSize];
        _initialSize = VT100GridSizeMake(-1, -1);
    }
}

- (iTermTemporaryDoubleBufferedGridController *)temporaryDoubleBuffer {
    if ([delegate_ screenShouldReduceFlicker] || _temporaryDoubleBuffer.explicit) {
        return _temporaryDoubleBuffer;
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

    state.colorMap = [self.delegate.screenColorMap.copy autorelease];
    state.cursorVisible = self.temporaryDoubleBuffer.explicit ? _cursorVisible : YES;

    return state;

}

- (void)temporaryDoubleBufferedGridDidExpire {
    [self mutRedrawGrid];
}

#pragma mark - iTermLineBufferDelegate

- (void)lineBufferDidDropLines:(LineBuffer *)lineBuffer {
    if (lineBuffer == linebuffer_) {
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

