//
//  VT100ScreenMutableState.m
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"
#import "VT100ScreenMutableState+Private.h"
#import "VT100ScreenMutableState+Resizing.h"
#import "VT100ScreenMutableState+TerminalDelegate.h"
#import "VT100ScreenState+Private.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "iTermRateLimitedUpdate.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "PTYAnnotation.h"
#import "PTYTriggerEvaluator.h"
#import "TmuxStateParser.h"
#import "TmuxWindowOpener.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenConfiguration.h"
#import "VT100ScreenDelegate.h"
#import "VT100ScreenStateSanitizingAdapter.h"
#import "VT100WorkingDirectory.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermGCD.h"
#import "iTermImageMark.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermOrderEnforcer.h"
#import "iTermTextExtractor.h"
#import "iTermURLMark.h"
#import "iTermURLStore.h"

#import <stdatomic.h>

static const int64_t VT100ScreenMutableStateSideEffectFlagNeedsRedraw = (1 << 0);
static const int64_t VT100ScreenMutableStateSideEffectFlagIntervalTreeVisibleRangeDidChange = (1 << 1);
const int64_t VT100ScreenMutableStateSideEffectFlagDidReceiveLineFeed = (1 << 2);
static const int64_t VT100ScreenMutableStateSideEffectFlagLineBufferDidDropLines = (1 << 3);

@interface VT100ScreenTokenExecutorUpdate()

@property (nonatomic, readonly) BOOL dirty;
@property (nonatomic, readwrite) NSInteger estimatedThroughput;

- (void)addBytesExecuted:(NSInteger)size;
- (void)didHandleInput;

// Returns a copy and resets self.
- (VT100ScreenTokenExecutorUpdate *)fork;

@end

@implementation VT100ScreenMutableState {
    BOOL _terminalEnabled;
    VT100Terminal *_terminal;
    BOOL _echoProbeShouldSendPassword;
    _Atomic int _executorUpdatePending;
    VT100ScreenTokenExecutorUpdate *_executorUpdate;
    iTermPeriodicScheduler *_executorUpdateScheduler;
    BOOL _screenNeedsUpdate;
    BOOL _alertOnNextMark;
    BOOL _runSideEffectAfterTopJoinFinishes;
    NSMutableArray<void (^)(void)> *_postTriggerActions;
}

static _Atomic int gPerformingJoinedBlock;

+ (BOOL)performingJoinedBlock {
    return atomic_load(&gPerformingJoinedBlock) != 0;
}

+ (void)setPerformingJoinedBlock:(BOOL)performingJoinedBlock {
    atomic_store(&gPerformingJoinedBlock, performingJoinedBlock ? 1 : 0);
}

- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer {
    dispatch_queue_t queue = [iTermGCD mutationQueue];

    self = [super initForMutationOnQueue:queue];
    if (self) {
        _queue = queue;
        _executorUpdate = [[VT100ScreenTokenExecutorUpdate alloc] init];
        __weak __typeof(self) weakSelf = self;
        _executorUpdateScheduler = [[iTermPeriodicScheduler alloc] initWithQueue:queue period:1 / 120.0 block:^{
            [weakSelf updateExecutor];
        }];
        _derivativeIntervalTree = [[IntervalTree alloc] init];
        _derivativeSavedIntervalTree = [[IntervalTree alloc] init];
        self.intervalTree =
        [[iTermEventuallyConsistentIntervalTree alloc] initWithSideEffectPerformer:self
                                                            derivativeIntervalTree:_derivativeIntervalTree];
        self.savedIntervalTree =
        [[iTermEventuallyConsistentIntervalTree alloc] initWithSideEffectPerformer:self
                                                            derivativeIntervalTree:_derivativeSavedIntervalTree];
        _terminal = [[VT100Terminal alloc] init];
        _terminal.output.optionIsMetaForSpecialKeys =
        [iTermAdvancedSettingsModel optionIsMetaForSpecialChars];
        _sideEffectPerformer = performer;
        _setWorkingDirectoryOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _currentDirectoryDidChangeOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _previousCommandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
        _triggerEvaluator = [[PTYTriggerEvaluator alloc] initWithQueue:queue];
        _postTriggerActions = [NSMutableArray array];
        _triggerEvaluator.delegate = self;
        _triggerEvaluator.dataSource = self;
        const int defaultWidth = 80;
        const int defaultHeight = 25;
        self.primaryGrid = [[VT100Grid alloc] initWithSize:VT100GridSizeMake(defaultWidth,
                                                                             defaultHeight)
                                                  delegate:self];
        self.primaryGrid.defaultChar = _terminal.defaultChar;
        self.currentGrid = self.primaryGrid;

        [self setInitialTabStops];
        _tokenExecutor = [[iTermTokenExecutor alloc] initWithTerminal:_terminal
                                                     slownessDetector:_triggerEvaluator.triggersSlownessDetector
                                                                queue:_queue];
        _tokenExecutor.delegate = self;
        _echoProbe = [[iTermEchoProbe alloc] initWithQueue:_queue];
        _echoProbe.delegate = self;
        self.unconditionalTemporaryDoubleBuffer.delegate = self;
        _sanitizingAdapter = (VT100ScreenState *)[[VT100ScreenStateSanitizingAdapter alloc] initWithSource:self];
        self.linebuffer.delegate = self;
        _promptStateMachine = [[iTermPromptStateMachine alloc] init];
        _promptStateMachine.delegate = self;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p sideEffectPerformer=%@>", NSStringFromClass([self class]), self, self.sideEffectPerformer];
}

// The block will be called twice, once for the mutable-thread copy and later with the main-thread copy.
- (void)mutateColorMap:(void (^)(iTermColorMap *colorMap))block {
    DLog(@"begin");
    // Mutate mutation thread instance.
    block([self mutableColorMap]);
    DLog(@"Schedule side effect");

    // Schedule a side-effect to mutate the main-thread instance.
    __weak __typeof(self) weakSelf = self;
    [self addNoDelegateSideEffect:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            DLog(@"dealloced");
            return;
        }
        DLog(@"Run color map mutation side effect");
        iTermColorMap *mainThreadColorMap = (iTermColorMap *)strongSelf.mainThreadCopy.colorMap;
        mainThreadColorMap.delegate = strongSelf;
        block(mainThreadColorMap);
    }];
}

- (void)updateExecutor {
    VT100ScreenTokenExecutorUpdate *update = [_executorUpdate fork];

    // Not a side-effect since it might join.
    dispatch_async(dispatch_get_main_queue(), ^{
        id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
        [delegate screenExecutorDidUpdate:update];
    });
}

- (VT100Terminal *)terminal {
    if (!self.terminalEnabled) {
        DLog(@"terminal disabled");
        return nil;
    }
    return _terminal;
}

- (void)setTerminalEnabled:(BOOL)enabled {
    if (enabled == _terminalEnabled) {
        return;
    }
    DLog(@"setTerminalEnabled:%@", @(enabled));
    _terminalEnabled = enabled;
    if (enabled) {
        _terminal.delegate = self;
        self.ansi = self.terminal.isAnsi;
        self.wraparoundMode = self.terminal.wraparoundMode;
        self.insert = self.terminal.insertMode;
        _commandRangeChangeJoiner = [iTermIdempotentOperationJoiner joinerWithScheduler:_tokenExecutor];
        _terminal.delegate = self;
        _tokenExecutor.delegate = self;
    } else {
        [_commandRangeChangeJoiner invalidate];
        _commandRangeChangeJoiner = nil;
        _tokenExecutor.delegate = nil;
        _terminal.delegate = nil;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenState alloc] initWithState:self
                                       predecessor:self.mainThreadCopy];
}

- (VT100ScreenState *)copy {
    return [self copyWithZone:nil];
}

#pragma mark - Private

- (void)assertOnMutationThread {
    [iTermGCD assertMutationQueueSafe];
}

#pragma mark - Internal

// Don't create an unpauser yourself. If the delegate is nil, your block
// doesn't get called to unpause. Use this instead unless you really know what
// you're doing.
- (void)addPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))sideEffect {
    DLog(@"Add paused side effect");
    iTermTokenExecutorUnpauser *unpauser = [_tokenExecutor pause];
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor addSideEffect:^{
        [weakSelf performPausedSideEffect:unpauser block:sideEffect];
    }];
}

- (void)addDeferredSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect {
    DLog(@"Add deferred side effect");
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor addDeferredSideEffect:^{
        [weakSelf performSideEffect:sideEffect];
    }];
}

- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect {
    DLog(@"Add side effect");
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor addSideEffect:^{
        [weakSelf performSideEffect:sideEffect];
    }];
}


- (void)addNoDelegateSideEffect:(void (^)(void))sideEffect {
    DLog(@"Add side effect");
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor addSideEffect:^{
        [weakSelf reallyPerformSideEffect:^(id<VT100ScreenDelegate> delegate) { sideEffect(); }
                                 delegate:nil];
    }];
}

- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect {
    DLog(@"Add interval tree side effect");
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor addSideEffect:^{
        [weakSelf performIntervalTreeSideEffect:sideEffect];
    }];
}

// Called on the mutation thread.
// Runs sideEffect asynchronously.
// No more tokens will be executed until it completes.
// The main thread will be stopped while running your side effect and you can safely access both
// mutation and main-thread data in it.
- (void)addJoinedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect {
    DLog(@"Add joined side effect");
    __weak __typeof(self) weakSelf = self;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [unpauser unpause];
            DLog(@"dealloced");
            return;
        }
        if (VT100ScreenMutableState.performingJoinedBlock) {
            sideEffect(delegate);
            [unpauser unpause];
            DLog(@"Already performing");
            return;
        }
        [strongSelf performBlockWithJoinedThreads:^(VT100Terminal * _Nonnull terminal,
                                                    VT100ScreenMutableState * _Nonnull mutableState,
                                                    id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"finished");
            sideEffect(delegate);
            [unpauser unpause];
        }];
    }];
}

// This is run on the main queue.
- (void)performSideEffect:(void (^)(id<VT100ScreenDelegate>))block {
    DLog(@"begin");
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    if (!delegate) {
        DLog(@"no delegate");
        return;
    }
    [self reallyPerformSideEffect:block delegate:delegate];
}

- (void)reallyPerformSideEffect:(void (^)(id<VT100ScreenDelegate>))block
                       delegate:(id<VT100ScreenDelegate>)delegate {
    const BOOL saved = self.performingSideEffect;
    self.performingSideEffect = YES;
    DLog(@"performing for delegate %@", delegate);
    block(delegate);
    self.performingSideEffect = saved;
}

- (void)performPausedSideEffect:(iTermTokenExecutorUnpauser *)unpauser
                          block:(void (^)(id<VT100ScreenDelegate>, iTermTokenExecutorUnpauser *))block {
    DLog(@"begin");
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    if (!delegate) {
        DLog(@"dealloced");
        [unpauser unpause];
        return;
    }
    const BOOL savedSideEffect = self.performingSideEffect;
    const BOOL savedPausedSideEffect = self.performingPausedSideEffect;
    self.performingSideEffect = YES;
    self.performingPausedSideEffect = YES;
    DLog(@"performing for delegate %@", delegate);
    block(delegate, unpauser);
    self.performingPausedSideEffect = savedPausedSideEffect;
    self.performingSideEffect = savedSideEffect;
}

// See threading notes on performSideEffect:.
- (void)performIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver>))block {
    DLog(@"begin");
    id<iTermIntervalTreeObserver> observer = self.sideEffectPerformer.sideEffectPerformingIntervalTreeObserver;
    if (!observer) {
        DLog(@"no observer");
        return;
    }
    const BOOL saved = self.performingSideEffect;
    self.performingSideEffect = YES;
    DLog(@"perform for observer %@", observer);
    block(observer);
    self.performingSideEffect = saved;
}

- (void)setNeedsRedraw {
    DLog(@"begin");
    [_tokenExecutor setSideEffectFlagWithValue:VT100ScreenMutableStateSideEffectFlagNeedsRedraw];
}

#pragma mark - Accessors

- (void)setConfig:(VT100MutableScreenConfiguration *)config {
    DLog(@"%@ begin %@", self, config);
    assert(VT100ScreenMutableState.performingJoinedBlock);
    if (config.desiredComposerRows.intValue != self.config.desiredComposerRows.intValue) {
        DLog(@"desiredComposerRows <- %@", config.desiredComposerRows);
    }
    [super setConfig:config];
    NSSet<NSString *> *dirty = [config dirtyKeyPaths];
    if ([dirty containsObject:@"triggerProfileDicts"]) {
        [_triggerEvaluator loadFromProfileArray:config.triggerProfileDicts];
    }
    if ([dirty containsObject:@"triggerParametersUseInterpolatedStrings"]) {
        _triggerEvaluator.triggerParametersUseInterpolatedStrings = config.triggerParametersUseInterpolatedStrings;
    }
    static NSSet<NSString *> *colorMapKeyPaths;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMapKeyPaths = [NSSet setWithArray:@[
            @"dimOnlyText",
            @"darkMode",
            @"useSeparateColorsForLightAndDarkMode",
            @"minimumContrast",
            @"faintTextAlpha",
            @"mutingAmount",
            @"dimmingAmount"
        ]];
    });
    if ([dirty intersectsSet:colorMapKeyPaths]) {
        DLog(@"Will mutate colormamp. Mine is colormap=%p, main thread's is colormap=%p", [self mutableColorMap], self.mainThreadCopy.colorMap);
        [self mutateColorMap:^(iTermColorMap *colorMap) {
            colorMap.dimOnlyText = config.dimOnlyText;
            colorMap.darkMode = config.darkMode;
            colorMap.useSeparateColorsForLightAndDarkMode = config.useSeparateColorsForLightAndDarkMode;
            DLog(@"mutable state setting min contrast of colormap=%p to %f, faint=%f", colorMap, config.minimumContrast, config.faintTextAlpha);
            colorMap.minimumContrast = config.minimumContrast;
            colorMap.mutingAmount = config.mutingAmount;
            colorMap.dimmingAmount = config.dimmingAmount;
            colorMap.faintTextAlpha = config.faintTextAlpha;
        }];
    }
    if (config.maxScrollbackLines != self.maxScrollbackLines) {
        self.maxScrollbackLines = config.maxScrollbackLines;
        [self.linebuffer setMaxLines:config.maxScrollbackLines];
        if (!self.unlimitedScrollback) {
            [self incrementOverflowBy:[self.linebuffer dropExcessLinesWithWidth:self.currentGrid.size.width]];
        }
    }
    if (config.useLineStyleMarks) {
        [self movePromptUnderComposerIfNeeded];
    }
    _terminal.stringForKeypress = config.stringForKeypress;
    _alertOnNextMark = config.alertOnNextMark;

    _autoComposerEnabled = config.autoComposerEnabled;
    if ([dirty containsObject:@"desiredComposerRows"]) {
        [_promptStateMachine revealOrDismissComposerAgain];
    }
}

- (void)movePromptUnderComposerIfNeeded {
    if (self.terminal.softAlternateScreenMode) {
        return;
    }
    const int minimumNumberOfRowsToKeepBeforeComposer = 1;
    if (self.config.desiredComposerRows && self.height > minimumNumberOfRowsToKeepBeforeComposer) {
        int end = MAX(minimumNumberOfRowsToKeepBeforeComposer,
                      self.height - self.config.desiredComposerRows.intValue);
        if (end >= self.height) {
            end = self.height - 2;
        }
        if (end < 1) {
            end = 1;
        }
        [self ensureContentEndsAt:end];
    }
}

- (void)setExited:(BOOL)exited {
    DLog(@"begin %@", @(exited));
    _exited = exited;
    _triggerEvaluator.sessionExited = exited;
}

- (iTermTokenExecutorUnpauser *)pauseTokenExecution {
    DLog(@"pause\n%@", [NSThread callStackSymbols]);
    return [_tokenExecutor pause];
}

- (iTermUnicodeNormalization)normalization {
    return self.config.normalization;
}

- (BOOL)appendToScrollbackWithStatusBar {
    return self.config.appendToScrollbackWithStatusBar;
}

- (BOOL)saveToScrollbackInAlternateScreen {
    return self.config.saveToScrollbackInAlternateScreen;
}

- (BOOL)unlimitedScrollback {
    return self.config.unlimitedScrollback;
}

#pragma mark - Terminal State Accessors

- (BOOL)terminalSoftAlternateScreenMode {
    return self.terminal.softAlternateScreenMode;
}

- (MouseMode)terminalMouseMode {
    return self.terminal.mouseMode;
}

- (NSStringEncoding)terminalEncoding {
    return self.terminal.encoding;
}

- (BOOL)terminalSendReceiveMode {
    return self.terminal.sendReceiveMode;
}

- (VT100Output *)terminalOutput {
    return self.terminal.output;
}

- (BOOL)terminalAllowPasteBracketing {
    return self.terminal.allowPasteBracketing;
}

- (BOOL)terminalBracketedPasteMode {
    return self.terminal.bracketedPasteMode;
}

- (NSMutableArray<NSNumber *> *)terminalSendModifiers {
    return self.terminal.sendModifiers;
}

- (VT100TerminalKeyReportingFlags)terminalKeyReportingFlags {
    return self.terminal.keyReportingFlags;
}

- (BOOL)terminalReportFocus {
    return self.terminal.reportFocus;
}

- (BOOL)terminalReportKeyUp {
    return self.terminal.reportKeyUp;
}

- (BOOL)terminalCursorMode {
    return self.terminal.cursorMode;
}

- (BOOL)terminalKeypadMode {
    return self.terminal.keypadMode;
}

- (BOOL)terminalReceivingFile {
    return self.terminal.receivingFile;
}

- (BOOL)terminalMetaSendsEscape {
    return self.terminal.metaSendsEscape;
}

- (BOOL)terminalReverseVideo {
    return self.terminal.reverseVideo;
}

- (BOOL)terminalAlternateScrollMode {
    return self.terminal.alternateScrollMode;
}

- (BOOL)terminalAutorepeatMode {
    return self.terminal.autorepeatMode;
}

- (int)terminalCharset {
    return self.terminal.charset;
}

- (MouseMode)terminalPreviousMouseMode {
    return self.terminal.previousMouseMode;
}

- (screen_char_t)terminalForegroundColorCode {
    return self.terminal.foregroundColorCode;
}

- (screen_char_t)terminalBackgroundColorCode {
    return self.terminal.backgroundColorCode;
}

- (NSDictionary *)terminalState {
    return self.terminal.stateDictionary;
}

#pragma mark - Scrollback

- (void)incrementOverflowBy:(int)overflowCount {
    [_tokenExecutor setSideEffectFlagWithValue:VT100ScreenMutableStateSideEffectFlagIntervalTreeVisibleRangeDidChange];
    if (overflowCount == 0) {
        return;
    }

    DLog(@"Increment overflow by %d", overflowCount);
    self.scrollbackOverflow += overflowCount;
    assert(self.cumulativeScrollbackOverflow >= 0);
    assert(overflowCount >= 0);
    self.cumulativeScrollbackOverflow += overflowCount;
}

#pragma mark - Terminal Fundamentals

- (void)appendLineFeed {
    LineBuffer *lineBufferToUse = self.linebuffer;
    const BOOL noScrollback = (self.currentGrid == self.altGrid && !self.saveToScrollbackInAlternateScreen);
    if (noScrollback) {
        // In alt grid but saving to scrollback in alt-screen is off, so pass in a nil linebuffer.
        lineBufferToUse = nil;
    }
    if (_currentBlockID) {
        [self.currentGrid setBlockID:_currentBlockID onLine:self.currentGrid.cursor.y];
    }
    [self incrementOverflowBy:[self.currentGrid moveCursorDownOneLineScrollingIntoLineBuffer:lineBufferToUse
                                                                         unlimitedScrollback:self.unlimitedScrollback
                                                                     useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                                  willScroll:nil]];
    // BE CAREFUL! This condition must match the implementation of -screenDidReceiveLineFeed.
    // See the more detailed note there.
    if (self.config.publishing || self.config.loggingEnabled) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenDidReceiveLineFeed];
        }];
    } else {
        [self.tokenExecutor setSideEffectFlagWithValue:VT100ScreenMutableStateSideEffectFlagDidReceiveLineFeed];
    }
}

- (void)appendCarriageReturnLineFeed {
    [self appendLineFeed];
    self.currentGrid.cursorX = 0;
}

- (void)carriageReturn {
    if (self.currentGrid.useScrollRegionCols && self.currentGrid.cursorX < self.currentGrid.leftMargin) {
        self.currentGrid.cursorX = 0;
    } else {
        [self.currentGrid moveCursorToLeftMargin];
    }
    // Consider moving this up to the top of the function so Inject triggers can run before the cursor moves. I should audit all calls to screenTriggerableChangeDidOccur since there could be other such opportunities.
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)softAlternateScreenModeDidChange {
    const BOOL enabled = self.terminal.softAlternateScreenMode;
    const BOOL showing = self.currentGrid == self.altGrid;;
    _triggerEvaluator.triggersSlownessDetector.enabled = enabled;
    [_triggerEvaluator.triggersSlownessDetector reset];
    [_promptStateMachine setAllowed:!enabled];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSoftAlternateScreenModeDidChangeTo:enabled showingAltScreen:showing];
    }];
}

- (void)performBlockWithoutTriggers:(void (^)(void))block {
    const BOOL saved = _triggerEvaluator.disableExecution;
    _triggerEvaluator.disableExecution = YES;
    block();
    _triggerEvaluator.disableExecution = saved;
}

- (void)appendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation {
    [self performBlockWithoutTriggers:^{
        [self appendScreenCharArrayAtCursor:line
                                     length:length
                     externalAttributeIndex:externalAttributeIndex];
        if (continuation.code == EOL_HARD) {
            [self carriageReturn];
            [self appendLineFeed];
        }
    }];
}

- (void)appendStringAtCursor:(NSString *)string {
    int len = [string length];
    if (len < 1 || !string) {
        return;
    }

    DLog(@"appendStringAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         [string characterAtIndex:0],
         self.currentGrid.cursorX,
         self.currentGrid.cursorY,
         self.currentGrid.cursorY + [self.linebuffer numLinesWithWidth:self.currentGrid.size.width]);

    // Allocate a buffer of screen_char_t and place the new string in it.
    const int kStaticBufferElements = 1024;
    screen_char_t staticBuffer[kStaticBufferElements];
    screen_char_t *dynamicBuffer = 0;
    screen_char_t *buffer;
    string = [string normalized:self.normalization];
    len = [string length];
    if (3 * len >= kStaticBufferElements) {
        buffer = dynamicBuffer = (screen_char_t *) iTermCalloc(3 * len,
                                                               sizeof(screen_char_t));
        assert(buffer);
        if (!buffer) {
            NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
            return;
        }
    } else {
        buffer = staticBuffer;
    }

    // `predecessorIsDoubleWidth` will be true if the cursor is over a double-width character
    // but NOT if it's over a DWC_RIGHT.
    BOOL predecessorIsDoubleWidth = NO;
    const VT100GridCoord pred = [self.currentGrid coordinateBefore:self.currentGrid.cursor
                                          movedBackOverDoubleWidth:&predecessorIsDoubleWidth];
    NSString *augmentedString = string;
    NSString *predecessorString = pred.x >= 0 ? [self.currentGrid stringForCharacterAt:pred] : nil;
    const BOOL augmented = predecessorString != nil;
    if (augmented) {
        augmentedString = [predecessorString stringByAppendingString:string];
    } else {
        // Prepend a space so we can detect if the first character is a combining mark.
        augmentedString = [@" " stringByAppendingString:string];
    }

    assert(self.terminal);
    // Add DWC_RIGHT after each double-width character, build complex characters out of surrogates
    // and combining marks, replace private codes with replacement characters, swallow zero-
    // width spaces, and set fg/bg colors and attributes.
    BOOL dwc = NO;
    StringToScreenChars(augmentedString,
                        buffer,
                        [self.terminal foregroundColorCode],
                        [self.terminal backgroundColorCode],
                        &len,
                        self.config.treatAmbiguousCharsAsDoubleWidth,
                        NULL,
                        &dwc,
                        self.config.normalization,
                        self.config.unicodeVersion,
                        self.terminal.softAlternateScreenMode);
    ssize_t bufferOffset = 0;
    if (augmented && len > 0) {
        [self.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(pred.x, pred.y, pred.x + 1, pred.y)
                                            block:^(screen_char_t *sct,
                                                    iTermExternalAttribute *__autoreleasing *eaOut,
                                                    VT100GridCoord coord,
                                                    BOOL *stop) {
            sct->code = buffer[0].code;
            sct->complexChar = buffer[0].complexChar;
        }];
        bufferOffset++;

        // Does the augmented result begin with a double-width character? If so skip over the
        // DWC_RIGHT when appending. I *think* this is redundant with the `predecessorIsDoubleWidth`
        // test but I'm reluctant to remove it because it could break something.
        const BOOL augmentedResultBeginsWithDoubleWidthCharacter = (augmented &&
                                                                    len > 1 &&
                                                                    ScreenCharIsDWC_RIGHT(buffer[1]) &&
                                                                    !buffer[1].complexChar);
        if ((augmentedResultBeginsWithDoubleWidthCharacter || predecessorIsDoubleWidth) && len > 1 && ScreenCharIsDWC_RIGHT(buffer[1])) {
            // Skip over a preexisting DWC_RIGHT in the predecessor.
            bufferOffset++;
        }
    } else if (!buffer[0].complexChar) {
        // We infer that the first character in |string| was not a combining mark. If it were, it
        // would have combined with the space we added to the start of |augmentedString|. Skip past
        // the space.
        bufferOffset++;
    }

    if (dwc) {
        self.linebuffer.mayHaveDoubleWidthCharacter = dwc;
    }
    [self appendScreenCharArrayAtCursor:buffer + bufferOffset
                                 length:len - bufferOffset
                 externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:self.terminal.externalAttributes]];
    if (buffer == dynamicBuffer) {
        free(buffer);
    }
}

