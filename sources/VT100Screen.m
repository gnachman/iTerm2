
#import "VT100Screen.h"
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"
#import "VT100Screen+Resizing.h"
#import "VT100Screen+Search.h"

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
#import "iTermIntervalTreeObserver.h"
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
#import "VT100ScreenMutableState+Resizing.h"
#import "VT100Screen+Mutation.h"
#import "VT100ScreenConfiguration.h"
#import "VT100Token.h"
#import "VT100ScreenState.h"

#import <apr-1/apr_base64.h>

int kVT100ScreenMinColumns = 2;
int kVT100ScreenMinRows = 2;


const NSInteger VT100ScreenBigFileDownloadThreshold = 1024 * 1024 * 1024;


@implementation VT100Screen {
    // Used for recording instant replay.
    // This is an inherently shared mutable data structure. I don't think it can be easily moved into
    // the VT100ScreenState model. Instad it will need lots of mutexes :(
    DVR* dvr_;
}

@synthesize dvr = dvr_;

- (instancetype)init {
    self = [super init];
    if (self) {
#warning TODO: update colormap's darkMode through VT100ScreenConfiguration
        _mutableState = [[VT100ScreenMutableState alloc] initWithSideEffectPerformer:self];
        _state = [_mutableState retain];

        _mutableState.temporaryDoubleBuffer.delegate = self;
        _findContext = [[FindContext alloc] init];

        [iTermNotificationController sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes] * 1024 * 1024];
    }
    return self;
}

- (void)dealloc {
    [dvr_ release];
    [_state release];
    [_mutableState release];
    [_findContext release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, _state.currentGrid];
}

#pragma mark - APIs

- (BOOL)shouldExpectPromptMarks {
    return _state.shouldExpectPromptMarks;
}

- (void)setShouldExpectPromptMarks:(BOOL)value {
    [self mutSetShouldExpectPromptMarks:value];
}

- (void)userDidPressReturn {
    [self mutateAsynchronously:^(VT100Terminal * _Nonnull terminal,
                                 VT100ScreenMutableState * _Nonnull mutableState,
                                 id<VT100ScreenDelegate>  _Nonnull delegate) {
        if (mutableState.fakePromptDetectedAbsLine >= 0) {
            [mutableState didInferEndOfCommand];
        }
    }];
}

- (void)setDelegate:(id<VT100ScreenDelegate>)delegate {
    [self mutSetDelegate:delegate];
}

- (id<VT100ScreenDelegate>)delegate {
    return delegate_;
}

- (void)setTerminalEnabled:(BOOL)enabled {
    if (_terminalEnabled == enabled) {
        return;
    }
    _terminalEnabled = enabled;
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.terminalEnabled = enabled;
        if (enabled) {
            [self mutSetDelegate:self.delegate];
        }
    }];
}

- (void)setSize:(VT100GridSize)size {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setSize:size delegate:delegate];
    }];
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
    if (_state.terminalCharset) {
        return NO;
    }
    return YES;
}

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors {
    [self mutHighlightTextInRange:range basedAtAbsoluteLineNumber:absoluteLineNumber colors:colors];
}

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                  URLCode:(unsigned int)code {
    [self mutLinkTextInRange:range basedAtAbsoluteLineNumber:absoluteLineNumber URLCode:code];
}

- (void)storeLastPositionInLineBufferAsFindContextSavedPosition {
    [self storeLastPositionInLineBufferAsFindContextSavedPositionImpl];
}

- (VT100GridAbsCoord)commandStartCoord {
    return _state.commandStartCoord;
}

- (void)setColor:(NSColor *)color forKey:(int)key {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setColor:color forKey:key];
    }];
}

- (void)setDimmingAmount:(double)value {
    [self mutSetDimmingAmount:value];
}

#pragma mark - PTYTextViewDataSource

- (BOOL)showingAlternateScreen {
    return _state.currentGrid == _state.altGrid;
}

