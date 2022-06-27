
#import "VT100Screen.h"
#import "VT100Screen+Private.h"
#import "VT100Screen+Search.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "DVR.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermColorMap.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermGCD.h"
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
#import "VT100LineInfo.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "VT100WorkingDirectory.h"
#import "VT100DCSParser.h"
#import "VT100ScreenMutableState+Resizing.h"
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
    NSMutableIndexSet *_animatedLines;
    // If positive, _state is a sanitizing adapter of _mutableState. Changes to the current grid are immediately reflected in the mutable state.
    NSInteger _sharedStateCount;

    // If YES, we reset dirty on a shared grid and the grid must be merged regardless of its dirty bits.
    BOOL _forceMergeGrids;
}

@synthesize dvr = dvr_;
@synthesize delegate = delegate_;

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableState = [[VT100ScreenMutableState alloc] initWithSideEffectPerformer:self];
        _animatedLines = [[NSMutableIndexSet alloc] init];
        _state = [_mutableState copy];
        _mutableState.mainThreadCopy = _state;
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
    [_animatedLines release];
    [_searchBuffer release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p grid:%@ mutableState:%p>", [self class], self, _state.currentGrid, _mutableState];
}

#pragma mark - APIs

- (BOOL)shouldExpectPromptMarks {
    return _state.shouldExpectPromptMarks;
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

- (void)setTerminalEnabled:(BOOL)enabled {
    if (_terminalEnabled == enabled) {
        return;
    }
    _terminalEnabled = enabled;
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.terminalEnabled = enabled;
    }];
}

- (void)setSize:(VT100GridSize)size {
    [self.delegate screenEnsureDefaultMode];
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

- (void)storeLastPositionInLineBufferAsFindContextSavedPosition {
    [self storeLastPositionInLineBufferAsFindContextSavedPositionImpl];
}

- (VT100GridAbsCoord)commandStartCoord {
    return _state.commandStartCoord;
}

- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setColorsFromDictionary:dict];
    }];
}

- (void)setColor:(NSColor *)color forKey:(int)key {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setColor:color forKey:key];
    }];
}

- (void)destructivelySetScreenWidth:(int)width
                             height:(int)height
                       mutableState:(VT100ScreenMutableState *)mutableState {
    [self.delegate screenEnsureDefaultMode];
    self.findContext.substring = nil;
    [mutableState destructivelySetScreenWidth:MAX(width, kVT100ScreenMinColumns)
                                       height:MAX(height, kVT100ScreenMinRows)];
}

#pragma mark - PTYTextViewDataSource

- (id<iTermTextDataSource>)snapshotDataSource {
    return [[[iTermTerminalContentSnapshot alloc] initWithLineBuffer:_state.linebuffer
                                                                grid:_state.currentGrid
                                                  cumulativeOverflow:_state.cumulativeScrollbackOverflow] autorelease];
}

- (void)replaceRange:(VT100GridAbsCoordRange)range
        withPorthole:(id<Porthole>)porthole
            ofHeight:(int)numLines {
    [self.delegate screenEnsureDefaultMode];
    [self mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState replaceRange:range withPorthole:porthole ofHeight:numLines];
    }];
}

- (void)replaceMark:(id<iTermMark>)mark withLines:(NSArray<ScreenCharArray *> *)lines {
    [self mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState replaceMark:mark.progenitor withLines:lines];
    }];
}

- (void)changeHeightOfMark:(id<iTermMark>)mark to:(int)newHeight {
    [self mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState changeHeightOfMark:mark.progenitor to:newHeight];
    }];
}

- (void)resetDirty {
    if (_sharedStateCount && !_forceMergeGrids && _state.currentGrid.isAnyCharDirty) {
        // We're resetting dirty in a grid shared by mutable & immutable state. That means when sync
        // ends the mutable grid won't be synced over, leaving the immutable one out-of-date. Set
        // this flag to ensure that doesn't happen.
        _forceMergeGrids = YES;
    }
    [_state.currentGrid markAllCharsDirty:NO updateTimestamps:NO];
}

- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> _Nullable))block {
    [_state performBlockWithSavedGrid:block];
}

- (BOOL)showingAlternateScreen {
    return _state.currentGrid == _state.altGrid;
}

- (NSOrderedSet<NSString *> *)sgrCodesForChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    return [VT100Terminal sgrCodesForCharacter:c externalAttributes:ea];
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

- (BOOL)continueFindAllResults:(NSMutableArray *)results
                      rangeOut:(NSRange *)rangePtr
                     inContext:(FindContext *)context
                 rangeSearched:(VT100GridAbsCoordRange *)rangeSearched {
    return [self continueFindAllResultsImpl:results
                                   rangeOut:rangePtr
                                  inContext:context
                              rangeSearched:rangeSearched];
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
    [_animatedLines addIndex:line];
}

- (void)resetAnimatedLines {
    [_animatedLines removeAllIndexes];
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

- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line {
    return [_state remoteHostOnLine:line];
}

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line {
    DLog(@"Figuring out path for %@ on line %d", filename, line);
    id<VT100RemoteHostReading> remoteHost = [self remoteHostOnLine:line];
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

- (void)removeAnnotation:(id<PTYAnnotationReading>)annotation {
    id<PTYAnnotationReading> progenitor = annotation.progenitor;
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState removeAnnotation:progenitor];
    }];
}

- (void)setStringValueOfAnnotation:(id<PTYAnnotationReading>)annotation to:(NSString *)stringValue {
    id<PTYAnnotationReading> progenitor = annotation.progenitor;
    if (!progenitor) {
        return;
    }
    DLog(@"Optimistically set main-thread copy of %@ to %@", annotation, stringValue);
    // Optimistically set it in the doppelganger. This will be overwritten at the next sync.
    ((PTYAnnotation *)annotation).stringValue = stringValue;
    [self mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setStringValueOfAnnotation:progenitor to:stringValue];
    }];
}

- (BOOL)markIsValid:(iTermMark *)mark {
    return [_state.intervalTree containsObject:mark];
}

- (VT100GridCoordRange)coordRangeOfAnnotation:(id<IntervalTreeImmutableObject>)note {
    return [_state coordRangeForInterval:note.entry.interval];
}