- (void)appendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                               length:(int)len
               externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes {
    if (len >= 1) {
        screen_char_t lastCharacter = buffer[len - 1];
        if (ScreenCharIsDWC_RIGHT(lastCharacter) && !lastCharacter.complexChar) {
            // Last character is the right half of a double-width character. Use the penultimate character instead.
            if (len >= 2) {
                self.lastCharacter = buffer[len - 2];
                self.lastCharacterIsDoubleWidth = YES;
                self.lastExternalAttribute = externalAttributes[len - 2];
            }
        } else {
            // Record the last character.
            self.lastCharacter = buffer[len - 1];
            self.lastCharacterIsDoubleWidth = NO;
            self.lastExternalAttribute = externalAttributes[len];
        }
        LineBuffer *lineBuffer = nil;
        if (self.currentGrid != self.altGrid || self.saveToScrollbackInAlternateScreen) {
            // Not in alt screen or it's ok to scroll into line buffer while in alt screen.k
            lineBuffer = self.linebuffer;
        }
        [self incrementOverflowBy:[self.currentGrid appendCharsAtCursor:buffer
                                                                 length:len
                                                scrollingIntoLineBuffer:lineBuffer
                                                    unlimitedScrollback:self.unlimitedScrollback
                                                useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                             wraparound:self.wraparoundMode
                                                                   ansi:self.ansi
                                                                 insert:self.insert
                                                 externalAttributeIndex:externalAttributes]];

        if (self.config.publishing) {
            iTermImmutableMetadata temp;
            iTermImmutableMetadataInit(&temp, 0, externalAttributes);

            screen_char_t continuation = buffer[0];
            continuation.code = EOL_SOFT;
            ScreenCharArray *sca = [[ScreenCharArray alloc] initWithCopyOfLine:buffer
                                                                        length:len
                                                                  continuation:continuation];
            [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                [delegate screenAppendScreenCharArray:sca
                                             metadata:temp];
                iTermImmutableMetadataRelease(temp);
            }];
        }
    }

    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)appendAsciiDataAtCursor:(AsciiData *)asciiData {
    int len = asciiData->length;
    if (len < 1 || !asciiData) {
        return;
    }
    STOPWATCH_START(appendAsciiDataAtCursor);
    char firstChar = asciiData->buffer[0];

    DLog(@"appendAsciiDataAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         self.currentGrid.cursorX,
         self.currentGrid.cursorY,
         self.currentGrid.cursorY + [self.linebuffer numLinesWithWidth:self.currentGrid.size.width]);

    screen_char_t *buffer;
    buffer = asciiData->screenChars->buffer;

    VT100Terminal *terminal = self.terminal;
    const screen_char_t defaultChar = terminal.processedDefaultChar;
    iTermExternalAttribute *ea = [terminal externalAttributes];

    screen_char_t zero = { 0 };
    if (memcmp(&defaultChar, &zero, sizeof(defaultChar))) {
        STOPWATCH_START(setUpScreenCharArray);
        for (int i = 0; i < len; i++) {
            CopyForegroundColor(&buffer[i], defaultChar);
            CopyBackgroundColor(&buffer[i], defaultChar);
        }
        STOPWATCH_LAP(setUpScreenCharArray);
    }

    // If a graphics character set was selected then translate buffer
    // characters into graphics characters.
    if ([self.charsetUsesLineDrawingMode containsObject:@(terminal.charset)]) {
        ConvertCharsToGraphicsCharset(buffer, len);
    }

    [self appendScreenCharArrayAtCursor:buffer
                                 length:len
                 externalAttributeIndex:ea ? [iTermUniformExternalAttributes withAttribute:ea] : nil];
    STOPWATCH_LAP(appendAsciiDataAtCursor);
}

- (void)reverseIndex {
    if (self.currentGrid.cursorY == self.currentGrid.topMargin) {
        if (self.cursorOutsideLeftRightMargin) {
            return;
        } else {
            [self.currentGrid scrollDown];
        }
    } else {
        self.currentGrid.cursorY = MAX(0, self.currentGrid.cursorY - 1);
    }
    [self clearTriggerLine];
}

- (void)forwardIndex {
    if ((self.currentGrid.cursorX == self.currentGrid.rightMargin && !self.cursorOutsideLeftRightMargin )||
        self.currentGrid.cursorX == self.currentGrid.size.width) {
        [self.currentGrid moveContentLeft:1];
    } else {
        self.currentGrid.cursorX += 1;
    }
    [self clearTriggerLine];
}

- (void)backIndex {
    if ((self.currentGrid.cursorX == self.currentGrid.leftMargin && !self.cursorOutsideLeftRightMargin )||
        self.currentGrid.cursorX == 0) {
        [self.currentGrid moveContentRight:1];
    } else if (self.currentGrid.cursorX > 0) {
        self.currentGrid.cursorX -= 1;
    } else {
        return;
    }
    [self clearTriggerLine];
}

- (void)cursorLeft:(int)n {
    [self.currentGrid moveCursorLeft:n];
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)cursorRight:(int)n {
    [self.currentGrid moveCursorRight:n];
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)cursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [self.currentGrid moveCursorDown:n];
    if (toStart) {
        [self.currentGrid moveCursorToLeftMargin];
    }
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)cursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [self.currentGrid moveCursorUp:n];
    if (toStart) {
        [self.currentGrid moveCursorToLeftMargin];
    }
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)cursorToX:(int)x Y:(int)y {
    DLog(@"cursorToX:Y");
    [self cursorToX:x];
    [self cursorToY:y];
}

- (void)cursorToX:(int)x {
    DLog(@"cursorToX:%d", x);
    const int leftMargin = [self.currentGrid leftMargin];
    const int rightMargin = [self.currentGrid rightMargin];

    int xPos = x - 1;

    if ([self.terminal originMode]) {
        DLog(@"In origin mode. Interpret relative to left margin %d, don't go past right margin %d",
             leftMargin, rightMargin);
        xPos += leftMargin;
        xPos = MAX(leftMargin, MIN(rightMargin, xPos));
    }

    self.currentGrid.cursorX = xPos;
}

- (void)cursorToY:(int)y {
    DLog(@"cursorToY:%d", y);
    int yPos;
    int topMargin = self.currentGrid.topMargin;
    int bottomMargin = self.currentGrid.bottomMargin;

    yPos = y - 1;

    if ([self.terminal originMode]) {
        DLog(@"In origin mode. Interpret relative to top margin %d, don't go past bottom margin %d",
             topMargin, bottomMargin);
        yPos += topMargin;
        yPos = MAX(topMargin, MIN(bottomMargin, yPos));
    }
    self.currentGrid.cursorY = yPos;
}

- (void)advanceCursorPastLastColumn {
    if (self.currentGrid.cursorX == self.width - 1) {
        self.currentGrid.cursorX = self.width;
    }
}

- (void)ensureContentEndsAt:(int)line {
    if (line < 0 || line >= self.height || self.terminalSoftAlternateScreenMode) {
        return;
    }
    const int delta = self.currentGrid.cursor.y - line;
    if (delta == 0) {
        return;
    }
    DLog(@"delta=%@", @(delta));
    const int cursorX = self.currentGrid.cursor.x;
    if (delta > 0) {
        for (int i = 0; i < delta && self.currentGrid.cursor.y > 0; i++) {
          DLog(@"Scroll up");
            [self incrementOverflowBy:
             [self.currentGrid scrollWholeScreenUpIntoLineBuffer:self.linebuffer unlimitedScrollback:self.unlimitedScrollback]];
            [self.currentGrid setCursor:VT100GridCoordMake(cursorX, self.currentGrid.cursor.y - 1)];
        }
    } else if (self.currentGrid.cursor.y - delta < self.height){
        const int count = [self.currentGrid scrollWholeScreenDownByLines:-delta poppingFromLineBuffer:self.linebuffer];
        DLog(@"Scrolled down by %@", @ (count));
        if (count < -delta) {
            // Line buffer became empty
            const int marginalDelta = -delta - count;
            DLog( @"Scroll down by yet more: %@", @(marginalDelta));
            [self.currentGrid scrollRect:VT100GridRectMake(0, 0, self.width, self.height)
                                  downBy:marginalDelta
                               softBreak:NO];
        }
        [self shiftIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                      0,
                                                                      self.numberOfScrollbackLines + self.height + delta,
                                                                      self.height)
                                startingAfter:-1
                                  downByLines:-delta];
        [self.currentGrid setCursor:VT100GridCoordMake(cursorX, self.currentGrid.cursor.y - delta)];
    }
}

- (void)setScrollRegionTop:(int)top bottom:(int)bottom {
    if (top >= 0 &&
        top < self.currentGrid.size.height &&
        bottom >= 0 &&
        bottom < self.currentGrid.size.height &&
        bottom > top) {
        self.currentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([self.terminal originMode]) {
            self.currentGrid.cursor = VT100GridCoordMake(self.currentGrid.leftMargin,
                                                         self.currentGrid.topMargin);
        } else {
            self.currentGrid.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

// Returns -1 if none.
- (int)lastGridLineWithVisibleMarkOrAnnotation {
    const int firstGridLine = [self numberOfScrollbackLines];
    NSEnumerator *enumerator = [self.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            id<IntervalTreeObject> ito = obj;
            const VT100GridCoordRange coordRange = [self coordRangeForInterval:ito.entry.interval];
            if (coordRange.start.y < firstGridLine) {
                return -1;
            }
            if ([obj isKindOfClass:[VT100ScreenMark class]] ||
                [obj isKindOfClass:[PTYAnnotation class]]) {
                return coordRange.start.y - firstGridLine;
            }
        }
        objects = [enumerator nextObject];
    }
    return -1;
}

- (void)scrollScreenIntoHistory {
    // Scroll the top lines of the screen into history, up to and including the last non-
    // empty line.
    LineBuffer *lineBuffer;
    if (self.currentGrid == self.altGrid && !self.saveToScrollbackInAlternateScreen) {
        lineBuffer = nil;
    } else {
        lineBuffer = self.linebuffer;
    }
    const int n = MAX(self.lastGridLineWithVisibleMarkOrAnnotation + 1,
                      [self.currentGrid numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:YES]);
    for (int i = 0; i < n; i++) {
        [self incrementOverflowBy:
         [self.currentGrid scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                         unlimitedScrollback:self.unlimitedScrollback]];
    }
}

- (void)eraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    int x1, yStart, x2, y2;
    BOOL shouldHonorProtected = NO;
    switch (self.protectedMode) {
        case VT100TerminalProtectedModeNone:
            shouldHonorProtected = NO;
            break;
        case VT100TerminalProtectedModeISO:
            shouldHonorProtected = YES;
            break;
        case VT100TerminalProtectedModeDEC:
            shouldHonorProtected = dec;
            break;
    }
    if (before && after) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenRemoveSelection];
        }];
        if (!shouldHonorProtected) {
            [self scrollScreenIntoHistory];
        }
        x1 = 0;
        yStart = 0;
        x2 = self.currentGrid.size.width - 1;
        y2 = self.currentGrid.size.height - 1;
    } else if (before) {
        x1 = 0;
        yStart = 0;
        x2 = MIN(self.currentGrid.cursor.x, self.currentGrid.size.width - 1);
        y2 = self.currentGrid.cursor.y;
    } else if (after) {
        x1 = MIN(self.currentGrid.cursor.x, self.currentGrid.size.width - 1);
        yStart = self.currentGrid.cursor.y;
        x2 = self.currentGrid.size.width - 1;
        y2 = self.currentGrid.size.height - 1;
        if (x1 == 0 && yStart == 0 && [iTermAdvancedSettingsModel saveScrollBufferWhenClearing] && self.terminal.softAlternateScreenMode) {
            // Save the whole screen. This helps the "screen" terminal, where CSI H CSI J is used to
            // clear the screen.
            // Only do it in alternate screen mode to avoid doing this for zsh (issue 8822)
            // And don't do it if in a protection mode since that would defeat the purpose.
            [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                [delegate screenRemoveSelection];
            }];
            if (!shouldHonorProtected) {
                [self scrollScreenIntoHistory];
            }
        } else if (self.cursorX == 1 && self.cursorY == 1 && self.terminal.lastToken.type == VT100CSI_CUP) {
            // This is important for tmux integration with shell integration enabled. The screen
            // terminal uses ED 0 instead of ED 2 to clear the screen (e.g., when you do ^L at the shell).
            [self removePromptMarksBelowLine:yStart + self.numberOfScrollbackLines];
        }
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }
    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, yStart),
                                                 VT100GridCoordMake(x2, y2),
                                                 self.currentGrid.size.width);
    if (shouldHonorProtected) {
        const BOOL foundProtected = [self selectiveEraseRange:VT100GridCoordRangeMake(x1, yStart, x2, y2)
                                              eraseAttributes:YES];
        const BOOL eraseAll = (x1 == 0 && yStart == 0 && x2 == self.currentGrid.size.width - 1 && y2 == self.currentGrid.size.height - 1);
        if (!foundProtected && eraseAll) {  // xterm has this logic, so we do too. My guess is that it's an optimization.
            self.protectedMode = VT100TerminalProtectedModeNone;
        }
    } else {
        [self.currentGrid setCharsInRun:theRun
                                 toChar:0
                     externalAttributes:nil];
    }
    [self clearTriggerLine];
}

- (void)eraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    BOOL shouldHonorProtected = NO;
    switch (self.protectedMode) {
        case VT100TerminalProtectedModeNone:
            shouldHonorProtected = NO;
            break;
        case VT100TerminalProtectedModeISO:
            shouldHonorProtected = YES;
            break;
        case VT100TerminalProtectedModeDEC:
            shouldHonorProtected = dec;
            break;
    }
    int x1 = 0;
    int x2 = 0;

    if (before && after) {
        x1 = 0;
        x2 = self.currentGrid.size.width - 1;
    } else if (before) {
        x1 = 0;
        x2 = MIN(self.currentGrid.cursor.x, self.currentGrid.size.width - 1);
    } else if (after) {
        x1 = self.currentGrid.cursor.x;
        x2 = self.currentGrid.size.width - 1;
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }

    if (shouldHonorProtected) {
        [self selectiveEraseRange:VT100GridCoordRangeMake(x1,
                                                          self.currentGrid.cursor.y,
                                                          x2,
                                                          self.currentGrid.cursor.y)
                  eraseAttributes:YES];
    } else {
        VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, self.currentGrid.cursor.y),
                                                     VT100GridCoordMake(x2, self.currentGrid.cursor.y),
                                                     self.currentGrid.size.width);
        [self.currentGrid setCharsInRun:theRun
                                 toChar:0
                     externalAttributes:nil];
    }
}

- (void)eraseCharactersAfterCursor:(int)j {
    if (self.currentGrid.cursorX >= self.currentGrid.size.width) {
        return;
    }
    if (j <= 0) {
        return;
    }

    switch (self.protectedMode) {
        case VT100TerminalProtectedModeNone:
        case VT100TerminalProtectedModeDEC: {
            // Do not honor protected mode.
            int limit = MIN(self.currentGrid.cursorX + j, self.currentGrid.size.width);
            [self.currentGrid setCharsFrom:self.currentGrid.cursor
                                        to:VT100GridCoordMake(limit - 1, self.currentGrid.cursorY)
                                    toChar:[self.currentGrid defaultChar]
                        externalAttributes:nil];
            // TODO: This used to always set the continuation mark to hard, but I think it should only do that if the last char in the line is erased.
            [self clearTriggerLine];
            break;
        }
        case VT100TerminalProtectedModeISO:
            // honor protected mode.
            [self selectiveEraseRange:VT100GridCoordRangeMake(self.currentGrid.cursorX,
                                                              self.currentGrid.cursorY,
                                                              MIN(self.currentGrid.size.width, self.currentGrid.cursorX + j),
                                                              self.currentGrid.cursorY)
                      eraseAttributes:YES];
            break;
    }
}

// Remove soft eol on previous line, provided the cursor is on the first column. This is useful
// because zsh likes to ED 0 after wrapping around before drawing the prompt. See issue 8938.
// For consistency, EL uses it, too.
- (void)removeSoftEOLBeforeCursor {
    if (self.currentGrid.cursor.x != 0) {
        return;
    }
    if (self.currentGrid.haveScrollRegion) {
        return;
    }
    if (self.currentGrid.cursor.y > 0) {
        [self.currentGrid setContinuationMarkOnLine:self.currentGrid.cursor.y - 1 to:EOL_HARD];
    } else {
        [self.linebuffer setPartial:NO];
    }
}

- (BOOL)selectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes {
    __block BOOL foundProtected = NO;
    const screen_char_t dc = self.currentGrid.defaultChar;
    [self.currentGrid mutateCharactersInRange:range
                                        block:^(screen_char_t *sct,
                                                iTermExternalAttribute **eaOut,
                                                VT100GridCoord coord,
                                                BOOL *stop) {
        if (self.protectedMode != VT100TerminalProtectedModeNone && sct->guarded) {
            foundProtected = YES;
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, eraseAttributes, &dc);
    }];
    [self clearTriggerLine];
    return foundProtected;
}

void VT100ScreenEraseCell(screen_char_t *sct,
                          iTermExternalAttribute **eaOut,
                          BOOL eraseAttributes,
                          const screen_char_t *defaultChar) {
    if (eraseAttributes) {
        *sct = *defaultChar;
        sct->code = ' ';
        *eaOut = nil;
        return;
    }
    sct->code = ' ';
    sct->complexChar = NO;
    sct->image = NO;
    if ((*eaOut).urlCode) {
        *eaOut = [iTermExternalAttribute attributeHavingUnderlineColor:(*eaOut).hasUnderlineColor
                                                        underlineColor:(*eaOut).underlineColor
                                                               urlCode:0
                                                               blockID:nil];
    }
}

- (void)eraseScreenAndRemoveSelection {
    // Unconditionally clear the whole screen, regardless of cursor position.
    // This behavior changed in the Great VT100Grid Refactoring of 2013. Before, clearScreen
    // used to move the cursor's wrapped line to the top of the screen. It's only used from
    // DECSET 1049, and neither xterm nor terminal have this behavior, and I'm not sure why it
    // would be desirable anyway. Like xterm (and unlike Terminal) we leave the cursor put.
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenRemoveSelection];
    }];
    [self.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                to:VT100GridCoordMake(self.currentGrid.size.width - 1,
                                                      self.currentGrid.size.height - 1)
                            toChar:[self.currentGrid defaultChar]
                externalAttributes:nil];
}

- (int)numberOfLinesToPreserveWhenClearingScreen {
    if (VT100GridAbsCoordEquals(self.currentPromptRange.start, self.currentPromptRange.end)) {
        // Prompt range not defined.
        return 1;
    }
    if (self.commandStartCoord.x < 0) {
        // Prompt apparently hasn't ended.
        return 1;
    }
    id<VT100ScreenMarkReading> lastCommandMark = [self lastPromptMark];
    if (!lastCommandMark) {
        // Never had a mark.
        return 1;
    }

    VT100GridCoordRange lastCommandMarkRange = [self coordRangeForInterval:lastCommandMark.entry.interval];
    int cursorLine = self.cursorY - 1 + self.numberOfScrollbackLines;
    int cursorMarkOffset = cursorLine - lastCommandMarkRange.start.y;
    return 1 + cursorMarkOffset;
}

- (void)resetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    if (modifyContent) {
        const int linesToSave = [self numberOfLinesToPreserveWhenClearingScreen];
        [self clearTriggerLine];
        if (preservePrompt) {
            [self clearAndResetScreenSavingLines:linesToSave];
        } else {
            [self incrementOverflowBy:[self.currentGrid resetWithLineBuffer:self.linebuffer
                                                        unlimitedScrollback:self.unlimitedScrollback
                                                         preserveCursorLine:NO
                                                      additionalLinesToSave:0]];
        }
    }

    // Use a joined side effect to force any pending side effects (including those possibly added by
    // clearTriggerLine above) to execute.
    __weak __typeof(self) weakSelf = self;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [weakSelf continueResettingWithModifyContent:modifyContent];
    }];
}

- (void)continueResettingWithModifyContent:(BOOL)modifyContent {
    [self setInitialTabStops];

    for (int i = 0; i < NUM_CHARSETS; i++) {
        [self setCharacterSet:i usesLineDrawingMode:NO];
    }

    [self loadInitialColorTable];
    if (modifyContent) {
        // Unmanaged because there are various things that add joined blocks, such as changing
        // whether cursor line movement is tracked or resetting colors. Paused because this will change
        // colors that could be queried for.
        dispatch_queue_t queue = _queue;
        __weak __typeof(self) weakSelf = self;
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
            [delegate screenDidReset];  // This could change the profile
            dispatch_async(queue, ^{
                [weakSelf finishResetting];
                [unpauser unpause];
            });
        }];
    } else {
        [self finishResetting];
    }
}

- (void)finishResetting {
    [self invalidateCommandStartCoordWithoutSideEffects];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetCursorVisible:YES];
    }];
    [self.currentGrid markCharDirty:YES at:self.currentGrid.cursor updateTimestamp:NO];
}

- (void)resetScrollbackOverflow {
    DLog(@"begin %@", @(self.scrollbackOverflow));
    self.scrollbackOverflow = 0;
}

- (void)clearScrollbackBuffer {
    const int history = self.numberOfScrollbackLines;

    // Remove all interval tree marks above the grid.
    [self removeIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                   0,
                                                                   self.width, history)];
    [self removeInaccessibleIntervalTreeObjects];

    // Move all remaining (i.e., on-grid) interval tree objects up.
    [self.mutableIntervalTree bulkMoveObjects:[self.intervalTree allObjects] block:^Interval * _Nonnull(id<IntervalTreeObject> object) {
        VT100GridAbsCoordRange range = [self absCoordRangeForInterval:object.entry.interval];
        range.start.y -= history;
        range.end.y -= history;
        return [self intervalForGridAbsCoordRange:range];
    }];

    [self.linebuffer clear];
    [self resetScrollbackOverflow];
    [self.currentGrid markAllCharsDirty:YES updateTimestamps:YES];
    [self reloadMarkCache];
    self.lastCommandMark = nil;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenResetTailFind];
        [delegate screenClearHighlights];
        [delegate screenRemoveSelection];
        [delegate screenDidClearScrollbackBuffer];
        [delegate screenRefreshFindOnPageView];
        [unpauser unpause];
    }];
}

- (void)clearBufferWithoutTriggersSavingPrompt:(BOOL)savePrompt {
    [self performBlockWithoutTriggers:^{
        [self clearBufferSavingPrompt:savePrompt];
    }];
}

- (void)clearBufferSavingPrompt:(BOOL)savePrompt {
    // Cancel out the current command if shell integration is in use and we are
    // at the shell prompt.
    DLog(@"clear buffer saving prompt");
    const int linesToSave = savePrompt ? [self numberOfLinesToPreserveWhenClearingScreen] : 0;
    id<VT100ScreenMarkReading> mark = [self lastPromptMark];
    const BOOL detectedByTrigger = mark.promptDetectedByTrigger;
    // NOTE: This is in screen coords (y=0 is the top)
    VT100GridCoord newCommandStart = VT100GridCoordMake(-1, -1);
    if (self.commandStartCoord.x >= 0) {
        // Compute the new location of the command's beginning, which is right
        // after the end of the prompt in its new location.
        int numberOfPromptLines = 1;
        if (!VT100GridAbsCoordEquals(self.currentPromptRange.start, self.currentPromptRange.end)) {
            numberOfPromptLines = MAX(1, self.currentPromptRange.end.y - self.currentPromptRange.start.y + 1);
        }
        newCommandStart = VT100GridCoordMake(self.commandStartCoord.x, numberOfPromptLines - 1);

        // Abort the current command.
        [self commandWasAborted];
    }
    // There is no last command after clearing the screen, so reset it.
    self.lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);

    DLog(@"Erase interval tree objects above grid");
    // Erase interval tree objects above grid.
    VT100GridAbsCoordRange absRangeToClear = VT100GridAbsCoordRangeMake(0, 0, self.width, self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow);
    Interval *intervalToClear = [self intervalForGridAbsCoordRange:absRangeToClear];
    DLog(@"BEFORE: %@", self.markCache.description);
    [self.markCache eraseUpToLocation:intervalToClear.limit - 1];
    DLog(@"AFTER: %@", self.markCache.description);
    [self removeIntervalTreeObjectsInAbsRange:absRangeToClear
                          exceptAbsCoordRange:VT100GridAbsCoordRangeMake(-1, -1, -1, -1)];

    // Clear the grid by scrolling it up into history.
    [self clearAndResetScreenSavingLines:linesToSave];
    // Erase history.
    [self clearScrollbackBuffer];

    // Redraw soon.
    [self redrawSoon];

    if (savePrompt && newCommandStart.x >= 0) {
        // Create a new mark and inform the delegate that there's new command start coord.
        [self setPromptStartLine:self.numberOfScrollbackLines detectedByTrigger:detectedByTrigger];
        [self commandDidStartAtScreenCoord:newCommandStart];
    }
    [self.terminal resetSavedCursorPositions];
}

// Calling -screenUpdateDisplay: while joined erases the dirty bits which breaks syncing grid
// content back to the main thread.
- (void)redrawSoon {
    if (VT100ScreenMutableState.performingJoinedBlock) {
        _screenNeedsUpdate = YES;
        return;
    }
    // Can't do this from a side-effect because it might detect a current job change and join.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        id<VT100ScreenDelegate> delegate = weakSelf.sideEffectPerformer.sideEffectPerformingScreenDelegate;
        [delegate screenUpdateDisplay:NO];
    });
}


// This clears the screen, leaving the cursor's line at the top and preserves the cursor's x
// coordinate. Scroll regions and the saved cursor position are reset.
- (void)clearAndResetScreenSavingLines:(int)linesToSave {
    DLog(@"clear grid. numberOfScrollbackLines=%@, cumulative overflow=%@", @(self.numberOfScrollbackLines), @(self.cumulativeScrollbackOverflow));
    [self clearTriggerLine];
    // This clears the screen.
    int x = self.currentGrid.cursorX;
    [self incrementOverflowBy:[self.currentGrid resetWithLineBuffer:self.linebuffer
                                                unlimitedScrollback:self.unlimitedScrollback
                                                 preserveCursorLine:linesToSave > 0
                                              additionalLinesToSave:MAX(0, linesToSave - 1)]];
    self.currentGrid.cursorX = x;
    self.currentGrid.cursorY = linesToSave - 1;
    DLog(@"will remove interval tree objects in grid. numberOfScrollbackLines=%@, cumulative overflow=%@", @(self.numberOfScrollbackLines), @(self.cumulativeScrollbackOverflow));
    [self removeIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                   self.numberOfScrollbackLines,
                                                                   self.width,
                                                                   self.numberOfScrollbackLines + self.height)];
    DLog(@"done clearing grid");
}

- (void)clearFromAbsoluteLineToEnd:(long long)unsafeAbsLine {
    [self performBlockWithoutTriggers:^{
        [self reallyClearFromAbsoluteLineToEnd:unsafeAbsLine];
    }];
}