- (NSSet<NSString *> *)sgrCodesForChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    return [VT100Terminal sgrCodesForCharacter:c externalAttributes:ea];
}

- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord {
    [self commandDidStartAt:VT100GridAbsCoordMake(coord.x, coord.y + _state.numberOfScrollbackLines + _state.cumulativeScrollbackOverflow)];
}

- (void)commandDidStartAt:(VT100GridAbsCoord)coord {
    [self mutSetCommandStartCoord:coord];
}

// NOTE: If you change this you probably want to change -haveCommandInRange:, too.
- (NSString *)commandInRange:(VT100GridCoordRange)range {
    return [_state commandInRange:range];
}

- (BOOL)haveCommandInRange:(VT100GridCoordRange)range {
    return [_state haveCommandInRange:range];
}

// This is a wee hack until PTYTextView breaks its direct dependence on PTYSession
- (PTYSession *)session {
    return (PTYSession *)delegate_;
}

// Returns the number of lines in scrollback plus screen height.
- (int)numberOfLines {
    return _state.numberOfLines;
}

- (int)width {
    return _state.currentGrid.size.width;
}

- (int)height {
    return _state.currentGrid.size.height;
}

- (int)cursorX {
    return _state.cursorX;
}

- (int)cursorY {
    return _state.cursorY;
}

- (void)enumerateLinesInRange:(NSRange)range block:(void (^)(int, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block {
    [_state enumerateLinesInRange:range block:block];
}

- (ScreenCharArray *)screenCharArrayForLine:(int)line {
    return [_state screenCharArrayForLine:line];
}

- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    return [_state screenCharArrayAtScreenIndex:index];
}

- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *))block {
    return [_state fetchLine:line block:block];
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber {
    return [_state metadataOnLine:lineNumber];
}

- (iTermImmutableMetadata)metadataAtScreenIndex:(int)index {
    return [_state.currentGrid immutableMetadataAtLineNumber:index];
}

- (id<iTermExternalAttributeIndexReading>)externalAttributeIndexForLine:(int)y {
    return [_state externalAttributeIndexForLine:y];
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex {
    return [_state getLineAtIndex:theIndex];
}

// theIndex = 0 for first line in history; for sufficiently large values, it pulls from the current
// grid.
- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer {
    return [_state getLineAtIndex:theIndex withBuffer:buffer];
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
    return _state.numberOfScrollbackLines;
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
    return _state.cumulativeScrollbackOverflow + _state.numberOfLines - _state.height + _state.currentGrid.cursorY;
}

- (int)lineNumberOfCursor {
    return _state.lineNumberOfCursor;
}

- (BOOL)continueFindAllResults:(NSMutableArray *)results inContext:(FindContext *)context {
    return [self continueFindAllResultsImpl:results inContext:context];
}

- (NSString *)debugString {
    return [_state.currentGrid debugString];
}

- (NSString *)compactLineDumpWithHistory {
    NSMutableString *string = [NSMutableString stringWithString:[_state.linebuffer compactLineDumpWithWidth:_state.width
                                                                                       andContinuationMarks:NO]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[_state.currentGrid compactLineDump]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarks {
    NSMutableString *string = [NSMutableString stringWithString:[_state.linebuffer compactLineDumpWithWidth:_state.width
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
    return [_state compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers];
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

- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord {
    coord.x--;
    while (coord.x < 0) {
        coord.x += _state.width;
        coord.y--;
        if (coord.y < 0) {
            coord.y = 0;
            return coord;
        }
    }
    return coord;
}

- (id)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    return [_state objectOnOrBeforeLine:line ofClass:cls];
}

- (VT100RemoteHost *)remoteHostOnLine:(int)line {
    return [_state remoteHostOnLine:line];
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
    return [_state workingDirectoryOnLine:line];
}

- (void)removeAnnotation:(PTYAnnotation *)annotation {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState removeAnnotation:annotation];
    }];
}

- (void)removeInaccessibleNotes {
    long long lastDeadLocation = _state.cumulativeScrollbackOverflow * (_state.width + 1);
    if (lastDeadLocation > 0) {
        Interval *deadInterval = [Interval intervalWithLocation:0 length:lastDeadLocation + 1];
        for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:deadInterval]) {
            if ([obj.entry.interval limit] <= lastDeadLocation) {
                [_mutableState removeObjectFromIntervalTree:obj];
            }
        }
    }
}

- (BOOL)markIsValid:(iTermMark *)mark {
    return [_state.intervalTree containsObject:mark];
}

- (VT100GridCoordRange)coordRangeOfAnnotation:(PTYAnnotation *)note {
    return [_state coordRangeForInterval:note.entry.interval];
}

- (NSArray *)charactersWithNotesOnLine:(int)line {
    NSMutableArray *result = [NSMutableArray array];
    Interval *interval = [_state intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                                   line,
                                                                                   0,
                                                                                   line + 1)];
    NSArray *objects = [_state.intervalTree objectsInInterval:interval];
    for (id<IntervalTreeObject> object in objects) {
        if ([object isKindOfClass:[PTYAnnotation class]]) {
            VT100GridCoordRange range = [_state coordRangeForInterval:object.entry.interval];
            VT100GridRange gridRange;
            if (range.start.y < line) {
                gridRange.location = 0;
            } else {
                gridRange.location = range.start.x;
            }
            if (range.end.y > line) {
                gridRange.length = _state.width + 1 - gridRange.location;
            } else {
                gridRange.length = range.end.x - gridRange.location;
            }
            [result addObject:[NSValue valueWithGridRange:gridRange]];
        }
    }
    return result;
}

