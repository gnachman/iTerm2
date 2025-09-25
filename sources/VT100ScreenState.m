//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"
#import "VT100ScreenState+Private.h"

#import "DebugLogging.h"
#import "IntervalTree.h"
#import "Interval+Additions.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermEchoProbe.h"
#import "iTermImageMark.h"
#import "iTermOrderEnforcer.h"
#import "iTermTextExtractor.h"
#import "LineBuffer.h"
#import "NSArray+iTerm.h"
#import "VT100Grid.h"
#import "NSDictionary+iTerm.h"
#import "VT100RemoteHost.h"
#import "VT100WorkingDirectory.h"
#import "iTerm2SharedARC-Swift.h"

// State restoration dictionary keys
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
NSString *const kScreenStateExfiltratedEnvironmentKey = @"Client Environment";
NSString *const kScreenStatePromptStateKey = @"Prompt State";
NSString *const kScreenStateBlockStartAbsLineKey = @"Block start lines";
NSString *const kScreenStateKittyImageDrawsKey = @"Kitty Image Draws";

NSString *VT100ScreenTerminalStateKeyVT100Terminal = @"VT100Terminal";
NSString *VT100ScreenTerminalStateKeySavedColors = @"SavedColors";
NSString *VT100ScreenTerminalStateKeyTabStops = @"TabStops";
NSString *VT100ScreenTerminalStateKeyLineDrawingCharacterSets = @"LineDrawingCharacterSets";
NSString *VT100ScreenTerminalStateKeyRemoteHost = @"RemoteHost";
NSString *VT100ScreenTerminalStateKeyPath = @"Path";

@implementation VT100ScreenState {
    id<iTermMarkCacheReading> _markCache;
}

@synthesize audibleBell = _audibleBell;
@synthesize showBellIndicator = _showBellIndicator;
@synthesize flashBell = _flashBell;
@synthesize postUserNotifications = _postUserNotifications;
@synthesize cursorBlinks = _cursorBlinks;
@synthesize collectInputForPrinting = _collectInputForPrinting;
@synthesize printBuffer = _printBuffer;
@synthesize allowTitleReporting = _allowTitleReporting;
@synthesize allowAlternateMouseScroll = _allowAlternateMouseScroll;
@synthesize lastBell = _lastBell;
@synthesize pasteboardString = _pasteboardString;
@synthesize intervalTree = _intervalTree;
@synthesize primaryGrid = _primaryGrid;
@synthesize altGrid = _altGrid;
@synthesize currentGrid = _currentGrid;
@synthesize realCurrentGrid = _realCurrentGrid;
@synthesize savedIntervalTree = _savedIntervalTree;
@synthesize wraparoundMode = _wraparoundMode;
@synthesize ansi = _ansi;
@synthesize insert = _insert;
@synthesize unlimitedScrollback = _unlimitedScrollback;
@synthesize scrollbackOverflow = _scrollbackOverflow;
@synthesize commandStartCoord = _commandStartCoord;
@synthesize maxScrollbackLines = _maxScrollbackLines;
@synthesize tabStops = _tabStops;
@synthesize charsetUsesLineDrawingMode = _charsetUsesLineDrawingMode;
@synthesize lastCharacter = _lastCharacter;
@synthesize lastCharacterIsDoubleWidth = _lastCharacterIsDoubleWidth;
@synthesize lastExternalAttribute = _lastExternalAttribute;
@synthesize saveToScrollbackInAlternateScreen = _saveToScrollbackInAlternateScreen;
@synthesize cursorVisible = _cursorVisible;
@synthesize shellIntegrationInstalled = _shellIntegrationInstalled;
@synthesize lastCommandOutputRange = _lastCommandOutputRange;
@synthesize currentPromptRange = _currentPromptRange;
@synthesize startOfRunningCommandOutput = _startOfRunningCommandOutput;
@synthesize protectedMode = _protectedMode;
@synthesize initialSize = _initialSize;
@synthesize cumulativeScrollbackOverflow = _cumulativeScrollbackOverflow;
@synthesize linebuffer = _linebuffer;
@synthesize trackCursorLineMovement = _trackCursorLineMovement;
@synthesize appendToScrollbackWithStatusBar = _appendToScrollbackWithStatusBar;
@synthesize normalization = _normalization;
@synthesize intervalTreeObserver = _intervalTreeObserver;
@synthesize lastCommandMark = _lastCommandMark;
@synthesize colorMap = _colorMap;
@synthesize temporaryDoubleBuffer = _temporaryDoubleBuffer;
@synthesize fakePromptDetectedAbsLine = _fakePromptDetectedAbsLine;
@synthesize lastPromptLine = _lastPromptLine;
@synthesize shouldExpectPromptMarks = _shouldExpectPromptMarks;
@synthesize echoProbeIsActive = _echoProbeIsActive;
@synthesize terminalSoftAlternateScreenMode = _terminalSoftAlternateScreenMode;
@synthesize terminalMouseMode = _terminalMouseMode;
@synthesize terminalEncoding = _terminalEncoding;
@synthesize terminalSendReceiveMode = _terminalSendReceiveMode;
@synthesize terminalOutput = _terminalOutput;
@synthesize terminalAllowPasteBracketing = _terminalAllowPasteBracketing;
@synthesize terminalBracketedPasteMode = _terminalBracketedPasteMode;
@synthesize terminalSendModifiers = _terminalSendModifiers;
@synthesize terminalKeyReportingFlags = _terminalKeyReportingFlags;
@synthesize terminalReportFocus = _terminalReportFocus;
@synthesize terminalEmulationLevel = _terminalEmulationLevel;
@synthesize terminalLiteralMode = _terminalLiteralMode;
@synthesize terminalReportKeyUp = _terminalReportKeyUp;
@synthesize terminalCursorMode = _terminalCursorMode;
@synthesize terminalKeypadMode = _terminalKeypadMode;
@synthesize terminalReceivingFile = _terminalReceivingFile;
@synthesize terminalMetaSendsEscape = _terminalMetaSendsEscape;
@synthesize terminalReverseVideo = _terminalReverseVideo;
@synthesize terminalAlternateScrollMode = _terminalAlternateScrollMode;
@synthesize terminalAutorepeatMode = _terminalAutorepeatMode;
@synthesize terminalSendResizeNotifications = _terminalSendResizeNotifications;
@synthesize terminalCharset = _terminalCharset;
@synthesize terminalPreviousMouseMode = _terminalPreviousMouseMode;
@synthesize terminalForegroundColorCode = _terminalForegroundColorCode;
@synthesize terminalBackgroundColorCode = _terminalBackgroundColorCode;
@synthesize terminalState = _terminalState;
@synthesize config = _config;
@synthesize exfiltratedEnvironment = _exfiltratedEnvironment;
@synthesize kittyImageDraws = _kittyImageDraws;
@synthesize promptStateDictionary = _promptStateDictionary;
@synthesize namedMarks = _namedMarks;
@synthesize blockStartAbsLine = _blockStartAbsLine;
@synthesize blocksGeneration = _blocksGeneration;

