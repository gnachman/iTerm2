//
//  VT100ScreenMutableState.m
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"
#import "VT100ScreenState+Private.h"

#import "DebugLogging.h"
#import "PTYAnnotation.h"
#import "PTYTriggerEvaluator.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenConfiguration.h"
#import "VT100ScreenDelegate.h"
#import "VT100WorkingDirectory.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermOrderEnforcer.h"

@interface VT100ScreenMutableState()<PTYTriggerEvaluatorDelegate, iTermMarkDelegate>
@property (atomic) BOOL hadCommand;
@end

@implementation VT100ScreenMutableState {
    VT100GridCoordRange _previousCommandRange;
    iTermIdempotentOperationJoiner *_commandRangeChangeJoiner;
    dispatch_queue_t _queue;
}

- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer {
    self = [super initForMutation];
    if (self) {
#warning TODO: When this moves to its own queue. change _queue.
        _queue = dispatch_get_main_queue();
        _sideEffectPerformer = performer;
        _setWorkingDirectoryOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _currentDirectoryDidChangeOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _previousCommandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
        _commandRangeChangeJoiner = [iTermIdempotentOperationJoiner asyncJoiner:_queue];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenState alloc] initWithState:self];
}

- (id<VT100ScreenState>)copy {
    return [self copyWithZone:nil];
}

#pragma mark - Private

- (void)assertOnMutationThread {
#warning TODO: Change this when creating the mutation thread.
    assert([NSThread isMainThread]);
}

#pragma mark - Internal

#warning TODO: I think side effects should happen atomically with copying state from mutable-to-immutable. Likewise, when the main thread needs to sync when resizing a screen, it should be able to force all these side-effects to happen synchronously.
- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect {
    [self.sideEffects addSideEffect:sideEffect];
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf performSideEffects];
    });
}

- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect {
    [self.sideEffects addIntervalTreeSideEffect:sideEffect];
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf performSideEffects];
    });
}

- (void)performSideEffects {
    id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    if (!delegate) {
        return;
    }
    [self.sideEffects executeWithDelegate:delegate
                     intervalTreeObserver:self.sideEffectPerformer.sideEffectPerformingIntervalTreeObserver];
}

- (void)setNeedsRedraw {
    if (self.needsRedraw) {
        return;
    }
    self.needsRedraw = YES;
    __weak __typeof(self) weakSelf = self;
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
#warning TODO: When a general syncing mechanism is developed, the assignment should occur there. This is kinda racey.
        weakSelf.needsRedraw = NO;
        [delegate screenNeedsRedraw];
    }];
}

#pragma mark - Scrollback

- (void)incrementOverflowBy:(int)overflowCount {
    if (overflowCount > 0) {
        self.scrollbackOverflow += overflowCount;
        self.cumulativeScrollbackOverflow += overflowCount;
    }
    [self.intervalTreeObserver intervalTreeVisibleRangeDidChange];
}

#pragma mark - Terminal Fundamentals

- (void)appendLineFeed {
    LineBuffer *lineBufferToUse = self.linebuffer;
    const BOOL noScrollback = (self.currentGrid == self.altGrid && !self.saveToScrollbackInAlternateScreen);
    if (noScrollback) {
        // In alt grid but saving to scrollback in alt-screen is off, so pass in a nil linebuffer.
        lineBufferToUse = nil;
    }
    [self incrementOverflowBy:[self.currentGrid moveCursorDownOneLineScrollingIntoLineBuffer:lineBufferToUse
                                                                         unlimitedScrollback:self.unlimitedScrollback
                                                                     useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                                  willScroll:^{
        if (noScrollback) {
            [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                // This isn't really necessary, although it has been this way for a very long time.
                // In theory we could truncate the selection to not begin in scrollback history.
                // Note that this happens in alternate screen mode when not adding to history.
                // Regardless of what we do the behavior is going to be strange.
                [delegate screenRemoveSelection];
            }];
        }
    }]];
}