- (NSArray<PTYAnnotation *> *)annotationsInRange:(VT100GridCoordRange)range {
    Interval *interval = [_state intervalForGridCoordRange:range];
    NSArray *objects = [_state.intervalTree objectsInInterval:interval];
    NSMutableArray *notes = [NSMutableArray array];
    for (id<IntervalTreeObject> o in objects) {
        if ([o isKindOfClass:[PTYAnnotation class]]) {
            [notes addObject:o];
        }
    }
    return notes;
}

- (VT100ScreenMark *)lastPromptMark {
    return [_state lastPromptMark];
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
    const NSInteger overflow = _state.cumulativeScrollbackOverflow;
    for (NSArray *objects in _state.intervalTree.forwardLimitEnumerator) {
        for (id<IntervalTreeObject> obj in objects) {
            const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(obj);
            if (type == iTermIntervalTreeObjectTypeUnknown) {
                continue;
            }
            NSInteger line = [_state coordRangeForInterval:obj.entry.interval].start.y + overflow;
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
    const int cursorLine = self.currentGrid.cursor.y + _state.numberOfScrollbackLines;
    VT100ScreenMark *lastMark = [self lastMarkPassingTest:^BOOL(__kindof id<IntervalTreeObject> obj) {
        if (![obj isKindOfClass:[VT100ScreenMark class]]) {
            return NO;
        }
        VT100ScreenMark *mark = obj;
        const VT100GridCoord intervalStart = [_state coordRangeForInterval:mark.entry.interval].start;
        if (intervalStart.y >= _state.numberOfScrollbackLines + self.currentGrid.cursor.y) {
            return NO;
        }
        // Found a screen mark above the cursor.
        return YES;
    }];
    long long line = overflow;
    if (lastMark) {
        const VT100GridCoordRange range = [_state coordRangeForInterval:lastMark.entry.interval];
        line = overflow + range.end.y;
        if (range.end.y != cursorLine - 1) {
            // Unless we're erasing exactly the line above the cursor, preserve the line with the mark.
            line += 1;
        }
    }
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState clearFromAbsoluteLineToEnd:line];
    }];
}