- (instancetype)initForMutationOnQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _commandStartCoord = VT100GridAbsCoordMake(-1, -1);
        _markCache = [[iTermMarkCache alloc] init];
        _maxScrollbackLines = -1;
        _tabStops = [[NSMutableSet alloc] init];
        _charsetUsesLineDrawingMode = [NSMutableSet set];
        _cursorVisible = YES;
        _lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _startOfRunningCommandOutput = VT100GridAbsCoordMake(-1, -1);
        _initialSize = VT100GridSizeMake(-1, -1);
        _linebuffer = [[LineBuffer alloc] init];
        _linebuffer.maintainBidiInfo = YES;
        _colorMap = [[iTermColorMap alloc] init];
        _temporaryDoubleBuffer = [[iTermTemporaryDoubleBufferedGridController alloc] initWithQueue:queue];
        _namedMarks = [[iTermMutableArrayOfWeakObjects alloc] init];
        _blockStartAbsLine = [NSMutableDictionary dictionary];
        _fakePromptDetectedAbsLine = -1;
    }
    return self;
}

- (id<iTermMarkCacheReading>)markCache {
    return _markCache;
}

- (iTermMarkCache *)mutableMarkCache {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id<VT100ScreenMarkReading>)cachedLastCommandMark {
    return _lastCommandMark;
}

- (void)copyFastStuffFrom:(VT100ScreenMutableState *)source {
    _audibleBell = source.audibleBell;
    _showBellIndicator = source.showBellIndicator;
    _flashBell = source.flashBell;
    _postUserNotifications = source.postUserNotifications;
    _cursorBlinks = source.cursorBlinks;
    _collectInputForPrinting = source.collectInputForPrinting;
    _printBuffer = [source.printBuffer copy];
    _allowTitleReporting = source.allowTitleReporting;
    _allowAlternateMouseScroll = source.allowAlternateMouseScroll;
    _lastBell = source.lastBell;
    _wraparoundMode = source.wraparoundMode;
    _ansi = source.ansi;
    _insert = source.insert;
    _unlimitedScrollback = source.unlimitedScrollback;
    _scrollbackOverflow = source.scrollbackOverflow;
    _commandStartCoord = source.commandStartCoord;
    _maxScrollbackLines = source.maxScrollbackLines;
    _lastCharacter = source.lastCharacter;
    _lastCharacterIsDoubleWidth = source.lastCharacterIsDoubleWidth;
    _lastExternalAttribute = source.lastExternalAttribute;
    _saveToScrollbackInAlternateScreen = source.saveToScrollbackInAlternateScreen;
    _cursorVisible = source.cursorVisible;
    _shellIntegrationInstalled = source.shellIntegrationInstalled;
    _lastCommandOutputRange = source.lastCommandOutputRange;
    _currentPromptRange = source.currentPromptRange;
    _startOfRunningCommandOutput = source.startOfRunningCommandOutput;
    _protectedMode = source.protectedMode;
    _initialSize = source.initialSize;
    _cumulativeScrollbackOverflow = source.cumulativeScrollbackOverflow;
    _trackCursorLineMovement = source.trackCursorLineMovement;
    _appendToScrollbackWithStatusBar = source.appendToScrollbackWithStatusBar;
    _normalization = source.normalization;
    _fakePromptDetectedAbsLine = source.fakePromptDetectedAbsLine;
    _lastPromptLine = source.lastPromptLine;
    _intervalTreeObserver = source.intervalTreeObserver;
    _lastCommandMark = [source.cachedLastCommandMark doppelganger];
    _shouldExpectPromptMarks = source.shouldExpectPromptMarks;
    _echoProbeIsActive = source.echoProbe.isActive;
    _terminalSoftAlternateScreenMode = source.terminalSoftAlternateScreenMode;
    _terminalMouseMode = source.terminalMouseMode;
    _terminalEncoding = source.terminalEncoding;
    _terminalSendReceiveMode = source.terminalSendReceiveMode;
    _terminalOutput = [source.terminalOutput copy];
    _terminalAllowPasteBracketing = source.terminalAllowPasteBracketing;
    _terminalBracketedPasteMode = source.terminalBracketedPasteMode;
    _terminalSendModifiers = source.terminalSendModifiers;
    _terminalKeyReportingFlags = source.terminalKeyReportingFlags;
    _terminalReportFocus = source.terminalReportFocus;
    _terminalEmulationLevel = source.terminalEmulationLevel;
    _terminalLiteralMode = source.terminalLiteralMode;
    _terminalReportKeyUp = source.terminalReportKeyUp;
    _terminalCursorMode = source.terminalCursorMode;
    _terminalKeypadMode = source.terminalKeypadMode;
    _terminalReceivingFile = source.terminalReceivingFile;
    _terminalMetaSendsEscape = source.terminalMetaSendsEscape;
    _terminalReverseVideo = source.terminalReverseVideo;
    _terminalAlternateScrollMode = source.terminalAlternateScrollMode;
    _terminalAutorepeatMode = source.terminalAutorepeatMode;
    _terminalSendResizeNotifications = source.terminalSendResizeNotifications;
    _terminalCharset = source.terminalCharset;
    _terminalPreviousMouseMode = source.terminalPreviousMouseMode;
    _terminalForegroundColorCode = source.terminalForegroundColorCode;
    _terminalBackgroundColorCode = source.terminalBackgroundColorCode;
    _pasteboardString = [source.pasteboardString copy];
    _intervalTree = source.mutableIntervalTree.derivative;
    _savedIntervalTree = source.mutableSavedIntervalTree.derivative;
    _tabStops = [source.tabStops copy];
    _charsetUsesLineDrawingMode = [source.charsetUsesLineDrawingMode copy];
    _config = source.config;
    _exfiltratedEnvironment = [source.exfiltratedEnvironment copy];
    _kittyImageDraws = [source.kittyImageDraws copy];
    _promptStateDictionary = [source.promptStateDictionary copy];
    if (source.blocksGeneration > _blocksGeneration) {
        _blocksGeneration = source.blocksGeneration;
        _blockStartAbsLine = [source.blockStartAbsLine copy];
    }
    if (source.namedMarksDirty) {
        _namedMarks = [source.namedMarks compactMap:^NSObject * _Nonnull(NSObject * _Nonnull obj) {
            id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)obj;
            return [mark doppelganger];
        }];
    }
}