- (void)appendCarriageReturnLineFeed {
    [self appendLineFeed];
    self.currentGrid.cursorX = 0;
}

- (void)softAlternateScreenModeDidChange {
    const BOOL enabled = self.terminal.softAlternateScreenMode;
    const BOOL showing = self.currentGrid == self.altGrid;;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSoftAlternateScreenModeDidChangeTo:enabled showingAltScreen:showing];
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
    string = StringByNormalizingString(string, self.normalization);
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
                        self.normalization,
                        self.config.unicodeVersion);
    ssize_t bufferOffset = 0;
    if (augmented && len > 0) {
        screen_char_t *theLine = [self.currentGrid screenCharsAtLineNumber:pred.y];
        theLine[pred.x].code = buffer[0].code;
        theLine[pred.x].complexChar = buffer[0].complexChar;
        bufferOffset++;

        // Does the augmented result begin with a double-width character? If so skip over the
        // DWC_RIGHT when appending. I *think* this is redundant with the `predecessorIsDoubleWidth`
        // test but I'm reluctant to remove it because it could break something.
        const BOOL augmentedResultBeginsWithDoubleWidthCharacter = (augmented &&
                                                                    len > 1 &&
                                                                    buffer[1].code == DWC_RIGHT &&
                                                                    !buffer[1].complexChar);
        if ((augmentedResultBeginsWithDoubleWidthCharacter || predecessorIsDoubleWidth) && len > 1 && buffer[1].code == DWC_RIGHT) {
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
        if (lastCharacter.code == DWC_RIGHT && !lastCharacter.complexChar) {
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
        iTermImmutableMetadata temp;
        iTermImmutableMetadataInit(&temp, 0, externalAttributes);
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenAppendScreenCharArray:buffer
                                         metadata:temp
                                           length:len];
        }];
        iTermImmutableMetadataRelease(temp);
    }

    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

#pragma mark - Interval Tree

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass {
    id<iTermMark> mark = [[markClass alloc] init];
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = mark;
        screenMark.delegate = self;
        screenMark.sessionGuid = self.config.sessionGuid;
    }
    long long totalOverflow = self.cumulativeScrollbackOverflow;
    if (line < totalOverflow || line > totalOverflow + self.numberOfLines) {
        return nil;
    }
    int nonAbsoluteLine = line - totalOverflow;
    VT100GridCoordRange range;
    if (oneLine) {
        range = VT100GridCoordRangeMake(0, nonAbsoluteLine, self.width, nonAbsoluteLine);
    } else {
        // Interval is whole screen
        int limit = nonAbsoluteLine + self.height - 1;
        if (limit >= self.numberOfScrollbackLines + [self.currentGrid numberOfLinesUsed]) {
            limit = self.numberOfScrollbackLines + [self.currentGrid numberOfLinesUsed] - 1;
        }
        range = VT100GridCoordRangeMake(0,
                                        nonAbsoluteLine,
                                        self.width,
                                        limit);
    }
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        self.markCache[@(self.cumulativeScrollbackOverflow + range.end.y)] = mark;
    }
    [self.intervalTree addObject:mark withInterval:[self intervalForGridCoordRange:range]];

    const iTermIntervalTreeObjectType objectType = iTermIntervalTreeObjectTypeForObject(mark);
    const long long absLine = range.start.y + self.cumulativeScrollbackOverflow;
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidAddObjectOfType:objectType
                                          onLine:absLine];
    }];
    [self setNeedsRedraw];
    return mark;
}

#pragma mark - Shell Integration

- (void)assignCurrentCommandEndDate {
    VT100ScreenMark *screenMark = self.lastCommandMark;
    if (!screenMark.endDate) {
#warning TODO: This mutates a shared object.
        screenMark.endDate = [NSDate date];
    }
}