- (VT100GridCoordRange)coordRangeOfPorthole:(id<Porthole>)porthole {
    id<PortholeMarkReading> mark = [[PortholeRegistry instance] markForKey:porthole.uniqueIdentifier];
    if (!mark) {
        return VT100GridCoordRangeInvalid;
    }
    if (!mark.entry.interval) {
        return VT100GridCoordRangeInvalid;
    }
    return [_state coordRangeForInterval:mark.entry.interval];
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

- (NSArray<id<PTYAnnotationReading>> *)annotationsInRange:(VT100GridCoordRange)range {
    Interval *interval = [_state intervalForGridCoordRange:range];
    NSArray *objects = [_state.intervalTree objectsInInterval:interval];
    NSMutableArray<id<PTYAnnotationReading>> *notes = [NSMutableArray array];
    for (id<IntervalTreeObject> o in objects) {
        if ([o isKindOfClass:[PTYAnnotation class]]) {
            [notes addObject:(id<PTYAnnotationReading>)o];
        }
    }
    return notes;
}

- (id<VT100ScreenMarkReading>)lastPromptMark {
    return [_state lastPromptMark];
}

- (id<VT100ScreenMarkReading>)promptMarkWithGUID:(NSString *)guid {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            id<VT100ScreenMarkReading> screenMark = [VT100ScreenMark castFrom:obj];
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
                       block:(void (^ NS_NOESCAPE)(id<VT100ScreenMarkReading> mark))block {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    BOOL foundFirst = (maybeFirst == nil);
    while (objects) {
        for (id obj in objects) {
            id<VT100ScreenMarkReading> screenMark = [VT100ScreenMark castFrom:obj];
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

- (void)enumeratePortholes:(void (^ NS_NOESCAPE)(id<PortholeMarkReading> mark))block {
    for (NSArray<id<IntervalTreeImmutableObject>> *objects in _state.intervalTree.forwardLimitEnumerator) {
        for (id<IntervalTreeImmutableObject> object in objects) {
            PortholeMark *mark = [PortholeMark castFrom:object];
            if (!mark) {
                continue;
            }
            block(mark);
        }
    }
}

- (void)clearToLastMark {
    [self.delegate screenEnsureDefaultMode];
    const long long overflow = self.totalScrollbackOverflow;
    const int cursorLine = self.currentGrid.cursor.y + _state.numberOfScrollbackLines;
    id<VT100ScreenMarkReading> lastMark = [self lastMarkPassingTest:^BOOL(__kindof id<IntervalTreeObject> obj) {
        if (![obj isKindOfClass:[VT100ScreenMark class]]) {
            return NO;
        }
        id<VT100ScreenMarkReading> mark = obj;
        const VT100GridCoord intervalStart = [_state coordRangeForInterval:mark.entry.interval].start;
        if (intervalStart.y >= _state.numberOfScrollbackLines + self.currentGrid.cursor.y) {
            return NO;
        }
        // Found a screen mark above the cursor.
        const VT100GridAbsCoord cursorAbsCoord = VT100GridAbsCoordFromCoord(intervalStart,
                                                                            self.totalScrollbackOverflow);
        if (VT100GridAbsCoordRangeContainsAbsCoord(_state.currentPromptRange, cursorAbsCoord)) {
            // Mark is within the current command's range.
            return NO;
        }
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

- (id<VT100ScreenMarkReading>)lastMark {
    return [self lastMarkMustBePrompt:NO class:[VT100ScreenMark class]];
}

- (id<VT100RemoteHostReading>)lastRemoteHost {
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

- (id<VT100ScreenMarkReading>)markOnLine:(int)line {
    return [_state markOnLine:line];
}

- (NSArray<id<VT100ScreenMarkReading>> *)lastMarks {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<id<VT100ScreenMarkReading>> *)firstMarks {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [VT100ScreenMark class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<id<PTYAnnotationReading>> *)lastAnnotations {
    NSEnumerator *enumerator = [_state.intervalTree reverseLimitEnumerator];
    return [self firstMarkBelongingToAnyClassIn:@[ [PTYAnnotation class] ]
                                usingEnumerator:enumerator];
}

- (NSArray<id<PTYAnnotationReading>> *)firstAnnotations {
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
                id<VT100ScreenMarkReading> mark = object;
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
                id<VT100ScreenMarkReading> mark = object;
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

- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark {
    NSEnumerator *enumerator = [_state.intervalTree forwardLimitEnumeratorAt:mark.entry.interval.limit];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [VT100ScreenMark class] ]];
        for (id<VT100ScreenMarkReading> nextMark in objects) {
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

- (id<VT100ScreenMarkReading>)lastCommandMark {
    return [_state lastCommandMark];
}

- (void)saveFindContextAbsPos {
    [self saveFindContextAbsPosImpl];
}

- (iTermAsyncFilter *)newAsyncFilterWithDestination:(id<iTermFilterDestination>)destination
                                              query:(NSString *)query
                                           refining:(iTermAsyncFilter *)refining
                                           progress:(void (^)(double))progress {
    [self.delegate screenEnsureDefaultMode];
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

#pragma mark - Mutation Wrappers

- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block {
    DLog(@"begin");
    [_mutableState performLightweightBlockWithJoinedThreads:block];
}

- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block {
    DLog(@"%@", [NSThread callStackSymbols]);
    // We don't want to allow joining inside a side-effect because that causes side-effects to run
    // out of order (joining runs remaining side-effects immediately, which is out of order since
    // the current one isn't done yet).
    assert(!_mutableState.performingSideEffect ||
           _mutableState.performingPausedSideEffect);
    [_mutableState performBlockWithJoinedThreads:block];
}

- (void)mutateAsynchronously:(void (^)(VT100Terminal *terminal,
                                       VT100ScreenMutableState *mutableState,
                                       id<VT100ScreenDelegate> delegate))block {
    [self.delegate screenEnsureDefaultMode];
    [_mutableState performBlockAsynchronously:block];
}

- (VT100ScreenState *)switchToSharedState {
    ++_sharedStateCount;
    DLog(@"switch to shared state. count becomes %@", @(_sharedStateCount));
    VT100ScreenState *savedState = [_state autorelease];
    _state = [[_mutableState sanitizingAdapter] retain];
    return savedState;
}

- (void)restoreState:(VT100ScreenState *)state {
    --_sharedStateCount;
    DLog(@"restore state. count becomes %@", @(_sharedStateCount));
    [_state autorelease];
    _state = [state retain];
    BOOL resetDirty = NO;
    if (_forceMergeGrids) {
        DLog(@"merge grids");
        _forceMergeGrids = NO;
        resetDirty = _mutableState.currentGrid.isAnyCharDirty;
        [_mutableState.primaryGrid markAllCharsDirty:YES updateTimestamps:NO];
        [_mutableState.altGrid markAllCharsDirty:YES updateTimestamps:NO];
    }
    [_state mergeFrom:_mutableState];
    if (resetDirty) {
        DLog(@"reset dirty");
        // More cells in the mutable grid were marked dirty since the last refresh.
        [_state.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
    }
}

- (VT100SyncResult)synchronizeWithConfig:(VT100MutableScreenConfiguration *)sourceConfig
                                  expect:(iTermExpect *)maybeExpect
                           checkTriggers:(VT100ScreenTriggerCheckType)checkTriggers
                           resetOverflow:(BOOL)resetOverflow
                            mutableState:(VT100ScreenMutableState *)mutableState {
    if (_sharedStateCount > 0) {
        DLog(@"Short-circuiting sync because there is shared state between threads.\n%@", [NSThread callStackSymbols]);
        return (VT100SyncResult) {
            .overflow = [mutableState scrollbackOverflow] > 0,
            .haveScrolled = _state.currentGrid.haveScrolled
        };
    }
    DLog(@"Begin %@", self);
    [mutableState willSynchronize];
    switch (checkTriggers) {
        case VT100ScreenTriggerCheckTypeNone:
            break;
        case VT100ScreenTriggerCheckTypePartialLines:
            // It's ok for this to run before syncing; although it would be slightly sad for
            // self.config to have changed and this not to pick it up, it's not *wrong* because
            // there's an inherent race between changing config and applying it to input (which can
            // be resolved by using a paused side-effect).
            [mutableState performPeriodicTriggerCheck];
            break;
        case VT100ScreenTriggerCheckTypeFullLines:
            // This intentionally runs before updating VT100Screen.state because it's done prior
            // to changing profiles and we want to activate triggers on the old profile.
            [mutableState forceCheckTriggers];
            break;
    }
    if (sourceConfig.isDirty) {
        DLog(@"source config is dirty");
        // Prevents reentrant sync from setting config more than once.
        sourceConfig.isDirty = NO;
        mutableState.config = sourceConfig;
    }
    if (maybeExpect) {
        DLog(@"update expect");
        [mutableState updateExpectFrom:maybeExpect];
    }
    const int overflow = [mutableState scrollbackOverflow];
    if (resetOverflow) {
        [mutableState resetScrollbackOverflow];
    }
    if (_state) {
        DLog(@"merge state");
        const BOOL mutableStateLineBufferWasDirty = mutableState.linebuffer.dirty;
        [_state mergeFrom:mutableState];

        if (!_wantsSearchBuffer) {
            [_searchBuffer release];
            _searchBuffer = nil;
            DLog(@"nil out searchBuffer");
        } else if (!_searchBuffer) {
            _searchBuffer = [_state.linebuffer copy];
            DLog(@"Initialize searchBuffer to fresh copy");
        } else {
            if (mutableStateLineBufferWasDirty) {
                // forceMergeFrom: is necessary because _state.linebuffer will
                // not be marked dirty since it hasn't been mutated. Because it
                // has an old copy, the merge did mutate it but linebuffer
                // doesn't know that the copy will be merged so it doesn't get
                // marked dirty.
                [_searchBuffer forceMergeFrom:_state.linebuffer];
            } else {
                DLog(@"Line buffer wasn't dirty so leaving searchBuffer alone");
            }
        }
    } else {
        DLog(@"copy state");
        [_state autorelease];
        _state = [mutableState copy];

        [_searchBuffer release];
        _searchBuffer = nil;
        if (_wantsSearchBuffer) {
            _searchBuffer = [_state.linebuffer copy];
            DLog(@"Initialize searchBuffer to fresh copy");
        } else {
            DLog(@"nil out searchBuffer");
        }
    }
    _wantsSearchBuffer = NO;
    [mutableState didSynchronize:resetOverflow];
    DLog(@"End overflow=%@ haveScrolled=%@", @(overflow), @(_state.currentGrid.haveScrolled));
    return (VT100SyncResult) {
        .overflow = overflow,
        .haveScrolled = _state.currentGrid.haveScrolled
    };
}

- (void)injectData:(NSData *)data {
    [self mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState injectData:data];
    }];
}

// Warning: this is called on PTYTask's thread.
- (void)threadedReadTask:(char *)buffer length:(int)length {
    [_mutableState threadedReadTask:buffer length:length];
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

- (long long)fakePromptDetectedAbsLine {
    return _state.fakePromptDetectedAbsLine;
}

- (void)clearBuffer {
    [self.delegate screenEnsureDefaultMode];
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
                                 reattached:reattached];
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

- (void)addNote:(PTYAnnotation *)note
        inRange:(VT100GridCoordRange)range
          focus:(BOOL)focus {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState addAnnotation:note inRange:range focus:focus visible:YES];
    }];
}

- (void)resetTimestamps {
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState.primaryGrid resetTimestamps];
        [mutableState.altGrid resetTimestamps];
    }];
}

- (NSDictionary<NSString *, NSString *> *)exfiltratedEnvironmentVariables:(NSArray<NSString *> *)names {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    [_state.exfiltratedEnvironment enumerateObjectsUsingBlock:^(iTermTuple<NSString *,NSString *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!names || [names containsObject:tuple.firstObject]) {
            result[tuple.firstObject] = tuple.secondObject;
        }
    }];
    return result;
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

- (NSArray<NSNumber *> *)terminalSendModifiers {
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

- (VT100GridCoordRange)extendedCommandRange {
    return _state.extendedCommandRange;
}

- (id<VT100ScreenConfiguration>)config {
    return _state.config;
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
    [self performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.intervalTreeObserver = intervalTreeObserver;
    }];
}

- (iTermUnicodeNormalization)normalization {
    return _state.normalization;
}

- (BOOL)shellIntegrationInstalled {
    return _state.shellIntegrationInstalled;
}

- (BOOL)appendToScrollbackWithStatusBar {
    return _state.appendToScrollbackWithStatusBar;
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

- (unsigned int)maxScrollbackLines {
    return _state.maxScrollbackLines;
}

- (BOOL)unlimitedScrollback {
    return _state.unlimitedScrollback;
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
    return _animatedLines;
}

#pragma mark - VT100ScreenSideEffectPerforming

// THis is accessed by both main and mutation queues and it must be atomic.
- (id<VT100ScreenDelegate>)sideEffectPerformingScreenDelegate {
    return self.delegate;
}

- (id<iTermIntervalTreeObserver>)sideEffectPerformingIntervalTreeObserver {
    [iTermGCD assertMainQueueSafe];
    return _state.intervalTreeObserver;
}

@end