- (VT100ScreenMark *)lastMark {
    return [self lastMarkMustBePrompt:NO class:[VT100ScreenMark class]];
}

- (VT100RemoteHost *)lastRemoteHost {
    return [_state lastRemoteHost];
}

- (id)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    return [_state lastMarkMustBePrompt:wantPrompt class:theClass];
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
    return [_state markOnLine:line];
}

- (NSArray<VT100ScreenMark *> *)lastMarks {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<VT100ScreenMark *> *)firstMarks {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<PTYAnnotation *> *)lastAnnotations {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYAnnotation class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<PTYAnnotation *> *)firstAnnotations {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYAnnotation class] ]
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
    Interval *interval = [_state intervalForGridCoordRange:VT100GridCoordRangeMake(0, line, 0, line)];
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return overflow + [_state coordRangeForInterval:mark.entry.interval].start.y;
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
    Interval *interval = [_state intervalForGridCoordRange:VT100GridCoordRangeMake(0, line + 1, 0, line + 1)];
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return overflow + [_state coordRangeForInterval:mark.entry.interval].end.y;
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
    NSArray<Class> *classes = @[ [PTYAnnotation class],
                                 [VT100ScreenMark class] ];
    return [self marksOfAnyClassIn:classes before:location];
}

- (NSArray *)marksOrNotesAfter:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYAnnotation class],
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
    NSArray<Class> *classes = @[ [PTYAnnotation class] ];
    return [self marksOfAnyClassIn:classes before:location];
}

- (NSArray *)annotationsAfter:(Interval *)location {
    NSArray<Class> *classes = @[ [PTYAnnotation class] ];
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
    return [_state lineNumberRangeOfInterval:interval];
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
                range.start = [_state coordRangeForInterval:mark.entry.interval].end;
                range.start.x = 0;
                range.start.y++;
                range.end = [_state coordRangeForInterval:nextMark.entry.interval].start;
                return range;
            }
        }
    } while (objects && !objects.count);

    // Command must still be running with no subsequent prompt.
    VT100GridCoordRange range;
    range.start = [_state coordRangeForInterval:mark.entry.interval].end;
    range.start.x = 0;
    range.start.y++;
    range.end.x = 0;
    range.end.y = _state.numberOfLines - _state.height + [_state.currentGrid numberOfLinesUsed];
    return range;
}

- (PTYTextViewSynchronousUpdateState *)setUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    return [self mutSetUseSavedGridIfAvailable:useSavedGrid];
}

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber {
    return [_state stringLineAsStringAtAbsoluteLineNumber:absoluteLineNumber startPtr:startAbsLineNumber];
}

#pragma mark - Private

- (BOOL)isAnyCharDirty {
    return [_state.currentGrid isAnyCharDirty];
}

// NSLog the screen contents for debugging.
- (void)dumpScreen {
    NSLog(@"%@", [self debugString]);
}

- (BOOL)useColumnScrollRegion {
    return _state.currentGrid.useScrollRegionCols;
}

- (void)blink {
    if ([_state.currentGrid isAnyCharDirty]) {
        [delegate_ screenNeedsRedraw];
    }
}

- (VT100ScreenMark *)lastCommandMark {
    return [_state lastCommandMark];
}