- (id<iTermMark>)addMarkOnLine:(int)line ofClass:(Class)markClass {
    DLog(@"addMarkOnLine:%@ ofClass:%@", @(line), markClass);
    id<iTermMark> newMark = [self addMarkStartingAtAbsoluteLine:self.cumulativeScrollbackOverflow + line
                                                        oneLine:YES
                                                        ofClass:markClass];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenDidAddMark:newMark];
    }];
    return newMark;
}

- (void)didUpdatePromptLocation {
    DLog(@"didUpdatePromptLocation %@", self);
    self.shouldExpectPromptMarks = YES;
}

- (void)setPromptStartLine:(int)line {
    DLog(@"FinalTerm: prompt started on line %d. Add a mark there. Save it as lastPromptLine.", line);
    // Reset this in case it's taking the "real" shell integration path.
    self.fakePromptDetectedAbsLine = -1;
    const long long lastPromptLine = (long long)line + self.cumulativeScrollbackOverflow;
    self.lastPromptLine = lastPromptLine;
    [self assignCurrentCommandEndDate];
    VT100ScreenMark *mark = [self addMarkOnLine:line ofClass:[VT100ScreenMark class]];
    [mark setIsPrompt:YES];
    mark.promptRange = VT100GridAbsCoordRangeMake(0, lastPromptLine, 0, lastPromptLine);
    [self didUpdatePromptLocation];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenPromptDidStartAtLine:line];
    }];
}

- (void)promptDidStartAt:(VT100GridAbsCoord)coord {
    DLog(@"FinalTerm: mutPromptDidStartAt");
    if (coord.x > 0 && self.config.shouldPlacePromptAtFirstColumn) {
        [self appendCarriageReturnLineFeed];
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
    [self setPromptStartLine:self.numberOfScrollbackLines + self.cursorY - 1];
    if ([iTermAdvancedSettingsModel resetSGROnPrompt]) {
        [self.terminal resetGraphicRendition];
    }
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
        VT100ScreenMark *mark = [self markOnLine:self.lastPromptLine - self.cumulativeScrollbackOverflow];
        mark.commandRange = VT100GridAbsCoordRangeFromCoordRange(current, self.cumulativeScrollbackOverflow);
        if (!self.hadCommand) {
            mark.promptRange = VT100GridAbsCoordRangeMake(0,
                                                          self.lastPromptLine,
                                                          current.start.x,
                                                          mark.commandRange.end.y);
        }
    }
    NSString *command = haveCommand ? [self commandInRange:current] : @"";

    __weak __typeof(self) weakSelf = self;
    [_commandRangeChangeJoiner setNeedsUpdateWithBlock:^{
        assert([NSThread isMainThread]);
        [weakSelf notifyDelegateOfCommandChange:command
                                       atPrompt:atPrompt
                                    haveCommand:haveCommand
                            sideEffectPerformer:weakSelf.sideEffectPerformer];
    }];
}

- (void)notifyDelegateOfCommandChange:(NSString *)command
                             atPrompt:(BOOL)atPrompt
                          haveCommand:(BOOL)haveCommand
                  sideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)sideEffectPerformer {
    assert([NSThread isMainThread]);

    __weak id<VT100ScreenDelegate> delegate = sideEffectPerformer.sideEffectPerformingScreenDelegate;
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
    VT100WorkingDirectory *workingDirectoryObj = [[VT100WorkingDirectory alloc] init];
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
        workingDirectoryObj.workingDirectory = workingDirectory;

        VT100WorkingDirectory *previousWorkingDirectory = [self objectOnOrBeforeLine:line
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
            [self.intervalTree removeObject:previousWorkingDirectory];
            range.end = VT100GridCoordMake(self.width, line);
            DLog(@"Extending the previous directory to %@", VT100GridCoordRangeDescription(range));
            Interval *interval = [self intervalForGridCoordRange:range];
            [self.intervalTree addObject:previousWorkingDirectory withInterval:interval];
        } else {
            VT100GridCoordRange range;
            range = VT100GridCoordRangeMake(self.currentGrid.cursorX, line, self.width, line);
            DLog(@"Set range of %@ to %@", workingDirectory, VT100GridCoordRangeDescription(range));
            [self.intervalTree addObject:workingDirectoryObj
                            withInterval:[self intervalForGridCoordRange:range]];
        }
    }
    VT100RemoteHost *remoteHost = [self remoteHostOnLine:line];
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
                                   onAbsLine:(long long)cursorAbsLine {
    DLog(@"currentDirectoryReallyDidChangeTo:%@ onAbsLine:%@", dir, @(cursorAbsLine));
    BOOL willChange = ![dir isEqualToString:[self workingDirectoryOnLine:cursorAbsLine - self.cumulativeScrollbackOverflow]];
    [self setWorkingDirectory:dir
                    onAbsLine:cursorAbsLine
                       pushed:YES
                        token:nil];
    if (willChange) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenCurrentDirectoryDidChangeTo:dir];
        }];
    }
}