- (void)reallyClearFromAbsoluteLineToEnd:(long long)unsafeAbsLine {
    const VT100GridCoord cursorCoord = VT100GridCoordMake(self.currentGrid.cursor.x,
                                                          self.currentGrid.cursor.y + self.numberOfScrollbackLines);
    const long long totalScrollbackOverflow = self.cumulativeScrollbackOverflow;
    const long long absLine = MAX(totalScrollbackOverflow, unsafeAbsLine);
    const VT100GridAbsCoord absCursorCoord = VT100GridAbsCoordFromCoord(cursorCoord, totalScrollbackOverflow);
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:self];
    const VT100GridWindowedRange cursorLineRange = [extractor rangeForWrappedLineEncompassing:cursorCoord
                                                                         respectContinuations:YES
                                                                                     maxChars:100000];
    ScreenCharArray *savedLine = [extractor combinedLinesInRange:NSMakeRange(cursorLineRange.coordRange.start.y,
                                                                             cursorLineRange.coordRange.end.y - cursorLineRange.coordRange.start.y + 1)];
    savedLine = [savedLine screenCharArrayByRemovingTrailingNullsAndHardNewline];

    const long long firstScreenAbsLine = self.numberOfScrollbackLines + totalScrollbackOverflow;
    [self clearGridFromLineToEnd:MAX(0, absLine - firstScreenAbsLine)];

    [self clearScrollbackBufferFromLine:absLine - self.cumulativeScrollbackOverflow];
    const VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                                                   absLine - totalScrollbackOverflow,
                                                                   self.width,
                                                                   self.numberOfScrollbackLines + self.height);

    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [self removeIntervalTreeObjectsInRange:coordRange
                                                                                exceptCoordRange:cursorLineRange.coordRange];
    if (absCursorCoord.y >= absLine) {
        Interval *cursorLineInterval = [self intervalForGridCoordRange:cursorLineRange.coordRange];
        for (id<IntervalTreeObject> obj in [self.intervalTree objectsInInterval:cursorLineInterval]) {
            if ([marksToMove containsObject:obj]) {
                continue;
            }
            [marksToMove addObject:obj];
        }

        // Cursor was among the cleared lines. Restore the line content.
        self.currentGrid.cursor = VT100GridCoordMake(0, absLine - totalScrollbackOverflow - self.numberOfScrollbackLines);
        [self appendScreenChars:savedLine.line
                         length:savedLine.length
         externalAttributeIndex:iTermImmutableMetadataGetExternalAttributesIndex(savedLine.metadata)
                   continuation:savedLine.continuation];

        // Restore marks on that line.
        const long long numberOfLinesRemoved = absCursorCoord.y - absLine;
        if (numberOfLinesRemoved > 0) {
            [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                // Make an interval shifted up by `numberOfLinesRemoved`
                VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
                range.start.y -= numberOfLinesRemoved;
                range.end.y -= numberOfLinesRemoved;
                Interval *interval = [self intervalForGridCoordRange:range];

                // Remove and re-add the object with the new interval.
                DLog(@"clearFromAbsoluteLineToEnd:%@", obj);
                const BOOL removed = [self removeObjectFromIntervalTree:obj];
                assert(removed);
                [self.mutableIntervalTree addObject:obj withInterval:interval];

                // Re-adding an annotation requires telling the delegate so it can create a vc
                id<PTYAnnotationReading> annotation = [PTYAnnotation castFrom:obj];
                if (annotation) {
                    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
                        [delegate screenDidAddNote:annotation focus:NO visible:YES];
                    }];
                }
                [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
                    [observer intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeForObject(obj)
                                                      onLine:range.start.y + totalScrollbackOverflow];
                }];
            }];
        }
    } else {
        [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self removeObjectFromIntervalTree:obj];
        }];
    }
    [self reloadMarkCache];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenRemoveSelection];
    }];
    [self setNeedsRedraw];
}


- (void)clearGridFromLineToEnd:(int)line {
    assert(line >= 0 && line < self.height);
    const VT100GridCoord savedCursor = self.currentGrid.cursor;
    self.currentGrid.cursor = VT100GridCoordMake(0, line);
    [self removeSoftEOLBeforeCursor];
    const VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(0, line),
                                                    VT100GridCoordMake(self.width, self.height),
                                                    self.width);
    [self.currentGrid setCharsInRun:run toChar:0 externalAttributes:nil];
    [self clearTriggerLine];
    self.currentGrid.cursor = savedCursor;
}

- (void)clearScrollbackBufferFromLine:(int)line {
    const int width = self.width;
    const int scrollbackLines = [self.linebuffer numberOfWrappedLinesWithWidth:width];
    if (scrollbackLines < line) {
        return;
    }
    [self.linebuffer removeLastWrappedLines:scrollbackLines - MAX(0, line)
                                      width:width];
}

- (void)removeLastLine {
    DLog(@"BEGIN removeLastLine with cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
    const int preHocNumberOfLines = [self.linebuffer numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesAppended = [self.currentGrid appendLines:self.currentGrid.numberOfLinesUsed
                                                       toLineBuffer:self.linebuffer];
    if (numberOfLinesAppended <= 0) {
        return;
    }
    [self.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                to:VT100GridCoordMake(self.width - 1,
                                                      self.height - 1)
                            toChar:self.currentGrid.defaultChar
                externalAttributes:nil];
    [self.linebuffer removeLastRawLine];
    const int postHocNumberOfLines = [self.linebuffer numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesToPop = MAX(0, postHocNumberOfLines - preHocNumberOfLines);

    [self.currentGrid restoreScreenFromLineBuffer:self.linebuffer
                                  withDefaultChar:[self.currentGrid defaultChar]
                                maxLinesToRestore:numberOfLinesToPop];
    // One of the lines "removed" will be the one the cursor is on. Don't need to move it up for
    // that one.
    const int adjustment = self.currentGrid.cursorX > 0 ? 1 : 0;
    self.currentGrid.cursorX = 0;
    const int numberOfLinesRemoved = MAX(0, numberOfLinesAppended - numberOfLinesToPop);
    const int y = MAX(0, self.currentGrid.cursorY - numberOfLinesRemoved + adjustment);
    DLog(@"numLinesAppended=%@ numLinesToPop=%@ numLinesRemoved=%@ adjustment=%@ y<-%@",
         @(numberOfLinesAppended), @(numberOfLinesToPop), @(numberOfLinesRemoved), @(adjustment), @(y));
    self.currentGrid.cursorY = y;
    DLog(@"Cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
}

// Move everything above the prompt mark into history.
- (void)clearForComposer {
    if (!_promptStateMachine.isEnteringCommand) {
        return;
    }
    if (self.terminal.softAlternateScreenMode) {
        return;
    }
    if (self.config.desiredComposerRows <= 0) {
        return;
    }
    id<VT100ScreenMarkReading> mark = [self lastPromptMark];
    Interval *interval = mark.entry.interval;
    if (!interval) {
        return;
    }
    const VT100GridAbsCoordRange absRange = [self absCoordRangeForInterval:interval];
    if (absRange.end.y <= self.numberOfScrollbackLines + self.totalScrollbackOverflow) {
        // Mark begins above screen.
        return;
    }

    // Move the prompt mark to the top of the grid.
    const int count = absRange.end.y - self.numberOfScrollbackLines - self.totalScrollbackOverflow - 1;
    for (int i = 0; i < count; i++) {
        [self incrementOverflowBy:
         [self.currentGrid scrollWholeScreenUpIntoLineBuffer:self.linebuffer
                                         unlimitedScrollback:self.unlimitedScrollback]];
    }

    // Add a bunch of blank lines to history so that it can then be moved down.
    // Note that this causes the interval tree objects to be misaligned.
    for (int i = 0; i < count; i++) {
        [self.linebuffer appendScreenCharArray:[ScreenCharArray emptyLineOfLength:self.width] width:self.width];
    }

    // Move the interval tree objects to be next to the prompt again.
    [self shiftIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                  self.numberOfScrollbackLines - count,
                                                                  self.width,
                                                                  self.numberOfScrollbackLines)
                            startingAfter:self.numberOfScrollbackLines - count - 1
                              downByLines:count];
     // Move content down so prompt ends at the bottom of the screen. This is based on the cursor's
    // position.
    self.currentGrid.cursorY -= count;
    [self movePromptUnderComposerIfNeeded];
}

- (void)setUseColumnScrollRegion:(BOOL)mode {
    self.currentGrid.useScrollRegionCols = mode;
    self.altGrid.useScrollRegionCols = mode;
    if (!mode) {
        self.currentGrid.scrollRegionCols = VT100GridRangeMake(0, self.currentGrid.size.width);
    }
}

- (void)setLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    if (self.currentGrid.useScrollRegionCols) {
        self.currentGrid.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                               scrollRight - scrollLeft + 1);
        // set cursor to the home position
        [self cursorToX:1 Y:1];
    }
}

- (void)setCursorVisible:(BOOL)visible {
    DLog(@"VT100ScreenMutableState.setCursorVisible(%@)", visible ? @"true" : @"false");
    if (visible != self.cursorVisible) {
        [super setCursorVisible:visible];
        if (visible) {
            [self.temporaryDoubleBuffer reset];
        } else {
            [self.temporaryDoubleBuffer start];
        }
    }
    if (visible) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenSetCursorVisible:YES];
        }];
    } else {
        // Wait to hide the cursor because it's pretty likely it'll be shown right away, such as
        // when editing in emacs. Doing this prevents flicker. See issue 10206.
        [self addDeferredSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenSetCursorVisible:NO];
        }];
    }
}

- (void)activateBell {
    const BOOL audibleBell = self.audibleBell;
    const BOOL flashBell = self.flashBell;
    const BOOL showBellIndicator = self.showBellIndicator;
    const BOOL shouldQuellBell = [self shouldQuellBell];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenActivateBellAudibly:audibleBell
                                    visibly:flashBell
                              showIndicator:showBellIndicator
                                      quell:shouldQuellBell];
    }];
}

- (BOOL)shouldQuellBell {
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    const NSTimeInterval interval = now - self.lastBell;
    const BOOL result = interval < [iTermAdvancedSettingsModel bellRateLimit];
    if (!result) {
        self.lastBell = now;
    }
    return result;
}

#pragma mark - Alternate Screen

- (void)showAltBuffer {
    if (self.currentGrid == self.altGrid) {
        return;
    }
    if (!self.altGrid) {
        self.altGrid = [[VT100Grid alloc] initWithSize:self.primaryGrid.size delegate:self];
        self.altGrid.defaultChar = self.terminal.defaultChar;
    }

    [self.temporaryDoubleBuffer reset];
    self.primaryGrid.savedDefaultChar = [self.primaryGrid defaultChar];
    [self hideOnScreenNotesAndTruncateSpanners];
    self.currentGrid = self.altGrid;
    self.currentGrid.cursor = self.primaryGrid.cursor;

    [self swapOnscreenIntervalTreeObjects];
    [self reloadMarkCache];

    [self.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
    [self invalidateCommandStartCoordWithoutSideEffects];
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenRemoveSelection];
        [delegate screenScheduleRedrawSoon];
        [unpauser unpause];
    }];
}

- (void)showPrimaryBuffer {
    if (self.currentGrid != self.altGrid) {
        return;
    }
    [self.temporaryDoubleBuffer reset];
    [self hideOnScreenNotesAndTruncateSpanners];
    self.currentGrid = self.primaryGrid;
    [self invalidateCommandStartCoordWithoutSideEffects];
    [self swapOnscreenIntervalTreeObjects];
    [self reloadMarkCache];

    [self.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenRemoveSelection];
        [delegate screenScheduleRedrawSoon];
        [unpauser unpause];
    }];
}

- (void)hideOnScreenNotesAndTruncateSpanners {
    int screenOrigin = self.numberOfScrollbackLines;
    VT100GridCoordRange screenRange =
    VT100GridCoordRangeMake(0,
                            screenOrigin,
                            self.width,
                            screenOrigin + self.height);
    Interval *screenInterval = [self intervalForGridCoordRange:screenRange];
    // Array of doppelgangers.
    [self.mutableIntervalTree bulkMutateObjects:[self.intervalTree objectsInInterval:screenInterval]
                                          block:^(id<IntervalTreeObject> note) {
        if (note.entry.interval.location < screenInterval.location) {
            // Truncate note so that it ends just before screen.
            // Subtract 1 because end coord is inclusive of y even when x is 0.
            note.entry.interval.length = screenInterval.location - note.entry.interval.location - 1;
        }
        PTYAnnotation *annotation = [PTYAnnotation castFrom:note];
        [annotation hide];
    }];
    // Force annotations frames to be updated.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [unpauser unpause];
    }];
    [self setNeedsRedraw];
}

- (void)insertColumns:(int)n {
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = self.currentGrid.topMargin; y <= self.currentGrid.bottomMargin; y++) {
        [self.currentGrid insertChar:self.currentGrid.defaultChar
                  externalAttributes:nil
                                  at:VT100GridCoordMake(self.currentGrid.cursor.x, y)
                               times:n];
    }
}

- (void)deleteColumns:(int)n {
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = self.currentGrid.topMargin; y <= self.currentGrid.bottomMargin; y++) {
        [self.currentGrid deleteChars:n
                           startingAt:VT100GridCoordMake(self.currentGrid.cursor.x, y)];
    }
}

- (void)setAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    void (^block)(VT100GridCoord, screen_char_t *, iTermExternalAttribute *, BOOL *) =
    ^(VT100GridCoord coord,
      screen_char_t *sct,
      iTermExternalAttribute *ea,
      BOOL *stop) {
        switch (sgrAttribute) {
            case 0:
                sct->bold = NO;
                sct->blink = NO;
                sct->underline = NO;
                if (sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;

            case 1:
                sct->bold = YES;
                break;
            case 4:
                sct->underline = YES;
                break;
            case 5:
                sct->blink = YES;
                break;
            case 7:
                if (!sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;

            case 22:
                sct->bold = NO;
                break;
            case 24:
                sct->underline = NO;
                break;
            case 25:
                sct->blink = NO;
                break;
            case 27:
                if (sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;
        }
    };
    if (self.terminal.decsaceRectangleMode) {
        [self.currentGrid mutateCellsInRect:rect
                                      block:^(VT100GridCoord coord,
                                              screen_char_t *sct,
                                              iTermExternalAttribute **eaOut,
                                              BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [self.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
                                                                          rect.origin.y,
                                                                          rect.origin.x + rect.size.width,
                                                                          rect.origin.y + rect.size.height - 1)
                                            block:^(screen_char_t *sct,
                                                    iTermExternalAttribute **eaOut,
                                                    VT100GridCoord coord,
                                                    BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    }
}

- (void)toggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    void (^block)(VT100GridCoord, screen_char_t *, iTermExternalAttribute *, BOOL *) =
    ^(VT100GridCoord coord,
      screen_char_t *sct,
      iTermExternalAttribute *ea,
      BOOL *stop) {
        switch (sgrAttribute) {
            case 1:
                sct->bold = !sct->bold;
                break;
            case 4:
                sct->underline = !sct->underline;
                break;
            case 5:
                sct->blink = !sct->blink;
                break;
            case 7:
                ScreenCharInvert(sct);
                break;
        }
    };
    if (self.terminal.decsaceRectangleMode) {
        [self.currentGrid mutateCellsInRect:rect
                                      block:^(VT100GridCoord coord,
                                              screen_char_t *sct,
                                              iTermExternalAttribute **eaOut,
                                              BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [self.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
                                                                          rect.origin.y,
                                                                          rect.origin.x + rect.size.width,
                                                                          rect.origin.y + rect.size.height - 1)
                                            block:^(screen_char_t *sct,
                                                    iTermExternalAttribute **eaOut,
                                                    VT100GridCoord coord,
                                                    BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    }
}

- (void)copyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    id<VT100GridReading> copy = [self.currentGrid copy];
    const VT100GridSize size = self.currentGrid.size;
    [copy enumerateCellsInRect:source
                         block:^(VT100GridCoord sourceCoord,
                                 screen_char_t sct,
                                 iTermExternalAttribute *ea,
                                 BOOL *stop) {
        const VT100GridCoord destCoord = VT100GridCoordMake(sourceCoord.x - source.origin.x + dest.x,
                                                            sourceCoord.y - source.origin.y + dest.y);
        if (destCoord.x < 0 || destCoord.x >= size.width || destCoord.y < 0 || destCoord.y >= size.height) {
            return;
        }
        [self.currentGrid setCharsFrom:destCoord
                                    to:destCoord
                                toChar:sct
                    externalAttributes:ea];
    }];
}

- (void)fillRectangle:(VT100GridRect)rect
                 with:(screen_char_t)c
   externalAttributes:(iTermExternalAttribute *)ea {
    [self.currentGrid setCharsFrom:rect.origin
                                to:VT100GridRectMax(rect)
                            toChar:c
                externalAttributes:ea];
}

// Note: this does not erase attributes! It just sets the character to space.
- (void)selectiveEraseRectangle:(VT100GridRect)rect {
    const screen_char_t dc = self.currentGrid.defaultChar;
    [self.currentGrid mutateCellsInRect:rect
                                  block:^(VT100GridCoord coord,
                                          screen_char_t *sct,
                                          iTermExternalAttribute **eaOut,
                                          BOOL *stop) {
        if (self.protectedMode == VT100TerminalProtectedModeDEC && sct->guarded) {
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, NO, &dc);
    }];
    [self clearTriggerLine];
}


#pragma mark - Character Sets

- (void)setCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode {
    if (lineDrawingMode) {
        [self.charsetUsesLineDrawingMode addObject:@(charset)];
    } else {
        [self.charsetUsesLineDrawingMode removeObject:@(charset)];
    }
}

#pragma mark - Tabs

- (void)setInitialTabStops {
    [self.tabStops removeAllObjects];
    const int kInitialTabWindow = 1000;
    const int width = MAX(1, [iTermAdvancedSettingsModel defaultTabStopWidth]);
    for (int i = 0; i < kInitialTabWindow; i += width) {
        [self.tabStops addObject:@(i)];
    }
    DLog(@"Initial tabstops set to %@", self.tabStops);
}

// See issue 6592 for why `setBackgroundColors` exists. tl;dr ncurses makes weird assumptions.
- (void)appendTabAtCursor:(BOOL)setBackgroundColors {
    int rightMargin;
    if (self.currentGrid.useScrollRegionCols) {
        rightMargin = self.currentGrid.rightMargin;
        if (self.currentGrid.cursorX > rightMargin) {
            rightMargin = self.width - 1;
        }
    } else {
        rightMargin = self.width - 1;
    }

    if (self.terminal.moreFix && self.cursorX > self.width && self.terminal.wraparoundMode) {
        [self terminalLineFeed];
        [self carriageReturn];
    }

    int nextTabStop = MIN(rightMargin, [self tabStopAfterColumn:self.currentGrid.cursorX]);
    if (nextTabStop <= self.currentGrid.cursorX) {
        // This happens when the cursor can't advance any farther.
        if ([iTermAdvancedSettingsModel tabsWrapAround]) {
            nextTabStop = [self tabStopAfterColumn:self.currentGrid.leftMargin];
            [self softWrapCursorToNextLineScrollingIfNeeded];
        } else {
            return;
        }
    }
    const int y = self.currentGrid.cursorY;
    screen_char_t *aLine = [self.currentGrid screenCharsAtLineNumber:y];
    BOOL allNulls = YES;
    for (int i = self.currentGrid.cursorX; i < nextTabStop; i++) {
        if (aLine[i].code) {
            allNulls = NO;
            break;
        }
    }
    if (allNulls) {
        screen_char_t filler;
        InitializeScreenChar(&filler, [self.terminal foregroundColorCode], [self.terminal backgroundColorCode]);
        ScreenCharSetTAB_FILLER(&filler);
        const int startX = self.currentGrid.cursorX;
        const int limit = nextTabStop - 1;
        iTermExternalAttribute *ea = [self.terminal externalAttributes];
        [self.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(startX, y, limit + 1, y)
                                            block:^(screen_char_t *c,
                                                    iTermExternalAttribute **eaOut,
                                                    VT100GridCoord coord,
                                                    BOOL *stop) {
            if (coord.x < limit) {
                if (setBackgroundColors) {
                    *c = filler;
                    *eaOut = ea;
                } else {
                    ScreenCharSetTAB_FILLER(c);
                }
            } else {
                if (setBackgroundColors) {
                    screen_char_t tab = filler;
                    tab.code = '\t';
                    *c = tab;
                    *eaOut = ea;
                } else {
                    c->image = NO;
                    c->complexChar = NO;
                    c->code = '\t';
                }
            }
        }];
        const int cursorX = self.currentGrid.cursorX;
        screen_char_t continuation = aLine[cursorX];
        continuation.code = EOL_SOFT;
        ScreenCharArray *sca = [[ScreenCharArray alloc] initWithCopyOfLine:aLine + cursorX
                                                                    length:nextTabStop - startX continuation:continuation];
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenAppendScreenCharArray:sca
                                         metadata:iTermImmutableMetadataDefault()];
        }];
    }
    self.currentGrid.cursorX = nextTabStop;
}

- (int)tabStopAfterColumn:(int)lowerBound {
    for (int i = lowerBound + 1; i < self.width - 1; i++) {
        if ([self.tabStops containsObject:@(i)]) {
            return i;
        }
    }
    return self.width - 1;
}

- (void)convertHardNewlineToSoftOnGridLine:(int)line {
    screen_char_t *aLine = [self.currentGrid screenCharsAtLineNumber:line];
    if (aLine[self.currentGrid.size.width].code == EOL_HARD) {
        aLine[self.currentGrid.size.width].code = EOL_SOFT;
    }
}

- (void)softWrapCursorToNextLineScrollingIfNeeded {
    if (self.currentGrid.rightMargin + 1 == self.currentGrid.size.width) {
        [self convertHardNewlineToSoftOnGridLine:self.currentGrid.cursorY];
    }
    if (self.currentGrid.cursorY == self.currentGrid.bottomMargin) {
        [self incrementOverflowBy:[self.currentGrid scrollUpIntoLineBuffer:self.linebuffer
                                                       unlimitedScrollback:self.unlimitedScrollback
                                                   useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                 softBreak:YES]];
    }
    self.currentGrid.cursorX = self.currentGrid.leftMargin;
    self.currentGrid.cursorY++;
}

- (void)setTabStopAtCursor {
    if (self.currentGrid.cursorX < self.currentGrid.size.width) {
        [self.tabStops addObject:[NSNumber numberWithInt:self.currentGrid.cursorX]];
        DLog(@"Set tabstop at cursor. Is now %@", self.tabStops);
    }
}

- (void)removeTabStopAtCursor {
    if (self.currentGrid.cursorX < self.currentGrid.size.width) {
        [self.tabStops removeObject:@(self.currentGrid.cursorX)];
        DLog(@"Remove tabstop at %@", @(self.currentGrid.cursorX));
    }
}

- (BOOL)haveTabStopAt:(int)x {
    return [self.tabStops containsObject:@(x)];
}

- (void)backTab:(int)n {
    for (int i = 0; i < n; i++) {
        // TODO: respect left-right margins
        if (self.currentGrid.cursorX > 0) {
            self.currentGrid.cursorX = self.currentGrid.cursorX - 1;
            while (![self haveTabStopAt:self.currentGrid.cursorX] && self.currentGrid.cursorX > 0) {
                self.currentGrid.cursorX = self.currentGrid.cursorX - 1;
            }
            [self clearTriggerLine];
        }
    }
}

#pragma mark - Backspace

// Reverse wrap is allowed when the cursor is on the left margin or left edge, wraparoundMode is
// set, the cursor is not at the top margin/edge, and:
// 1. reverseWraparoundMode is set (xterm's rule), or
// 2. there's no left-right margin and the preceding line has EOL_SOFT (Terminal.app's rule)
- (BOOL)shouldReverseWrap {
    if (!self.terminal.wraparoundMode) {
        return NO;
    }

    // Cursor must be at left margin/edge.
    const int leftMargin = self.currentGrid.leftMargin;
    const int cursorX = self.currentGrid.cursorX;
    if (cursorX != leftMargin && cursorX != 0) {
        return NO;
    }

    // Cursor must not be at top margin/edge.
    const int topMargin = self.currentGrid.topMargin;
    const int cursorY = self.currentGrid.cursorY;
    if (cursorY == topMargin || cursorY == 0) {
        return NO;
    }

    // If reverseWraparoundMode is reset, then allow only if there's a soft newline on previous line
    if (!self.terminal.reverseWraparoundMode) {
        if (self.currentGrid.useScrollRegionCols) {
            return NO;
        }

        const screen_char_t *line = [self.currentGrid screenCharsAtLineNumber:cursorY - 1];
        const unichar c = line[self.width].code;
        return (c == EOL_SOFT || c == EOL_DWC);
    }

    return YES;
}

- (void)backspace {
    const int leftMargin = self.currentGrid.leftMargin;
    const int rightMargin = self.currentGrid.rightMargin;
    const int cursorX = self.currentGrid.cursorX;
    const int cursorY = self.currentGrid.cursorY;

    if (cursorX >= self.width && self.terminal.reverseWraparoundMode && self.terminal.wraparoundMode) {
        // Reverse-wrap when past the screen edge is a special case.
        self.currentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY);
    } else if ([self shouldReverseWrap]) {
        self.currentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY - 1);
    } else if (cursorX > leftMargin ||  // Cursor can move back without hitting the left margin: normal case
               (cursorX < leftMargin && cursorX > 0)) {  // Cursor left of left margin, right of left edge.
        if (cursorX >= self.currentGrid.size.width) {
            // Cursor right of right edge, move back twice.
            self.currentGrid.cursorX = cursorX - 2;
        } else {
            // Normal case.
            self.currentGrid.cursorX = cursorX - 1;
        }
    }

    // It is OK to land on the right half of a double-width character (issue 3475).
}

#pragma mark - Interval Tree

- (iTermEventuallyConsistentIntervalTree *)mutableIntervalTree {
    return [iTermEventuallyConsistentIntervalTree castFrom:self.intervalTree];
}

- (iTermEventuallyConsistentIntervalTree *)mutableSavedIntervalTree {
    return [iTermEventuallyConsistentIntervalTree castFrom:self.savedIntervalTree];
}

- (iTermColorMap *)mutableColorMap {
    return (iTermColorMap *)[super colorMap];
}

- (void)setName:(NSString *)name forMark:(VT100ScreenMark *)mark {
    [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull mutableObj) {
        VT100ScreenMark *mutableMark = [VT100ScreenMark castFrom:mutableObj];
        mutableMark.name = name;
    }];
    if (name) {
        [self.namedMarks addObject:mark];
    } else {
        [self.namedMarks removeObjectsPassingTest:^BOOL(id _Nullable obj) {
            id<VT100ScreenMarkReading> anObject = obj;
            return [anObject.guid isEqualToString:mark.guid];
        }];
    }
    self.namedMarksDirty = YES;
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass {
    return [self addMarkStartingAtAbsoluteLine:line oneLine:oneLine ofClass:markClass modifier:nil];
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                        column:(int)column
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass {
    return [self addMarkStartingAtAbsoluteLine:line column:column oneLine:oneLine ofClass:markClass modifier:nil];
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass
                                      modifier:(void (^ NS_NOESCAPE)(id<iTermMark>))modifier {
    return [self addMarkStartingAtAbsoluteLine:line column:-1 oneLine:oneLine ofClass:markClass modifier:modifier];
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                        column:(int)column
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass
                                      modifier:(void (^ NS_NOESCAPE)(id<iTermMark>))modifier {
    iTermMark *mark = [[markClass alloc] init];
    if (modifier) {
        modifier(mark);
    }
    return [self addMark:mark onLine:line column:column singleLine:oneLine];
}

- (id<iTermMark>)addMark:(iTermMark *)mark onLine:(long long)line singleLine:(BOOL)oneLine {
    return [self addMark:mark onLine:line column:-1 singleLine:oneLine];
}

- (id<iTermMark>)addMark:(iTermMark *)mark onLine:(long long)line column:(int)column singleLine:(BOOL)oneLine {
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = (VT100ScreenMark *)mark;
        screenMark.delegate = self;
        screenMark.sessionGuid = self.config.sessionGuid;
    }
    long long totalOverflow = self.cumulativeScrollbackOverflow;
    if (line < totalOverflow || line > totalOverflow + self.numberOfLines) {
        return nil;
    }
    VT100GridAbsCoordRange absRange;
    if (oneLine) {
        absRange = VT100GridAbsCoordRangeMake(0, line, self.width, line);
    } else {
        long long absLimit = line + self.height - 1;
        const long long maxAbsLimit = self.cumulativeScrollbackOverflow + self.numberOfScrollbackLines + [self.currentGrid numberOfLinesUsed];
        if (absLimit >= maxAbsLimit) {
            absLimit = maxAbsLimit - 1;
        }
        if (column < 0) {
            // Interval is whole screen
            absRange = VT100GridAbsCoordRangeMake(0, line, self.width, absLimit);
        } else {
            // Interval is one cell
            absRange = VT100GridAbsCoordRangeMake(column, line, column + 1, absLimit);
        }
    }
    DLog(@"addMarkStartingAtAbsoluteLine: %@", mark);
    [self.mutableIntervalTree addObject:mark withInterval:[self intervalForGridAbsCoordRange:absRange]];
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        self.markCache[absRange.end.y] = mark;
    }

    const iTermIntervalTreeObjectType objectType = iTermIntervalTreeObjectTypeForObject(mark);
    const long long absLine = absRange.start.y;
    DLog(@"Add mark %p with abs range %@", mark, VT100GridAbsCoordRangeDescription(absRange));
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidAddObjectOfType:objectType
                                          onLine:absLine];
    }];
    [self setNeedsRedraw];
    VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:mark];
    if (screenMark.name) {
        [self.namedMarks addObject:screenMark];
        self.namedMarksDirty = YES;
    }
    return mark;
}
// Remove screen mark from mark cache
// If there is a screen mark, reset lastCommandMark
// If mark is named, remove from namedMarks and set namedMarkDirty
// Call willRemove on annotations
// Remove from the interval tree
// For minimap marks, call observer methods