- (void)copySlowStuffFrom:(VT100ScreenMutableState *)source {
    if (!_markCache || source.mutableMarkCache.dirty) {
        DLog(@"Mark cache is dirty. Update copy in read-only state.");
        _markCache = source.mutableMarkCache.readOnlyCopy;
    }
    if (!_colorMap) {
        _colorMap = [source.colorMap copy];
    }
    if (!_temporaryDoubleBuffer || source.unconditionalTemporaryDoubleBuffer.dirty) {
        _temporaryDoubleBuffer = [source.unconditionalTemporaryDoubleBuffer copy];
        _temporaryDoubleBuffer.queue = dispatch_get_main_queue();
    }
    _primaryGrid.delegate = self;
    _altGrid.delegate = self;
    if (source.currentGrid == source.primaryGrid) {
        _currentGrid = _primaryGrid;
    } else {
        _currentGrid = _altGrid;
    }
}

// Search for images in the mutable area of the old instance of VT100ScreenState and check in the
// updated version if any cell of that image is still present. If not, it can be released.
- (void)releaseOverwrittenImagesIn:(VT100ScreenMutableState *)updated {
    DLog(@"Start");
    if (self.width != updated.width || self.height != updated.height) {
        // It's way too complicated to check if an image was overwritten when the grid resizes.
        // These will stay in memory until they exit scrollback history.
        DLog(@"Size changed %dx%d -> %dx%d", self.width, self.height, updated.width, updated.height);
        return;
    }
    if (!updated.currentGrid.hasChanged) {
        DLog(@"Don't scan for overwritten images because current grid remains unchanged");
        return;
    }
    Interval *topOfScreen = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, self.numberOfScrollbackLines, 0, self.numberOfScrollbackLines)];
    const int height = self.height;
    NSMutableArray<iTermMark *> *marksToRemove = [NSMutableArray array];
    [_intervalTree enumerateLimitsAfter:topOfScreen.location
                                  block:^(id<IntervalTreeObject> object, BOOL *stop) {
        DLog(@"Consider %@", object);
        iTermImageMark *imageMark = [iTermImageMark castFrom:object];
        if (!imageMark || !imageMark.imageCode) {
            DLog(@"Not an image");
            return;
        }
        VT100GridAbsCoordRange coordRange = [self absCoordRangeForInterval:imageMark.entry.interval];
        iTermMark *progenitor = imageMark.progenitor;
        if (progenitor != nil &&
            ![updated imageInUse:imageMark above:coordRange.end.y searchHeight:height]) {
            DLog(@"Not in use. Add to delete list.");
            [marksToRemove addObject:progenitor];
        }
    }];
    for (iTermMark *mark in marksToRemove) {
        DLog(@"Remove %@", mark);
        [[updated mutableIntervalTree] removeObject:mark];
    }
}

// Search cells backwards from the image mark to see if any of it is still referenced.
- (BOOL)imageInUse:(iTermImageMark *)mark above:(long long)aboveAbsY searchHeight:(int)searchHeight {
    const int code = mark.imageCode.intValue;
    iTermImageInfo *imageInfo = [[iTermImageRegistry sharedInstance] infoForCode:code];
    if (!imageInfo) {
        DLog(@"No image info with code %d", code);
        return NO;
    }
    const long long aboveY = aboveAbsY - self.cumulativeScrollbackOverflow;
    if (aboveY < 0) {
        DLog(@"Image has scrolled off");
        return NO;
    }
    const long long startY = MAX(0, aboveY - imageInfo.size.height);
    __block BOOL found = NO;
    [self enumerateLinesInRange:NSMakeRange(startY, aboveY - startY + 1)
                          block:^(int line,
                                  ScreenCharArray *sca,
                                  iTermImmutableMetadata metadata,
                                  BOOL *stop) {
        DLog(@"Check line %d: %@", line, sca);
        if ([self screenCharArray:sca containsImageCode:code]) {
            found = YES;
            *stop = YES;
        }
    }];
    return found;
}

- (BOOL)screenCharArray:(ScreenCharArray *)sca containsImageCode:(int)code {
    const int width = sca.length;
    const screen_char_t *line = sca.line;
    for (int i = 0; i < width; i++) {
        if (line[i].image && line[i].code == code && !line[i].virtualPlaceholder) {
            DLog(@"Found code %d at column %d", code, i);
            return YES;
        }
    }
    return NO;
}

- (void)mergeFrom:(VT100ScreenMutableState *)source {
    [self copyFastStuffFrom:source];
    [self releaseOverwrittenImagesIn:source];
    if ([iTermPreferences boolForKey:kPreferenceKeyBidi]) {
        [source populateRTLStateIfNeeded];
    }

    const BOOL lineBufferDirty = (!_linebuffer || source.linebuffer.dirty);
    if (lineBufferDirty) {
        DLog(@"line buffer is dirty");
        [source.linebuffer seal];
        [_linebuffer mergeFrom:source.linebuffer];
    } else {
        DLog(@"line buffer not dirty");
    }
    //  NSString *mine = [_linebuffer debugString];
    //  NSString *theirs = [source.linebuffer debugString];
    //  assert([mine isEqual:theirs]);

    [_primaryGrid copyDirtyFromGrid:source.primaryGrid didScroll:source.primaryGrid.haveScrolled];
    [source.primaryGrid markAllCharsDirty:NO updateTimestamps:NO];

    if (_altGrid && source.altGrid) {
        [_altGrid copyDirtyFromGrid:source.altGrid didScroll:source.altGrid.haveScrolled];
    } else {
        _altGrid = [source.altGrid copy];
    }
    [source.altGrid markAllCharsDirty:NO updateTimestamps:NO];
    if (!_terminalState || source.terminal.dirty) {
        source.terminal.dirty = NO;
        _terminalState = [source.terminalState copy];
    }

    [self copySlowStuffFrom:source];
}

- (instancetype)initWithState:(VT100ScreenMutableState *)source
                  predecessor:(VT100ScreenState *)predecessor {
    self = [super init];
    if (self) {
        _linebuffer = [source.linebuffer copy];
        _primaryGrid = [source.primaryGrid copy];
        _altGrid = [source.altGrid copy];
        _terminalState = [source.terminalState copy];

        [self copyFastStuffFrom:source];
        [self copySlowStuffFrom:source];
        DLog(@"Copy mutable to immutable");
    }
    return self;
}

- (void)dealloc {
    [_temporaryDoubleBuffer reset];
}

#pragma mark - Grid

- (int)cursorY {
    return self.currentGrid.cursorY + 1;
}