- (void)currentDirectoryDidChangeTo:(NSString *)dir {
    DLog(@"%p: terminalCurrentDirectoryDidChangeTo:%@", self, dir);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetPreferredProxyIcon:nil]; // Clear current proxy icon if exists.
    }];

    const int cursorLine = self.numberOfLines - self.height + self.currentGrid.cursorY;
    const long long cursorAbsLine = self.cumulativeScrollbackOverflow + cursorLine;
    if (dir.length) {
        [self currentDirectoryReallyDidChangeTo:dir onAbsLine:cursorAbsLine];
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
            [weakSelf currentDirectoryReallyDidChangeTo:workingDirectory onAbsLine:cursorAbsLine];
        }];
    }];
}

- (void)setRemoteHostFromString:(NSString *)remoteHost {
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
    VT100RemoteHost *currentHost = [self remoteHostOnLine:self.numberOfLines];
    if (!host || !user) {
        // A trigger can set the host and user alone. If remoteHost looks like example.com or
        // user@, then preserve the previous host/user. Also ensure neither value is nil; the
        // empty string will stand in for a real value if necessary.
        VT100RemoteHost *lastRemoteHost = [self lastRemoteHost];
        if (!host) {
            host = [lastRemoteHost.hostname copy] ?: @"";
        }
        if (!user) {
            user = [lastRemoteHost.username copy] ?: @"";
        }
    }

    const int cursorLine = self.numberOfLines - self.height + self.currentGrid.cursorY;
    VT100RemoteHost *remoteHostObj = [self setRemoteHost:host user:user onLine:cursorLine];

    if (![remoteHostObj isEqualToRemoteHost:currentHost]) {
        const int line = [self numberOfScrollbackLines] + self.cursorY;
        NSString *pwd = [self workingDirectoryOnLine:line];
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenCurrentHostDidChange:remoteHostObj pwd:pwd];
        }];
    }
}

- (VT100RemoteHost *)setRemoteHost:(NSString *)host user:(NSString *)user onLine:(int)line {
    VT100RemoteHost *remoteHostObj = [[VT100RemoteHost alloc] init];
    remoteHostObj.hostname = host;
    remoteHostObj.username = user;
    VT100GridCoordRange range = VT100GridCoordRangeMake(0, line, self.width, line);
    [self.intervalTree addObject:remoteHostObj
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
    VT100ScreenMark *mark = self.lastCommandMark;
    if (mark) {
        DLog(@"FinalTerm: setting code on mark %@", mark);
        const NSInteger line = [self coordRangeForInterval:mark.entry.interval].start.y + self.cumulativeScrollbackOverflow;
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:iTermIntervalTreeObjectTypeForObject(mark)
                                                                onLine:line];
        mark.code = returnCode;
        [self.intervalTreeObserver intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeForObject(mark)
                                                             onLine:line];
        VT100RemoteHost *remoteHost = [self remoteHostOnLine:self.numberOfLines];
#warning TODO: mark is mutable shared state. Don't pass to main thread like this.
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenDidUpdateReturnCodeForMark:mark
                                            remoteHost:remoteHost];
        }];
    } else {
        DLog(@"No last command mark found.");
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
#warning TODO: mark is mutable shared state. Don't pass to main thread like this.
        [delegate screenCommandDidExitWithCode:returnCode mark:mark];
    }];
}