- (BOOL)removeObjectFromIntervalTree:(id<IntervalTreeObject>)obj {
    DLog(@"Remove %@", obj);
    [self willRemoveObjectsFromIntervalTree:@[ obj ]];
    DLog(@"removeObjectFromIntervalTree: %@", obj);
    const BOOL removed = [self.mutableIntervalTree removeObject:obj];
    [self didRemoveObjectFromIntervalTree:obj];
    return removed;
}

- (void)willRemoveObjectsFromIntervalTree:(NSArray<id<IntervalTreeObject>> *)objects {
    [self willRemoveScreenMarksFromIntervalTree:[objects mapWithBlock:^id _Nullable(id<IntervalTreeObject>  _Nonnull anObject) {
        return [VT100ScreenMark castFrom:anObject];
    }]];
    [self willRemoveAnnotationsFromIntervalTree:[objects mapWithBlock:^id _Nullable(id<IntervalTreeObject>  _Nonnull anObject) {
        return [PTYAnnotation castFrom:anObject];
    }]];
}

- (void)didRemoveObjectFromIntervalTree:(id<IntervalTreeObject>)obj {
    const VT100GridAbsCoordRange range = [self absCoordRangeForInterval:obj.entry.interval];
    iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(obj);
    if (type != iTermIntervalTreeObjectTypeUnknown) {
        const long long line = range.start.y;
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidRemoveObjectOfType:type
                                                 onLine:line];
        }];
    }
}

- (void)willRemoveScreenMarksFromIntervalTree:(NSArray<VT100ScreenMark *> *)objects {
    const long long totalScrollbackOverflow = self.cumulativeScrollbackOverflow;
    NSArray<NSNumber *> *keys = [objects mapWithBlock:^id _Nullable(VT100ScreenMark * _Nonnull obj) {
        long long theKey = (totalScrollbackOverflow +
                            [self coordRangeForInterval:obj.entry.interval].end.y);
        return @(theKey);
    }];
    [self.markCache removeMarks:objects onLines:keys];
    [objects enumerateObjectsUsingBlock:^(VT100ScreenMark * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        self.lastCommandMark = nil;
        VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:obj];
        if (screenMark.name) {
            [self.namedMarks removeObjectsPassingTest:^BOOL(id  _Nullable obj) {
                id<VT100ScreenMarkReading> anObject = obj;
                return anObject == screenMark;
            }];
            self.namedMarksDirty = YES;
        }
    }];
}

- (void)willRemoveAnnotationsFromIntervalTree:(NSArray<PTYAnnotation *> *)objects {
    [objects enumerateObjectsUsingBlock:^(PTYAnnotation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self.mutableIntervalTree mutateObject:obj block:^(id<IntervalTreeObject> _Nonnull mutableObj) {
            PTYAnnotation *mutableAnnotation = (PTYAnnotation *)mutableObj;
            [mutableAnnotation willRemove];
        }];
    }];
}

- (void)removeObjectsFromIntervalTree:(NSArray<id<IntervalTreeObject>> *)objects {
    [self willRemoveObjectsFromIntervalTree:objects];
    [objects enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        const BOOL removed = [self.mutableIntervalTree removeObject:obj];
        assert(removed);
        [self didRemoveObjectFromIntervalTree:obj];
    }];
}

- (void)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange {
    [self removeIntervalTreeObjectsInRange:coordRange
                          exceptCoordRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
}

- (NSMutableArray<id<IntervalTreeObject>> *)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange
                                                            exceptCoordRange:(VT100GridCoordRange)coordRangeToSave {
    const VT100GridAbsCoordRange absCoordRangeToClear =
    VT100GridAbsCoordRangeFromCoordRange(coordRange,
                                         self.cumulativeScrollbackOverflow);

    VT100GridAbsCoordRange absCoordRangeToSave;
    if (coordRangeToSave.start.x < 0) {
        absCoordRangeToSave = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        if (absCoordRangeToClear.start.y == 0 &&
            absCoordRangeToClear.start.x == 0) {
            Interval *interval = [self intervalForGridAbsCoordRange:absCoordRangeToClear];
            [self.markCache eraseUpToLocation:interval.location];
        }
    } else {
        absCoordRangeToSave = VT100GridAbsCoordRangeFromCoordRange(coordRangeToSave, self.cumulativeScrollbackOverflow);
    }
    return [self removeIntervalTreeObjectsInAbsRange:absCoordRangeToClear
                                 exceptAbsCoordRange:absCoordRangeToSave];
}

- (NSMutableArray<id<IntervalTreeObject>> *)removeIntervalTreeObjectsInAbsRange:(VT100GridAbsCoordRange)absCoordRange
                                                            exceptAbsCoordRange:(VT100GridAbsCoordRange)absCoordRangeToSave {
    DLog(@"Remove interval tree objects in range %@", VT100GridAbsCoordRangeDescription(absCoordRange));
    Interval *intervalToClear = [self intervalForGridAbsCoordRange:absCoordRange];
    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [NSMutableArray array];
    NSMutableArray<id<IntervalTreeObject>> *marksToRemove = [NSMutableArray array];

    for (id<IntervalTreeObject> obj in [self.intervalTree objectsInInterval:intervalToClear]) {
        const VT100GridAbsCoordRange absMarkRange = [self absCoordRangeForInterval:obj.entry.interval];
        if (VT100GridAbsCoordRangeContainsAbsCoord(absCoordRangeToSave, absMarkRange.start)) {
            [marksToMove addObject:obj];
        } else {
            DLog(@"Remove %p with range %@", obj, VT100GridAbsCoordRangeDescription([self absCoordRangeForInterval:obj.entry.interval]));
            DLog(@"Remove in range: %@", obj);
            [marksToRemove addObject:obj];
        }
    }
    [self removeObjectsFromIntervalTree:marksToRemove];
    return marksToMove;
}

// FTCS C
- (void)commandDidEndWithRange:(VT100GridCoordRange)range {
    NSString *command = [self commandInRange:range];
    DLog(@"FinalTerm: Command <<%@>> ended with range %@",
         command, VT100GridCoordRangeDescription(range));
    id<VT100ScreenMarkReading> mark = nil;
    if (command) {
        NSString *trimmedCommand =
        [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedCommand.length) {
            mark = [self markOnLine:self.lastPromptLine - self.cumulativeScrollbackOverflow];
            if (mark && !mark.command) {
                // This code path should not be taken with auto-composer because mark.command gets
                // set prior to sending the command.
                const VT100GridAbsCoordRange commandRange = VT100GridAbsCoordRangeFromCoordRange(range, self.cumulativeScrollbackOverflow);
                const VT100GridAbsCoord outputStart = VT100GridAbsCoordMake(self.currentGrid.cursor.x,
                                                                            self.currentGrid.cursor.y + [self.linebuffer numLinesWithWidth:self.currentGrid.size.width] + self.cumulativeScrollbackOverflow);
                DLog(@"FinalTerm:  Make the mark on lastPromptLine %lld (%@) a command mark for command %@",
                     self.lastPromptLine - self.cumulativeScrollbackOverflow, mark, command);
                [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
                    VT100ScreenMark *mark = (VT100ScreenMark *)obj;
                    mark.command = command;
                    mark.commandRange = commandRange;
                    mark.outputStart = outputStart;
                    // If you change this also update -setCommand:startingAt:inMark:
                }];
            } else {
                DLog(@"No mark");
            }
        }
    }
    id<VT100RemoteHostReading> remoteHost = command ? [[self remoteHostOnLine:range.end.y] doppelganger] : nil;
    NSString *workingDirectory = command ? [self workingDirectoryOnLine:range.end.y] : nil;
    if (!command) {
        mark = nil;
    }
    mark = [mark doppelganger];
    // Pause because delegate will change variables.
    __weak __typeof(self) weakSelf = self;
    DLog(@"commandDidEndWithRange: add paused side effect");
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        DLog(@"commandDidEndWithRange: side effect calling screenDidExecuteCommand");
        [delegate screenDidExecuteCommand:command
                                    range:range
                                   onHost:remoteHost
                              inDirectory:workingDirectory
                                     mark:mark];
        DLog(@"commandDidEndWithRange: unpause");
        [unpauser unpause];
    }];
}

- (void)removeInaccessibleIntervalTreeObjects {
    long long lastDeadLocation = self.cumulativeScrollbackOverflow * (self.width + 1);
    if (lastDeadLocation <= 0) {
        return;
    }
    DLog(@"Begin");
    DLog(@"BEFORE: %@", self.markCache);
    [self.markCache eraseUpToLocation:lastDeadLocation - 1];
    DLog(@"AFTER: %@", self.markCache);
    Interval *deadInterval = [Interval intervalWithLocation:0 length:lastDeadLocation + 1];
    for (id<IntervalTreeObject> obj in [self.intervalTree objectsInInterval:deadInterval]) {
        if ([obj.entry.interval limit] <= lastDeadLocation) {
            DLog(@"remove innaccessible objects: %@", obj);
            const BOOL removed = [self removeObjectFromIntervalTree:obj];
            assert(removed);
        }
    }
    DLog(@"End");
}

- (iTermBlockMark *)mutableBlockMarkWithID:(NSString *)blockID {
    return (iTermBlockMark *)[super blockMarkWithID:blockID];
}

#pragma mark - Shell Integration

- (NSDictionary *)promptStateDictionary {
    return _promptStateMachine.dictionaryValue;
}

- (void)assignCurrentCommandEndDate {
    id<VT100ScreenMarkReading> screenMark = self.lastCommandMark;
    NSDate *now = [NSDate date];
    if (screenMark.command != nil && !screenMark.endDate) {
        [self.mutableIntervalTree mutateObject:screenMark block:^(id<IntervalTreeObject> _Nonnull obj) {
            ((VT100ScreenMark *)obj).endDate = now;
        }];
    }
}

- (id<iTermMark>)addMarkOnLine:(int)line ofClass:(Class)markClass {
    return [self addMarkOnLine:line column:-1 ofClass:markClass];
}

- (id<iTermMark>)addMarkOnLine:(int)line column:(int)column ofClass:(Class)markClass {
    DLog(@"addMarkOnLine:%@ ofClass:%@", @(line), markClass);
    id<iTermMark> newMark = [self addMarkStartingAtAbsoluteLine:self.cumulativeScrollbackOverflow + line
                                                         column:column
                                                        oneLine:column < 0
                                                        ofClass:markClass];
    if (_alertOnNextMark) {
        _alertOnNextMark = NO;
        [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
            [delegate screenDidAddMark:newMark
                                 alert:YES
                            completion:^{ [unpauser unpause]; }];
        }];
    } else {
        [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenDidAddMark:newMark alert:NO completion:^{}];
        }];
    }
    return newMark;
}

- (void)removeNamedMark:(VT100ScreenMark *)mark {
    VT100GridAbsCoordRange range = [self absCoordRangeForInterval:mark.entry.interval];
    [self.mutableIntervalTree removeObject:mark];
    [self.namedMarks removeObjectsPassingTest:^BOOL(id  _Nullable obj) {
        id<VT100ScreenMarkReading> anObject = obj;
        return anObject == mark;
    }];
    self.namedMarksDirty = YES;
    if (self.markCache[range.end.y] == mark) {
        [self.markCache removeMark:mark onLine:range.end.y];
    }
}

- (void)didUpdatePromptLocation {
    DLog(@"didUpdatePromptLocation %@", self);
    self.shouldExpectPromptMarks = YES;
}

- (VT100ScreenMark *)setPromptStartLine:(int)line detectedByTrigger:(BOOL)detectedByTrigger {
    DLog(@"FinalTerm: prompt started on line %d. Add a mark there. Save it as lastPromptLine.", line);
    // Reset this in case it's taking the "real" shell integration path.
    self.fakePromptDetectedAbsLine = -1;
    const long long lastPromptLine = (long long)line + self.cumulativeScrollbackOverflow;
    self.lastPromptLine = lastPromptLine;
    [self assignCurrentCommandEndDate];
    VT100ScreenMark *mark = (VT100ScreenMark *)[self addMarkOnLine:line ofClass:[VT100ScreenMark class]];
    if (mark) {
        const VT100GridAbsCoordRange promptRange = VT100GridAbsCoordRangeMake(0, lastPromptLine, 0, lastPromptLine);
        const BOOL lineStyle = self.config.useLineStyleMarks;
        [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
            VT100ScreenMark *mark = (VT100ScreenMark *)obj;
            [mark setIsPrompt:YES];
            mark.promptRange = promptRange;
            mark.promptDetectedByTrigger = detectedByTrigger;
            mark.lineStyle = lineStyle;
        }];
    }
    [self didUpdatePromptLocation];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenPromptDidStartAtLine:line];
    }];
    return mark;
}

// Line-style marks need an extra newline injected.
- (int)insertNewlinesBeforeAddingPromptMarkAfterPrompt:(BOOL)afterPrompt {
    if (!self.config.useLineStyleMarks) {
        return 0;
    }
    int count = 0;
    if (!afterPrompt) {
        // The shell may opt to redraw the prompt & command before running it, meaning you
        // get final term codes: ABABCD. Don't want to add a new linefeed if we don't need
        // to.
        if (![self.currentGrid lineIsEmpty:self.currentGrid.cursor.y]) {
            [self appendCarriageReturnLineFeed];
            count += 1;
        }
    }

    // Make room for the horizontal line above the line with the mark.
    [self appendCarriageReturnLineFeed];
    count += 1;
    return count;
}

- (VT100ScreenMark *)promptDidStartAt:(VT100GridAbsCoord)initialCoord
                         wasInCommand:(BOOL)wasInCommand
                    detectedByTrigger:(BOOL)detectedByTrigger {
    DLog(@"FinalTerm: promptDidStartAt");
    VT100GridAbsCoord coord = initialCoord;
    BOOL didAnything = NO;
    if (initialCoord.x > 0 && self.config.shouldPlacePromptAtFirstColumn) {
        [self appendCarriageReturnLineFeed];
        coord.x = 0;
        coord.y += 1;
        didAnything = YES;
    }
    if (!wasInCommand) {
        didAnything = YES;
        const int newlines = [self insertNewlinesBeforeAddingPromptMarkAfterPrompt:NO];
        if (newlines) {
            coord.x = 0;
            coord.y += newlines;
        }
    }
    if (!didAnything &&
        !detectedByTrigger &&
        VT100GridAbsCoordEquals(self.currentPromptRange.start, coord)) {
        // Some shells will redraw the prompt including shell integration marks on every keystroke.
        // We want to avoid running a side effect in that case because it is very slow.
        // Issue 10963.
        DLog(@"Re-setting prompt mark. Short circuit.");
        return nil;
    }
    self.shellIntegrationInstalled = YES;

    self.lastCommandOutputRange = VT100GridAbsCoordRangeMake(self.startOfRunningCommandOutput.x,
                                                             self.startOfRunningCommandOutput.y,
                                                             coord.x,
                                                             coord.y);
    self.currentPromptRange = VT100GridAbsCoordRangeMake(coord.x,
                                                         coord.y,
                                                         coord.x,
                                                         coord.y);

    // FinalTerm uses this to define the start of a collapsible region. That would be a nightmare
    // to add to iTerm, and our answer to this is marks, which already existed anyway.
    VT100ScreenMark *mark = [self setPromptStartLine:self.numberOfScrollbackLines + self.cursorY - 1
                                   detectedByTrigger:detectedByTrigger];
    if ([iTermAdvancedSettingsModel resetSGROnPrompt]) {
        [self.terminal resetGraphicRendition];
    }
    return mark;
}

- (void)commandRangeDidChange {
    [self assertOnMutationThread];

    const VT100GridCoordRange current = self.commandRange;
    DLog(@"FinalTerm: command changed %@ -> %@",
         VT100GridCoordRangeDescription(_previousCommandRange),
         VT100GridCoordRangeDescription(current));
    _previousCommandRange = current;
    const BOOL haveCommand = current.start.x >= 0 && [self haveCommandInRange:current];
    const BOOL atPrompt = current.start.x >= 0;

    if (haveCommand) {
        id<VT100ScreenMarkReading> mark = [self markOnLine:self.lastPromptLine - self.cumulativeScrollbackOverflow];
        const VT100GridAbsCoordRange commandRange = VT100GridAbsCoordRangeFromCoordRange(current, self.cumulativeScrollbackOverflow);
        const BOOL hadCommand = self.hadCommand;
        const VT100GridAbsCoordRange promptRange = VT100GridAbsCoordRangeMake(0,
                                                                              self.lastPromptLine,
                                                                              current.start.x,
                                                                              mark.commandRange.end.y);
        if (mark) {
            [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
                VT100ScreenMark *mark = (VT100ScreenMark *)obj;
                mark.commandRange = commandRange;
                if (!hadCommand) {
                    mark.promptRange = promptRange;
                }
            }];
        }
    }
    NSString *command = haveCommand ? [self commandInRange:current] : @"";

    __weak __typeof(self) weakSelf = self;
    [_commandRangeChangeJoiner setNeedsUpdateWithBlock:^{
        // This runs as a side-effect
        assert([NSThread isMainThread]);
        [weakSelf performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [weakSelf notifyDelegateOfCommandChange:command
                                           atPrompt:atPrompt
                                        haveCommand:haveCommand
                                sideEffectPerformer:weakSelf.sideEffectPerformer
                                           delegate:delegate];
        }];
    }];
}

- (void)notifyDelegateOfCommandChange:(NSString *)command
                             atPrompt:(BOOL)atPrompt
                          haveCommand:(BOOL)haveCommand
                  sideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)sideEffectPerformer
                             delegate:(id<VT100ScreenDelegate>)delegate {
    [delegate screenCommandDidChangeTo:command
                              atPrompt:atPrompt
                            hadCommand:self.hadCommand
                           haveCommand:haveCommand];
    self.hadCommand = haveCommand;
}

// Adds a working directory mark at the given line.
//
// nil token means it was "strongly" pushed (e.g., CurrentDir=) and you oughtn't poll.
// You can also get a "weak" push - window title OSC is pushed = YES, token != nil.
//
// non-pushed means we polled for the working directory sua sponte. This is considered poor quality
// because it's quite spammy - every time you press enter, for example - and it shoul dhave
// minimal side effects.
//
// pushed means it's a higher confidence update. The directory must be pushed to be remote, but
// that alone is not sufficient evidence that it is remote. Pushed directories will update the
// recently used directories and will change the current remote host to the remote host on `line`.
- (void)setWorkingDirectory:(NSString *)workingDirectory
                  onAbsLine:(long long)absLine
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken>)token {
    DLog(@"%p: setWorkingDirectory:%@ onLine:%lld token:%@", self, workingDirectory, absLine, token);
    const long long bigLine = MAX(0, absLine - self.cumulativeScrollbackOverflow);
    if (bigLine >= INT_MAX) {
        DLog(@"suspiciously large line %@ from absLine %@ cumulative %@", @(bigLine), @(absLine), @(self.cumulativeScrollbackOverflow));
        return;
    }
    const int line = bigLine;
    if (token && !workingDirectory) {
        __weak __typeof(self) weakSelf = self;
        DLog(@"%p: Performing async working directory fetch for token %@", self, token);
        dispatch_queue_t queue = _queue;
        [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenGetWorkingDirectoryWithCompletion:^(NSString *path) {
                DLog(@"%p: Async update got %@ for token %@", weakSelf, path, token);
                if (path) {
                    dispatch_async(queue, ^{
                        [weakSelf setWorkingDirectory:path onAbsLine:absLine pushed:pushed token:token];
                    });
                }
            }];
        }];
        return;
    }

    DLog(@"%p: Set finished working directory token to %@", self, token);
    if (workingDirectory.length) {
        DLog(@"Changing working directory to %@", workingDirectory);
        VT100WorkingDirectory *workingDirectoryObj = [[VT100WorkingDirectory alloc] initWithDirectory:workingDirectory];

        id<VT100WorkingDirectoryReading> previousWorkingDirectory =
        (id<VT100WorkingDirectoryReading>)[self objectOnOrBeforeLine:line
                                                             ofClass:[VT100WorkingDirectory class]];
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
            DLog(@"setWorkingDirectory - remove %@", previousWorkingDirectory);
            const BOOL removed = [self.mutableIntervalTree removeObject:(VT100WorkingDirectory *)previousWorkingDirectory];
            assert(removed);
            range.end = VT100GridCoordMake(self.width, line);
            DLog(@"Extending the previous directory to %@", VT100GridCoordRangeDescription(range));
            DLog(@"setWorkingDirectory (1): %@", previousWorkingDirectory);
            Interval *interval = [self intervalForGridCoordRange:range];
            [self.mutableIntervalTree addObject:(VT100WorkingDirectory *)previousWorkingDirectory withInterval:interval];
        } else {
            VT100GridCoordRange range;
            range = VT100GridCoordRangeMake(self.currentGrid.cursorX, line, self.width, line);
            DLog(@"Set range of %@ to %@", workingDirectory, VT100GridCoordRangeDescription(range));
            DLog(@"setWorkingDirectory (2): %@", workingDirectoryObj);
            [self.mutableIntervalTree addObject:workingDirectoryObj
                                   withInterval:[self intervalForGridCoordRange:range]];
        }
    }
    id<VT100RemoteHostReading> remoteHost = [[self remoteHostOnLine:line] doppelganger];
    VT100ScreenWorkingDirectoryPushType pushType;
    if (!pushed) {
        pushType = VT100ScreenWorkingDirectoryPushTypePull;
    } else if (token == nil) {
        pushType = VT100ScreenWorkingDirectoryPushTypeStrongPush;
    } else {
        pushType = VT100ScreenWorkingDirectoryPushTypeWeakPush;
    }
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        const BOOL accepted = !token || [token commit];
        [delegate screenLogWorkingDirectoryOnAbsoluteLine:absLine
                                               remoteHost:remoteHost
                                            withDirectory:workingDirectory
                                                 pushType:pushType
                                                 accepted:accepted];
    }];
}

- (void)currentDirectoryReallyDidChangeTo:(NSString *)dir
                                onAbsLine:(long long)cursorAbsLine
                               completion:(void (^)(void))completion {
    DLog(@"currentDirectoryReallyDidChangeTo:%@ onAbsLine:%@", dir, @(cursorAbsLine));
    BOOL willChange = ![dir isEqualToString:[self workingDirectoryOnLine:cursorAbsLine - self.cumulativeScrollbackOverflow]];
    [self setWorkingDirectory:dir
                    onAbsLine:cursorAbsLine
                       pushed:YES
                        token:nil];
    if (willChange) {
        int line = [self numberOfScrollbackLines] + self.cursorY;
        id<VT100RemoteHostReading> remoteHost = [[self remoteHostOnLine:line] doppelganger];
        dispatch_queue_t queue = _queue;
        // Use an unmanaged side effect because APS might change the profile which would cause it
        // to call sync. Running side-effects happens from sync. Reentrant syncs are too hard to
        // understand. This should make the profile change behave like it was the session's idea
        // from "out of the blue" rather than originated here.
        // If you get here from a trigger, the profile change will happen after remaining triggers
        // run but before side-effects they add.
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate> delegate,
                                             iTermTokenExecutorUnpauser *unpauser) {
            [delegate screenCurrentDirectoryDidChangeTo:dir remoteHost:remoteHost];
            dispatch_async(queue, ^{
                completion();
                [unpauser unpause];
            });
        }];
    } else {
        completion();
    }
}

- (void)currentDirectoryDidChangeTo:(NSString *)dir
                         completion:(void (^)(void))completion {
    DLog(@"%p: currentDirectoryDidChangeTo:%@", self, dir);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetPreferredProxyIcon:nil]; // Clear current proxy icon if exists.
    }];

    const int cursorLine = self.numberOfLines - self.height + self.currentGrid.cursorY;
    const long long cursorAbsLine = self.cumulativeScrollbackOverflow + cursorLine;
    if (dir.length) {
        [self currentDirectoryReallyDidChangeTo:dir onAbsLine:cursorAbsLine completion:completion];
        return;
    }

    // Go fetch the working directory and then update it.
    __weak __typeof(self) weakSelf = self;
    id<iTermOrderedToken> token = [self.currentDirectoryDidChangeOrderEnforcer newToken];
    DLog(@"Fetching directory asynchronously with token %@", token);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenGetWorkingDirectoryWithCompletion:^(NSString *workingDirectory) {
            DLog(@"For token %@, the working directory is %@", token, workingDirectory);
            if (![token commit]) {
                return;
            }
            [weakSelf performBlockAsynchronously:^(VT100Terminal * _Nonnull terminal,
                                                   VT100ScreenMutableState * _Nonnull mutableState,
                                                   id<VT100ScreenDelegate>  _Nonnull delegate) {
                [mutableState currentDirectoryReallyDidChangeTo:workingDirectory
                                                      onAbsLine:cursorAbsLine
                                                     completion:completion];
            }];
        }];
    }];
}