- (int)cursorX {
    return self.currentGrid.cursorX + 1;
}

- (int)width {
    return self.currentGrid.size.width;
}

- (int)height {
    return self.currentGrid.size.height;
}

- (BOOL)cursorOutsideLeftRightMargin {
    return (self.currentGrid.useScrollRegionCols && (self.currentGrid.cursorX < self.currentGrid.leftMargin ||
                                                     self.currentGrid.cursorX > self.currentGrid.rightMargin));
}

- (BOOL)cursorOutsideTopBottomMargin {
    return (self.currentGrid.cursorY < self.currentGrid.topMargin ||
            self.currentGrid.cursorY > self.currentGrid.bottomMargin);
}


- (int)lineNumberOfCursor {
    return self.numberOfLines - self.height + self.currentGrid.cursorY;
}

#pragma mark - Scollback

- (int)numberOfScrollbackLines {
    return [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
}

#pragma mark - Interval Tree

- (id<IntervalTreeReading>)intervalTree {
    return _intervalTree;
}

- (id<IntervalTreeReading>)savedIntervalTree {
    return _savedIntervalTree;
}

- (VT100GridAbsCoordRange)absCoordRangeForInterval:(Interval *)interval {
    return [interval absCoordRangeForWidth:self.width];
}

- (VT100GridCoordRange)coordRangeForInterval:(Interval *)interval {
    VT100GridCoordRange result;
    const int w = self.width + 1;
    result.start.y = interval.location / w - self.cumulativeScrollbackOverflow;
    result.start.x = interval.location % w;
    result.end.y = interval.limit / w - self.cumulativeScrollbackOverflow;
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

- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval {
    VT100GridCoordRange range = [self coordRangeForInterval:interval];
    return VT100GridRangeMake(range.start.y, range.end.y - range.start.y + 1);
}

- (Interval *)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)range {
    return [self intervalForGridAbsCoordRange:range
                                        width:self.width];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range {
    return [self intervalForGridAbsCoordRange:VT100GridAbsCoordRangeFromCoordRange(range, self.cumulativeScrollbackOverflow)
                                        width:self.width];
}

- (Interval *)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)absRange
                                     width:(int)width {
    return [Interval intervalForGridAbsCoordRange:absRange width:width];
}

- (__kindof id<IntervalTreeImmutableObject>)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    long long pos = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                            line + 1,
                                                                            0,
                                                                            line + 1)].location;
    if (pos < 0) {
        return nil;
    }
    NSEnumerator *enumerator = [self.intervalTree reverseEnumeratorAt:pos];
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

- (NSArray<id<IntervalTreeImmutableObject>> *)objectsOnLine:(int)line ofClass:(Class)cls {
    Interval *queryInterval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                                      line,
                                                                                      self.width + 1,
                                                                                      line)];
    if (!queryInterval) {
        return @[];
    }
    NSArray<id<IntervalTreeImmutableObject>> *objects = [self.intervalTree objectsInInterval:queryInterval];
    return [objects filteredArrayUsingBlock:^BOOL(id<IntervalTreeImmutableObject> anObject) {
        return [anObject isKindOfClass:cls];
    }];
}

- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line {
    return (id<VT100RemoteHostReading>)[self objectOnOrBeforeLine:line ofClass:[VT100RemoteHost class]];
}

- (NSArray<iTermTerminalButtonPlace *> *)buttonsInRange:(VT100GridRange)range {
    NSMutableArray<iTermTerminalButtonPlace *> *places = [NSMutableArray array];
    const long long offset = self.cumulativeScrollbackOverflow;
    Interval *interval =
    [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                            range.location,
                                                            0,
                                                            range.location)];
    for (NSArray *objects in [self.intervalTree forwardLimitEnumeratorAt:interval.location]) {
        for (id<IntervalTreeObject> obj in objects) {
            VT100GridAbsCoordRange objRange = [self absCoordRangeForInterval:obj.entry.interval];
            if (objRange.start.y >= range.location + range.length + offset) {
                return places;
            }
            if ([obj isKindOfClass:[iTermButtonMark class]]) {
                iTermButtonMark *buttonMark = (iTermButtonMark *)obj;
                iTermTerminalButtonPlace *place = [[iTermTerminalButtonPlace alloc] initWithMark:buttonMark coord:objRange.start];
                [places addObject:place];
            }
        }
    }
    return places;
}

- (VT100GridCoordRange)rangeOfBlockWithID:(NSString *)blockID {
    id<iTermBlockMarkReading> mark = [self blockMarkWithID:blockID];
    if (!mark) {
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    }
    return [self coordRangeForInterval:mark.entry.interval];
}

- (iTermBlockMark *)blockMarkWithID:(NSString *)blockID {
    NSNumber *n = self.blockStartAbsLine[blockID];
    if (!n) {
        return nil;
    }
    const long long line = n.longLongValue;
    Interval *interval = [self intervalForGridAbsCoordRange:VT100GridAbsCoordRangeMake(0, line, 0, line)];
    BOOL foundBlock = NO;
    for (NSArray *objects in [self.intervalTree forwardLocationEnumeratorAt:interval.limit]) {
        for (id<IntervalTreeObject> obj in objects) {
            iTermBlockMark *candidate = [iTermBlockMark castFrom:obj];
            if (!candidate) {
                continue;
            }
            if ([candidate.blockID isEqualToString:blockID]) {
                return candidate;
            }
            foundBlock = YES;
        }
        if (foundBlock) {
            // Already found a different block.
            break;
        }
    }
    return nil;
}

- (BOOL)haveFoldsInRange:(NSRange)absLineRange {
    return [self foldMarksInRange:absLineRange max:1].count > 0;
}

- (NSArray<iTermFoldMark *> *)foldMarksInRange:(NSRange)absLineRange max:(NSUInteger)maxCount {
    return [self marksInRange:absLineRange max:maxCount ofClass:[iTermFoldMark class]];
}

- (NSArray *)marksInRange:(NSRange)absLineRange
                      max:(NSUInteger)maxCount
                  ofClass:(Class)theClass {
    NSMutableArray *results = [NSMutableArray array];
    Interval *interval = [self intervalForGridAbsCoordRange:VT100GridAbsCoordRangeMake(0,
                                                                                       absLineRange.location,
                                                                                       0,
                                                                                       NSMaxRange(absLineRange))];
    const long long stopLocation = interval.limit;
    for (NSArray<id<IntervalTreeObject>> *objects in [self.intervalTree forwardLocationEnumeratorAt:interval.location]) {
        if (objects.firstObject.entry.interval.location >= stopLocation) {
            return results;
        }
        for (id<IntervalTreeObject> obj in objects) {
            id candidate = [theClass castFrom:obj];
            if (candidate) {
                [results addObject:candidate];
                if (results.count == maxCount) {
                    return results;
                }
            }
        }
    }
    return results;
}