#pragma mark - Annotations

- (void)removeAnnotation:(PTYAnnotation *)annotation {
    if ([self.intervalTree containsObject:annotation]) {
        self.lastCommandMark = nil;
        const iTermIntervalTreeObjectType type = iTermIntervalTreeObjectTypeForObject(annotation);
        const long long absLine = [self coordRangeForInterval:annotation.entry.interval].start.y + self.cumulativeScrollbackOverflow;
        [self.intervalTree removeObject:annotation];
        [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
            [observer intervalTreeDidRemoveObjectOfType:type
                                                 onLine:absLine];
        }];
    } else if ([self.savedIntervalTree containsObject:annotation]) {
        self.lastCommandMark = nil;
        [self.savedIntervalTree removeObject:annotation];
    }
    [self setNeedsRedraw];
}

- (void)addAnnotation:(PTYAnnotation *)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus {
    [self.intervalTree addObject:annotation withInterval:[self intervalForGridCoordRange:range]];
    [self.currentGrid markAllCharsDirty:YES];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenDidAddNote:annotation focus:focus];
    }];
    const long long line = range.start.y + self.cumulativeScrollbackOverflow;
    [self addIntervalTreeSideEffect:^(id<iTermIntervalTreeObserver>  _Nonnull observer) {
        [observer intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeAnnotation
                                          onLine:line];
    }];
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


#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    [self assertOnMutationThread];
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        self.lastCommandMark = mark;
    }
}

#pragma mark - PTYTriggerEvaluatorDelegate

- (BOOL)triggerEvaluatorShouldUseTriggers:(PTYTriggerEvaluator *)evaluator {
    if (![self.terminal softAlternateScreenMode]) {
        return YES;
    }
    return self.config.enableTriggersInInteractiveApps;
}

- (void)triggerEvaluatorOfferToDisableTriggersInInteractiveApps:(PTYTriggerEvaluator *)evaluator {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenOfferToDisableTriggersInInteractiveApps];
    }];
}

#pragma mark - iTermTriggerSession

#warning TODO: Move triggerSession impls here from PTYSession
- (void)triggerSessionRingBell:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSessionRingBell:trigger];
}

- (void)triggerSessionShowCapturedOutputTool:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSessionShowCapturedOutputTool:trigger];
}

- (BOOL)triggerSessionIsShellIntegrationInstalled:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    return [delegate triggerSessionIsShellIntegrationInstalled:trigger];
}

- (void)triggerSessionShowShellIntegrationRequiredAnnouncement:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSessionShowShellIntegrationRequiredAnnouncement:trigger];
}

- (void)triggerSession:(Trigger *)trigger didCaptureOutput:(CapturedOutput *)output {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger didCaptureOutput:output];
}

- (void)triggerSessionShowCapturedOutputToolNotVisibleAnnouncementIfNeeded:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSessionShowCapturedOutputToolNotVisibleAnnouncementIfNeeded:trigger];
}

- (void)triggerSession:(Trigger *)trigger launchCoprocessWithCommand:(NSString *)command identifier:(NSString * _Nullable)identifier silent:(BOOL)silent {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger launchCoprocessWithCommand:command identifier:identifier silent:silent];
}

- (id<iTermTriggerScopeProvider>)triggerSessionVariableScopeProvider:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    return [delegate triggerSessionVariableScopeProvider:trigger];
}

- (BOOL)triggerSessionShouldUseInterpolatedStrings:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    return [delegate triggerSessionShouldUseInterpolatedStrings:trigger];
}