- (void)setRemoteHostFromString:(NSString *)unsafeRemoteHost {
    DLog(@"Set remote host to %@ %@", unsafeRemoteHost, self);
    // Search backwards because Windows UPN format includes an @ in the user name. I don't think hostnames would ever have an @ sign.
    NSCharacterSet *controlCharacters = [NSCharacterSet controlCharacterSet];
    NSString *remoteHost = [[unsafeRemoteHost componentsSeparatedByCharactersInSet:controlCharacters] componentsJoinedByString:@""];
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

    [self setHost:host user:user ssh:NO completion:^{}];
}

- (void)setHost:(NSString *)host
           user:(NSString *)user
            ssh:(BOOL)ssh  // Due to ssh integration?
     completion:(void (^)(void))completion {
    DLog(@"setHost:%@ user:%@ %@", host, user, self);
    id<VT100RemoteHostReading> currentHost = [self remoteHostOnLine:self.numberOfLines];
    if (!host || !user) {
        // A trigger can set the host and user alone. If remoteHost looks like example.com or
        // user@, then preserve the previous host/user. Also ensure neither value is nil; the
        // empty string will stand in for a real value if necessary.
        id<VT100RemoteHostReading> lastRemoteHost = [self lastRemoteHost];
        if (!host) {
            host = [lastRemoteHost.hostname copy] ?: @"";
        }
        if (!user) {
            user = [lastRemoteHost.username copy] ?: @"";
        }
    }

    const int cursorLine = self.numberOfLines - self.height + self.currentGrid.cursorY;
    id<VT100RemoteHostReading> remoteHostObj = [[self setRemoteHost:host user:user onLine:cursorLine] doppelganger];

    if (![remoteHostObj isEqualToRemoteHost:currentHost]) {
        const int line = [self numberOfScrollbackLines] + self.cursorY;
        NSString *pwd = [self workingDirectoryOnLine:line];
        dispatch_queue_t queue = _queue;
        // Unmanaged because this can make APS change profile.
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate, iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            [delegate screenCurrentHostDidChange:remoteHostObj pwd:pwd ssh:ssh];
            dispatch_async(queue, ^{
                completion();
                [unpauser unpause];
            });
        }];
    } else {
        completion();
    }
}

- (id<VT100RemoteHostReading>)setRemoteHost:(NSString *)host user:(NSString *)user onLine:(int)line {
    VT100RemoteHost *remoteHostObj = [[VT100RemoteHost alloc] initWithUsername:user hostname:host];
    VT100GridCoordRange range = VT100GridCoordRangeMake(0, line, self.width, line);
    DLog(@"setRemoteHost:%@", remoteHostObj);
    [self.mutableIntervalTree addObject:remoteHostObj
                           withInterval:[self intervalForGridCoordRange:range]];
    return remoteHostObj;
}

- (void)setCoordinateOfCommandStart:(VT100GridAbsCoord)coord {
    self.commandStartCoord = coord;
    [self didUpdatePromptLocation];
    [self commandRangeDidChange];
}

- (void)saveCursorLine {
    const int scrollbackLines = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    [self addMarkOnLine:scrollbackLines + self.currentGrid.cursor.y
                ofClass:[VT100ScreenMark class]];
}

- (void)setReturnCodeOfLastCommand:(int)returnCode {
    DLog(@"FinalTerm: terminalReturnCodeOfLastCommandWas:%d", returnCode);
    id<VT100ScreenMarkReading> mark = self.lastCommandMark;
    id<VT100ScreenMarkReading> doppelganger = mark.doppelganger;
    DLog(@"Set return code for mark %@ to %@", mark, @(returnCode));
    if (mark) {
        DLog(@"FinalTerm: setting code on mark %@", mark);
        const NSInteger line = [self coordRangeForInterval:mark.entry.interval].start.y + self.cumulativeScrollbackOverflow;
        const iTermIntervalTreeObjectType originalType = iTermIntervalTreeObjectTypeForObject(mark);
        [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
            ((VT100ScreenMark *)obj).code = returnCode;
        }];
        const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(mark);
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidRemoveObjectOfType:originalType
                                                 onLine:line];
            [observer intervalTreeDidAddObjectOfType:type
                                              onLine:line];
        }];
        id<VT100RemoteHostReading> remoteHost = [[self remoteHostOnLine:self.numberOfLines] doppelganger];
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenDidUpdateReturnCodeForMark:doppelganger
                                            remoteHost:remoteHost];
        }];
    } else {
        DLog(@"No last command mark found.");
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenCommandDidExitWithCode:returnCode mark:doppelganger];
    }];
}

- (NSArray<VT100ScreenMark *> *)promptMarksBelowLine:(int)line {
    DLog(@"Search for all marks below line %d", line);
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, line, 0, line)];
    NSEnumerator *enumerator = [self.intervalTree forwardLimitEnumeratorAt:interval.location];
    NSMutableArray<VT100ScreenMark *> *marks = [NSMutableArray array];
    NSArray<VT100ScreenMark *> *objects = [enumerator nextObject];
    while (objects) {
        NSArray<VT100ScreenMark *> *screenMarks = [objects objectsOfClasses:@[ [VT100ScreenMark class]]];
        NSArray<VT100ScreenMark *> *promptMarks = [screenMarks filteredArrayUsingBlock:^BOOL(VT100ScreenMark *mark) {
            return mark.isPrompt;
        }];
        [marks addObjectsFromArray:promptMarks];
        objects = [enumerator nextObject];
    }
    DLog(@"Found %@ prompt marks", @(objects.count));
    return marks;
}

- (void)removePromptMarksBelowLine:(int)line {
    DLog(@"removePromptMarksBelowLine:%d", line);
    [[self promptMarksBelowLine:line] enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        DLog(@"remove %@", obj);
        if (obj == self.lastCommandMark) {
            DLog(@"This was the last command mark");
            self.lastCommandMark = nil;
        }
        const BOOL removed = [self removeObjectFromIntervalTree:obj];
        assert(removed);
    }];
}

- (void)setCommandStartCoordWithoutSideEffects:(VT100GridAbsCoord)coord {
    self.commandStartCoord = coord;
}

- (void)invalidateCommandStartCoordWithoutSideEffects {
    [self setCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake(-1, -1)];
}

- (void)invalidateCommandStartCoord {
    [self setCoordinateOfCommandStart:VT100GridAbsCoordMake(-1, -1)];
}

// offset is added to intervals before inserting into interval tree.
- (NSArray<id<IntervalTreeObject>> *)moveNotesOnScreenFrom:(IntervalTree *)source
                                                        to:(IntervalTree *)dest
                                                    offset:(long long)offset
                                              screenOrigin:(int)screenOrigin {
    VT100GridCoordRange screenRange =
    VT100GridCoordRangeMake(0,
                            screenOrigin,
                            self.width,
                            screenOrigin + self.height);
    DLog(@"  moveNotes: looking in range %@", VT100GridCoordRangeDescription(screenRange));
    Interval *sourceInterval = [self intervalForGridCoordRange:screenRange];
    self.lastCommandMark = nil;
    NSArray<id<IntervalTreeObject>> *objectsMoved = [source mutableObjectsInInterval:sourceInterval];
    for (id<IntervalTreeObject> obj in objectsMoved) {
        Interval *interval = obj.entry.interval;
        DLog(@"  found note with interval %@. Remove %@", interval, obj);
        const BOOL removed = [source removeObject:obj];
        assert(removed);
        Interval *newInterval = [Interval intervalWithLocation:interval.location + offset
                                                        length:interval.length];
        DLog(@"  new interval is %@", interval);
        [dest addObject:obj withInterval:newInterval];
    }
    return objectsMoved;
}

- (NSArray<iTermTuple<id<IntervalTreeObject>, Interval *> *> *)removeNotesOnScreenFrom:(IntervalTree *)source
                                                                                offset:(long long)offset
                                                                          screenOrigin:(int)screenOrigin {
    VT100GridCoordRange screenRange =
    VT100GridCoordRangeMake(0,
                            screenOrigin,
                            self.width,
                            screenOrigin + self.height);
    DLog(@"  moveNotes: looking in range %@", VT100GridCoordRangeDescription(screenRange));
    Interval *sourceInterval = [self intervalForGridCoordRange:screenRange];
    self.lastCommandMark = nil;
    NSMutableArray<iTermTuple<id<IntervalTreeObject>, Interval *> *> *objects = [NSMutableArray array];
    for (id<IntervalTreeObject> obj in [source objectsInInterval:sourceInterval]) {
        Interval *interval = obj.entry.interval;
        DLog(@"  found note with interval %@. Remove %@", interval, obj);
        const BOOL removed = [source removeObject:obj];
        assert(removed);
        Interval *newInterval = [Interval intervalWithLocation:interval.location + offset
                                                        length:interval.length];
        DLog(@"  new interval is %@", interval);
        [objects addObject:[iTermTuple tupleWithObject:obj andObject:newInterval]];
    }
    return objects;
}

- (void)swapOnscreenIntervalTreeObjects {
    int historyLines = self.numberOfScrollbackLines;
    Interval *origin = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                               historyLines,
                                                                               1,
                                                                               historyLines)];

    DLog(@"- begin swap -");
    DLog(@"moving onscreen notes into savedNotes");
    DLog(@"primary:\n%@", self.mutableIntervalTree);
    // primary -> temp
    NSArray<iTermTuple<id<IntervalTreeObject>, Interval *> *> *formerlyInPrimary =
    [self removeNotesOnScreenFrom:self.mutableIntervalTree
                           offset:-origin.location
                     screenOrigin:self.numberOfScrollbackLines];
    DLog(@"after moving primary -> temp, primary:\n%@", self.mutableIntervalTree);
    DLog(@"after moving primary -> temp, formerlyInPrimary:\n%@", formerlyInPrimary);

    DLog(@"moving onscreen savedNotes into notes");
    // alt -> primary
    DLog(@"saved: %@", self.mutableSavedIntervalTree);
    // Notes in the saved tree have 0 as the top of the mutable screen area. -movesNotes… adds
    // the current cumulative overflow to the screenOrigin, so give it a negative origin to offset
    // that.
    NSArray<id<IntervalTreeObject>> *revealedObjects =
    [self moveNotesOnScreenFrom:self.mutableSavedIntervalTree
                             to:self.mutableIntervalTree
                         offset:origin.location
                   screenOrigin:-self.cumulativeScrollbackOverflow];
    DLog(@"after moving saved to primary, primary:\n%@", self.mutableIntervalTree);
    DLog(@"after moving saved to primary, saved:\n%@", self.mutableSavedIntervalTree);

    [self.mutableSavedIntervalTree removeAllObjects];

    DLog(@"after removing all from saved, saved:\n%@", self.mutableSavedIntervalTree);
    DLog(@"moving formerlyInPrimary -> saved");
    for (iTermTuple<id<IntervalTreeObject>, Interval *> *tuple in formerlyInPrimary) {
        DLog(@"swapOnscreenIntervalTreeObjects: %@", tuple);
        [self.mutableSavedIntervalTree addObject:tuple.firstObject
                                    withInterval:tuple.secondObject];
    }
    DLog(@"after moving temp to saved, saved:\n%@", self.mutableSavedIntervalTree);

    // Let delegate know about changes.
    for (id<IntervalTreeObject> ito in revealedObjects) {
        const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(ito.doppelganger);
        const long long line = [self absCoordRangeForInterval:ito.entry.interval].start.y;
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidUnhideObject:ito.doppelganger
                                           ofType:type
                                           onLine:line];
        }];
    }
    for (iTermTuple<id<IntervalTreeObject>, Interval *> *tuple in formerlyInPrimary) {
        id<IntervalTreeObject> ito = tuple.firstObject;
        const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(ito.doppelganger);
        const long long line = [self absCoordRangeForInterval:ito.entry.interval].start.y;
        id<IntervalTreeImmutableObject> doppelganger = ito.doppelganger;
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidHideObject:doppelganger
                                         ofType:type
                                         onLine:line];
        }];
    }
    DLog(@"- done -");
}

- (void)reloadMarkCache {
    long long totalScrollbackOverflow = self.cumulativeScrollbackOverflow;
    [self.markCache removeAll];
    for (id<IntervalTreeObject> obj in [self.intervalTree allObjects]) {
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
            id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)obj;
            self.markCache[totalScrollbackOverflow + range.end.y] = mark;
        }
    }
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidReset];
    }];
}

- (void)setWorkingDirectoryFromURLString:(NSString *)URLString {
    DLog(@"terminalSetWorkingDirectoryURL:%@", URLString);

    if (![iTermAdvancedSettingsModel acceptOSC7]) {
        return;
    }
    NSURL *URL = [NSURL URLWithString:URLString];
    if (!URL || URLString.length == 0) {
        return;
    }
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:URL resolvingAgainstBaseURL:NO];
    NSString *host = components.host;
    NSString *user = components.user;
    NSString *path = components.path;

    if (host || user) {
        __weak __typeof(self) weakSelf = self;
        [self setHost:host user:user ssh:NO completion:^{
            [weakSelf setPathFromURL:path];
        }];
    } else {
        [self setPathFromURL:path];
    }
}

- (void)setPathFromURL:(NSString *)path {
    __weak __typeof(self) weakSelf = self;
    [self currentDirectoryDidChangeTo:path completion:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf insertNewlinesBeforeAddingPromptMarkAfterPrompt:YES];
        [strongSelf setPromptStartLine:strongSelf.numberOfScrollbackLines + strongSelf.cursorY - 1
                     detectedByTrigger:NO];
    }];
}

- (void)commandWasAborted {
    id<VT100ScreenMarkReading> screenMark = [self lastPromptMark];
    BOOL hadMark = NO;
    int line = 0;
    VT100GridCoordRange outputRange = { 0 };
    NSString *command = nil;
    if (screenMark) {
        hadMark = YES;
        const VT100GridRange lineRange = [self lineNumberRangeOfInterval:screenMark.entry.interval];
        line = lineRange.location;
        outputRange = [self rangeOfOutputForCommandMark:screenMark];
        command = [[[self contentInRange:screenMark.commandRange] mapWithBlock:^id _Nullable(ScreenCharArray * _Nonnull sca) {
            return sca.stringValue;
        }] componentsJoinedByString:@"\n"];

        DLog(@"Removing last command mark %@", screenMark);
        const NSInteger line = [self coordRangeForInterval:screenMark.entry.interval].start.y + self.cumulativeScrollbackOverflow;
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidRemoveObjectOfType:iTermIntervalTreeObjectTypeForObject(screenMark)
                                                 onLine:line];
        }];
        DLog(@"Command was aborted. Remove %@", screenMark);
        [self.mutableIntervalTree removeObject:(VT100ScreenMark *)screenMark];
        [self.mutableSavedIntervalTree removeObject:(VT100ScreenMark *)screenMark];
    }
    [self invalidateCommandStartCoordWithoutSideEffects];
    [self didUpdatePromptLocation];
    [self commandDidEndWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
    if (hadMark) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenCommandDidAbortOnLine:line
                                      outputRange:outputRange
                                          command:command];
        }];
    }
}

- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord {
    [self commandDidStartAt:VT100GridAbsCoordMake(coord.x,
                                                  coord.y + self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow)];
}

- (void)commandDidStartAt:(VT100GridAbsCoord)coord {
    [self setCoordinateOfCommandStart:coord];
}

// End of command prompt, will start accepting command to run as the user types at the prompt.
- (void)commandDidStart {
    VT100GridCoord coord = self.currentGrid.cursor;
    [self promptEndedAndCommandStartedAt:coord shortCircuitDups:YES];
}

- (void)didSendCommand {
    DLog(@"didSendCommand (trigger-detected prompt path)");
    [self commandDidEnd];
}

// FTCS B
- (void)promptEndedAndCommandStartedAt:(VT100GridCoord)commandStartLocation
                      shortCircuitDups:(BOOL)shortCircuitDups {
    DLog(@"FinalTerm: terminalCommandDidStart");

    VT100GridAbsCoordRange promptRange = VT100GridAbsCoordRangeMake(self.currentPromptRange.start.x,
                                                                    self.currentPromptRange.start.y,
                                                                    commandStartLocation.x,
                                                                    commandStartLocation.y + self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow);
    if (shortCircuitDups &&
        VT100GridAbsCoordRangeEquals(self.currentPromptRange, promptRange)) {
        // See note in promptDidStartAt:wasInCommand:detectedByTrigger:.
        DLog(@"Re-setting end-of-prompt. Short circuit.");
        return;
    }
    NSArray<ScreenCharArray *> *promptText = [[self contentInRange:promptRange] filteredArrayUsingBlock:^BOOL(ScreenCharArray *sca) {
        return [[sca.stringValue stringByTrimmingTrailingWhitespace] length] > 0;
    }];
    self.currentPromptRange = promptRange;
    [self commandDidStartAtScreenCoord:commandStartLocation];
    const int line = self.numberOfScrollbackLines + commandStartLocation.y;
    id<VT100ScreenMarkReading> mark = [[self updatePromptMarkRangesForPromptEndingOnLine:line
                                                                              promptText:promptText] doppelganger];
    [_promptStateMachine didCapturePrompt:promptText];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenPromptDidEndWithMark:mark];
    }];
}

- (NSArray<ScreenCharArray *> *)contentInRange:(VT100GridAbsCoordRange)range {
    NSMutableArray<ScreenCharArray *> *result = [NSMutableArray array];
    const long long offset = self.cumulativeScrollbackOverflow;
    for (long long y = range.start.y; y <= range.end.y; y++) {
        if (y < offset) {
            continue;
        }
        ScreenCharArray *sca = [self screenCharArrayForLine:y - offset];
        [sca makeSafe];
        if (y == range.end.y) {
            sca = [sca screenCharArrayByRemovingLast:sca.length - range.end.x];
        }
        if (y == range.start.y) {
            sca = [sca screenCharArrayByRemovingFirst:range.start.x];
        }

        [result addObject:sca];
    }
    return result;
}

- (id<VT100ScreenMarkReading>)updatePromptMarkRangesForPromptEndingOnLine:(int)line
                                                               promptText:(NSArray<ScreenCharArray *> *)promptText {
    id<VT100ScreenMarkReading> mark = [self lastPromptMark];
    if (!mark) {
        return nil;
    }
    const int x = self.currentGrid.cursor.x;
    const long long y = (long long)line + self.cumulativeScrollbackOverflow;

    [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
        VT100ScreenMark *mark = (VT100ScreenMark *)obj;
        mark.promptRange = VT100GridAbsCoordRangeMake(mark.promptRange.start.x,
                                                      mark.promptRange.end.y,
                                                      x,
                                                      y);
        mark.commandRange = VT100GridAbsCoordRangeMake(x, y, x, y);
        mark.promptText = promptText;
    }];
    return mark;
}

- (void)commandDidEnd {
    DLog(@"FinalTerm: terminalCommandDidEnd");
    self.currentPromptRange = VT100GridAbsCoordRangeMake(0, 0, 0, 0);

    [self commandDidEndAtAbsCoord:VT100GridAbsCoordMake(self.currentGrid.cursor.x,
                                                        self.currentGrid.cursor.y + self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow)];
}

- (BOOL)commandDidEndAtAbsCoord:(VT100GridAbsCoord)coord {
    DLog(@"commandDidEndAtAbsCoord self.commandStartCoord.x=%d", self.commandStartCoord.x);
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandDidEndWithRange:self.commandRange];
        [self invalidateCommandStartCoord];
        self.startOfRunningCommandOutput = coord;
        return YES;
    }
    return NO;
}

- (void)composerWillSendCommand:(NSString *)command 
                     startingAt:(VT100GridAbsCoord)startAbsCoord {
    [_promptStateMachine willSendCommand];
    id<VT100ScreenMarkReading> mark = self.lastPromptMark;
    if (!mark) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
        VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:obj];
        if (!screenMark) {
            return;
        }
        [weakSelf setCommand:command startingAt:startAbsCoord inMark:screenMark];
    }];
}

// This code path is taken when using the auto-composer.
- (void)setCommand:(NSString *)command
        startingAt:(VT100GridAbsCoord)startAbsCoord
            inMark:(VT100ScreenMark *)screenMark {
    screenMark.command = [command stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    const int width = self.width;

    const int len = [self lengthOfStringInCells:command];
    screenMark.commandRange = VT100GridAbsCoordRangeMake(startAbsCoord.x,
                                                         startAbsCoord.y,
                                                         (startAbsCoord.x + len) % width,
                                                         startAbsCoord.y + (startAbsCoord.x + len) / width);
    screenMark.outputStart = VT100GridAbsCoordMake(0, screenMark.commandRange.end.y + 1);
    // If you modify this also update -commandDidEndWithRange:
}

- (int)lengthOfStringInCells:(NSString *)string {
    screen_char_t *buf = iTermCalloc(string.length * 3, sizeof(screen_char_t));
    int len = string.length;
    BOOL dwc = NO;
    StringToScreenChars(string,
                        buf,
                        (screen_char_t){0},
                        (screen_char_t){0},
                        &len,
                        self.config.treatAmbiguousCharsAsDoubleWidth,
                        NULL,
                        &dwc,
                        self.config.normalization,
                        self.config.unicodeVersion,
                        self.terminal.softAlternateScreenMode);
    free(buf);
    return len;
}

- (void)didInferEndOfCommand {
    DLog(@"Inferring end of command");
    VT100GridAbsCoord coord;
    coord.x = 0;
    coord.y = (self.currentGrid.cursor.y +
               [self.linebuffer numLinesWithWidth:self.currentGrid.size.width]
               + self.cumulativeScrollbackOverflow);
    if (self.currentGrid.cursorX > 0) {
        // End of command was detected before the newline came in. This is the normal case.
        coord.y += 1;
    }
    if ([self commandDidEndAtAbsCoord:coord]) {
        self.fakePromptDetectedAbsLine = -2;
    } else {
        // Screen didn't think we were in a command.
        self.fakePromptDetectedAbsLine = -1;
    }
}

- (void)setFakePromptDetectedAbsLine:(long long)fakePromptDetectedAbsLine {
    DLog(@"fakePromptDetectedAbsLine <- %@\n%@", @(fakePromptDetectedAbsLine), [NSThread callStackSymbols]);
    [super setFakePromptDetectedAbsLine:fakePromptDetectedAbsLine];
}

- (void)incrementClearCountForCommandMark:(id<VT100ScreenMarkReading>)mark {
    if (![self.intervalTree containsObject:mark]) {
        return;
    }
    [self.mutableIntervalTree mutateObject:mark block:^(id<IntervalTreeObject> _Nonnull obj) {
        VT100ScreenMark *mark = (VT100ScreenMark *)obj;
        [mark incrementClearCount];
    }];
}

#pragma mark - Annotations

- (id<PTYAnnotationReading>)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange {
    VT100GridCoordRange range = VT100GridCoordRangeFromAbsCoordRange(absRange,
                                                                     self.cumulativeScrollbackOverflow);
    if (range.start.x < 0) {
        return nil;
    }
    PTYAnnotation *annotation = [[PTYAnnotation alloc] init];
    annotation.stringValue = text;
    [self addAnnotation:annotation inRange:range focus:NO visible:YES];
    return annotation;
}


- (void)removeAnnotation:(id<PTYAnnotationReading>)annotation {
    if ([self.intervalTree containsObject:annotation]) {
        self.lastCommandMark = nil;
        const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(annotation);
        const long long absLine = [self coordRangeForInterval:annotation.entry.interval].start.y + self.cumulativeScrollbackOverflow;
        DLog(@"removeannotation %@", annotation);
        const BOOL removed = [self.mutableIntervalTree removeObject:(PTYAnnotation *)annotation];
        assert(removed);
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidRemoveObjectOfType:type
                                                 onLine:absLine];
        }];
    } else if ([self.savedIntervalTree containsObject:annotation]) {
        self.lastCommandMark = nil;
        const BOOL removed = [self.mutableSavedIntervalTree removeObject:(PTYAnnotation *)annotation];
        assert(removed);
    }
    [self setNeedsRedraw];
}

- (void)addAnnotation:(PTYAnnotation *)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus
              visible:(BOOL)visible {
    annotation.delegate = self;
    DLog(@"addAnnotation:inRange:focus:");
    [self.mutableIntervalTree addObject:annotation withInterval:[self intervalForGridCoordRange:range]];
    [self.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
    id<PTYAnnotationReading> doppelganger = annotation.doppelganger;
    const long long line = range.start.y + self.cumulativeScrollbackOverflow;
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeAnnotation
                                          onLine:line];
    }];
    // Because -refresh gets called.
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenDidAddNote:doppelganger focus:focus visible:visible];
        [unpauser unpause];
    }];
}

- (void)setStringValueOfAnnotation:(id<PTYAnnotationReading>)annotation to:(NSString *)stringValue {
    DLog(@"Set progenitor %@ to %@", annotation, stringValue);
    if (!annotation) {
        return;
    }
    [self.mutableIntervalTree mutateObject:annotation block:^(id<IntervalTreeObject> _Nonnull obj) {
        PTYAnnotation *mutableAnnotation = (PTYAnnotation *)obj;
        DLog(@"%@.stringValue=%@", mutableAnnotation, stringValue);
        [mutableAnnotation setStringValueWithoutSideEffects:stringValue];
    }];
}

#pragma mark - Portholes

- (void)replaceMark:(iTermMark *)mark withLines:(NSArray<ScreenCharArray *> *)lines {
    const VT100GridAbsCoordRange range = [self absCoordRangeForInterval:mark.entry.interval];
    if (range.end.y < self.totalScrollbackOverflow) {
        // Nothing to do - it has already scrolled off to the great beyond.
        return;
    }
    NSArray<ScreenCharArray *> *trimmed = lines;
    if (range.start.y <= self.totalScrollbackOverflow) {
        VT100GridCoordRange relativeRange = VT100GridCoordRangeFromAbsCoordRange(range, self.totalScrollbackOverflow);
        trimmed = [self linesByTruncatingLines:lines toWrappedHeight:relativeRange.end.y - relativeRange.start.y + 1];
    }
    [self replaceRange:range withLines:trimmed];
    [self.mutableIntervalTree removeObject:mark];
}

- (NSArray<ScreenCharArray *> *)linesByTruncatingLines:(NSArray<ScreenCharArray *> *)originalLines
                                       toWrappedHeight:(int)desiredHeight {
    LineBuffer *temp = [[LineBuffer alloc] init];
    const int width = self.width;
    for (ScreenCharArray *sca in originalLines) {
        [temp appendScreenCharArray:sca width:width];
    }
    [temp setMaxLines:desiredHeight];
    [temp dropExcessLinesWithWidth:width];

    NSMutableArray<ScreenCharArray *> *result = [NSMutableArray array];
    [temp enumerateLinesInRange:NSMakeRange(0, [temp numLinesWithWidth:width])
                          width:width block:^(int i,
                                              ScreenCharArray * _Nonnull sca,
                                              iTermImmutableMetadata metadata,
                                              BOOL * _Nonnull stop) {
        [result addObject:[sca copy]];
    }];
    return result;
}