#pragma mark - Combined Grid And Scrollback

- (int)numberOfLines {
    return [self.linebuffer numLinesWithWidth:self.currentGrid.size.width] + self.currentGrid.size.height;
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber {
    ITBetaAssert(lineNumber >= 0, @"Negative index to getLineAtIndex");
    const int width = self.currentGrid.size.width;
    int numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:width];
    if (lineNumber >= numLinesInLineBuffer) {
        return [self.currentGrid immutableMetadataAtLineNumber:lineNumber - numLinesInLineBuffer];
    } else {
        return [self.linebuffer metadataForLineNumber:lineNumber width:width];
    }
}

- (iTermBidiDisplayInfo *)bidiInfoForLine:(int)lineNumber {
    if (lineNumber < 0) {
        return nil;
    }
    const int width = self.currentGrid.size.width;
    int numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:width];
    if (lineNumber >= numLinesInLineBuffer) {
        if (!self.terminalSoftAlternateScreenMode || iTermAdvancedSettingsModel.alternateScreenBidi) {
            return [self.currentGrid bidiInfoForLine:lineNumber - numLinesInLineBuffer];
        } else {
            return nil;
        }
    } else {
        return [self.linebuffer bidiInfoForLine:lineNumber width:width];
    }
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex {
    return [self getLineAtIndex:theIndex
                    destination:[self.currentGrid resultLineData]
                          width:self.currentGrid.size.width];
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t *)buffer {
    return [self getLineAtIndex:theIndex
                    destination:[NSMutableData dataWithBytesNoCopy:buffer
                                                            length:(self.currentGrid.size.width + 1) * sizeof(screen_char_t)
                                                      freeWhenDone:NO]
                          width:self.currentGrid.size.width];
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex
                            destination:(NSMutableData *)dataBuffer
                                  width:(int)width {
    ITBetaAssert(theIndex >= 0, @"Negative index to getLineAtIndex");
    assert(dataBuffer.length >= (width + 1) * sizeof(screen_char_t));
    int numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    screen_char_t *buffer = dataBuffer.mutableBytes;
    if (theIndex >= numLinesInLineBuffer) {
        // Get a line from the circular screen buffer
        return [self.currentGrid immutableScreenCharsAtLineNumber:(theIndex - numLinesInLineBuffer)];
    } else {
        // Get a line from the scrollback buffer.
        screen_char_t continuation;
        ITAssertWithMessage(width == self.currentGrid.size.width,
                            @"width is %@, data length is %@, current grid %@ has width %@",
                            @(width), @(dataBuffer.length), self.currentGrid, @(self.currentGrid.size.width));
        int cont = [self.linebuffer copyLineToData:dataBuffer
                                             width:width
                                           lineNum:theIndex
                                      continuation:&continuation];
        if (cont == EOL_SOFT &&
            theIndex == numLinesInLineBuffer - 1 &&
            ScreenCharIsDWC_RIGHT([self.currentGrid immutableScreenCharsAtLineNumber:0][1]) &&
            buffer[self.currentGrid.size.width - 1].code == 0) {
            // The last line in the scrollback buffer is actually a split DWC
            // if the first char on the screen is double-width and the buffer is soft-wrapped without
            // a last char.
            cont = EOL_DWC;
        }
        if (cont == EOL_DWC) {
            ScreenCharSetDWC_SKIP(&buffer[self.currentGrid.size.width - 1]);
        }
        buffer[self.currentGrid.size.width] = continuation;
        buffer[self.currentGrid.size.width].code = cont;

        return buffer;
    }
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
    const int numLines = [self numberOfLines];
    for (i = MIN(numLines, lineNumber) - 1; i >= 0 && i >= lineNumber - kMaxRadius; i--) {
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

    return [[iTermStringLine alloc] initWithScreenChars:data.mutableBytes
                                                 length:data.length / sizeof(screen_char_t)];
}

- (void)enumerateLinesInRange:(NSRange)range
                        block:(void (^)(int,
                                        ScreenCharArray *,
                                        iTermImmutableMetadata,
                                        BOOL *))block {
    NSInteger i = range.location;
    const NSInteger lastLine = NSMaxRange(range);
    const NSInteger numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    const int width = self.width;
    while (i < lastLine) {
        if (i < numLinesInLineBuffer) {
            [self.linebuffer enumerateLinesInRange:NSMakeRange(i, lastLine - i)
                                             width:width
                                             block:block];
            i = numLinesInLineBuffer;
            continue;
        }
        BOOL stop = NO;
        const int screenIndex = i - numLinesInLineBuffer;
        block(i,
              [self screenCharArrayAtScreenIndex:screenIndex],
              [self.currentGrid immutableMetadataAtLineNumber:screenIndex],
              &stop);
        if (stop) {
            return;
        }
        i += 1;
    }
}

- (int)numberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                     encoder:(id<iTermEncoderAdapter>)encoder
                                              intervalOffset:(long long *)intervalOffsetPtr {
    // We want 10k lines of history at 80 cols, and fewer for small widths, to keep the size
    // reasonable.
    const int maxLines80 = [iTermAdvancedSettingsModel maxHistoryLinesToRestore];
    const int effectiveWidth = self.width ?: 80;
    const int maxArea = maxLines80 * (includeGrid ? 80 : effectiveWidth);
    const int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [self.linebuffer copyWithMinimumLines:maxLines
                                                     atWidth:effectiveWidth];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([self.linebuffer numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
    -(linesDroppedForBrevity + self.cumulativeScrollbackOverflow) * (self.width + 1);

    if (includeGrid) {
        int numLines;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            numLines = self.currentGrid.size.height;
        } else {
            numLines = [self.currentGrid numberOfLinesUsed];
        }
        [self.currentGrid appendLines:numLines toLineBuffer:temp];
    }
    [temp commitLastBlock];
    [temp encode:encoder maxLines:maxLines80];
    *intervalOffsetPtr = intervalOffset;
    return linesDroppedForBrevity;
}

#pragma mark - Shell Integration

- (id<VT100ScreenMarkReading>)lastCommandMark {
    DLog(@"Searching for last command mark...");
    if (_lastCommandMark) {
        DLog(@"Return cached mark %@", _lastCommandMark);
        return _lastCommandMark;
    }
    NSEnumerator *enumerator = [self.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    int numChecked = 0;
    while (objects && numChecked < 500) {
        for (id<IntervalTreeObject> obj in objects) {
            if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)obj;
                if (mark.command) {
                    DLog(@"Found mark %@ in line number range %@", mark,
                         VT100GridRangeDescription([self lineNumberRangeOfInterval:obj.entry.interval]));
                    _lastCommandMark = mark;
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

// Range from start of last command to the cursor.
- (VT100GridCoordRange)commandRange {
    const long long offset = self.cumulativeScrollbackOverflow;
    if (self.commandStartCoord.x < 0) {
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    } else {
        return VT100GridCoordRangeMake(self.commandStartCoord.x,
                                       MAX(0, self.commandStartCoord.y - offset),
                                       self.currentGrid.cursorX,
                                       self.currentGrid.cursorY + self.numberOfScrollbackLines);
    }
}

- (VT100GridCoordRange)extendedCommandRange {
    const VT100GridCoordRange basicRange = [self commandRange];
    if (basicRange.start.x < 0) {
        return basicRange;
    }

    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:self];
    const VT100GridCoord firstNull = [extractor searchFrom:basicRange.end forward:YES forCharacterMatchingFilter:^BOOL(screen_char_t c, VT100GridCoord coord) {
        return c.code == 0 && !c.complexChar && !c.image;
    }];
    if (firstNull.x < 0) {
        return basicRange;
    }
    return (VT100GridCoordRange) {
        .start = basicRange.start,
        .end = firstNull
    };
}

- (BOOL)haveCommandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return NO;
    }

    // If semantic history goes nuts and the end-of-command code isn't received (which seems to be a
    // common problem, probably because of buggy old versions of SH scripts) , the command can grow
    // without bound. We'll limit the length of a command to avoid performance problems.
    const int kMaxLines = 50;
    if (range.end.y - range.start.y > kMaxLines) {
        range.end.y = range.start.y + kMaxLines;
    }
    const int width = self.width;
    range.end.x = MIN(range.end.x, width - 1);
    range.start.x = MIN(range.start.x, width - 1);

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    return [extractor haveNonWhitespaceInFirstLineOfRange:VT100GridWindowedRangeMake(range, 0, 0)];
}

- (VT100GridCoordRange)rangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark {
    NSEnumerator *enumerator = [self.markCache enumerateFrom:mark.entry.interval.limit];
    for (id<iTermMark> nextMark in enumerator) {
        if (![nextMark conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
            continue;
        }
        id<VT100ScreenMarkReading> nextScreenMark = (id<VT100ScreenMarkReading>)nextMark;
        if (nextScreenMark.isPrompt) {
            VT100GridCoordRange range;
            BOOL ok = NO;
            range.start = VT100GridCoordFromAbsCoord(mark.outputStart, self.cumulativeScrollbackOverflow, &ok);
            if (!ok) {
                range.start = [self coordRangeForInterval:mark.entry.interval].end;
                range.start.x = 0;
                range.start.y++;
            }
            range.end = [self coordRangeForInterval:nextScreenMark.entry.interval].start;
            if (nextScreenMark.lineStyle) {
                DLog(@"Move end up one line for line-style mark at next prompt");
                range.end.y -= 1;
            }
            return range;
        }
    }

    // Command must still be running with no subsequent prompt.
    VT100GridCoordRange range;
    range.start = [self coordRangeForInterval:mark.entry.interval].end;
    range.start.x = 0;
    range.start.y++;
    range.end.x = 0;
    range.end.y = self.numberOfLines - self.height + [self.currentGrid numberOfLinesUsed];
    return range;
}

- (NSIndexSet *)foldsInRange:(VT100GridRange)gridRange {
    const NSRange absLineRange = NSMakeRange(gridRange.location + self.cumulativeScrollbackOverflow,
                                             gridRange.length);
    NSArray<iTermFoldMark *> *foldMarks = [self foldMarksInRange:absLineRange max:NSUIntegerMax];
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    [foldMarks enumerateObjectsUsingBlock:^(iTermFoldMark *foldMark, NSUInteger idx, BOOL * _Nonnull stop) {
        const int line = [self coordRangeForInterval:foldMark.entry.interval].start.y;
        if (line >= 0) {
            [indexSet addIndex:line];
        }
    }];
    return indexSet;
}

- (NSArray<id<iTermFoldMarkReading>> *)foldMarksInRange:(VT100GridRange)range {
    return [self foldMarksInRange:NSMakeRange(MAX(0, range.location) + self.cumulativeScrollbackOverflow, range.length)
                              max:NSUIntegerMax];
}

- (id<VT100ScreenMarkReading> _Nullable)screenMarkOnLine:(int)line {
    return [VT100ScreenMark castFrom:self.markCache[self.cumulativeScrollbackOverflow + line]];
}

- (id<iTermMark>)drawableMarkOnLine:(int)line {
    id obj = self.markCache[self.cumulativeScrollbackOverflow + line];
    if (!obj) {
        return nil;
    }
    if ([obj isKindOfClass:[VT100ScreenMark class]]) {
        return obj;
    }
    return nil;
}

- (id<VT100ScreenMarkReading>)penultimateCommandMark {
    int skip = 1;
    for (NSArray *objects in [self.intervalTree reverseEnumerator]) {
        id<VT100ScreenMarkReading> mark = [objects objectPassingTest:^BOOL(id element, NSUInteger index, BOOL *stop) {
            if (![element conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
                return NO;
            }
            id<VT100ScreenMarkReading> temp = element;
            return temp.isPrompt;
        }];
        if (mark) {
            if (skip == 0) {
                return mark;
            } else {
                skip -= 1;
            }
        }
    }
    return nil;
}

- (id<VT100ScreenMarkReading>)commandMarkAtOrBeforeLine:(int)line {
    const int width = self.width;
    long long pos = [self intervalForGridCoordRange:VT100GridCoordRangeMake(width - 1,
                                                                            line,
                                                                            width - 1,
                                                                            line)].location;
    if (pos < 0) {
        return nil;
    }
    for (NSArray *objects in [self.intervalTree reverseEnumeratorAt:pos]) {
        id<VT100ScreenMarkReading> mark = [objects objectPassingTest:^BOOL(id element, NSUInteger index, BOOL *stop) {
            if (![element conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
                return NO;
            }
            id<VT100ScreenMarkReading> temp = element;
            return temp.isPrompt;
        }];
        if (mark) {
            return mark;
        }
    }
    return nil;
}

- (NSArray<id<PTYAnnotationReading>> *)annotationsOnAbsLine:(long long)absLine {
    return [[self.intervalTree objectsInInterval:[self intervalForGridAbsCoordRange:VT100GridAbsCoordRangeMake(0, absLine, self.width, absLine)]] filteredArrayUsingBlock:^BOOL(id<IntervalTreeImmutableObject> anObject) {
        return [anObject conformsToProtocol:@protocol(PTYAnnotationReading)];
    }];
}

- (id<VT100ScreenMarkReading>)promptMarkAfterPromptMark:(id<VT100ScreenMarkReading>)predecessor {
    if (!predecessor) {
        return nil;
    }
    const long long pos = MAX(0, predecessor.entry.interval.limit);

    for (NSArray *objects in [self.intervalTree forwardLocationEnumeratorAt:pos]) {
        id<VT100ScreenMarkReading> mark = [objects objectPassingTest:^BOOL(id element, NSUInteger index, BOOL *stop) {
            if (![element conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
                return NO;
            }
            id<VT100ScreenMarkReading> temp = element;
            return temp.isPrompt;
        }];
        if (mark) {
            return mark;
        }
    }
    return nil;
}

- (id<VT100ScreenMarkReading> _Nullable)promptMarkBeforePromptMark:(id<VT100ScreenMarkReading>)successor {
    if (!successor) {
        return nil;
    }
    const long long pos = MAX(1, successor.entry.interval.location) - 1;

    for (NSArray *objects in [self.intervalTree reverseEnumeratorAt:pos]) {
        id<VT100ScreenMarkReading> mark = [objects objectPassingTest:^BOOL(id element, NSUInteger index, BOOL *stop) {
            if (![element conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
                return NO;
            }
            id<VT100ScreenMarkReading> temp = element;
            return temp.isPrompt;
        }];
        if (mark) {
            return mark;
        }
    }
    return nil;
}

// If mustHaveCommand is NO then a prompt with a not-yet-run command is sufficient.
- (id<VT100ScreenMarkReading>)commandMarkAt:(VT100GridCoord)coord
                            mustHaveCommand:(BOOL)mustHaveCommand
                                      range:(out VT100GridWindowedRange *)rangeOut {
    id<VT100ScreenMarkReading> mark = [self screenMarkOnLine:coord.y];
    const VT100GridCoordRange range = [self coordRangeForInterval:mark.entry.interval];
    if (mustHaveCommand && mark.command == nil) {
        return nil;
    }
    if (mark.promptRange.start.x >= 0 && VT100GridCoordRangeContainsCoord(range, coord)) {
        if (rangeOut) {
            rangeOut->columnWindow = VT100GridRangeMake(-1, -1);
            rangeOut->coordRange = VT100GridCoordRangeFromAbsCoordRange(mark.promptRange, self.cumulativeScrollbackOverflow);
        }
        return mark;
    }
    return nil;
}

- (id<iTermPathMarkReading>)pathMarkAt:(VT100GridCoord)coord {
    NSArray<id<IntervalTreeImmutableObject>> *objects = [self intervalTreeObjectsAtCoord:VT100GridAbsCoordFromCoord(coord, self.cumulativeScrollbackOverflow)];
    for (id<IntervalTreeImmutableObject> object in objects) {
        if ([object conformsToProtocol:@protocol(iTermPathMarkReading)]) {
            return (id<iTermPathMarkReading>)object;
        }
    }
    return nil;
}

- (NSArray<id<IntervalTreeImmutableObject>> *)intervalTreeObjectsAtCoord:(VT100GridAbsCoord)coord {
    const VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeMake(coord.x, coord.y, coord.x + 1, coord.y);
    Interval *interval = [self intervalForGridAbsCoordRange:absRange];
    return [_intervalTree objectsInInterval:interval];
}

- (NSString *)commandInRange:(VT100GridCoordRange)range {
    return [self commandInRange:range maxLines:50];
}

- (NSString *)commandInRange:(VT100GridCoordRange)range maxLines:(int)maxLines {
    if (range.start.x == -1) {
        return nil;
    }
    if (range.end.y - range.start.y > maxLines) {
        range.end.y = range.start.y + maxLines;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSString *command = [extractor contentInRange:VT100GridWindowedRangeMake(range, 0, 0)
                                attributeProvider:nil
                                       nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                              pad:NO
                               includeLastNewline:NO
                           trimTrailingWhitespace:NO
                                     cappedAtSize:-1
                                     truncateTail:YES
                                continuationChars:nil
                                           coords:nil];
    NSRange newline = [command rangeOfString:@"\n"];
    if (newline.location != NSNotFound) {
        command = [command substringToIndex:newline.location];
    }

    return [command stringByTrimmingLeadingWhitespace];
}

- (id<IntervalTreeImmutableObject>)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    NSEnumerator *enumerator = [self.intervalTree reverseLimitEnumerator];
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

- (id<IntervalTreeImmutableObject>)firstMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    NSEnumerator *enumerator = [self.intervalTree forwardLocationEnumeratorAt:0];
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

- (NSString *)workingDirectoryOnLine:(int)line {
    id<VT100WorkingDirectoryReading> workingDirectory =
        [self objectOnOrBeforeLine:line ofClass:[VT100WorkingDirectory class]];
    return workingDirectory.workingDirectory;
}

- (id<VT100RemoteHostReading>)lastRemoteHost {
    return (id<VT100RemoteHostReading>)[self lastMarkMustBePrompt:NO class:[VT100RemoteHost class]];
}

- (id<VT100ScreenMarkReading>)lastPromptMark {
    return (id<VT100ScreenMarkReading>)[self lastMarkMustBePrompt:YES class:[VT100ScreenMark class]];
}

- (id<VT100ScreenMarkReading>)firstPromptMark {
    return (id<VT100ScreenMarkReading>)[self firstMarkMustBePrompt:YES class:[VT100ScreenMark class]];
}

#pragma mark - Colors

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

#pragma mark - Double Buffer

- (iTermTemporaryDoubleBufferedGridController *)temporaryDoubleBuffer {
    if (!self.config.reduceFlicker && !_temporaryDoubleBuffer.explicit) {
        return nil;
    }
    return _temporaryDoubleBuffer;
}

- (iTermTemporaryDoubleBufferedGridController *)unconditionalTemporaryDoubleBuffer {
    return _temporaryDoubleBuffer;
}

- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> _Nullable state))block {
    if (!self.realCurrentGrid && self.temporaryDoubleBuffer.savedState) {
        // Swap in saved state.
        self.realCurrentGrid = self.currentGrid;
        self.currentGrid = self.temporaryDoubleBuffer.savedState.grid;

        block(self.temporaryDoubleBuffer.savedState);

        // Restore original state.
        self.currentGrid = self.realCurrentGrid;
        self.realCurrentGrid = nil;
        return;
    }

    // Regular behavior.
    block(nil);
}

#pragma mark - Advanced Prefs

- (BOOL)terminalIsTrusted {
    const BOOL result = ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences];
    DLog(@"terminalIsTrusted returning %@", @(result));
    return result;
}

#pragma mark - SSH State

- (NSDictionary *)savedState {
    NSSet *tabStops = self.tabStops ?: [NSSet set];
    NSSet *lineDrawingCharacterSets = self.charsetUsesLineDrawingMode ?: [NSSet set];

    return [@{ VT100ScreenTerminalStateKeyVT100Terminal: self.terminalState ?: @{},
               VT100ScreenTerminalStateKeySavedColors: self.colorMap.savedColorsSlot.plist ?: @{},
               VT100ScreenTerminalStateKeyTabStops: [tabStops allObjects],
               VT100ScreenTerminalStateKeyLineDrawingCharacterSets: [lineDrawingCharacterSets allObjects],
               VT100ScreenTerminalStateKeyRemoteHost: (self.lastRemoteHost ?: [VT100RemoteHost localhost]).dictionaryValue,
               VT100ScreenTerminalStateKeyPath: [self currentWorkingDirectory] ?: [NSNull null],
    } dictionaryByRemovingNullValues];
}

- (NSString *)currentWorkingDirectory {
    return [self workingDirectoryOnLine:self.numberOfLines];
}

#pragma mark - Development

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers {
    NSMutableString *string =
        [NSMutableString stringWithString:[self.linebuffer compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
    NSMutableArray *lines = [[string componentsSeparatedByString:@"\n"] mutableCopy];
    long long absoluteLineNumber = self.totalScrollbackOverflow;
    if (string.length) {
        for (int i = 0; i < lines.count; i++) {
            lines[i] = [NSString stringWithFormat:@"%8lld:        %@", absoluteLineNumber++, lines[i]];
        }

        [lines addObject:@"- end of history -"];
    }
    NSString *gridDump = [self.currentGrid compactLineDumpWithContinuationMarks];
    NSArray *gridLines = [gridDump componentsSeparatedByString:@"\n"];
    for (int i = 0; i < gridLines.count; i++) {
        [lines addObject:[NSString stringWithFormat:@"%8lld (%04d): %@", absoluteLineNumber++, i, gridLines[i]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbersAndIntervalTreeObjects {
    NSMutableString *string =
        [NSMutableString stringWithString:[self.linebuffer compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
    NSMutableArray *lines = [[string componentsSeparatedByString:@"\n"] mutableCopy];
    long long absoluteLineNumber = self.totalScrollbackOverflow;
    if (string.length) {
        for (int i = 0; i < lines.count; i++) {
            NSString *ito = [self debugStringForIntervalTreeObjectsOnLine:i];
            NSString *ea = [self debugStringForExtendedAttributesOnLine:i];
            lines[i] = [NSString stringWithFormat:@"%8lld:        %@%@%@", absoluteLineNumber++, lines[i], ito, ea];
        }

        [lines addObject:@"- end of history -"];
    }
    NSString *gridDump = [self.currentGrid compactLineDumpWithContinuationMarks];
    NSArray *gridLines = [gridDump componentsSeparatedByString:@"\n"];
    for (int i = 0; i < gridLines.count; i++) {
        NSString *ito = [self debugStringForIntervalTreeObjectsOnLine:i + self.numberOfScrollbackLines];
        NSString *ea = [self debugStringForExtendedAttributesOnLine:i + self.numberOfScrollbackLines];
        [lines addObject:[NSString stringWithFormat:@"%8lld (%04d): %@%@%@", absoluteLineNumber++, i, gridLines[i], ito, ea]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)debugStringForIntervalTreeObjectsOnLine:(int)line {
    const long long offset = self.cumulativeScrollbackOverflow;
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    const VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeMake(0, line + offset, self.width, line + offset);
    Interval *interval = [self intervalForGridAbsCoordRange:absRange];
    for (id<IntervalTreeImmutableObject> object in [_intervalTree objectsInInterval:interval]) {
        [strings addObject:[object shortDebugDescription]];
    }
    if (strings.count == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@"ITOs: %@", [strings componentsJoinedByString:@", "]];
}

- (NSString *)debugStringForExtendedAttributesOnLine:(int)line {
    iTermExternalAttributeIndex *eaindex = [self externalAttributeIndexForLine:line];
    if (!eaindex) {
        return @"";
    }
    return [@" " stringByAppendingString:eaindex.description];
}

#pragma mark - iTermTextDataSource

- (ScreenCharArray *)screenCharArrayForLine:(int)line {
    const NSInteger numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    if (line < numLinesInLineBuffer) {
        const BOOL eligibleForDWC = (line == numLinesInLineBuffer - 1 &&
                                     ScreenCharIsDWC_RIGHT([self.currentGrid immutableScreenCharsAtLineNumber:0][1]));
        return [self.linebuffer screenCharArrayForLine:line width:self.width paddedTo:self.width eligibleForDWC:eligibleForDWC];
    }
    return [self screenCharArrayAtScreenIndex:line - numLinesInLineBuffer];
}

- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    const screen_char_t *line = [self.currentGrid immutableScreenCharsAtLineNumber:index];
    const int width = self.width;
    ScreenCharArray *array = [[ScreenCharArray alloc] initWithLine:line
                                                            length:width
                                                          metadata:[self.currentGrid immutableMetadataAtLineNumber:index]
                                                      continuation:line[width]
                                                          bidiInfo:[self.currentGrid bidiInfoForLine:index]];
    return array;
}

- (id<iTermExternalAttributeIndexReading>)externalAttributeIndexForLine:(int)y {
    iTermImmutableMetadata metadata = [self metadataOnLine:y];
    return iTermImmutableMetadataGetExternalAttributesIndex(metadata);
}

- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}

- (long long)totalScrollbackOverflow {
    return self.cumulativeScrollbackOverflow;
}

- (NSDate *)dateForLine:(int)line {
    const NSInteger numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    if (line < numLinesInLineBuffer) {
        const NSTimeInterval timestamp = [self.linebuffer metadataForLineNumber:line width:self.currentGrid.size.width].timestamp;
        if (!timestamp) {
            return nil;
        }
        return [NSDate dateWithTimeIntervalSinceReferenceDate:timestamp];
    }
    const NSTimeInterval timestamp = [self.currentGrid timestampForLine:line - numLinesInLineBuffer];
    if (!timestamp) {
        return nil;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:timestamp];
}

#pragma mark - VT100GridDelgate

- (iTermUnicodeNormalization)gridUnicodeNormalizationForm {
    return self.normalization;
}

- (void)gridCursorDidMove {
}

- (void)gridCursorDidChangeLineFrom:(int)previous {
}

- (void)gridDidResize {
}

@end