- (void)triggerSessionMakeFirstResponder:(Trigger *)trigger {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSessionMakeFirstResponder:trigger];
}

- (void)triggerSession:(Trigger *)trigger postUserNotificationWithMessage:(NSString *)message {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger postUserNotificationWithMessage:message];
}

- (void)triggerSession:(Trigger *)trigger
  highlightTextInRange:(NSRange)rangeInScreenChars
          absoluteLine:(long long)lineNumber
                colors:(NSDictionary<NSString *, NSColor *> *)colors {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger highlightTextInRange:rangeInScreenChars absoluteLine:lineNumber colors:colors];
}

- (void)triggerSession:(Trigger *)trigger saveCursorLineAndStopScrolling:(BOOL)stopScrolling {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger saveCursorLineAndStopScrolling:stopScrolling];
}

- (void)triggerSession:(Trigger *)trigger openPasswordManagerToAccountName:(NSString *)accountName {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger openPasswordManagerToAccountName:accountName];
}

- (void)triggerSession:(Trigger *)trigger
            runCommand:(NSString *)command
        withRunnerPool:(iTermBackgroundCommandRunnerPool *)pool {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger runCommand:command withRunnerPool:pool];
}

- (void)triggerSession:(Trigger *)trigger writeText:(NSString *)text {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger writeText:text];
}

- (void)triggerSession:(Trigger *)trigger setRemoteHostName:(NSString *)remoteHost {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger setRemoteHostName:remoteHost];
}

- (void)triggerSession:(Trigger *)trigger setCurrentDirectory:(NSString *)text {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger setCurrentDirectory:text];
}

- (void)triggerSession:(Trigger *)trigger didChangeNameTo:(NSString *)newName {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger didChangeNameTo:newName];
}

- (void)triggerSession:(Trigger *)trigger didDetectPromptAt:(VT100GridAbsCoordRange)range {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger didDetectPromptAt:range];
}

- (void)triggerSession:(Trigger *)trigger
    makeHyperlinkToURL:(NSURL *)url
               inRange:(NSRange)rangeInString
                  line:(long long)lineNumber {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger makeHyperlinkToURL:url inRange:rangeInString line:lineNumber];
}

- (void)triggerSession:(Trigger *)trigger
                invoke:(NSString *)invocation
         withVariables:(NSDictionary *)temporaryVariables
              captures:(NSArray<NSString *> *)captureStringArray {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger invoke:invocation withVariables:temporaryVariables captures:captureStringArray];
}

- (void)triggerSession:(Trigger *)trigger
         setAnnotation:(PTYAnnotation *)annotation
              stringTo:(NSString *)stringValue {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger setAnnotation:annotation stringTo:stringValue];
}

- (void)triggerSession:(Trigger *)trigger
       highlightLineAt:(VT100GridAbsCoord)absCoord
                colors:(NSDictionary *)colors {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger highlightLineAt:absCoord colors:colors];
}

- (void)triggerSession:(Trigger *)trigger injectData:(NSData *)data {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger injectData:data];
}

- (void)triggerSession:(Trigger *)trigger setVariableNamed:(NSString *)name toValue:(id)value {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger setVariableNamed:name toValue:value];
}

- (void)triggerSession:(Trigger *)trigger
  showAlertWithMessage:(NSString *)message
             rateLimit:(iTermRateLimitedUpdate *)rateLimit
               disable:(void (^)(void))disable {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    [delegate triggerSession:trigger showAlertWithMessage:message rateLimit:rateLimit disable:disable];
}

- (PTYAnnotation * _Nullable)triggerSession:(Trigger *)trigger
                      makeAnnotationInRange:(NSRange)rangeInScreenChars
                                       line:(long long)lineNumber {
    id<iTermTriggerSession> delegate = (id<iTermTriggerSession>)self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
    return [delegate triggerSession:trigger makeAnnotationInRange:rangeInScreenChars line:lineNumber];
}


@end