- (void)replaceRange:(VT100GridAbsCoordRange)absRange
        withPorthole:(id<Porthole>)porthole
            ofHeight:(int)numLines {
    NSMutableArray<ScreenCharArray *> *lines = [NSMutableArray array];
    for (int i = 0; i < numLines; i++) {
        [lines addObject:[[ScreenCharArray alloc] init]];
    }
    const VT100GridAbsCoordRange markRange = [self replaceRange:absRange withLines:lines];
    if (!VT100GridAbsCoordRangeIsValid(markRange)) {
        return;
    }
    Interval *interval = [self intervalForGridAbsCoordRange:markRange];
    PortholeMark *mark = [[PortholeMark alloc] init:porthole.uniqueIdentifier];
    [self.mutableIntervalTree addObject:mark withInterval:interval];
    [self addSideEffect:^(id<VT100ScreenDelegate> _Nonnull delegate) {
        [delegate screenDidAddPorthole:porthole];
    }];
}

- (void)changeHeightOfMark:(iTermMark *)mark to:(int)newHeight {
    VT100GridAbsCoordRange range = [self absCoordRangeForInterval:mark.entry.interval];
    if (range.end.y < self.totalScrollbackOverflow) {
        return;
    }
    VT100GridAbsCoordRange replacementAbsRange = range;
    range.start.y = MAX(self.totalScrollbackOverflow, range.start.y);
    NSMutableArray<ScreenCharArray *> *lines = [NSMutableArray array];

    for (int i = 0; i < newHeight; i++) {
        [lines addObject:[[ScreenCharArray alloc] init]];
    }
    [self replaceRange:range withLines:lines];

    replacementAbsRange.end.y = replacementAbsRange.start.y + newHeight - 1;
    replacementAbsRange.start.y = MAX(self.totalScrollbackOverflow, replacementAbsRange.start.y);
    Interval *interval = [self intervalForGridAbsCoordRange:replacementAbsRange];

    [self.mutableIntervalTree removeObject:mark];
    [self.mutableIntervalTree addObject:mark
                           withInterval:interval];
}

- (VT100GridAbsCoordRange)replaceRange:(VT100GridAbsCoordRange)absRange
                             withLines:(NSArray<ScreenCharArray *> *)replacementLines {
    __block VT100GridAbsCoordRange result;
    [self performBlockWithoutTriggers:^{
        result = [self reallyReplaceRange:absRange withLines:replacementLines];
    }];
    return result;
}

- (VT100GridAbsCoordRange)reallyReplaceRange:(VT100GridAbsCoordRange)absRange
                                   withLines:(NSArray<ScreenCharArray *> *)replacementLines {
    VT100GridCoordRange range = VT100GridCoordRangeFromAbsCoordRange(absRange, self.cumulativeScrollbackOverflow);
    if (range.start.y < 0) {
        // Already scrolled into the dustbin.
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    [self clearTriggerLine];

    const VT100GridSize gridSize = self.currentGrid.size;
    const int originalNumLines = self.numberOfScrollbackLines + gridSize.height;

    // If cursor is inside the range, move it below.
    VT100GridCoord cursorCoord = self.currentGrid.cursor;
    const BOOL cursorOnLastLine = (cursorCoord.y == gridSize.height + 1);
    const int numberOfScrollbackLines = self.numberOfScrollbackLines;
    cursorCoord.y += numberOfScrollbackLines;
    const BOOL rangeIncludesCursor = VT100GridCoordRangeContainsCoord(range, cursorCoord);
    if (rangeIncludesCursor && !cursorOnLastLine) {
        cursorCoord.y = range.end.y + 1;
        self.currentGrid.cursorY = cursorCoord.y - numberOfScrollbackLines;
    }

    const int savedMaxLines = self.linebuffer.maxLines;
    [self.linebuffer setMaxLines:-1];

    // 0 |
    // 1 | linebuffer
    // 2 |               X replacement range
    // 3 )               X
    // 4 ) grid
    // 5 )

    LineBuffer *scratch = [[LineBuffer alloc] init];
    for (ScreenCharArray *sca in replacementLines) {
        [scratch appendScreenCharArray:sca width:gridSize.width];
    }
    const int numLines = [scratch numLinesWithWidth:gridSize.width];

    int deltaLines = numLines - (range.end.y - range.start.y + 1);
    const int numberOfLinesUsed = [self.currentGrid numberOfLinesUsed];
    const int numberOfEmptyLines = gridSize.height - numberOfLinesUsed;
    // Elide empty lines to avoid shifting the grid up into the line buffer unnecessarily.
    [self.currentGrid appendLines:gridSize.height - MIN(numberOfEmptyLines, MAX(0, deltaLines))
                     toLineBuffer:self.linebuffer];
    self.linebuffer.partial = NO;

    // 0 |
    // 1 |
    // 2 |               X replacement range
    // 3 | linebuffer    X
    // 4 |
    // 5 |

    LineBuffer *temp = [self.linebuffer copy];
    const int numLinesAfterReplacementRange = [temp numLinesWithWidth:gridSize.width] - range.end.y - (range.end.x == 0 ? 0 : 1);
    [temp setMaxLines:MAX(0, numLinesAfterReplacementRange)];
    [temp dropExcessLinesWithWidth:gridSize.width];

    // 4 | temp
    // 5 |

    [self clearScrollbackBufferFromLine:range.start.y];

    // 0 |
    // 1 | linebuffer

    // Make sure it ends in a hard newline.
    [self.linebuffer setPartial:NO];

    // Add replacement lines.
    VT100GridCoordRange replacementRange = VT100GridCoordRangeMake(0,
                                                            range.start.y,
                                                            gridSize.width - 1,
                                                            range.start.y + numLines - 1);
    const VT100GridAbsCoordRange resultingRange =
    VT100GridAbsCoordRangeFromCoordRange(replacementRange, self.totalScrollbackOverflow);

    [self.linebuffer appendContentsOfLineBuffer:scratch width:gridSize.width includingCursor:NO];

    // 0 |
    // 1 | linebuffer
    // 2 |             (empty)
    // 3 |             (empty)

    [self.linebuffer appendContentsOfLineBuffer:temp width:gridSize.width includingCursor:YES];

    // 0 |
    // 1 | linebuffer
    // 2 |             (empty)
    // 3 |             (empty)
    // 4 |
    // 5 |

    [self.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                to:VT100GridCoordMake(self.currentGrid.size.width - 1,
                                                      self.currentGrid.size.height - 1)
                            toChar:self.currentGrid.defaultChar
                externalAttributes:nil];
    [self.currentGrid restoreScreenFromLineBuffer:self.linebuffer
                                  withDefaultChar:self.currentGrid.defaultChar
                                maxLinesToRestore:gridSize.height];
    [self.currentGrid setAllDirty:YES];
    // 0 |
    // 1 | linebuffer
    // 2 |             (empty)
    // 3 )             (empty)
    // 4 ) grid
    // 5 )

    if (rangeIncludesCursor && cursorOnLastLine) {
        self.currentGrid.cursorY = gridSize.height - 1;
        [self appendLineFeed];
    }

    // Shift interval tree objects under range.start.y down this much.

    const VT100GridCoordRange rangeFromPortholeToEnd =
    VT100GridCoordRangeMake(replacementRange.start.x,
                            replacementRange.start.y,
                            gridSize.width,
                            originalNumLines);
    [self shiftIntervalTreeObjectsInRange:rangeFromPortholeToEnd
                            startingAfter:range.end.y
                              downByLines:deltaLines];

    [self.linebuffer setMaxLines:savedMaxLines];
    if (!self.config.unlimitedScrollback) {
        [self incrementOverflowBy:[self.linebuffer dropExcessLinesWithWidth:gridSize.width]];
    }

    return resultingRange;
}

// If an object starts on or before the line `startingAfter` then its start stays put but its end
// moves (the end always moves). This is useful when inserting lines into the middle of an interval.
// If you just want to shift everything in inputRange down, use a startingAfter of -1.
- (void)shiftIntervalTreeObjectsInRange:(VT100GridCoordRange)inputRange
                          startingAfter:(int)startingAfter
                            downByLines:(int)deltaLines {
    Interval *intervalToMove =
    [self intervalForGridCoordRange:inputRange];

    NSArray<id<IntervalTreeImmutableObject>> *objects =
    [self.intervalTree objectsInInterval:intervalToMove];

    [self.mutableIntervalTree bulkMoveObjects:objects
                                        block:^Interval*(id<IntervalTreeObject> object) {
        VT100GridCoordRange itoRange = [self coordRangeForInterval:object.entry.interval];
        if (itoRange.start.y > startingAfter) {
            itoRange.start.y += deltaLines;
        }
        itoRange.end.y += deltaLines;
        return [self intervalForGridCoordRange:itoRange];
    }];
    NSArray<id<IntervalTreeImmutableObject>> *doppelgangers = [objects mapWithBlock:^id _Nullable(id<IntervalTreeImmutableObject>  _Nonnull anObject) {
        return anObject.doppelganger;
    }];
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidMoveObjects:doppelgangers];
    }];
    [self reloadMarkCache];
}

#pragma mark - URLs

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                URLCode:(unsigned int)code {
    long long lineNumber = absoluteLineNumber - self.cumulativeScrollbackOverflow - self.numberOfScrollbackLines;
    if (lineNumber < 0) {
        return;
    }
    VT100GridRun gridRun = [self.currentGrid gridRunFromRange:range relativeToRow:lineNumber];
    if (gridRun.length > 0) {
        [self linkRun:gridRun withURLCode:code];
    }
}

- (void)linkRun:(VT100GridRun)run
    withURLCode:(unsigned int)code {
    for (NSValue *value in [self.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self.currentGrid setURLCode:code
                          inRectFrom:rect.origin
                                  to:VT100GridRectMax(rect)];
    }
}

- (void)addURLMarkAtLineAfterCursorWithCode:(unsigned int)code {
    long long absLine = (self.cumulativeScrollbackOverflow +
                         self.numberOfScrollbackLines +
                         self.currentGrid.cursor.y + 1);
    iTermURLMark *mark = [[iTermURLMark alloc] initWithCode:code];
    [self addMark:mark onLine:absLine singleLine:YES];
}


#pragma mark - Highlighting

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors {
    long long lineNumber = absoluteLineNumber - self.cumulativeScrollbackOverflow - self.numberOfScrollbackLines;

    VT100GridRun gridRun = [self.currentGrid gridRunFromRange:range relativeToRow:lineNumber];
    DLog(@"Highlight range %@ with colors %@ at lineNumber %@ giving grid run %@",
         NSStringFromRange(range),
         colors,
         @(lineNumber),
         VT100GridRunDescription(gridRun));

    if (gridRun.length > 0) {
        NSColor *foreground = colors[kHighlightForegroundColor];
        NSColor *background = colors[kHighlightBackgroundColor];
        [self highlightRun:gridRun withForegroundColor:foreground backgroundColor:background];
    }
}

// Set the color of prototypechar to all chars between startPoint and endPoint on the screen.
- (void)highlightRun:(VT100GridRun)run
 withForegroundColor:(NSColor *)fgColor
     backgroundColor:(NSColor *)bgColor {
    DLog(@"Really highlight run %@ fg=%@ bg=%@", VT100GridRunDescription(run), fgColor, bgColor);

    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };

    NSColor *genericFgColor = [fgColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    NSColor *genericBgColor = [bgColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];

    if (fgColor) {
        fg.foregroundColor = genericFgColor.redComponent * 255;
        fg.fgBlue = genericFgColor.blueComponent * 255;
        fg.fgGreen = genericFgColor.greenComponent * 255;
        fg.foregroundColorMode = ColorMode24bit;
    } else {
        fg.foregroundColorMode = ColorModeInvalid;
    }

    if (bgColor) {
        bg.backgroundColor = genericBgColor.redComponent * 255;
        bg.bgBlue = genericBgColor.blueComponent * 255;
        bg.bgGreen = genericBgColor.greenComponent * 255;
        bg.backgroundColorMode = ColorMode24bit;
    } else {
        bg.backgroundColorMode = ColorModeInvalid;
    }

    for (NSValue *value in [self.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self.currentGrid setBackgroundColor:bg
                             foregroundColor:fg
                                  inRectFrom:rect.origin
                                          to:VT100GridRectMax(rect)];
    }
}


#pragma mark - Token Execution

// WARNING: This is called on PTYTask's thread.
- (void)threadedReadTask:(char *)buffer length:(int)length {
    // Pass the input stream to the parser.
    [self.terminal.parser putStreamData:buffer length:length];

    // Parse the input stream into an array of tokens.
    CVector vector;
    CVectorCreate(&vector, 100);
    [self.terminal.parser addParsedTokensToVector:&vector];

    if (CVectorCount(&vector) == 0) {
        CVectorDestroy(&vector);
        return;
    }

    [self addTokens:vector length:length highPriority:NO];
}

// WARNING: This is called on PTYTask's thread.
- (void)addTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority {
    [_echoProbe updateEchoProbeStateWithTokenCVector:&vector];
    [_tokenExecutor addTokens:vector length:length highPriority:highPriority];
}

- (void)scheduleTokenExecution {
    [_tokenExecutor schedule];
}

- (void)injectData:(NSData *)data {
    VT100Parser *parser = [[VT100Parser alloc] init];
    parser.encoding = self.terminal.encoding;
    [parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 100);
    [parser addParsedTokensToVector:&vector];
    if (CVectorCount(&vector) == 0) {
        CVectorDestroy(&vector);
        return;
    }
    [self addTokens:vector length:data.length highPriority:YES];
}

#pragma mark - Triggers

- (void)evaluateTriggers:(void (^ NS_NOESCAPE)(PTYTriggerEvaluator *triggerEvaluator))block {
    block(_triggerEvaluator);
    if (_tokenExecutor.isExecutingToken) {
        return;
    }
    [self executePostTriggerActions];
}

- (void)executePostTriggerActions {
    if (_postTriggerActions.count == 0) {
        return;
    }
    NSArray<void (^)(void)> *actions = [_postTriggerActions copy];
    [_postTriggerActions removeAllObjects];
    for (void (^block)(void) in actions) {
        block();
    }
}

- (void)performPeriodicTriggerCheck {
    DLog(@"begin");
    [self evaluateTriggers:^(PTYTriggerEvaluator *triggerEvaluator) {
        [triggerEvaluator checkPartialLineTriggers];
        [triggerEvaluator checkIdempotentTriggersIfAllowed];
    }];
}

- (void)clearTriggerLine {
    [self evaluateTriggers:^(PTYTriggerEvaluator *triggerEvaluator) {
        [triggerEvaluator clearTriggerLine];
    }];
}

- (void)appendStringToTriggerLine:(NSString *)string {
    [self evaluateTriggers:^(PTYTriggerEvaluator *triggerEvaluator) {
        [triggerEvaluator appendStringToTriggerLine:string];
    }];
}

- (BOOL)appendAsciiDataToTriggerLine:(AsciiData *)asciiData {
    if (!_triggerEvaluator.haveTriggersOrExpectations && 
        !self.config.loggingEnabled &&
        _postTriggerActions.count == 0) {
        return YES;
    }
    __block BOOL result = NO;
    [self evaluateTriggers:^(PTYTriggerEvaluator *triggerEvaluator) {
        result = [self reallyAppendAsciiDataToTriggerLine:asciiData
                                         triggerEvaluator:(PTYTriggerEvaluator *)triggerEvaluator];
    }];
    return result;
}

- (BOOL)reallyAppendAsciiDataToTriggerLine:(AsciiData *)asciiData
                          triggerEvaluator:(PTYTriggerEvaluator *)triggerEvaluator {
    if (!_triggerEvaluator.haveTriggersOrExpectations && !self.config.loggingEnabled) {
        // Avoid making the string, which could be slow.
        return YES;
    }
    NSString *string = [_triggerEvaluator appendAsciiDataToCurrentLine:asciiData];
    if (!string) {
        return NO;
    }
    if (self.config.loggingEnabled) {
        const screen_char_t foregroundColorCode = self.terminal.foregroundColorCode;
        const screen_char_t backgroundColorCode = self.terminal.backgroundColorCode;
        const BOOL atPrompt = _promptStateMachine.isAtPrompt;
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenDidAppendStringToCurrentLine:string
                                             isPlainText:YES
                                              foreground:foregroundColorCode
                                              background:backgroundColorCode
                                                atPrompt:atPrompt];
        }];
    }
    return YES;
}

- (void)forceCheckTriggers {
    DLog(@"begin");
    [self evaluateTriggers:^(PTYTriggerEvaluator *triggerEvaluator) {
        [triggerEvaluator forceCheck];
    }];
}

#pragma mark - Color

- (void)loadInitialColorTable {
    [self mutateColorMap:^(iTermColorMap *colorMap) {
        for (int i = 16; i < 256; i++) {
            NSColor *theColor = [NSColor colorForAnsi256ColorIndex:i];
            [colorMap setColor:theColor forKey:kColorMap8bitBase + i];
        }
    }];
}

- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict {
    [self mutateColorMap:^(iTermColorMap *colorMap) {
        [dict enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            if ([obj isKindOfClass:[NSNull class]]) {
                [colorMap setColor:nil forKey:key.intValue];
            } else {
                [colorMap setColor:(NSColor *)obj forKey:key.intValue];
            }
        }];
    }];
}

- (void)setColor:(NSColor *)color forKey:(int)key {
    [self mutateColorMap:^(iTermColorMap *colorMap) {
        [colorMap setColor:color forKey:key];
    }];
}

- (void)restoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    const int limit = MIN(kColorMapNumberOf8BitColors, slot.indexedColors.count);
    NSMutableDictionary<NSNumber *, id> *dict = [NSMutableDictionary dictionary];
    for (int i = 16; i < limit; i++) {
        dict[@(kColorMap8bitBase + i)] = slot.indexedColors[i] ?: [NSNull null];
    }
    [self setColorsFromDictionary:dict];
    // Pause so that HTML logging gets an up-to-date colormap before the next token.
    // Unmanaged because it will set the profile and this avoids reentrant syncs/joined side effects.
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenRestoreColorsFromSlot:slot];
        [unpauser unpause];
    }];
}

#pragma mark - Cross-Thread Sync

- (void)willSynchronize {
    assert(VT100ScreenMutableState.performingJoinedBlock);

    if (self.currentGrid.isAnyCharDirty) {
        [_triggerEvaluator invalidateIdempotentTriggers];
    }
}

- (void)didSynchronize:(BOOL)resetOverflow {
    DLog(@"Did synchronize. Set drewSavedGrid=YES");
    if (resetOverflow) {
        self.temporaryDoubleBuffer.drewSavedGrid = YES;
        self.currentGrid.haveScrolled = NO;
    }
    self.primaryGrid.hasChanged = NO;
    self.altGrid.hasChanged = NO;
    // We don't want to run side effects while joined because that causes syncing to be skipped if
    // one of the side effects adds a joined block.
    _runSideEffectAfterTopJoinFinishes = YES;
    [self removeInaccessibleIntervalTreeObjects];
}

- (void)updateExpectFrom:(iTermExpect *)source {
    _triggerEvaluator.expect = [source copy];
}

- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block {
    DLog(@"%@", [NSThread callStackSymbols]);
    [iTermGCD assertMainQueueSafe];

    if (VT100ScreenMutableState.performingJoinedBlock) {
        // Reentrant call. Avoid deadlock by running it immediately.
        [self reallyPerformLightweightBlockWithJoinedThreads:block];
        return;
    }

    __weak __typeof(self) weakSelf = self;
    [self performSynchroDanceWithBlock:^{
        [weakSelf reallyPerformLightweightBlockWithJoinedThreads:block];
    }];
    if (_runSideEffectAfterTopJoinFinishes) {
        [_tokenExecutor executeSideEffectsImmediatelySyncingFirst:NO];
        _runSideEffectAfterTopJoinFinishes = NO;
    }
}

// This is called on the main thread (externally) or while locked up (internally)
- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block {
    DLog(@"%@", [NSThread callStackSymbols]);
    [iTermGCD assertMainQueueSafe];

    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;

    if (gPerformingJoinedBlock) {
        // Reentrant call. Avoid deadlock by running it immediately.
        [self reallyPerformBlockWithJoinedThreads:block delegate:delegate topmost:NO];
    } else {
        assert([iTermGCD onMainQueue]);

        // Wait for the mutation thread to finish its current tasks+tokens, then run the block.
        __weak __typeof(self) weakSelf = self;
        [self performSynchroDanceWithBlock:^{
            __strong __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [weakSelf reallyPerformBlockWithJoinedThreads:block
                                                 delegate:delegate
                                                  topmost:YES];
        }];
    }
}

- (void)performSynchroDanceWithBlock:(void (^)(void))block {
    assert(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(dispatch_get_main_queue()));
    DLog(@"begin");
    [iTermGCD setMainQueueSafe:YES];

    // Stop the token executor while we run `block`.
    DLog(@"Calling whilePaused:");
    [_tokenExecutor whilePaused:^{
        // The token executor is now stopped. This runs on the main thread.
        DLog(@"done waiting");
        block();
        DLog(@"block finished");
        [iTermGCD setMainQueueSafe:NO];
        DLog(@"unblock executor");
    }];
    DLog(@"returning");
}

// This runs on the main queue while the mutation queue waits on `group`.
- (void)reallyPerformBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *,
                                                                  VT100ScreenMutableState *,
                                                                  id<VT100ScreenDelegate>))block
                                   delegate:(id<VT100ScreenDelegate>)delegate
                                    topmost:(BOOL)topmost {
    DLog(@"begin");
    // Set `performingJoinedBlock` to YES so that a side-effect that wants to join threads won't
    // deadlock.
    // This get-and-set is not a data race because assignment to performingJoinedBlock only happens
    // on the mutation queue.
    const BOOL wasPerformingJoinedBlock = atomic_exchange(&gPerformingJoinedBlock, 1);

    VT100ScreenState *oldState;
    if (!wasPerformingJoinedBlock) {
        DLog(@"switch to shared state");
        oldState = [delegate screenSwitchToSharedState];
    }
    [self loadConfigIfNeededFromDelegate:delegate];

    const NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    self.primaryGrid.currentDate = now;
    self.altGrid.currentDate = now;

    // Now that the delegate has the most recent state, perform pending side effects which may operate on
    // that state. Don't have the token executor initiate sync because that depends on having a non-
    // empty list of side-effects. Note that if we're already executing a side-effect this
    // will have no effect because re-entrant side effects are almost impossible to reason about.
    // Reentrancy could happen like this:
    // performSideEffect
    //    [NSAlert run]
    //      (runloop)
    //        applicationDidResignActive
    //          encodeRestorableState
    //            performJoinedBlock
    //              executeSideEffectsImmediatelySyncingFirst (here)
    DLog(@"Execute side effects without syncing first");
    [_tokenExecutor executeSideEffectsImmediatelySyncingFirst:NO];

    if (block) {
        DLog(@"start block");
        block(self.terminal, self, delegate);
        DLog(@"finish block");
    }
    // Run any side-effects enqueued by the block, taking advantage of the fact that state is in sync.
    DLog(@"Execute side effects without syncing first (2)");
    [_tokenExecutor executeSideEffectsImmediatelySyncingFirst:NO];
    if (!wasPerformingJoinedBlock) {
        DLog(@"restore state");
        [delegate screenRestoreState:oldState];
    }
    [self loadConfigIfNeededFromDelegate:delegate];
    DLog(@"expect");
    [delegate screenSyncExpect:self];

    if (topmost && _screenNeedsUpdate) {
        [delegate screenUpdateDisplay:NO];
        _screenNeedsUpdate = NO;
    }

    VT100ScreenMutableState.performingJoinedBlock = wasPerformingJoinedBlock;
    DLog(@"done");
}

- (void)loadConfigIfNeededFromDelegate:(id<VT100ScreenDelegate>)delegate {
    DLog(@"begin");
    assert(VT100ScreenMutableState.performingJoinedBlock);
    VT100MutableScreenConfiguration *config = [delegate screenConfiguration];
    if (config.isDirty) {
        DLog(@"config is dirty");
        self.config = config;
    }
}

- (void)reallyPerformLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *))block {
    // Set `performingJoinedBlock` to YES so that a side-effect that wants to join threads won't
    // deadlock.
    DLog(@"begin");
    const BOOL previousValue = VT100ScreenMutableState.performingJoinedBlock;
    VT100ScreenMutableState.performingJoinedBlock = YES;
    if (block) {
        block(self);
    }
    VT100ScreenMutableState.performingJoinedBlock = previousValue;
}

- (void)performBlockAsynchronously:(void (^ _Nullable)(VT100Terminal *terminal,
                                                       VT100ScreenMutableState *mutableState,
                                                       id<VT100ScreenDelegate> delegate))block {
    DLog(@"begin %@", [NSThread callStackSymbols]);
    [iTermGCD assertMainQueueSafe];
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    __weak __typeof(self) weakSelf = self;
    [_tokenExecutor scheduleHighPriorityTask:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        block(strongSelf.terminal, strongSelf, delegate);
    }];
}