- (void)saveFindContextAbsPos {
    [self saveFindContextAbsPosImpl];
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

// Deprecated
- (int)numberOfLinesDroppedWhenEncodingLegacyFormatWithEncoder:(id<iTermEncoderAdapter>)encoder
                                                intervalOffset:(long long *)intervalOffsetPtr {
    if (gDebugLogging) {
        DLog(@"Saving state with width=%@", @(_state.width));
        for (id<IntervalTreeObject> object in _state.intervalTree.allObjects) {
            if (![object isKindOfClass:[PTYAnnotation class]]) {
                continue;
            }
            DLog(@"Save note with coord range %@", VT100GridCoordRangeDescription([_state coordRangeForInterval:object.entry.interval]));
        }
    }
    return [_state numberOfLinesDroppedWhenEncodingContentsIncludingGrid:YES
                                                                 encoder:encoder
                                                          intervalOffset:intervalOffsetPtr];
}

- (int)numberOfLinesDroppedWhenEncodingModernFormatWithEncoder:(id<iTermEncoderAdapter>)encoder
                                                intervalOffset:(long long *)intervalOffsetPtr {
    __block int linesDropped = 0;
    [encoder encodeDictionaryWithKey:@"LineBuffer"
                          generation:iTermGenerationAlwaysEncode
                               block:^BOOL(id<iTermEncoderAdapter>  _Nonnull subencoder) {
        linesDropped = [_state numberOfLinesDroppedWhenEncodingContentsIncludingGrid:NO
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
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
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
               kScreenStateTerminalKey: _state.terminalState ?: @{},
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
    // The grid can't be copied later unless it has a delegate. Use _state since it is an immutable snapshot of this point in time.
    state.grid.delegate = _state;

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

#pragma mark - Mutation Wrappers

- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block {
    [_mutableState performBlockWithJoinedThreads:block];
}

- (void)mutateAsynchronously:(void (^)(VT100Terminal *terminal,
                                       VT100ScreenMutableState *mutableState,
                                       id<VT100ScreenDelegate> delegate))block {
    [_mutableState performBlockAsynchronously:block];
}

- (void)forceCheckTriggers {
    [self mutForceCheckTriggers];
}

- (void)synchronizeWithConfig:(id<VT100ScreenConfiguration>)sourceConfig
                       expect:(iTermExpect *)maybeExpect
                checkTriggers:(BOOL)checkTriggers {
    [_mutableState willSynchronize];
    if (checkTriggers) {
        [_mutableState forceCheckTriggers];
    }
    if (sourceConfig.isDirty) {
        self.config = sourceConfig;
    }
    if (maybeExpect) {
        [_mutableState updateExpectFrom:maybeExpect];
    }
    _mutableState.mainThreadCopy = [_mutableState copy];
#warning TODO: _state = [_mutableState copy]
}

- (void)performPeriodicTriggerCheck {
    [self mutPerformPeriodicTriggerCheck];
}

- (void)setExited:(BOOL)exited {
    [self mutSetExited:exited];
}

- (void)injectData:(NSData *)data {
    [self mutInjectData:data];
}

// Warning: this is called on PTYTask's thread.
- (void)threadedReadTask:(char *)buffer length:(int)length {
    [_mutableState threadedReadTask:buffer length:length];
}

// Warning: this is called on PTYTask's thread.
- (void)addTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority {
    [self mutAddTokens:vector length:length highPriority:highPriority];
}

- (void)scheduleTokenExecution {
    [self mutScheduleTokenExecution];
}

- (long long)lastPromptLine {
    return _state.lastPromptLine;
}

- (void)beginEchoProbeWithBackspace:(NSData *)backspace
                           password:(NSString *)password
                           delegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        mutableState.echoProbeDelegate = echoProbeDelegate;
        [mutableState.echoProbe beginProbeWithBackspace:backspace
                                               password:password];
    }];
}

- (void)sendPasswordInEchoProbe {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                          VT100ScreenMutableState *mutableState,
                                          id<VT100ScreenDelegate> delegate) {
        [mutableState.echoProbe enterPassword];
    }];
}

- (void)setEchoProbeDelegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        mutableState.echoProbeDelegate = echoProbeDelegate;
    }];
}

- (void)resetEchoProbe {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        [mutableState.echoProbe reset];
    }];
}

- (BOOL)echoProbeIsActive {
    return _state.echoProbeIsActive;
}

- (void)setLastPromptLine:(long long)lastPromptLine {
    [self mutSetLastPromptLine:lastPromptLine];
}

- (long long)fakePromptDetectedAbsLine {
    return _state.fakePromptDetectedAbsLine;
}