#pragma mark - State Restoration

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached {
    const BOOL newFormat = (dictionary[@"PrimaryGrid"] != nil);
    if (!newFormat) {
        return;
    }
    if (!self.altGrid) {
        self.altGrid = [self.primaryGrid copy];

    }
    NSDictionary *screenState = dictionary[kScreenStateKey];
    if (screenState) {
        if ([screenState[kScreenStateCurrentGridIsPrimaryKey] boolValue]) {
            self.currentGrid = self.primaryGrid;
        } else {
            self.currentGrid = self.altGrid;
        }
    }

    if (screenState) {
        // New format
        [self restoreFromDictionary:dictionary
           includeRestorationBanner:includeRestorationBanner];

        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary[@"LineBuffer"]];
        [lineBuffer setMaxLines:self.maxScrollbackLines + self.height];
        if (!self.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
        lineBuffer.delegate = self;
        self.linebuffer = lineBuffer;
    }
    if (includeRestorationBanner && [iTermAdvancedSettingsModel showSessionRestoredBanner]) {
        [self appendSessionRestoredBanner];
    }

    if (screenState) {
        [self.blockStartAbsLine it_mergeFrom:[NSDictionary castFrom:screenState[kScreenStateBlockStartAbsLineKey]] ?: @{}];
        self.blocksGeneration = 1;
        self.protectedMode = [screenState[kScreenStateProtectedMode] unsignedIntegerValue];
        [_promptStateMachine loadPromptStateDictionary:screenState[kScreenStatePromptStateKey]];
        [self.tabStops removeAllObjects];
        [self.tabStops addObjectsFromArray:screenState[kScreenStateTabStopsKey]];
        DLog(@"Restored tabstops: %@", self.tabStops);

        [self.terminal setStateFromDictionary:screenState[kScreenStateTerminalKey]];
        NSArray<NSNumber *> *array = screenState[kScreenStateLineDrawingModeKey];
        for (int i = 0; i < NUM_CHARSETS && i < array.count; i++) {
            [self setCharacterSet:i usesLineDrawingMode:array[i].boolValue];
        }

        NSString *guidOfLastCommandMark = screenState[kScreenStateLastCommandMarkKey];
        if (reattached) {
            [self setCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake([screenState[kScreenStateCommandStartXKey] intValue],
                                                                               [screenState[kScreenStateCommandStartYKey] longLongValue])];
            self.startOfRunningCommandOutput = [screenState[kScreenStateNextCommandOutputStartKey] gridAbsCoord];
        }
        self.cursorVisible = [screenState[kScreenStateCursorVisibleKey] boolValue];
        self.trackCursorLineMovement = [screenState[kScreenStateTrackCursorLineMovementKey] boolValue];
        self.lastCommandOutputRange = [screenState[kScreenStateLastCommandOutputRangeKey] gridAbsCoordRange];
        self.shellIntegrationInstalled = [screenState[kScreenStateShellIntegrationInstalledKey] boolValue];


        [self.mutableIntervalTree restoreFromDictionary:screenState[kScreenStateIntervalTreeKey]];
        [self fixUpDeserializedIntervalTree:self.mutableIntervalTree
                                    visible:YES
                      guidOfLastCommandMark:guidOfLastCommandMark];

        [self.mutableSavedIntervalTree restoreFromDictionary:screenState[kScreenStateSavedIntervalTreeKey]];
        [self fixUpDeserializedIntervalTree:self.mutableSavedIntervalTree
                                    visible:NO
                      guidOfLastCommandMark:guidOfLastCommandMark];

        Interval *interval = [self lastPromptMark].entry.interval;
        if (interval) {
            const VT100GridRange gridRange = [self lineNumberRangeOfInterval:interval];
            self.lastPromptLine = gridRange.location + self.cumulativeScrollbackOverflow;
        }

        [self reloadMarkCache];
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenSendModifiersDidChange];
        }];

        if (gDebugLogging) {
            DLog(@"Notes after restoring with width=%@", @(self.width));
            for (id<IntervalTreeObject> object in self.intervalTree.allObjects) {
                if (![object isKindOfClass:[PTYAnnotation class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([self coordRangeForInterval:object.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }
}

- (void)appendSessionRestoredBanner {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *message = [NSString stringWithFormat:@"Session Contents Restored on %@", [dateFormatter stringFromDate:[NSDate date]]];

    // Record the cursor position and append the message.
    const int yBefore = self.currentGrid.cursor.y;

    [self appendBannerMessage:message];

    const int delta = self.currentGrid.cursor.y - yBefore;
    // Update the preferred cursor position if needed.
    if (self.currentGrid.preferredCursorPosition.y >= 0 && self.currentGrid.preferredCursorPosition.y + 1 < self.currentGrid.size.height) {
        VT100GridCoord coord = self.currentGrid.preferredCursorPosition;
        coord.y = MAX(0, MIN(self.currentGrid.size.height - 1, coord.y + delta));
        self.currentGrid.preferredCursorPosition = coord;
    }
}

- (void)appendBannerMessage:(NSString *)message {
    [self performBlockWithoutTriggers:^{
        [self reallyAppendBannerMessage:message];
    }];
}

- (void)reallyAppendBannerMessage:(NSString *)message {
    DLog(@"Append banner %@", message);
    // Save graphic rendition. Set to system message color.
    const VT100GraphicRendition saved = self.terminal.graphicRendition;

    if (self.currentGrid.cursor.x > 0) {
        [self appendCarriageReturnLineFeed];
    }

    {
        VT100GraphicRendition temp = saved;
        temp.fgColorMode = ColorModeAlternate;
        temp.fgColorCode = ALTSEM_SYSTEM_MESSAGE;
        temp.bgColorMode = ColorModeAlternate;
        temp.bgColorCode = ALTSEM_SYSTEM_MESSAGE;
        self.terminal.graphicRendition = temp;
        [self.terminal updateDefaultChar];
        self.currentGrid.defaultChar = self.terminal.defaultChar;

        [self eraseLineBeforeCursor:YES afterCursor:YES decProtect:NO];
        [self appendStringAtCursor:message];

        self.currentGrid.cursorX = 0;
        self.currentGrid.preferredCursorPosition = self.currentGrid.cursor;

        self.terminal.graphicRendition = saved;
        [self.terminal updateDefaultChar];
        self.currentGrid.defaultChar = self.terminal.defaultChar;
    }
    
    [self appendCarriageReturnLineFeed];
}

// Link references to marks in CapturedOutput (for the lines where output was captured) to the deserialized mark.
// Link marks for commands to CommandUse objects in command history.
// Notify delegate of annotations so they get added as subviews, and set the delegate of not view controllers to self.
// Materialize portholes.
- (void)fixUpDeserializedIntervalTree:(iTermEventuallyConsistentIntervalTree *)intervalTree
                              visible:(BOOL)visible
                guidOfLastCommandMark:(NSString *)guidOfLastCommandMark {
    assert(VT100ScreenMutableState.performingJoinedBlock);
    id<VT100RemoteHostReading> lastRemoteHost = nil;
    NSMutableDictionary<NSString *, id<CapturedOutputReading>> *markGuidToCapturedOutput = [NSMutableDictionary dictionary];
    for (NSArray *objects in [intervalTree forwardLimitEnumerator]) {
        for (id<IntervalTreeImmutableObject> object in objects) {
            if ([object isKindOfClass:[VT100RemoteHost class]]) {
                lastRemoteHost = (id<VT100RemoteHostReading>)object;
            } else if ([object isKindOfClass:[VT100ScreenMark class]]) {
                id<VT100ScreenMarkReading> screenMark = (id<VT100ScreenMarkReading>)object;
                // Breaking the rules here because I don't want the doppelganger to get a delegate.
                ((VT100ScreenMark *)screenMark).delegate = self;
                // If |capturedOutput| is not empty then this mark is a command, some of whose output
                // was captured. The iTermCapturedOutputMarks will come later so save the GUIDs we need
                // in markGuidToCapturedOutput and they'll get backfilled when found.
                for (id<CapturedOutputReading> capturedOutput in screenMark.capturedOutput) {
                    if (capturedOutput.markGuid) {
                        markGuidToCapturedOutput[capturedOutput.markGuid] = capturedOutput;
                    }
                }
                if (screenMark.command) {
                    // Find the matching object in command history and link it.
                    id<VT100RemoteHostReading> lastRemoteHostDoppelganger = lastRemoteHost.doppelganger;
                    id<VT100ScreenMarkReading> screenMarkDoppelganger = screenMark.doppelganger;
                    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                        [delegate screenUpdateCommandUseWithGuid:screenMark.guid
                                                          onHost:lastRemoteHostDoppelganger
                                                   toReferToMark:screenMarkDoppelganger];
                    }];
                }
                if ([screenMark.guid isEqualToString:guidOfLastCommandMark]) {
                    self.lastCommandMark = screenMark;
                }
                if (screenMark.name) {
                    [self.namedMarks addObject:screenMark];
                    self.namedMarksDirty = YES;
                }
            } else if ([object isKindOfClass:[iTermCapturedOutputMark class]]) {
                // This mark represents a line whose output was captured. Find the preceding command
                // mark that has a CapturedOutput corresponding to this mark and fill it in.
                id<iTermCapturedOutputMarkReading> capturedOutputMark = (id<iTermCapturedOutputMarkReading>)object;
                id<CapturedOutputReading> capturedOutput = markGuidToCapturedOutput[capturedOutputMark.guid];
                if (capturedOutput) {
                    [intervalTree mutateObject:capturedOutputMark
                                         block:^(id<IntervalTreeObject> obj) {
                        if (obj == (iTermCapturedOutputMark *)capturedOutputMark) {
                            ((CapturedOutput *)capturedOutput).mark = capturedOutputMark;
                        } else {
                            ((CapturedOutput *)capturedOutput.doppelganger).mark = (iTermCapturedOutputMark *)obj;
                        }
                    }];
                } else {
                    DLog(@"No mark");
                }
            } else if ([object isKindOfClass:[PTYAnnotation class]]) {
                id<PTYAnnotationReading> note = (id<PTYAnnotationReading>)[object doppelganger];
                if (visible) {
                    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                        [delegate screenDidAddNote:note focus:NO visible:YES];
                    }];
                }
            } else if ([object isKindOfClass:[iTermImageMark class]]) {
                id<iTermImageMarkReading> imageMark = (id<iTermImageMarkReading>)object;
                ScreenCharClearProvisionalFlagForImageWithCode(imageMark.imageCode.intValue);
            }
        }
    }
}

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner {
    const BOOL onPrimary = (self.currentGrid == self.primaryGrid);
    self.primaryGrid.delegate = nil;
    self.altGrid.delegate = nil;
    self.altGrid = nil;

    self.primaryGrid = [[VT100Grid alloc] initWithDictionary:dictionary[@"PrimaryGrid"]
                                                    delegate:self];
    self.primaryGrid.defaultChar = self.terminal.defaultChar;
    if (!self.primaryGrid) {
        // This is to prevent a crash if the dictionary is bad (i.e., non-backward compatible change in a future version).
        self.primaryGrid = [[VT100Grid alloc] initWithSize:VT100GridSizeMake(2, 2) delegate:self];
    }
    if ([dictionary[@"AltGrid"] count]) {
        self.altGrid = [[VT100Grid alloc] initWithDictionary:dictionary[@"AltGrid"]
                                                    delegate:self];
    }
    if (!self.altGrid) {
        self.altGrid = [[VT100Grid alloc] initWithSize:self.primaryGrid.size delegate:self];
    }
    self.altGrid.defaultChar = self.terminal.defaultChar;
    if (onPrimary || includeRestorationBanner) {
        self.currentGrid = self.primaryGrid;
    } else {
        self.currentGrid = self.altGrid;
    }
}

- (void)restoreFromSavedState:(NSDictionary *)terminalState {
    NSDictionary *terminalDict = [NSDictionary castFrom:terminalState[VT100ScreenTerminalStateKeyVT100Terminal]];
    if (terminalDict) {
        [_terminal setStateFromDictionary:terminalDict];
    }
    NSData *colorData = [NSData castFrom:terminalState[VT100ScreenTerminalStateKeySavedColors]];
    if (colorData) {
        VT100SavedColorsSlot *slot = [VT100SavedColorsSlot fromData:colorData];
        if (slot) {
            [self setColorsFromDictionary:slot.indexedColorsDictionary];
        }
    }
    NSArray *tabStopsArray = [NSArray castFrom:terminalState[VT100ScreenTerminalStateKeyTabStops]];
    if (tabStopsArray) {
        [self setTabStops:[NSMutableSet setWithArray:tabStopsArray]];
    }
    NSArray *lineDrawingCharsetsArray = terminalState[VT100ScreenTerminalStateKeyLineDrawingCharacterSets];
    if (lineDrawingCharsetsArray) {
        [self setCharsetUsesLineDrawingMode:[NSMutableSet setWithArray:lineDrawingCharsetsArray]];
    }
    NSDictionary *remoteHostDictionary = [NSDictionary castFrom:terminalState[VT100ScreenTerminalStateKeyRemoteHost]];
    VT100RemoteHost *remoteHost = remoteHostDictionary ? [[VT100RemoteHost alloc] initWithDictionary:remoteHostDictionary] : nil;
    [self setHost:remoteHost.hostname user:remoteHost.username ssh:YES completion:^{}];
    NSString *path = [NSString castFrom:terminalState[VT100ScreenTerminalStateKeyPath]];
    if (path) {
        [self setPathFromURL:path];
    }
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<VT100ScreenMarkReading>)mark {
    [self assertOnMutationThread];
    DLog(@"mark %@ became command mark", mark);
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        DLog(@"Set last command mark to %@", mark);
        self.lastCommandMark = mark;
    }
}

#pragma mark - Inline Images

- (BOOL)confirmBigDownloadWithBeforeSize:(NSInteger)sizeBefore
                               afterSize:(NSInteger)afterSize
                                    name:(NSString *)name
                                delegate:(id<VT100ScreenDelegate>)delegate
                                   queue:(dispatch_queue_t)queue
                                unpauser:(iTermTokenExecutorUnpauser *)unpauser {
    if (sizeBefore < VT100ScreenBigFileDownloadThreshold && afterSize >= VT100ScreenBigFileDownloadThreshold) {
        if (![delegate screenConfirmDownloadNamed:name
                                    canExceedSize:VT100ScreenBigFileDownloadThreshold]) {
            DLog(@"Aborting big download");
            __weak __typeof(self) weakSelf = self;
            dispatch_async(queue, ^{
                [weakSelf stopTerminalReceivingFile];
                [unpauser unpause];
            });
            return NO;
        }
    }
    [unpauser unpause];
    return YES;
}

- (void)stopTerminalReceivingFile {
    [self.terminal stopReceivingFile];
    [self fileReceiptEndedUnexpectedly];
}

- (void)fileReceiptEndedUnexpectedly {
    self.inlineImageHelper = nil;
    // Delegate may join to call [terminal stopReceivingFile], so use unamanged to avoid reentrancy.
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenFileReceiptEndedUnexpectedly];
        [unpauser unpause];
    }];
}

- (void)appendNativeImageAtCursorWithName:(NSString *)name width:(int)width {
    VT100InlineImageHelper *helper = [[VT100InlineImageHelper alloc] initWithNativeImageNamed:name
                                                                                spanningWidth:width
                                                                                  scaleFactor:self.config.backingScaleFactor];
    helper.delegate = self;
    [helper writeToGrid:self.currentGrid];
}

- (void)setHistory:(NSArray<NSData *> *)history {
    // This is way more complicated than it should be to work around something dumb in tmux.
    // It pads lines in its history with trailing spaces, which we'd like to trim. More importantly,
    // we need to trim empty lines at the end of the history because that breaks how we move the
    // screen contents around on resize. So we take the history from tmux, append it to a temporary
    // line buffer, grab each wrapped line and trim spaces from it, and then append those modified
    // line (excluding empty ones at the end) to the real line buffer.
    [self clearBufferWithoutTriggersSavingPrompt:YES];
    LineBuffer *temp = [[LineBuffer alloc] init];
    temp.mayHaveDoubleWidthCharacter = YES;
    self.linebuffer.mayHaveDoubleWidthCharacter = YES;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    // TODO(externalAttributes): Add support for external attributes here. This is only used by tmux at the moment.
    iTermMetadata metadata;
    iTermMetadataInit(&metadata, now, nil);
    for (NSData *chars in history) {
        screen_char_t *line = (screen_char_t *) [chars bytes];
        const int len = [chars length] / sizeof(screen_char_t);
        screen_char_t continuation;
        if (len) {
            continuation = line[len - 1];
            continuation.code = EOL_HARD;
        } else {
            memset(&continuation, 0, sizeof(continuation));
        }
        [temp appendLine:line
                  length:len
                 partial:NO
                   width:self.currentGrid.size.width
                metadata:iTermMetadataMakeImmutable(metadata)
            continuation:continuation];
    }
    NSMutableArray *wrappedLines = [NSMutableArray array];
    int n = [temp numLinesWithWidth:self.currentGrid.size.width];
    int numberOfConsecutiveEmptyLines = 0;
    for (int i = 0; i < n; i++) {
        ScreenCharArray *line = [temp wrappedLineAtIndex:i
                                                   width:self.currentGrid.size.width
                                            continuation:NULL];
        if (line.eol == EOL_HARD) {
            [self stripTrailingSpaceFromLine:line];
            if (line.length == 0) {
                ++numberOfConsecutiveEmptyLines;
            } else {
                numberOfConsecutiveEmptyLines = 0;
            }
        } else {
            numberOfConsecutiveEmptyLines = 0;
        }
        [wrappedLines addObject:line];
    }
    for (int i = 0; i < n - numberOfConsecutiveEmptyLines; i++) {
        ScreenCharArray *line = [wrappedLines objectAtIndex:i];
        screen_char_t continuation = { 0 };
        if (line.length) {
            continuation = line.line[line.length - 1];
        }
        [self.linebuffer appendLine:line.line
                             length:line.length
                            partial:(line.eol != EOL_HARD)
                              width:self.currentGrid.size.width
                           metadata:iTermMetadataMakeImmutable(metadata)
                       continuation:continuation];
    }
    if (!self.unlimitedScrollback) {
        [self.linebuffer dropExcessLinesWithWidth:self.currentGrid.size.width];
    }

    // We don't know the cursor position yet but give the linebuffer something
    // so it doesn't get confused in restoreScreenFromScrollback.
    [self.linebuffer setCursor:0];
    [self.currentGrid restoreScreenFromLineBuffer:self.linebuffer
                                  withDefaultChar:[self.currentGrid defaultChar]
                                maxLinesToRestore:MIN([self.linebuffer numLinesWithWidth:self.currentGrid.size.width],
                                                      self.currentGrid.size.height - numberOfConsecutiveEmptyLines)];
}

- (void)stripTrailingSpaceFromLine:(ScreenCharArray *)line {
    const screen_char_t *p = line.line;
    int len = line.length;
    for (int i = len - 1; i >= 0; i--) {
        // TODO: When I add support for URLs to tmux, don't pass 0 here - pass the URL code instead.
        if (p[i].code == ' ' && ScreenCharHasDefaultAttributesAndColors(p[i], 0)) {
            len--;
        } else {
            break;
        }
    }
    line.length = len;
}

- (void)setAltScreen:(NSArray<NSData *> *)lines {
    self.linebuffer.mayHaveDoubleWidthCharacter = YES;
    if (!self.altGrid) {
        self.altGrid = [self.primaryGrid copy];
    }

    // Initialize alternate screen to be empty
    [self.altGrid setCharsFrom:VT100GridCoordMake(0, 0)
                            to:VT100GridCoordMake(self.altGrid.size.width - 1, self.altGrid.size.height - 1)
                        toChar:[self.altGrid defaultChar]
            externalAttributes:nil];
    // Copy the lines back over it
    int o = 0;
    for (int i = 0; o < self.altGrid.size.height && i < MIN(lines.count, self.altGrid.size.height); i++) {
        NSData *chars = [lines objectAtIndex:i];
        screen_char_t *line = (screen_char_t *) [chars bytes];
        int length = [chars length] / sizeof(screen_char_t);

        do {
            // Add up to self.altGrid.size.width characters at a time until they're all used.
            screen_char_t *dest = [self.altGrid screenCharsAtLineNumber:o];
            memcpy(dest, line, MIN(self.altGrid.size.width, length) * sizeof(screen_char_t));
            const BOOL isPartial = (length > self.altGrid.size.width);
            dest[self.altGrid.size.width] = dest[self.altGrid.size.width - 1];  // TODO: This is probably wrong?
            dest[self.altGrid.size.width].code = (isPartial ? EOL_SOFT : EOL_HARD);
            length -= self.altGrid.size.width;
            line += self.altGrid.size.width;
            o++;
        } while (o < self.altGrid.size.height && length > 0);
    }
}


#pragma mark - Tmux

- (id)objectInDictionary:(NSDictionary *)dict withFirstKeyFrom:(NSArray *)keys {
    for (NSString *key in keys) {
        NSObject *object = [dict objectForKey:key];
        if (object) {
            return object;
        }
    }
    return nil;
}

- (void)setTmuxState:(NSDictionary *)state {
    BOOL inAltScreen = [[self objectInDictionary:state
                                withFirstKeyFrom:@[ kStateDictSavedGrid, kStateDictSavedGrid]] intValue];
    if (inAltScreen) {
        // Alt and primary have been populated with each other's content.
        id<VT100GridReading> temp = self.altGrid;
        self.altGrid = self.primaryGrid;
        self.primaryGrid = temp;
    }

    NSNumber *altSavedX = state[kStateDictAltSavedCX];
    NSNumber *altSavedY = state[kStateDictAltSavedCY];
    if (altSavedX && altSavedY && inAltScreen) {
        self.primaryGrid.cursor = VT100GridCoordMake(altSavedX.intValue,
                                                     altSavedY.intValue);
        [self.terminal setSavedCursorPosition:self.primaryGrid.cursor];
    }

    self.currentGrid.cursorX = [state[kStateDictCursorX] intValue];
    self.currentGrid.cursorY = [state[kStateDictCursorY] intValue];
    int top = [state[kStateDictScrollRegionUpper] intValue];
    int bottom = [state[kStateDictScrollRegionLower] intValue];
    self.currentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetCursorVisible:[state[kStateDictCursorMode] boolValue]];
    }];

    [self.tabStops removeAllObjects];
    int maxTab = 0;
    for (NSNumber *n in state[kStateDictTabstops]) {
        [self.tabStops addObject:n];
        maxTab = MAX(maxTab, [n intValue]);
    }
    for (int i = 0; i < 1000; i += 8) {
        if (i > maxTab) {
            [self.tabStops addObject:@(i)];
        }
    }
    DLog(@"tmux tabstops set to %@", self.tabStops);

    NSNumber *cursorMode = state[kStateDictCursorMode];
    if (cursorMode) {
        [self terminalSetCursorVisible:!!cursorMode.intValue];
    }

    // Everything below this line needs testing
    NSNumber *insertMode = state[kStateDictInsertMode];
    if (insertMode) {
        [self.terminal setInsertMode:!!insertMode.intValue];
    }

    NSNumber *applicationCursorKeys = state[kStateDictKCursorMode];
    if (applicationCursorKeys) {
        [self.terminal setCursorMode:!!applicationCursorKeys.intValue];
    }

    NSNumber *keypad = state[kStateDictKKeypadMode];
    if (keypad) {
        [self.terminal setKeypadMode:!!keypad.boolValue];
    }

    NSNumber *mouse = state[kStateDictMouseStandardMode];
    if (mouse && mouse.intValue) {
        [self.terminal setMouseMode:MOUSE_REPORTING_NORMAL];
    }
    mouse = state[kStateDictMouseButtonMode];
    if (mouse && mouse.intValue) {
        [self.terminal setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
    }
    mouse = state[kStateDictMouseButtonMode];
    if (mouse && mouse.intValue) {
        [self.terminal setMouseMode:MOUSE_REPORTING_ALL_MOTION];
    }

    // NOTE: You can get both SGR and UTF8 set. In that case SGR takes priority. See comment in
    // tmux's input_key_get_mouse()
    mouse = state[kStateDictMouseSGRMode];
    if (mouse && mouse.intValue) {
        [self.terminal setMouseFormat:MOUSE_FORMAT_SGR];
    } else {
        mouse = state[kStateDictMouseUTF8Mode];
        if (mouse && mouse.intValue) {
            [self.terminal setMouseFormat:MOUSE_FORMAT_XTERM_EXT];
        }
    }

    NSNumber *wrap = state[kStateDictWrapMode];
    if (wrap) {
        [self.terminal setWraparoundMode:!!wrap.intValue];
    }

    NSData *pendingOutput = state[kTmuxWindowOpenerStatePendingOutput];
    if (pendingOutput && pendingOutput.length) {
        [self.terminal.parser putStreamData:pendingOutput.bytes
                                     length:pendingOutput.length];
    }
    self.terminal.insertMode = [state[kStateDictInsertMode] boolValue];
    self.terminal.cursorMode = [state[kStateDictKCursorMode] boolValue];
    self.terminal.keypadMode = [state[kStateDictKKeypadMode] boolValue];
    if ([state[kStateDictMouseStandardMode] boolValue]) {
        [self.terminal setMouseMode:MOUSE_REPORTING_NORMAL];
    } else if ([state[kStateDictMouseButtonMode] boolValue]) {
        [self.terminal setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
    } else if ([state[kStateDictMouseAnyMode] boolValue]) {
        [self.terminal setMouseMode:MOUSE_REPORTING_ALL_MOTION];
    } else {
        [self.terminal setMouseMode:MOUSE_REPORTING_NONE];
    }
    // NOTE: You can get both SGR and UTF8 set. In that case SGR takes priority. See comment in
    // tmux's input_key_get_mouse()
    if ([state[kStateDictMouseSGRMode] boolValue]) {
        [self.terminal setMouseFormat:MOUSE_FORMAT_SGR];
    } else if ([state[kStateDictMouseUTF8Mode] boolValue]) {
        [self.terminal setMouseFormat:MOUSE_FORMAT_XTERM_EXT];
    } else {
        [self.terminal setMouseFormat:MOUSE_FORMAT_XTERM];
    }
}

#pragma mark - SSH

- (NSString *)sshEndBannerTerminatingCount:(NSInteger)count newLocation:(NSString *)sshLocation {
    NSString *preamble;
    if (count == 1) {
        preamble = @"ssh exited";
    } else if (count > 1) {
        preamble = [NSString stringWithFormat:@"%@ ssh sessions ended.", @(count)];
    }
    if (sshLocation) {
        return [NSString stringWithFormat:@"%@ — now at %@.", preamble, sshLocation];
    }
    return [NSString stringWithFormat:@"%@.", preamble];
}

#pragma mark - DVR

- (void)setFromFrame:(const screen_char_t *)s
                 len:(int)len
            metadata:(NSArray<NSArray *> *)metadataArrays
                info:(DVRFrameInfo)info {
    assert(len == (info.width + 1) * info.height * sizeof(screen_char_t));
    NSMutableData *storage = [NSMutableData dataWithLength:sizeof(iTermMetadata) * info.height];
    iTermMetadata *md = (iTermMetadata *)storage.mutableBytes;
    [metadataArrays enumerateObjectsUsingBlock:^(NSArray * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= info.height) {
            *stop = YES;
            return;
        }
        iTermMetadataInitFromArray(&md[idx], obj);
    }];
    [self.currentGrid setContentsFromDVRFrame:s metadataArray:md info:info];
    for (int i = 0; i < info.height; i++) {
        iTermMetadataRelease(md[i]);
    }
    [self resetScrollbackOverflow];
    // Unpause so tail find can continue after resetting it.
    [self setNeedsRedraw];
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenResetTailFind];
        [delegate screenRemoveSelection];
        [unpauser unpause];
    }];
    [self.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
}

#pragma mark - PTYTriggerEvaluatorDelegate

- (BOOL)triggerEvaluatorShouldUseTriggers:(PTYTriggerEvaluator *)evaluator {
    if (![self.terminal softAlternateScreenMode]) {
        return YES;
    }
    return self.config.enableTriggersInInteractiveApps;
}

- (void)triggerEvaluatorOfferToDisableTriggersInInteractiveApps:(PTYTriggerEvaluator *)evaluator {
    // Use unmanaged concurrency because this will be rare and it can't run as a regular side-
    // effect since it modifies the profile.
    [self addUnmanagedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenOfferToDisableTriggersInInteractiveApps];
    }];
}