- (void)clearBuffer {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState clearBufferSavingPrompt:YES];
    }];
}

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                          VT100ScreenMutableState *mutableState,
                                          id<VT100ScreenDelegate> delegate) {
        [mutableState restoreFromDictionary:dictionary
                   includeRestorationBanner:includeRestorationBanner
                                 reattached:reattached
                                   delegate:delegate];
    }];
}


- (void)restoreSavedPositionToFindContext:(FindContext *)context {
    [self restoreSavedPositionToFindContextImpl:context];
}

- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults {
    [self setFindStringImpl:aString
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

- (void)addNote:(PTYAnnotation *)note
        inRange:(VT100GridCoordRange)range
          focus:(BOOL)focus {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState addAnnotation:note inRange:range focus:focus];
    }];
}

- (void)resetTimestamps {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState.primaryGrid resetTimestamps];
        [mutableState.altGrid resetTimestamps];
    }];
}

- (void)setMaxScrollbackLines:(unsigned int)lines {
    [self mutSetMaxScrollbackLines:lines];
}

#pragma mark - Accessors

- (BOOL)terminalSoftAlternateScreenMode {
    return _state.terminalSoftAlternateScreenMode;
}

- (MouseMode)terminalMouseMode {
    return _state.terminalMouseMode;
}

- (NSStringEncoding)terminalEncoding {
    return _state.terminalEncoding;
}

- (BOOL)terminalSendReceiveMode {
    return _state.terminalSendReceiveMode;
}

- (VT100Output *)terminalOutput {
    return _state.terminalOutput;
}

- (BOOL)terminalAllowPasteBracketing {
    return _state.terminalAllowPasteBracketing;
}

- (BOOL)terminalBracketedPasteMode {
    return _state.terminalBracketedPasteMode;
}

- (NSMutableArray<NSNumber *> *)terminalSendModifiers {
    return _state.terminalSendModifiers;
}

- (VT100TerminalKeyReportingFlags)terminalKeyReportingFlags {
    return _state.terminalKeyReportingFlags;
}

- (BOOL)terminalReportFocus {
    return _state.terminalReportFocus;
}

- (BOOL)terminalReportKeyUp {
    return _state.terminalReportKeyUp;
}

- (BOOL)terminalCursorMode {
    return _state.terminalCursorMode;
}

- (BOOL)terminalKeypadMode {
    return _state.terminalKeypadMode;
}

- (BOOL)terminalReceivingFile {
    return _state.terminalReceivingFile;
}

- (BOOL)terminalMetaSendsEscape {
    return _state.terminalMetaSendsEscape;
}

- (BOOL)terminalReverseVideo {
    return _state.terminalReverseVideo;
}

- (BOOL)terminalAlternateScrollMode {
    return _state.terminalAlternateScrollMode;
}

- (BOOL)terminalAutorepeatMode {
    return _state.terminalAutorepeatMode;
}

- (int)terminalCharset {
    return _state.terminalCharset;
}

- (VT100GridCoordRange)commandRange {
    return _state.commandRange;
}

- (void)setConfig:(id<VT100ScreenConfiguration>)config {
    [_nextConfig autorelease];
    _nextConfig = [config copyWithZone:nil];
#warning TODO: Fix this up when moving to a mutation thread.
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
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        _mutableState.trackCursorLineMovement = trackCursorLineMovement;
    }];
}

- (VT100GridAbsCoordRange)lastCommandOutputRange {
    return _state.lastCommandOutputRange;
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

#pragma mark - VT100ScreenSideEffectPerforming

- (id<VT100ScreenDelegate>)sideEffectPerformingScreenDelegate {
    assert([NSThread isMainThread]);
    return self.delegate;
}

- (id<iTermIntervalTreeObserver>)sideEffectPerformingIntervalTreeObserver {
    assert([NSThread isMainThread]);
    return _state.intervalTreeObserver;
}

@end