- (void)addUnmanagedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))block {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            block(delegate);
        }];
    });
}

// Use this when the delegate can cause a sync. It completely prevents reentrant syncs, which are
// very hard to reason about and are almost certainly incorrect.
- (void)addUnmanagedPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))block {
    __weak __typeof(self) weakSelf = self;
    iTermTokenExecutorUnpauser *unpauser = [_tokenExecutor pause];
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [unpauser unpause];
            return;
        }
        [strongSelf.tokenExecutor executeSideEffectsImmediatelySyncingFirst:YES];
        [strongSelf performPausedSideEffect:unpauser
                                      block:^(id<VT100ScreenDelegate> delegate,
                                              iTermTokenExecutorUnpauser *unpauser) {
            block(delegate, unpauser);
        }];
    });
}

#pragma mark - iTermTriggerScopeProvider

- (void)performBlockWithScope:(void (^)(iTermVariableScope *scope, id<iTermObject> object))block {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [iTermGCD assertMainQueueSafe];
        block([delegate triggerSideEffectVariableScope], delegate);
        [unpauser unpause];
    }];
}

// Main queue or mutation queue.
- (id<iTermTriggerCallbackScheduler>)triggerCallbackScheduler {
    return self;
}

#pragma mark - iTermTriggerCallbackScheduler

// Main queue or mutation queue.
- (void)scheduleTriggerCallback:(void (^)(void))block {
    if ([iTermGCD onMutationQueue] && _triggerEvaluator.evaluating) {
        block();
        return;
    }
    [_tokenExecutor scheduleHighPriorityTask:block];
}

#pragma mark - iTermTriggerSession

- (void)triggerSession:(Trigger *)trigger
  showAlertWithMessage:(NSString *)message
             rateLimit:(iTermRateLimitedUpdate *)rateLimit
               disable:(void (^)(void))disable {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectShowAlertWithMessage:message
                                              rateLimit:rateLimit
                                                disable:disable];
    }];
}

- (void)triggerSessionRingBell:(Trigger *)trigger {
    [self activateBell];
}

- (void)triggerSessionShowCapturedOutputTool:(Trigger *)trigger {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectShowCapturedOutputTool];
    }];
}

- (BOOL)triggerSessionIsShellIntegrationInstalled:(Trigger *)trigger {
    return self.shellIntegrationInstalled;
}

- (void)triggerSessionShowShellIntegrationRequiredAnnouncement:(Trigger *)trigger {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectShowShellIntegrationRequiredAnnouncement];
    }];
}

- (void)triggerSessionShowCapturedOutputToolNotVisibleAnnouncementIfNeeded:(Trigger *)trigger {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded];
    }];
}

- (void)triggerSession:(Trigger *)trigger didCaptureOutput:(CapturedOutput *)capturedOutput {
    id<iTermCapturedOutputMarkReading> mark = (id<iTermCapturedOutputMarkReading>)[self addMarkOnLine:self.numberOfScrollbackLines + self.cursorY - 1
                                                                                              ofClass:[iTermCapturedOutputMark class]];
    capturedOutput.mark = mark;
    ((CapturedOutput *)capturedOutput.doppelganger).mark = (id<iTermCapturedOutputMarkReading>)mark.doppelganger;

    id<VT100ScreenMarkReading> lastCommandMark = self.lastCommandMark;
    if (!lastCommandMark) {
        // TODO: Show an announcement
        return;
    }
    [self.mutableIntervalTree mutateObject:lastCommandMark block:^(id<IntervalTreeObject> _Nonnull obj) {
        VT100ScreenMark *mutableMark = (VT100ScreenMark *)obj;
        if (mutableMark == lastCommandMark) {
            [mutableMark addCapturedOutput:capturedOutput];
        } else {
            [mutableMark addCapturedOutput:(CapturedOutput *)capturedOutput.doppelganger];
        }
    }];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectDidCaptureOutput];
    }];
}

- (void)triggerSession:(Trigger *)trigger
launchCoprocessWithCommand:(NSString *)command
            identifier:(NSString * _Nullable)identifier
                silent:(BOOL)silent {
    NSString *triggerName = [NSString stringWithFormat:@"%@ trigger", [[trigger.class title] stringByRemovingSuffix:@"…"]];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectLaunchCoprocessWithCommand:command
                                                   identifier:identifier
                                                       silent:silent
                                                 triggerTitle:triggerName];
    }];
}

- (id<iTermTriggerScopeProvider>)triggerSessionVariableScopeProvider:(Trigger *)trigger {
    return self;
}

- (BOOL)triggerSessionShouldUseInterpolatedStrings:(Trigger *)trigger {
    return _triggerEvaluator.triggerParametersUseInterpolatedStrings;
}

- (void)triggerSession:(Trigger *)trigger postUserNotificationWithMessage:(NSString *)message rateLimit:(nonnull iTermRateLimitedUpdate *)rateLimit {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [rateLimit performRateLimitedBlock:^{
            [delegate triggerSideEffectPostUserNotificationWithMessage:message];
        }];
    }];
}

- (void)triggerSession:(Trigger *)trigger
  highlightTextInRange:(NSRange)rangeInScreenChars
          absoluteLine:(long long)lineNumber
                colors:(NSDictionary<NSString *, NSColor *> *)colors {
    [self highlightTextInRange:rangeInScreenChars
     basedAtAbsoluteLineNumber:lineNumber
                        colors:colors];
}

- (void)triggerSession:(Trigger *)trigger saveCursorLineAndStopScrolling:(BOOL)stopScrolling {
    [self saveCursorLine];
    if (!stopScrolling) {
        return;
    }
    const long long line = self.cumulativeScrollbackOverflow + self.numberOfScrollbackLines + self.currentGrid.cursorY;
    // Pause to avoid a visual stutter if more tokens cause scrolling.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate triggerSideEffectStopScrollingAtLine:line];
        [unpauser unpause];
    }];
}

- (void)triggerSession:(Trigger *)trigger openPasswordManagerToAccountName:(NSString *)accountName {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectOpenPasswordManagerToAccountName:accountName];
    }];
}

- (void)triggerSession:(Trigger *)trigger
            runCommand:(nonnull NSString *)command
        withRunnerPool:(nonnull iTermBackgroundCommandRunnerPool *)pool {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectRunBackgroundCommand:command pool:pool];
    }];
}

- (void)triggerSession:(Trigger *)trigger writeText:(NSString *)text {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerWriteTextWithoutBroadcasting:text];
    }];
}

- (void)triggerSession:(Trigger *)trigger setRemoteHostName:(NSString *)remoteHost {
    [self setRemoteHostFromString:remoteHost];
}

- (void)triggerSession:(Trigger *)trigger setCurrentDirectory:(NSString *)currentDirectory {
    // Stop the world (this affects a variable)
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectCurrentDirectoryDidChange:currentDirectory];
    }];
    // This can be sync
    [self currentDirectoryDidChangeTo:currentDirectory completion:^{}];
}

- (void)triggerSession:(Trigger *)trigger didChangeNameTo:(NSString *)newName {
    // This updates the profile so it must be paused.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate triggerSideEffectSetTitle:newName];
        [unpauser unpause];
    }];
}

- (void)handleTriggerDetectedPromptAt:(VT100GridAbsCoordRange)range {
    DLog(@"handleTriggerDetectedPromptAt: %@", VT100GridAbsCoordRangeDescription(range));
    _triggerDidDetectPrompt = NO;
    if (self.fakePromptDetectedAbsLine == -2) {
        // Infer the end of the preceding command. Set a return status of 0 since we don't know what it was.
        [self setReturnCodeOfLastCommand:0];
    }

    if (self.config.useLineStyleMarks) {
        // Insert an empty line above the prompt.
        if (range.start.y == self.numberOfLines + self.cumulativeScrollbackOverflow - 1) {
            // Make room at the bottom of the grid.
            [self incrementOverflowBy:
             [self.currentGrid scrollWholeScreenUpIntoLineBuffer:self.linebuffer
                                             unlimitedScrollback:self.unlimitedScrollback]];
        } else {
            // The prompt will be one line lower so move the cursor to stay with it.
            [self.currentGrid moveCursorDown:1];
        }
        // Move the prompt and anything below it down by 1
        const int scrollbackLines = self.numberOfScrollbackLines;
        const int gridRow = range.start.y - scrollbackLines - self.cumulativeScrollbackOverflow;
        [self.currentGrid scrollRect:VT100GridRectMake(0,
                                                       gridRow,
                                                       self.width,
                                                       self.height - gridRow)
                              downBy:1
                           softBreak:NO];
        range.start.y += 1;
        range.end.y += 1;
    }

    // Use 0 here to avoid the screen inserting a newline.
    range.start.x = 0;

    // Simulate FinalTerm A:
    // We pass YES for wasInCommand to avoid getting an extra newline added at the cursor.
    VT100ScreenMark *mark = [self promptDidStartAt:range.start wasInCommand:YES detectedByTrigger:YES];
    mark.promptDetectedByTrigger = YES;
    self.fakePromptDetectedAbsLine = range.start.y;

    BOOL ok = NO;
    VT100GridCoord coord = VT100GridCoordFromAbsCoord(range.end, self.cumulativeScrollbackOverflow, &ok);
    coord.y -= self.numberOfScrollbackLines;
    if (ok) {
        // Simulate FinalTerm B:
        [self promptEndedAndCommandStartedAt:coord shortCircuitDups:NO];
    } else {
        DLog(@"Range end is invalid %@, overflow=%@", VT100GridAbsCoordRangeDescription(range),
             @(self.cumulativeScrollbackOverflow));
    }
}

- (void)triggerSession:(Trigger *)trigger didDetectPromptAt:(VT100GridAbsCoordRange)range {
    DLog(@"Trigger detected prompt at %@", VT100GridAbsCoordRangeDescription(range));

    id<VT100ScreenMarkReading> lastPromptMark = [self lastPromptMark];
    if (lastPromptMark) {
        const VT100GridAbsCoordRange existingRange = [self absCoordRangeForInterval:lastPromptMark.entry.interval];
        if (existingRange.start.y == range.start.y) {
            DLog(@"There's already a prompt at this line. Ignore. existing=%@ proposed=%@",
                 VT100GridAbsCoordRangeDescription(existingRange),
                 VT100GridAbsCoordRangeDescription(range));
            return;
        }
    }
    // We can't mutate the session at this point. Wait until trigger processing is done and the
    // current token (if any) is executed and then do the prompt handling.
    _triggerDidDetectPrompt = YES;
    __weak __typeof(self) weakSelf = self;
    [_postTriggerActions addObject:[^{
        [weakSelf handleTriggerDetectedPromptAt:range];
    } copy]];
    if (_tokenExecutor.isExecutingToken) {
        self.terminal.wantsDidExecuteCallback = YES;
    }
}

- (void)triggerSession:(Trigger *)trigger
    makeHyperlinkToURL:(NSURL *)url
               inRange:(NSRange)rangeInString
                  line:(long long)lineNumber {
    // Add URL to URL Store and retrieve URL code for later reference.
    unsigned int code = [[iTermURLStore sharedInstance] codeForURL:url withParams:@""];

    // Modify grid to add URL attribute to affected cells.
    [self linkTextInRange:rangeInString basedAtAbsoluteLineNumber:lineNumber URLCode:code];

    // Add invisible URL Mark so the URL can automatically freed.
    iTermURLMark *mark = [[iTermURLMark alloc] initWithCode:code];
    [self addMark:mark onLine:lineNumber singleLine:YES];
}

- (void)triggerSession:(Trigger *)trigger
                invoke:(NSString *)invocation
         withVariables:(NSDictionary *)temporaryVariables
              captures:(NSArray<NSString *> *)captureStringArray {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate triggerSideEffectInvokeFunctionCall:invocation
                                        withVariables:temporaryVariables
                                             captures:captureStringArray
                                              trigger:trigger];
        [unpauser unpause];
    }];
}

- (id<PTYAnnotationReading>)triggerSession:(Trigger *)trigger
                     makeAnnotationInRange:(NSRange)rangeInScreenChars
                                      line:(long long)lineNumber {
    assert(rangeInScreenChars.length > 0);
    const long long width = self.width;
    const VT100GridAbsCoordRange absRange =
    VT100GridAbsCoordRangeMake(rangeInScreenChars.location,
                               lineNumber,
                               NSMaxRange(rangeInScreenChars) % width,
                               lineNumber + (NSMaxRange(rangeInScreenChars) - 1) / width);
    return [self addNoteWithText:@"" inAbsoluteRange:absRange];
}

- (void)triggerSession:(Trigger *)trigger
         setAnnotation:(id<PTYAnnotationReading>)annotation
              stringTo:(NSString *)stringValue {
    if (!annotation) {
        return;
    }
    [self.mutableIntervalTree mutateObject:annotation block:^(id<IntervalTreeObject> _Nonnull obj) {
        PTYAnnotation *mutableAnnotation = (PTYAnnotation *)obj;
        mutableAnnotation.stringValue = stringValue;
    }];
}

- (void)triggerSession:(Trigger *)trigger
       highlightLineAt:(VT100GridAbsCoord)absCoord
                colors:(NSDictionary *)colors {
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:self];
    BOOL ok = NO;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, self.cumulativeScrollbackOverflow, &ok);
    if (!ok) {
        return;
    }
    const VT100GridWindowedRange wrappedRange =
    [extractor rangeForWrappedLineEncompassing:coord
                          respectContinuations:NO
                                      maxChars:self.width * 10];

    const long long lineLength = VT100GridCoordRangeLength(wrappedRange.coordRange,
                                                           self.width);
    const int width = self.width;
    const long long lengthToHighlight = ceil((double)lineLength / (double)width);
    const NSRange range = NSMakeRange(0, lengthToHighlight * width);
    [self highlightTextInRange:range
     basedAtAbsoluteLineNumber:absCoord.y
                        colors:colors];
}

- (void)triggerSession:(Trigger *)trigger injectData:(NSData *)data {
    [self injectData:data];
}

- (void)triggerSession:(Trigger *)trigger setVariableNamed:(NSString *)name toValue:(id)value {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate triggerSideEffectSetValue:value forVariableNamed:name];
    }];
}

- (BOOL)triggerSessionIsInAlternateScreen {
    return self.terminal.softAlternateScreenMode;
}

#pragma mark - VT100GridDelegate

- (void)gridCursorDidChangeLineFrom:(int)previous {
    if (!self.trackCursorLineMovement) {
        return;
    }
    const int line = self.currentGrid.cursorY + self.numberOfScrollbackLines;
    // This can happen pretty frequently so I think it's worth deferring.
    [self addDeferredSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenCursorDidMoveToLine:line];
    }];
}

- (iTermUnicodeNormalization)gridUnicodeNormalizationForm {
    return self.normalization;
}

- (void)gridCursorDidMove {
}

- (void)gridDidResize {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidResize];
    }];
}

#pragma mark - VT100InlineImageHelperDelegate

- (void)inlineImageConfirmBigDownloadWithBeforeSize:(NSInteger)lengthBefore
                                          afterSize:(NSInteger)lengthAfter
                                               name:(NSString *)name {
    dispatch_queue_t queue = _queue;
    __weak __typeof(self) weakSelf = self;
    // Unamanged because this will have a runloop.
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [unpauser unpause];
            return;
        }
        [strongSelf confirmBigDownloadWithBeforeSize:lengthBefore
                                           afterSize:lengthAfter
                                                name:name
                                            delegate:delegate
                                               queue:queue
                                            unpauser:unpauser];
        [unpauser unpause];
    }];
}

- (NSSize)inlineImageCellSize {
    return self.config.cellSize;
}

- (void)inlineImageAppendLinefeed {
    [self appendLineFeed];
}

- (void)inlineImageSetMarkOnScreenLine:(NSInteger)line
                                  code:(unichar)code {
    long long absLine = (self.cumulativeScrollbackOverflow +
                         self.numberOfScrollbackLines +
                         line);
    iTermImageMark *mark = [[iTermImageMark alloc] initWithImageCode:@(code)];
    mark = (iTermImageMark *)[self addMark:mark onLine:absLine singleLine:YES];
    [self setNeedsRedraw];
}

- (void)inlineImageDidFinishWithImageData:(NSData *)imageData {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidAppendImageData:imageData];
    }];
}

- (void)inlineImageDidCreateTextDocumentInRange:(VT100GridAbsCoordRange)range
                                           type:(NSString *)type
                                       filename:(NSString *)filename
                                      forceWide:(BOOL)forceWide {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenConvertAbsoluteRange:range
                        toTextDocumentOfType:type
                                    filename:filename
                                   forceWide:forceWide];
        [unpauser unpause];
    }];
}

- (void)inlineImageAppendStringAtCursor:(nonnull NSString *)string {
    [self appendStringAtCursor:string];
}


- (VT100GridAbsCoord)inlineImageCursorAbsoluteCoord {
    return VT100GridAbsCoordMake(self.currentGrid.cursor.x, self.cumulativeScrollbackOverflow + self.numberOfScrollbackLines + self.currentGrid.cursor.y);
}

#pragma mark - iTermEchoProbeDelegate

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data {
    __weak __typeof(self) weakSelf = self;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [weakSelf.echoProbeDelegate echoProbe:echoProbe writeData:data];
    }];
}

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string {
    __weak __typeof(self) weakSelf = self;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [weakSelf.echoProbeDelegate echoProbe:echoProbe writeString:string];
    }];
}

- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe {
    __weak __typeof(self) weakSelf = self;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        id<iTermEchoProbeDelegate> echoProbeDelegate = weakSelf.echoProbeDelegate;
        if (!echoProbeDelegate) {
            [echoProbe reset];
        }
        [echoProbeDelegate echoProbeDidFail:echoProbe];
    }];
}

- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe {
    __weak __typeof(self) weakSelf = self;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [weakSelf.echoProbeDelegate echoProbeDidSucceed:echoProbe];
    }];
}

- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe {
    return _echoProbeShouldSendPassword;
}

- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe {
}

- (void)setEchoProbeDelegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate {
    if (echoProbeDelegate == _echoProbeDelegate) {
        return;
    }
    [self.echoProbeDelegate echoProbeDelegateWillChange:self.echoProbe];
    _echoProbeDelegate = echoProbeDelegate;
    _echoProbeShouldSendPassword = [echoProbeDelegate echoProbeShouldSendPassword:self.echoProbe];
}

#pragma mark - iTermColorMapDelegate

- (void)colorMap:(iTermColorMap *)colorMap didChangeColorForKey:(iTermColorMapKey)theKey from:(NSColor *)before to:(NSColor *)after {
    [iTermGCD assertMainQueueSafe];
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate immutableColorMap:self.mainThreadCopy.colorMap didChangeColorForKey:theKey from:before to:after];
}

- (void)colorMap:(iTermColorMap *)colorMap dimmingAmountDidChangeTo:(double)dimmingAmount {
    [iTermGCD assertMainQueueSafe];
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate immutableColorMap:self.mainThreadCopy.colorMap dimmingAmountDidChangeTo:dimmingAmount];

}
- (void)colorMap:(iTermColorMap *)colorMap mutingAmountDidChangeTo:(double)mutingAmount {
    [iTermGCD assertMainQueueSafe];
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate immutableColorMap:self.mainThreadCopy.colorMap mutingAmountDidChangeTo:mutingAmount];
}

#pragma mark - iTermTemporaryDoubleBufferedGridControllerDelegate

- (PTYTextViewSynchronousUpdateState *)temporaryDoubleBufferedGridSavedState {
    PTYTextViewSynchronousUpdateState *state = [[PTYTextViewSynchronousUpdateState alloc] init];

    state.grid = self.currentGrid.copy;
    // The grid can't be copied later unless it has a delegate. Use _state since it is an immutable snapshot of this point in time.
    state.grid.delegate = self;

    state.colorMap = self.colorMap.copy;
    state.cursorVisible = self.temporaryDoubleBuffer.explicit ? self.cursorVisible : YES;

    return state;
}

- (void)temporaryDoubleBufferedGridDidExpire {
    [self.currentGrid setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [self redrawSoon];
}

#pragma mark - PTYAnnotationDelegate

- (void)annotationDidRequestHide:(id<PTYAnnotationReading>)annotation {
}

- (void)annotationStringDidChange:(id<PTYAnnotationReading>)annotation {
}

- (void)annotationWillBeRemoved:(id<PTYAnnotationReading>)annotation {
}

- (void)highlight {
}

- (BOOL)setNoteHidden:(BOOL)hidden {
    return NO;
}

#pragma mark - iTermEventuallyConsistentIntervalTreeSideEffectPerformer

- (void)addEventuallyConsistentIntervalTreeSideEffect:(void (^)(void))block {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        block();
    }];
}

#pragma mark - iTermTokenExecutorDelegate

- (BOOL)tokenExecutorShouldQueueTokens {
    const NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    self.primaryGrid.currentDate = now;
    self.altGrid.currentDate = now;

    if (!self.terminalEnabled) {
        return YES;
    }
    if (self.taskPaused) {
        return YES;
    }
    if (self.copyMode) {
        return YES;
    }
    if (self.shortcutNavigationMode) {
        return YES;
    }
    return NO;
}

- (BOOL)tokenExecutorShouldDiscardTokensWithHighPriority:(BOOL)highPriority {
    if (_exited) {
        return YES;
    }
    if (!_terminalEnabled) {
        return YES;
    }
    if (!highPriority && !_isTmuxGateway && _hasMuteCoprocess) {
        return YES;
    }
    if (_suppressAllOutput) {
        return YES;
    }
    return NO;
}

- (void)tokenExecutorDidExecuteWithLength:(NSInteger)length throughput:(NSInteger)throughput {
    [_executorUpdate addBytesExecuted:length];
    _executorUpdate.estimatedThroughput = throughput;
    [_executorUpdateScheduler markNeedsUpdate];
}

- (NSString *)tokenExecutorCursorCoordString {
    return VT100GridCoordDescription(self.currentGrid.cursor);
}

// Main queue or mutation queue while joined.
- (void)tokenExecutorSync {
    DLog(@"tokenExecutorSync");
    [self performLightweightBlockWithJoinedThreads:^(VT100ScreenMutableState * _Nonnull mutableState) {
        [self performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenSync:mutableState];
        }];
    }];
}

// Runs on mutation queue
- (void)tokenExecutorWillExecuteTokens {
    DLog(@"begin");
    [self.linebuffer ensureLastBlockUncopied];
}

// Runs on the main thread or while joined.
- (void)tokenExecutorHandleSideEffectFlags:(int64_t)flags {
    DLog(@"tokenExecutorHandleSideEffectFlags:%llx", (long long)flags);
    if (flags & VT100ScreenMutableStateSideEffectFlagNeedsRedraw) {
        [self performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenNeedsRedraw];
        }];
    }
    if (flags & VT100ScreenMutableStateSideEffectFlagIntervalTreeVisibleRangeDidChange) {
        [self performIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver> observer) {
            [observer intervalTreeVisibleRangeDidChange];
        }];
    }
    if (flags & VT100ScreenMutableStateSideEffectFlagDidReceiveLineFeed) {
        [self performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenDidReceiveLineFeed];
        }];
    }
    if (flags & VT100ScreenMutableStateSideEffectFlagLineBufferDidDropLines) {
        [self performSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenRefreshFindOnPageView];
        }];
    }
}

- (void)willSendReport {
    const int newCount = ++_pendingReportCount;
    DLog(@"_pendingReportCount += 1 -> %@", @(newCount));
}

- (void)didSendReport:(id<VT100ScreenDelegate>)delegate {
    const int newCount = --_pendingReportCount;
    DLog(@"_pendingReportCount -= 1 -> %@", @(newCount));
    if (newCount == 0) {
        [delegate screenDidSendAllPendingReports];
    }
}

// Main queue
- (BOOL)sendingIsBlocked {
    const BOOL result = _pendingReportCount > 0;
    DLog(@"Block sending");
    return result;
}

#pragma mark - iTermLineBufferDelegate

- (void)lineBufferDidDropLines:(LineBuffer *)lineBuffer {
    if (lineBuffer == self.linebuffer) {
        [_tokenExecutor setSideEffectFlagWithValue:VT100ScreenMutableStateSideEffectFlagLineBufferDidDropLines];
    }
}

#pragma mark - iTermPromptStateMachineDelegate

- (VT100GridAbsCoord)promptStateMachineCursorAbsCoord {
    return VT100GridAbsCoordMake(self.currentGrid.cursor.x,
                                 self.currentGrid.cursor.y + self.cumulativeScrollbackOverflow);
}

- (void)promptStateMachineRevealComposerWithPrompt:(NSArray<ScreenCharArray *> *)prompt {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenRevealComposerWithPrompt:prompt];
        [unpauser unpause];
    }];
}

- (void)promptStateMachineDismissComposer {
    if (!self.config.autoComposerEnabled) {
        return;
    }
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenDismissComposer];
        [unpauser unpause];
    }];
}

- (NSArray<ScreenCharArray *> *)promptStateMachineLastPrompt {
    id<VT100ScreenMarkReading> mark = [self lastPromptMark];
    return mark.promptText;
}

- (void)promptStateMachineAppendCommandToComposer:(NSString *)command {
    if (!self.config.autoComposerEnabled) {
        return;
    }
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenAppendStringToComposer:command];
        [unpauser unpause];
    }];
}

- (void)promptStateMachineCheckForPrompt {
    DLog(@"Prompt check requested");
    if (_triggerEvaluator.havePromptDetectingTrigger) {
        DLog(@"Have a prompt-detecting trigger");
        [_triggerEvaluator resetRateLimit];
        [self performPeriodicTriggerCheck];
    }
}

@end


@implementation VT100ScreenTokenExecutorUpdate {
    NSInteger _numberOfBytesExecuted;
    BOOL _inputHandled;
}

- (void)addBytesExecuted:(NSInteger)size {
    @synchronized (self) {
        _dirty = YES;
        _numberOfBytesExecuted += size;
    }
}

- (NSInteger)numberOfBytesExecuted {
    @synchronized (self) {
        return _numberOfBytesExecuted;
    }
}

- (void)didHandleInput {
    @synchronized (self) {
        _dirty = YES;
        _inputHandled = YES;
    }
}

- (BOOL)inputHandled {
    @synchronized (self) {
        return _inputHandled;
    }
}

- (VT100ScreenTokenExecutorUpdate *)fork {
    @synchronized (self) {
        VT100ScreenTokenExecutorUpdate *copy = [self copyWithZone:nil];
        _numberOfBytesExecuted = 0;
        _inputHandled = NO;
        return copy;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    @synchronized (self) {
        VT100ScreenTokenExecutorUpdate *copy = [[VT100ScreenTokenExecutorUpdate alloc] init];
        [copy addBytesExecuted:_numberOfBytesExecuted];
        if (_inputHandled) {
            [copy didHandleInput];
        }
        copy.estimatedThroughput = self.estimatedThroughput;
        return copy;
    }
}

@end

