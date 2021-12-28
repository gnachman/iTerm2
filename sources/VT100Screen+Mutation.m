//
//  VT100Screen+Mutation.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

// For mysterious reasons this needs to be in the iTerm2XCTests to avoid runtime failures to call
// its methods in tests. If I ever have an appetite for risk try https://stackoverflow.com/a/17581430/321984
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Resizing.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100RemoteHost.h"
#import "VT100Screen+Private.h"
#import "VT100Token.h"
#import "VT100WorkingDirectory.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO.h"
#import "iTermImageMark.h"
#import "iTermNotificationController.h"
#import "iTermOrderEnforcer.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermShellHistoryController.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "iTermTextExtractor.h"
#import "iTermURLMark.h"

#include <sys/time.h>

#warning TODO: I can't call regular VT100Screen methods from here because they'll use _state instead of _mutableState! I think this should eventually be its own class, not a category, to enfore the shared-nothing regime.

@implementation VT100Screen (Mutation)

- (VT100Grid *)mutableAltGrid {
    return (VT100Grid *)_state.altGrid;
}

- (VT100Grid *)mutablePrimaryGrid {
    return (VT100Grid *)_state.primaryGrid;
}

- (LineBuffer *)mutableLineBuffer {
    return (LineBuffer *)_mutableState.linebuffer;
}

- (void)mutUpdateConfig {
    [_config autorelease];
    _config = [_nextConfig retain];
}

- (void)setNeedsRedraw {
    if (_mutableState.needsRedraw) {
        return;
    }
    _mutableState.needsRedraw = YES;
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        _mutableState.needsRedraw = NO;
        [delegate screenNeedsRedraw];
#warning TODO: When a general syncing mechanism is developed, the assignment should occur there. This is kinda racey.
    }];
}

#pragma mark - FinalTerm

- (void)mutPromptDidStartAt:(VT100GridAbsCoord)coord {
    DLog(@"FinalTerm: mutPromptDidStartAt");
    if (coord.x > 0 && _config.shouldPlacePromptAtFirstColumn) {
        [_mutableState appendCarriageReturnLineFeed];
    }
    _mutableState.shellIntegrationInstalled = YES;

    _mutableState.lastCommandOutputRange = VT100GridAbsCoordRangeMake(_state.startOfRunningCommandOutput.x,
                                                                      _state.startOfRunningCommandOutput.y,
                                                                      coord.x,
                                                                      coord.y);
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(coord.x,
                                                                  coord.y,
                                                                  coord.x,
                                                                  coord.y);

    // FinalTerm uses this to define the start of a collapsible region. That would be a nightmare
    // to add to iTerm, and our answer to this is marks, which already existed anyway.
    [self mutSetPromptStartLine:_mutableState.numberOfScrollbackLines + _mutableState.cursorY - 1];
    if ([iTermAdvancedSettingsModel resetSGROnPrompt]) {
        [_mutableState.terminal resetGraphicRendition];
    }
}

- (void)mutSetLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange {
    _mutableState.lastCommandOutputRange = lastCommandOutputRange;
}

// End of command prompt, will start accepting command to run as the user types at the prompt.
- (void)mutCommandDidStart {
    DLog(@"FinalTerm: terminalCommandDidStart");
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(_state.currentPromptRange.start.x,
                                                                  _state.currentPromptRange.start.y,
                                                                  _state.currentGrid.cursor.x,
                                                                  _state.currentGrid.cursor.y + _mutableState.numberOfScrollbackLines + self.totalScrollbackOverflow);
    [self commandDidStartAtScreenCoord:_state.currentGrid.cursor];
    const int line = _mutableState.numberOfScrollbackLines + _mutableState.cursorY - 1;
    VT100ScreenMark *mark = [self updatePromptMarkRangesForPromptEndingOnLine:line];
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenPromptDidEndWithMark:mark];
    }];
}

- (VT100ScreenMark *)updatePromptMarkRangesForPromptEndingOnLine:(int)line {
#warning TODO: -lastPromptMark should be a method on VT100ScreenState since I need this to operate on the mutable copy of tstate.
    VT100ScreenMark *mark = [self lastPromptMark];
    const int x = _mutableState.currentGrid.cursor.x;
    const long long y = (long long)line + _mutableState.cumulativeScrollbackOverflow;
#warning TODO: modifies shared state. I need a way to sync this back to the main thread later.
    mark.promptRange = VT100GridAbsCoordRangeMake(mark.promptRange.start.x,
                                                  mark.promptRange.end.y,
                                                  x,
                                                  y);
    mark.commandRange = VT100GridAbsCoordRangeMake(x, y, x, y);
    return mark;
}

- (void)mutCommandDidEnd {
    DLog(@"FinalTerm: terminalCommandDidEnd");
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(0, 0, 0, 0);

    [self commandDidEndAtAbsCoord:VT100GridAbsCoordMake(_state.currentGrid.cursor.x, _state.currentGrid.cursor.y + _mutableState.numberOfScrollbackLines + _mutableState.cumulativeScrollbackOverflow)];
}

- (BOOL)mutCommandDidEndAtAbsCoord:(VT100GridAbsCoord)coord {
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [self mutCommandDidEndWithRange:[self commandRange]];
        [self mutInvalidateCommandStartCoord];
        _mutableState.startOfRunningCommandOutput = coord;
        return YES;
    }
    return NO;
}

#pragma mark - Interval Tree

- (void)mutCommandDidEndWithRange:(VT100GridCoordRange)range {
    NSString *command = [self commandInRange:range];
    DLog(@"FinalTerm: Command <<%@>> ended with range %@",
         command, VT100GridCoordRangeDescription(range));
    VT100ScreenMark *mark = nil;
    if (command) {
        NSString *trimmedCommand =
            [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedCommand.length) {
            mark = [self markOnLine:self.lastPromptLine - _mutableState.cumulativeScrollbackOverflow];
#warning TODO: This modifies shared state
            DLog(@"FinalTerm:  Make the mark on lastPromptLine %lld (%@) a command mark for command %@",
                 _mutableState.lastPromptLine - _mutableState.cumulativeScrollbackOverflow, mark, command);
            mark.command = command;
            mark.commandRange = VT100GridAbsCoordRangeFromCoordRange(range, _mutableState.cumulativeScrollbackOverflow);
            mark.outputStart = VT100GridAbsCoordMake(_mutableState.currentGrid.cursor.x,
                                                     _mutableState.currentGrid.cursor.y + [_mutableState.linebuffer numLinesWithWidth:_mutableState.currentGrid.size.width] + _mutableState.cumulativeScrollbackOverflow);
            [[mark retain] autorelease];
        }
    }
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenDidExecuteCommand:command
                                    range:range
                                   onHost:command ? [self remoteHostOnLine:range.end.y] : nil
                              inDirectory:command ? [self workingDirectoryOnLine:range.end.y] : nil
                                     mark:command ? mark : nil];
    }];
}

- (id<iTermMark>)mutAddMarkOnLine:(int)line ofClass:(Class)markClass {
    DLog(@"addMarkOnLine:%@ ofClass:%@", @(line), markClass);
    id<iTermMark> newMark = [self mutAddMarkStartingAtAbsoluteLine:_mutableState.cumulativeScrollbackOverflow + line
                                                           oneLine:YES
                                                           ofClass:markClass];
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenDidAddMark:newMark];
    }];
    return newMark;
}

- (void)assignCurrentCommandEndDate {
    VT100ScreenMark *screenMark = self.lastCommandMark;
    if (!screenMark.endDate) {
#warning TODO: This mutates a shared object.
        screenMark.endDate = [NSDate date];
    }
}

- (void)mutSetPromptStartLine:(int)line {
    DLog(@"FinalTerm: prompt started on line %d. Add a mark there. Save it as lastPromptLine.", line);
    // Reset this in case it's taking the "real" shell integration path.
    _mutableState.fakePromptDetectedAbsLine = -1;
    const long long lastPromptLine = (long long)line + _mutableState.cumulativeScrollbackOverflow;
    _mutableState.lastPromptLine = lastPromptLine;
    [self assignCurrentCommandEndDate];
    VT100ScreenMark *mark = [self mutAddMarkOnLine:line ofClass:[VT100ScreenMark class]];
    [mark setIsPrompt:YES];
    mark.promptRange = VT100GridAbsCoordRangeMake(0, lastPromptLine, 0, lastPromptLine);
    [self mutDidUpdatePromptLocation];
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenPromptDidStartAtLine:line];
    }];
}

- (void)mutDidUpdatePromptLocation {
    DLog(@"mutDidUpdatePromptLocation %@", self);
    _mutableState.shouldExpectPromptMarks = YES;
}

- (void)mutUserDidPressReturn {
    if (_mutableState.fakePromptDetectedAbsLine >= 0) {
        [self didInferEndOfCommand];
    }
}

- (void)mutSetFakePromptDetectedAbsLine:(long long)value {
    _mutableState.fakePromptDetectedAbsLine = value;
}

- (void)didInferEndOfCommand {
    DLog(@"Inferring end of command");
    VT100GridAbsCoord coord;
    coord.x = 0;
    coord.y = (_mutableState.currentGrid.cursor.y +
               [_mutableState.linebuffer numLinesWithWidth:_mutableState.currentGrid.size.width]
               + _mutableState.cumulativeScrollbackOverflow);
    if (_mutableState.currentGrid.cursorX > 0) {
        // End of command was detected before the newline came in. This is the normal case.
        coord.y += 1;
    }
    if ([self mutCommandDidEndAtAbsCoord:coord]) {
        _mutableState.fakePromptDetectedAbsLine = -2;
    } else {
        // Screen didn't think we were in a command.
        _mutableState.fakePromptDetectedAbsLine = -1;
    }
}

// offset is added to intervals before inserting into interval tree.
- (void)moveNotesOnScreenFrom:(IntervalTree *)source
                           to:(IntervalTree *)dest
                       offset:(long long)offset
                 screenOrigin:(int)screenOrigin {
    VT100GridCoordRange screenRange =
        VT100GridCoordRangeMake(0,
                                screenOrigin,
                                [self width],
                                screenOrigin + self.height);
    DLog(@"  moveNotes: looking in range %@", VT100GridCoordRangeDescription(screenRange));
    Interval *sourceInterval = [self intervalForGridCoordRange:screenRange];
    _mutableState.lastCommandMark = nil;
    for (id<IntervalTreeObject> obj in [source objectsInInterval:sourceInterval]) {
        Interval *interval = [[obj.entry.interval retain] autorelease];
        [[obj retain] autorelease];
        DLog(@"  found note with interval %@", interval);
        [source removeObject:obj];
        interval.location = interval.location + offset;
        DLog(@"  new interval is %@", interval);
        [dest addObject:obj withInterval:interval];
    }
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
- (void)mutSetWorkingDirectory:(NSString *)workingDirectory
#warning TODO: I need to use an absolute line number here to avoid race conditions between main thread and mutation thread.
                        onLine:(int)line
                        pushed:(BOOL)pushed
                         token:(id<iTermOrderedToken>)token {
    DLog(@"%p: setWorkingDirectory:%@ onLine:%d token:%@", self, workingDirectory, line, token);
    VT100WorkingDirectory *workingDirectoryObj = [[[VT100WorkingDirectory alloc] init] autorelease];
    if (token && !workingDirectory) {
        __weak __typeof(self) weakSelf = self;
        DLog(@"%p: Performing async working directory fetch for token %@", self, token);
        [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenGetWorkingDirectoryWithCompletion:^(NSString *path) {
                DLog(@"%p: Async update got %@ for token %@", self, path, token);
                if (path) {
                    [weakSelf mutSetWorkingDirectory:path onLine:line pushed:pushed token:token];
                }
            }];
        }];
        return;
    }

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
    VT100RemoteHost *remoteHost = [self remoteHostOnLine:line];
    const long long absLine = _mutableState.cumulativeScrollbackOverflow + line;
    VT100ScreenWorkingDirectoryPushType pushType;
    if (!pushed) {
        pushType = VT100ScreenWorkingDirectoryPushTypePull;
    } else if (token == nil) {
        pushType = VT100ScreenWorkingDirectoryPushTypeStrongPush;
    } else {
        pushType = VT100ScreenWorkingDirectoryPushTypeWeakPush;
    }
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        const BOOL accepted = !token || [token commit];
        [delegate screenLogWorkingDirectoryOnAbsoluteLine:absLine
                                               remoteHost:remoteHost
                                            withDirectory:workingDirectory
                                                 pushType:pushType
                                                 accepted:accepted];
    }];
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

- (id<iTermMark>)mutAddMarkStartingAtAbsoluteLine:(long long)line
                                          oneLine:(BOOL)oneLine
                                          ofClass:(Class)markClass {
    id<iTermMark> mark = [[[markClass alloc] init] autorelease];
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = mark;
        screenMark.delegate = self;
        screenMark.sessionGuid = _config.sessionGuid;
    }
    long long totalOverflow = _mutableState.cumulativeScrollbackOverflow;
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
        if (limit >= _mutableState.numberOfScrollbackLines + [_state.currentGrid numberOfLinesUsed]) {
            limit = _mutableState.numberOfScrollbackLines + [_state.currentGrid numberOfLinesUsed] - 1;
        }
        range = VT100GridCoordRangeMake(0,
                                        nonAbsoluteLine,
                                        self.width,
                                        limit);
    }
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        _mutableState.markCache[@(_mutableState.cumulativeScrollbackOverflow + range.end.y)] = mark;
    }
    [_mutableState.intervalTree addObject:mark withInterval:[self intervalForGridCoordRange:range]];
    [self.intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:mark]
                                                       onLine:range.start.y + self.totalScrollbackOverflow];
    [self setNeedsRedraw];
    return mark;
}

- (void)mutReloadMarkCache {
    long long totalScrollbackOverflow = _mutableState.cumulativeScrollbackOverflow;
    [_mutableState.markCache removeAllObjects];
    for (id<IntervalTreeObject> obj in [_mutableState.intervalTree allObjects]) {
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
            VT100ScreenMark *mark = (VT100ScreenMark *)obj;
            _mutableState.markCache[@(totalScrollbackOverflow + range.end.y)] = mark;
        }
    }
    [self.intervalTreeObserver intervalTreeDidReset];
}

- (void)mutAddNote:(PTYAnnotation *)annotation
           inRange:(VT100GridCoordRange)range
             focus:(BOOL)focus {
    [_mutableState.intervalTree addObject:annotation withInterval:[self intervalForGridCoordRange:range]];
    [_mutableState.currentGrid markAllCharsDirty:YES];
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenDidAddNote:annotation focus:focus];
        [self.intervalTreeObserver intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeAnnotation
                                                           onLine:range.start.y + self.totalScrollbackOverflow];
    }];
}

- (void)mutCommandWasAborted {
    VT100ScreenMark *screenMark = [self lastCommandMark];
    if (screenMark) {
        DLog(@"Removing last command mark %@", screenMark);
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:screenMark]
                                                              onLine:[self coordRangeForInterval:screenMark.entry.interval].start.y + self.totalScrollbackOverflow];
        [_mutableState.intervalTree removeObject:screenMark];
    }
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
    [self mutDidUpdatePromptLocation];
    [self mutCommandDidEndWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
}

- (void)mutRemoveObjectFromIntervalTree:(id<IntervalTreeObject>)obj {
    long long totalScrollbackOverflow = _mutableState.cumulativeScrollbackOverflow;
    if ([obj isKindOfClass:[VT100ScreenMark class]]) {
        long long theKey = (totalScrollbackOverflow +
                            [self coordRangeForInterval:obj.entry.interval].end.y);
        [_mutableState.markCache removeObjectForKey:@(theKey)];
        _mutableState.lastCommandMark = nil;
    }
    PTYAnnotation *annotation = [PTYAnnotation castFrom:obj];
    if (annotation) {
        [annotation willRemove];
    }
    [_mutableState.intervalTree removeObject:obj];
    iTermIntervalTreeObjectType type = [self intervalTreeObserverTypeForObject:obj];
    if (type != iTermIntervalTreeObjectTypeUnknown) {
        VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:type
                                                              onLine:range.start.y + self.totalScrollbackOverflow];
    }
}

- (void)removePromptMarksBelowLine:(int)line {
    VT100ScreenMark *mark = [self lastPromptMark];
    if (!mark) {
        return;
    }

    VT100GridCoordRange range = [self coordRangeForInterval:mark.entry.interval];
    while (range.start.y >= line) {
        if (mark == self.lastCommandMark) {
            _mutableState.lastCommandMark = nil;
        }
        [self mutRemoveObjectFromIntervalTree:mark];
        mark = [self lastPromptMark];
        if (!mark) {
            return;
        }
        range = [self coordRangeForInterval:mark.entry.interval];
    }
}

- (void)mutRemoveAnnotation:(PTYAnnotation *)annotation {
    if ([_state.intervalTree containsObject:annotation]) {
        _mutableState.lastCommandMark = nil;
        [[annotation retain] autorelease];
        [_mutableState.intervalTree removeObject:annotation];
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:annotation]
                                                              onLine:[self coordRangeForInterval:annotation.entry.interval].start.y + self.totalScrollbackOverflow];
    } else if ([_state.savedIntervalTree containsObject:annotation]) {
        _mutableState.lastCommandMark = nil;
        [_mutableState.savedIntervalTree removeObject:annotation];
    }
    [self setNeedsRedraw];
}

#pragma mark - Clearing

- (void)mutClearBuffer {
    [self mutClearBufferSavingPrompt:YES];
}

- (void)mutClearBufferSavingPrompt:(BOOL)savePrompt {
    // Cancel out the current command if shell integration is in use and we are
    // at the shell prompt.

    const int linesToSave = savePrompt ? [self numberOfLinesToPreserveWhenClearingScreen] : 0;
    // NOTE: This is in screen coords (y=0 is the top)
    VT100GridCoord newCommandStart = VT100GridCoordMake(-1, -1);
    if (_state.commandStartCoord.x >= 0) {
        // Compute the new location of the command's beginning, which is right
        // after the end of the prompt in its new location.
        int numberOfPromptLines = 1;
        if (!VT100GridAbsCoordEquals(_state.currentPromptRange.start, _state.currentPromptRange.end)) {
            numberOfPromptLines = MAX(1, _state.currentPromptRange.end.y - _state.currentPromptRange.start.y + 1);
        }
        newCommandStart = VT100GridCoordMake(_state.commandStartCoord.x, numberOfPromptLines - 1);

        // Abort the current command.
        [self mutCommandWasAborted];
    }
    // There is no last command after clearing the screen, so reset it.
    _mutableState.lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);

    // Clear the grid by scrolling it up into history.
    [self clearAndResetScreenSavingLines:linesToSave];
    // Erase history.
    [self mutClearScrollbackBuffer];

    // Redraw soon.
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenUpdateDisplay:NO];
    }];

    if (savePrompt && newCommandStart.x >= 0) {
        // Create a new mark and inform the delegate that there's new command start coord.
        [self mutSetPromptStartLine:_mutableState.numberOfScrollbackLines];
        [self commandDidStartAtScreenCoord:newCommandStart];
    }
    [_mutableState.terminal resetSavedCursorPositions];
}

- (int)numberOfLinesToPreserveWhenClearingScreen {
    if (VT100GridAbsCoordEquals(_state.currentPromptRange.start, _state.currentPromptRange.end)) {
        // Prompt range not defined.
        return 1;
    }
    if (_state.commandStartCoord.x < 0) {
        // Prompt apparently hasn't ended.
        return 1;
    }
    VT100ScreenMark *lastCommandMark = [self lastPromptMark];
    if (!lastCommandMark) {
        // Never had a mark.
        return 1;
    }

    VT100GridCoordRange lastCommandMarkRange = [self coordRangeForInterval:lastCommandMark.entry.interval];
    int cursorLine = _mutableState.cursorY - 1 + _mutableState.numberOfScrollbackLines;
    int cursorMarkOffset = cursorLine - lastCommandMarkRange.start.y;
    return 1 + cursorMarkOffset;
}

// This clears the screen, leaving the cursor's line at the top and preserves the cursor's x
// coordinate. Scroll regions and the saved cursor position are reset.
- (void)clearAndResetScreenSavingLines:(int)linesToSave {
    [delegate_ screenTriggerableChangeDidOccur];
    // This clears the screen.
    int x = _state.currentGrid.cursorX;
    [_mutableState incrementOverflowBy:[_mutableState.currentGrid resetWithLineBuffer:_mutableState.linebuffer
                                                                unlimitedScrollback:_state.unlimitedScrollback
                                                                 preserveCursorLine:linesToSave > 0
                                                              additionalLinesToSave:MAX(0, linesToSave - 1)]];
    _mutableState.currentGrid.cursorX = x;
    _mutableState.currentGrid.cursorY = linesToSave - 1;
    [self removeIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                   _mutableState.numberOfScrollbackLines,
                                                                   self.width,
                                                                   _mutableState.numberOfScrollbackLines + self.height)];
}

- (void)mutClearScrollbackBuffer {
    _mutableState.linebuffer = [[[LineBuffer alloc] init] autorelease];
    [self.mutableLineBuffer setMaxLines:_state.maxScrollbackLines];
    [delegate_ screenClearHighlights];
    [_mutableState.currentGrid markAllCharsDirty:YES];

    _mutableState.savedFindContextAbsPos = 0;

    [self resetScrollbackOverflow];
    [delegate_ screenRemoveSelection];
    [_mutableState.currentGrid markAllCharsDirty:YES];
    [self removeIntervalTreeObjectsInRange:VT100GridCoordRangeMake(0,
                                                                   0,
                                                                   self.width, _mutableState.numberOfScrollbackLines + self.height)];
    _mutableState.intervalTree = [[[IntervalTree alloc] init] autorelease];
    [self mutReloadMarkCache];
    _mutableState.lastCommandMark = nil;
    [delegate_ screenDidClearScrollbackBuffer:self];
    [delegate_ screenRefreshFindOnPageView];
}

- (void)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange {
    [self removeIntervalTreeObjectsInRange:coordRange
                          exceptCoordRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
}

- (NSMutableArray<id<IntervalTreeObject>> *)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange exceptCoordRange:(VT100GridCoordRange)coordRangeToSave {
    Interval *intervalToClear = [self intervalForGridCoordRange:coordRange];
    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [NSMutableArray array];
    for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:intervalToClear]) {
        const VT100GridCoordRange markRange = [self coordRangeForInterval:obj.entry.interval];
        if (VT100GridCoordRangeContainsCoord(coordRangeToSave, markRange.start)) {
            [marksToMove addObject:obj];
        } else {
            [self mutRemoveObjectFromIntervalTree:obj];
        }
    }
    return marksToMove;
}

- (void)clearScrollbackBufferFromLine:(int)line {
    const int width = self.width;
    const int scrollbackLines = [_mutableState.linebuffer numberOfWrappedLinesWithWidth:width];
    if (scrollbackLines < line) {
        return;
    }
    [self.mutableLineBuffer removeLastWrappedLines:scrollbackLines - line
                                             width:width];
}

- (void)mutResetTimestamps {
    [self.mutablePrimaryGrid resetTimestamps];
    [self.mutableAltGrid resetTimestamps];
}

- (void)mutRemoveLastLine {
    DLog(@"BEGIN removeLastLine with cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
    const int preHocNumberOfLines = [_mutableState.linebuffer numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesAppended = [_mutableState.currentGrid appendLines:self.currentGrid.numberOfLinesUsed
                                                                toLineBuffer:_mutableState.linebuffer];
    if (numberOfLinesAppended <= 0) {
        return;
    }
    [_mutableState.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                         to:VT100GridCoordMake(self.width - 1,
                                                               self.height - 1)
                                     toChar:self.currentGrid.defaultChar
                         externalAttributes:nil];
    [self.mutableLineBuffer removeLastRawLine];
    const int postHocNumberOfLines = [_mutableState.linebuffer numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesToPop = MAX(0, postHocNumberOfLines - preHocNumberOfLines);

    [_mutableState.currentGrid restoreScreenFromLineBuffer:_mutableState.linebuffer
                                           withDefaultChar:[self.currentGrid defaultChar]
                                         maxLinesToRestore:numberOfLinesToPop];
    // One of the lines "removed" will be the one the cursor is on. Don't need to move it up for
    // that one.
    const int adjustment = self.currentGrid.cursorX > 0 ? 1 : 0;
    _mutableState.currentGrid.cursorX = 0;
    const int numberOfLinesRemoved = MAX(0, numberOfLinesAppended - numberOfLinesToPop);
    const int y = MAX(0, self.currentGrid.cursorY - numberOfLinesRemoved + adjustment);
    DLog(@"numLinesAppended=%@ numLinesToPop=%@ numLinesRemoved=%@ adjustment=%@ y<-%@",
          @(numberOfLinesAppended), @(numberOfLinesToPop), @(numberOfLinesRemoved), @(adjustment), @(y));
    _mutableState.currentGrid.cursorY = y;
    DLog(@"Cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
}

- (void)mutClearFromAbsoluteLineToEnd:(long long)absLine {
    const VT100GridCoord cursorCoord = VT100GridCoordMake(_state.currentGrid.cursor.x,
                                                          _state.currentGrid.cursor.y + _mutableState.numberOfScrollbackLines);
    const long long totalScrollbackOverflow = self.totalScrollbackOverflow;
    const VT100GridAbsCoord absCursorCoord = VT100GridAbsCoordFromCoord(cursorCoord, totalScrollbackOverflow);
    iTermTextExtractor *extractor = [[[iTermTextExtractor alloc] initWithDataSource:self] autorelease];
    const VT100GridWindowedRange cursorLineRange = [extractor rangeForWrappedLineEncompassing:cursorCoord
                                                                         respectContinuations:YES
                                                                                     maxChars:100000];
    ScreenCharArray *savedLine = [extractor combinedLinesInRange:NSMakeRange(cursorLineRange.coordRange.start.y,
                                                                             cursorLineRange.coordRange.end.y - cursorLineRange.coordRange.start.y + 1)];
    savedLine = [savedLine screenCharArrayByRemovingTrailingNullsAndHardNewline];

    const long long firstScreenAbsLine = _mutableState.numberOfScrollbackLines + totalScrollbackOverflow;
    [self clearGridFromLineToEnd:MAX(0, absLine - firstScreenAbsLine)];

    [self clearScrollbackBufferFromLine:absLine - self.totalScrollbackOverflow];
    const VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                                                   absLine - totalScrollbackOverflow,
                                                                   self.width,
                                                                   _mutableState.numberOfScrollbackLines + self.height);

    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [self removeIntervalTreeObjectsInRange:coordRange
                                                                                exceptCoordRange:cursorLineRange.coordRange];
    if (absCursorCoord.y >= absLine) {
        Interval *cursorLineInterval = [self intervalForGridCoordRange:cursorLineRange.coordRange];
        for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:cursorLineInterval]) {
            if ([marksToMove containsObject:obj]) {
                continue;
            }
            [marksToMove addObject:obj];
        }

        // Cursor was among the cleared lines. Restore the line content.
        _mutableState.currentGrid.cursor = VT100GridCoordMake(0, absLine - totalScrollbackOverflow - _mutableState.numberOfScrollbackLines);
        [self mutAppendScreenChars:savedLine.line
                            length:savedLine.length
            externalAttributeIndex:savedLine.metadata.externalAttributes
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
                [self mutRemoveObjectFromIntervalTree:obj];
                [_mutableState.intervalTree addObject:obj withInterval:interval];

                // Re-adding an annotation requires telling the delegate so it can create a vc
                PTYAnnotation *annotation = [PTYAnnotation castFrom:obj];
                if (annotation) {
                    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
                        [delegate screenDidAddNote:annotation focus:NO];
                    }];
                }
                // TODO: This needs to be a side effect.
                [self.intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:obj]
                                                                   onLine:range.start.y + totalScrollbackOverflow];
            }];
        }
    } else {
        [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self mutRemoveObjectFromIntervalTree:obj];
        }];
    }
    [self mutReloadMarkCache];
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
}

- (void)clearGridFromLineToEnd:(int)line {
    assert(line >= 0 && line < self.height);
    const VT100GridCoord savedCursor = self.currentGrid.cursor;
    _mutableState.currentGrid.cursor = VT100GridCoordMake(0, line);
    [self removeSoftEOLBeforeCursor];
    const VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(0, line),
                                                    VT100GridCoordMake(self.width, self.height),
                                                    self.width);
    [_mutableState.currentGrid setCharsInRun:run toChar:0 externalAttributes:nil];
    [delegate_ screenTriggerableChangeDidOccur];
    _mutableState.currentGrid.cursor = savedCursor;
}

- (void)mutResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    if (modifyContent) {
        const int linesToSave = [self numberOfLinesToPreserveWhenClearingScreen];
        [delegate_ screenTriggerableChangeDidOccur];
        if (preservePrompt) {
            [self clearAndResetScreenSavingLines:linesToSave];
        } else {
            [_mutableState incrementOverflowBy:[_mutableState.currentGrid resetWithLineBuffer:_mutableState.linebuffer
                                                                          unlimitedScrollback:_state.unlimitedScrollback
                                                                           preserveCursorLine:NO
                                                                        additionalLinesToSave:0]];
        }
    }

    [self mutSetInitialTabStops];

    for (int i = 0; i < NUM_CHARSETS; i++) {
        [self mutSetCharacterSet:i usesLineDrawingMode:NO];
    }
    [delegate_ screenDidResetAllowingContentModification:modifyContent];
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
    [self showCursor:YES];
}

- (void)mutSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    if (_state.currentGrid.useScrollRegionCols) {
        _mutableState.currentGrid.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                                        scrollRight - scrollLeft + 1);
        // set cursor to the home position
        [self mutCursorToX:1 Y:1];
    }
}

- (void)mutEraseScreenAndRemoveSelection {
    // Unconditionally clear the whole screen, regardless of cursor position.
    // This behavior changed in the Great VT100Grid Refactoring of 2013. Before, clearScreen
    // used to move the cursor's wrapped line to the top of the screen. It's only used from
    // DECSET 1049, and neither xterm nor terminal have this behavior, and I'm not sure why it
    // would be desirable anyway. Like xterm (and unlike Terminal) we leave the cursor put.
    [delegate_ screenRemoveSelection];
    [_mutableState.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                         to:VT100GridCoordMake(_state.currentGrid.size.width - 1,
                                                               _state.currentGrid.size.height - 1)
                                     toChar:[_state.currentGrid defaultChar]
                         externalAttributes:nil];
}


#pragma mark - Appending

- (void)mutAppendStringAtCursor:(NSString *)string {
    int len = [string length];
    if (len < 1 || !string) {
        return;
    }

    unichar firstChar =  [string characterAtIndex:0];

    DLog(@"appendStringAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         _state.currentGrid.cursorX,
         _state.currentGrid.cursorY,
         _state.currentGrid.cursorY + [_mutableState.linebuffer numLinesWithWidth:_state.currentGrid.size.width]);

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
    VT100GridCoord pred = [_state.currentGrid coordinateBefore:_state.currentGrid.cursor
                                movedBackOverDoubleWidth:&predecessorIsDoubleWidth];
    NSString *augmentedString = string;
    NSString *predecessorString = pred.x >= 0 ? [_state.currentGrid stringForCharacterAt:pred] : nil;
    const BOOL augmented = predecessorString != nil;
    if (augmented) {
        augmentedString = [predecessorString stringByAppendingString:string];
    } else {
        // Prepend a space so we can detect if the first character is a combining mark.
        augmentedString = [@" " stringByAppendingString:string];
    }

    assert(_state.terminal);
    // Add DWC_RIGHT after each double-byte character, build complex characters out of surrogates
    // and combining marks, replace private codes with replacement characters, swallow zero-
    // width spaces, and set fg/bg colors and attributes.
    BOOL dwc = NO;
    StringToScreenChars(augmentedString,
                        buffer,
                        [_state.terminal foregroundColorCode],
                        [_state.terminal backgroundColorCode],
                        &len,
                        [delegate_ screenShouldTreatAmbiguousCharsAsDoubleWidth],
                        NULL,
                        &dwc,
                        self.normalization,
                        [delegate_ screenUnicodeVersion]);
    ssize_t bufferOffset = 0;
    if (augmented && len > 0) {
        screen_char_t *theLine = [self getLineAtScreenIndex:pred.y];
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
        self.mutableLineBuffer.mayHaveDoubleWidthCharacter = dwc;
    }
    [self mutAppendScreenCharArrayAtCursor:buffer + bufferOffset
                                    length:len - bufferOffset
                    externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:_state.terminal.externalAttributes]];
    if (buffer == dynamicBuffer) {
        free(buffer);
    }
}

- (void)mutAppendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                                  length:(int)len
                  externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes {
    if (len >= 1) {
        screen_char_t lastCharacter = buffer[len - 1];
        if (lastCharacter.code == DWC_RIGHT && !lastCharacter.complexChar) {
            // Last character is the right half of a double-width character. Use the penultimate character instead.
            if (len >= 2) {
                _mutableState.lastCharacter = buffer[len - 2];
                _mutableState.lastCharacterIsDoubleWidth = YES;
                _mutableState.lastExternalAttribute = externalAttributes[len - 2];
            }
        } else {
            // Record the last character.
            _mutableState.lastCharacter = buffer[len - 1];
            _mutableState.lastCharacterIsDoubleWidth = NO;
            _mutableState.lastExternalAttribute = externalAttributes[len];
        }
        LineBuffer *lineBuffer = nil;
        if (_state.currentGrid != _state.altGrid || _state.saveToScrollbackInAlternateScreen) {
            // Not in alt screen or it's ok to scroll into line buffer while in alt screen.k
            lineBuffer = _mutableState.linebuffer;
        }
        [_mutableState incrementOverflowBy:[_mutableState.currentGrid appendCharsAtCursor:buffer
                                                                                   length:len
                                                                  scrollingIntoLineBuffer:lineBuffer
                                                                      unlimitedScrollback:_state.unlimitedScrollback
                                                                  useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                               wraparound:_state.wraparoundMode
                                                                                     ansi:_state.ansi
                                                                                   insert:_state.insert
                                                                   externalAttributeIndex:externalAttributes]];
        iTermImmutableMetadata temp;
        iTermImmutableMetadataInit(&temp, 0, externalAttributes);
        [delegate_ screenAppendScreenCharArray:buffer
                                      metadata:temp
                                        length:len];
        iTermImmutableMetadataRelease(temp);
    }

    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)appendSessionRestoredBanner {
    // Save graphic rendition. Set to system message color.
    const VT100GraphicRendition saved = _state.terminal.graphicRendition;

    VT100GraphicRendition temp = saved;
    temp.fgColorMode = ColorModeAlternate;
    temp.fgColorCode = ALTSEM_SYSTEM_MESSAGE;
    temp.bgColorMode = ColorModeAlternate;
    temp.bgColorCode = ALTSEM_SYSTEM_MESSAGE;
    _state.terminal.graphicRendition = temp;

    // Record the cursor position and append the message.
    const int yBefore = _state.currentGrid.cursor.y;
    if (_state.currentGrid.cursor.x > 0) {
        [_mutableState appendCarriageReturnLineFeed];
    }
    [self mutEraseLineBeforeCursor:YES afterCursor:YES decProtect:NO];
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *message = [NSString stringWithFormat:@"Session Contents Restored on %@", [dateFormatter stringFromDate:[NSDate date]]];
    [self mutAppendStringAtCursor:message];
    _mutableState.currentGrid.cursorX = 0;
    _mutableState.currentGrid.preferredCursorPosition = _state.currentGrid.cursor;

    // Restore the graphic rendition, add a newline, and calculate how far down the cursor moved.
    _state.terminal.graphicRendition = saved;
    [_mutableState appendCarriageReturnLineFeed];
    const int delta = _state.currentGrid.cursor.y - yBefore;

    // Update the preferred cursor position if needed.
    if (_state.currentGrid.preferredCursorPosition.y >= 0 && _state.currentGrid.preferredCursorPosition.y + 1 < _state.currentGrid.size.height) {
        VT100GridCoord coord = _state.currentGrid.preferredCursorPosition;
        coord.y = MAX(0, MIN(_state.currentGrid.size.height - 1, coord.y + delta));
        _mutableState.currentGrid.preferredCursorPosition = coord;
    }
}

- (void)mutAppendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation {
    [self mutAppendScreenCharArrayAtCursor:line
                                    length:length
                    externalAttributeIndex:externalAttributeIndex];
    if (continuation.code == EOL_HARD) {
        [self mutCarriageReturn];
        [_mutableState appendLineFeed];
    }
}

- (void)mutAppendAsciiDataAtCursor:(AsciiData *)asciiData {
    int len = asciiData->length;
    if (len < 1 || !asciiData) {
        return;
    }
    STOPWATCH_START(appendAsciiDataAtCursor);
    char firstChar = asciiData->buffer[0];

    DLog(@"appendAsciiDataAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         _state.currentGrid.cursorX,
         _state.currentGrid.cursorY,
         _state.currentGrid.cursorY + [_mutableState.linebuffer numLinesWithWidth:_state.currentGrid.size.width]);

    screen_char_t *buffer;
    buffer = asciiData->screenChars->buffer;

    screen_char_t fg = [_state.terminal foregroundColorCode];
    screen_char_t bg = [_state.terminal backgroundColorCode];
    iTermExternalAttribute *ea = [_state.terminal externalAttributes];

    screen_char_t zero = { 0 };
    if (memcmp(&fg, &zero, sizeof(fg)) || memcmp(&bg, &zero, sizeof(bg))) {
        STOPWATCH_START(setUpScreenCharArray);
        for (int i = 0; i < len; i++) {
            CopyForegroundColor(&buffer[i], fg);
            CopyBackgroundColor(&buffer[i], bg);
        }
        STOPWATCH_LAP(setUpScreenCharArray);
    }

    // If a graphics character set was selected then translate buffer
    // characters into graphics characters.
    if ([_state.charsetUsesLineDrawingMode containsObject:@(_state.terminal.charset)]) {
        ConvertCharsToGraphicsCharset(buffer, len);
    }

    [self mutAppendScreenCharArrayAtCursor:buffer
                                    length:len
                    externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:ea]];
    STOPWATCH_LAP(appendAsciiDataAtCursor);
}

#pragma mark - Arrangements

- (void)mutRestoreInitialSize {
    if (_state.initialSize.width > 0 && _state.initialSize.height > 0) {
        [self setSize:_state.initialSize];
        _mutableState.initialSize = VT100GridSizeMake(-1, -1);
    }
}

- (void)mutSetContentsFromLineBuffer:(LineBuffer *)lineBuffer {
    [self mutClearBuffer];
    [self.mutableLineBuffer appendContentsOfLineBuffer:lineBuffer width:_state.currentGrid.size.width];
    const int numberOfLines = [self numberOfLines];
    [_mutableState.currentGrid restoreScreenFromLineBuffer:_mutableState.linebuffer
                                           withDefaultChar:[self.currentGrid defaultChar]
                                         maxLinesToRestore:MIN(numberOfLines, self.height)];
}

- (void)mutSetHistory:(NSArray *)history {
    // This is way more complicated than it should be to work around something dumb in tmux.
    // It pads lines in its history with trailing spaces, which we'd like to trim. More importantly,
    // we need to trim empty lines at the end of the history because that breaks how we move the
    // screen contents around on resize. So we take the history from tmux, append it to a temporary
    // line buffer, grab each wrapped line and trim spaces from it, and then append those modified
    // line (excluding empty ones at the end) to the real line buffer.
    [self mutClearBuffer];
    LineBuffer *temp = [[[LineBuffer alloc] init] autorelease];
    temp.mayHaveDoubleWidthCharacter = YES;
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = YES;
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
                   width:_state.currentGrid.size.width
                metadata:iTermMetadataMakeImmutable(metadata)
            continuation:continuation];
    }
    NSMutableArray *wrappedLines = [NSMutableArray array];
    int n = [temp numLinesWithWidth:_state.currentGrid.size.width];
    int numberOfConsecutiveEmptyLines = 0;
    for (int i = 0; i < n; i++) {
        ScreenCharArray *line = [temp wrappedLineAtIndex:i
                                                   width:_state.currentGrid.size.width
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
        [self.mutableLineBuffer appendLine:line.line
                                    length:line.length
                                   partial:(line.eol != EOL_HARD)
                                     width:_state.currentGrid.size.width
                                  metadata:iTermMetadataMakeImmutable(metadata)
                              continuation:continuation];
    }
    if (!_state.unlimitedScrollback) {
        [self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width];
    }

    // We don't know the cursor position yet but give the linebuffer something
    // so it doesn't get confused in restoreScreenFromScrollback.
    [self.mutableLineBuffer setCursor:0];
    [_mutableState.currentGrid restoreScreenFromLineBuffer:_mutableState.linebuffer
                                           withDefaultChar:[_state.currentGrid defaultChar]
                                         maxLinesToRestore:MIN([_mutableState.linebuffer numLinesWithWidth:_state.currentGrid.size.width],
                                                               _state.currentGrid.size.height - numberOfConsecutiveEmptyLines)];
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

- (void)mutSetAltScreen:(NSArray *)lines {
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = YES;
    if (!_state.altGrid) {
        _mutableState.altGrid = [[self.mutablePrimaryGrid copy] autorelease];
    }

    // Initialize alternate screen to be empty
    [self.mutableAltGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                   to:VT100GridCoordMake(_state.altGrid.size.width - 1, _state.altGrid.size.height - 1)
                               toChar:[_state.altGrid defaultChar]
        externalAttributes:nil];
    // Copy the lines back over it
    int o = 0;
    for (int i = 0; o < _state.altGrid.size.height && i < MIN(lines.count, _state.altGrid.size.height); i++) {
        NSData *chars = [lines objectAtIndex:i];
        screen_char_t *line = (screen_char_t *) [chars bytes];
        int length = [chars length] / sizeof(screen_char_t);

        do {
            // Add up to _state.altGrid.size.width characters at a time until they're all used.
            screen_char_t *dest = [self.mutableAltGrid screenCharsAtLineNumber:o];
            memcpy(dest, line, MIN(_state.altGrid.size.width, length) * sizeof(screen_char_t));
            const BOOL isPartial = (length > _state.altGrid.size.width);
            dest[_state.altGrid.size.width] = dest[_state.altGrid.size.width - 1];  // TODO: This is probably wrong?
            dest[_state.altGrid.size.width].code = (isPartial ? EOL_SOFT : EOL_HARD);
            length -= _state.altGrid.size.width;
            line += _state.altGrid.size.width;
            o++;
        } while (o < _state.altGrid.size.height && length > 0);
    }
}

- (int)mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                        encoder:(id<iTermEncoderAdapter>)encoder
                                                 intervalOffset:(long long *)intervalOffsetPtr {
    // We want 10k lines of history at 80 cols, and fewer for small widths, to keep the size
    // reasonable.
    const int maxLines80 = [iTermAdvancedSettingsModel maxHistoryLinesToRestore];
    const int effectiveWidth = self.width ?: 80;
    const int maxArea = maxLines80 * (includeGrid ? 80 : effectiveWidth);
    const int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [[_mutableState.linebuffer copyWithMinimumLines:maxLines
                                                               atWidth:effectiveWidth] autorelease];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([_mutableState.linebuffer numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
        -(linesDroppedForBrevity + _mutableState.cumulativeScrollbackOverflow) * (self.width + 1);

    if (includeGrid) {
        int numLines;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            numLines = _state.currentGrid.size.height;
        } else {
            numLines = [_state.currentGrid numberOfLinesUsed];
        }
        [_mutableState.currentGrid appendLines:numLines toLineBuffer:temp];
    }

    [temp encode:encoder maxLines:maxLines80];
    *intervalOffsetPtr = intervalOffset;
    return linesDroppedForBrevity;
}

#warning TODO: This method is an unusual mutator because it has to be on the main thread and it's probably always during initialization.

- (void)mutRestoreFromDictionary:(NSDictionary *)dictionary
        includeRestorationBanner:(BOOL)includeRestorationBanner
                   knownTriggers:(NSArray *)triggers
                      reattached:(BOOL)reattached {
    if (!_state.altGrid) {
        _mutableState.altGrid = [[_state.primaryGrid copy] autorelease];
    }
    NSDictionary *screenState = dictionary[kScreenStateKey];
    if (screenState) {
        if ([screenState[kScreenStateCurrentGridIsPrimaryKey] boolValue]) {
            _mutableState.currentGrid = _state.primaryGrid;
        } else {
            _mutableState.currentGrid = _state.altGrid;
        }
    }

    const BOOL newFormat = (dictionary[@"PrimaryGrid"] != nil);
    if (!newFormat) {
        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary];
        [lineBuffer setMaxLines:_state.maxScrollbackLines + self.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
        _mutableState.linebuffer = [lineBuffer autorelease];
        int maxLinesToRestore;
        if ([iTermAdvancedSettingsModel runJobsInServers] && reattached) {
            maxLinesToRestore = _state.currentGrid.size.height;
        } else {
            maxLinesToRestore = _state.currentGrid.size.height - 1;
        }
        const int linesRestored = MIN(MAX(0, maxLinesToRestore),
                                [lineBuffer numLinesWithWidth:self.width]);
        BOOL setCursorPosition = [_mutableState.currentGrid restoreScreenFromLineBuffer:_mutableState.linebuffer
                                                                        withDefaultChar:[_state.currentGrid defaultChar]
                                                                      maxLinesToRestore:linesRestored];
        DLog(@"appendFromDictionary: Grid size is %dx%d", _state.currentGrid.size.width, _state.currentGrid.size.height);
        DLog(@"Restored %d wrapped lines from dictionary", _mutableState.numberOfScrollbackLines + linesRestored);
        DLog(@"setCursorPosition=%@", @(setCursorPosition));
        if (!setCursorPosition) {
            VT100GridCoord coord;
            if (VT100GridCoordFromDictionary(screenState[kScreenStateCursorCoord], &coord)) {
                // The initial size of this session might be smaller than its eventual size.
                // Save the coord because after the window is set to its correct size it might be
                // possible to place the cursor in this position.
                _mutableState.currentGrid.preferredCursorPosition = coord;
                DLog(@"Save preferred cursor position %@", VT100GridCoordDescription(coord));
                if (coord.x >= 0 &&
                    coord.y >= 0 &&
                    coord.x <= self.width &&
                    coord.y < self.height) {
                    DLog(@"Also set the cursor to this position");
                    _mutableState.currentGrid.cursor = coord;
                    setCursorPosition = YES;
                }
            }
        }
        if (!setCursorPosition) {
            DLog(@"Place the cursor on the first column of the last line");
            _mutableState.currentGrid.cursorY = linesRestored + 1;
            _mutableState.currentGrid.cursorX = 0;
        }
        // Reduce line buffer's max size to not include the grid height. This is its final state.
        [lineBuffer setMaxLines:_state.maxScrollbackLines];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
    } else if (screenState) {
        // New format
        const BOOL onPrimary = (_state.currentGrid == _state.primaryGrid);
        self.mutablePrimaryGrid.delegate = nil;
        self.mutableAltGrid.delegate = nil;
        _mutableState.altGrid = nil;

        _mutableState.primaryGrid = [[[VT100Grid alloc] initWithDictionary:dictionary[@"PrimaryGrid"]
                                                                  delegate:self] autorelease];
        if (!_state.primaryGrid) {
            // This is to prevent a crash if the dictionary is bad (i.e., non-backward compatible change in a future version).
            _mutableState.primaryGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(2, 2) delegate:self] autorelease];
        }
        if ([dictionary[@"AltGrid"] count]) {
            _mutableState.altGrid = [[[VT100Grid alloc] initWithDictionary:dictionary[@"AltGrid"]
                                                                  delegate:self] autorelease];
        }
        if (!_state.altGrid) {
            _mutableState.altGrid = [[[VT100Grid alloc] initWithSize:_state.primaryGrid.size delegate:self] autorelease];
        }
        if (onPrimary || includeRestorationBanner) {
            _mutableState.currentGrid = _state.primaryGrid;
        } else {
            _mutableState.currentGrid = _state.altGrid;
        }

        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary[@"LineBuffer"]];
        [lineBuffer setMaxLines:_state.maxScrollbackLines + self.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
        _mutableState.linebuffer = [lineBuffer autorelease];
    }
    BOOL addedBanner = NO;
    if (includeRestorationBanner && [iTermAdvancedSettingsModel showSessionRestoredBanner]) {
        [self appendSessionRestoredBanner];
        addedBanner = YES;
    }

    if (screenState) {
        _mutableState.protectedMode = [screenState[kScreenStateProtectedMode] unsignedIntegerValue];
        [_mutableState.tabStops removeAllObjects];
        [_mutableState.tabStops addObjectsFromArray:screenState[kScreenStateTabStopsKey]];

        [_state.terminal setStateFromDictionary:screenState[kScreenStateTerminalKey]];
        NSArray<NSNumber *> *array = screenState[kScreenStateLineDrawingModeKey];
        for (int i = 0; i < NUM_CHARSETS && i < array.count; i++) {
            [self mutSetCharacterSet:i usesLineDrawingMode:array[i].boolValue];
        }

        if (!newFormat) {
            // Legacy content format restoration
            VT100Grid *otherGrid = (_state.currentGrid == _state.primaryGrid) ? _state.altGrid : _state.primaryGrid;
            LineBuffer *otherLineBuffer = [[[LineBuffer alloc] initWithDictionary:screenState[kScreenStateNonCurrentGridKey]] autorelease];
            [otherGrid restoreScreenFromLineBuffer:otherLineBuffer
                                   withDefaultChar:[_state.altGrid defaultChar]
                                 maxLinesToRestore:_state.altGrid.size.height];
            VT100GridCoord savedCursor = _state.primaryGrid.cursor;
            [self.mutablePrimaryGrid setStateFromDictionary:screenState[kScreenStatePrimaryGridStateKey]];
            if (addedBanner && _state.currentGrid.preferredCursorPosition.x < 0 && _state.currentGrid.preferredCursorPosition.y < 0) {
                self.mutablePrimaryGrid.cursor = savedCursor;
            }
            [self.mutableAltGrid setStateFromDictionary:screenState[kScreenStateAlternateGridStateKey]];
        }

        NSString *guidOfLastCommandMark = screenState[kScreenStateLastCommandMarkKey];
        if (reattached) {
            [self mutSetCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake([screenState[kScreenStateCommandStartXKey] intValue],
                                                                                  [screenState[kScreenStateCommandStartYKey] longLongValue])];
            _mutableState.startOfRunningCommandOutput = [screenState[kScreenStateNextCommandOutputStartKey] gridAbsCoord];
        }
        _mutableState.cursorVisible = [screenState[kScreenStateCursorVisibleKey] boolValue];
        self.trackCursorLineMovement = [screenState[kScreenStateTrackCursorLineMovementKey] boolValue];
        _mutableState.lastCommandOutputRange = [screenState[kScreenStateLastCommandOutputRangeKey] gridAbsCoordRange];
        _mutableState.shellIntegrationInstalled = [screenState[kScreenStateShellIntegrationInstalledKey] boolValue];


        if (!newFormat) {
            _mutableState.initialSize = self.size;
            // Change the size to how big it was when state was saved so that
            // interval trees can be fixed up properly when it is set back later by
            // restoreInitialSize. Interval tree ranges cannot be interpreted
            // outside the context of the data they annotate because when an
            // annotation affects all the trailing nulls on a line, the length of
            // that annotation is dependent on the screen size and how text laid
            // out (maybe there are no nulls after reflow!).
            VT100GridSize savedSize = [VT100Grid sizeInStateDictionary:screenState[kScreenStatePrimaryGridStateKey]];
            [self mutSetSize:savedSize];
        }
        _mutableState.intervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.intervalTree
                              knownTriggers:triggers
                                    visible:YES
                      guidOfLastCommandMark:guidOfLastCommandMark];

        _mutableState.savedIntervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateSavedIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.savedIntervalTree
                              knownTriggers:triggers
                                    visible:NO
                      guidOfLastCommandMark:guidOfLastCommandMark];

        Interval *interval = [self lastPromptMark].entry.interval;
        if (interval) {
            const VT100GridRange gridRange = [self lineNumberRangeOfInterval:interval];
            _mutableState.lastPromptLine = gridRange.location + _mutableState.cumulativeScrollbackOverflow;
        }

        [self mutReloadMarkCache];
        [self.delegate screenSendModifiersDidChange];

        if (gDebugLogging) {
            DLog(@"Notes after restoring with width=%@", @(self.width));
            for (id<IntervalTreeObject> object in _mutableState.intervalTree.allObjects) {
                if (![object isKindOfClass:[PTYAnnotation class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([self coordRangeForInterval:object.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }
}

// Link references to marks in CapturedOutput (for the lines where output was captured) to the deserialized mark.
// Link marks for commands to CommandUse objects in command history.
// Notify delegate of annotations so they get added as subviews, and set the delegate of not view controllers to self.
- (void)fixUpDeserializedIntervalTree:(IntervalTree *)intervalTree
                        knownTriggers:(NSArray *)triggers
                              visible:(BOOL)visible
                guidOfLastCommandMark:(NSString *)guidOfLastCommandMark {
    VT100RemoteHost *lastRemoteHost = nil;
    NSMutableDictionary *markGuidToCapturedOutput = [NSMutableDictionary dictionary];
    for (NSArray *objects in [intervalTree forwardLimitEnumerator]) {
        for (id<IntervalTreeObject> object in objects) {
            if ([object isKindOfClass:[VT100RemoteHost class]]) {
                lastRemoteHost = object;
            } else if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *screenMark = (VT100ScreenMark *)object;
                screenMark.delegate = self;
                // If |capturedOutput| is not empty then this mark is a command, some of whose output
                // was captured. The iTermCapturedOutputMarks will come later so save the GUIDs we need
                // in markGuidToCapturedOutput and they'll get backfilled when found.
                for (CapturedOutput *capturedOutput in screenMark.capturedOutput) {
                    [capturedOutput setKnownTriggers:triggers];
                    if (capturedOutput.markGuid) {
                        markGuidToCapturedOutput[capturedOutput.markGuid] = capturedOutput;
                    }
                }
                if (screenMark.command) {
                    // Find the matching object in command history and link it.
                    iTermCommandHistoryCommandUseMO *commandUse =
                        [[iTermShellHistoryController sharedInstance] commandUseWithMarkGuid:screenMark.guid
                                                                                      onHost:lastRemoteHost];
                    commandUse.mark = screenMark;
                }
                if ([screenMark.guid isEqualToString:guidOfLastCommandMark]) {
                    _mutableState.lastCommandMark = screenMark;
                }
            } else if ([object isKindOfClass:[iTermCapturedOutputMark class]]) {
                // This mark represents a line whose output was captured. Find the preceding command
                // mark that has a CapturedOutput corresponding to this mark and fill it in.
                iTermCapturedOutputMark *capturedOutputMark = (iTermCapturedOutputMark *)object;
                CapturedOutput *capturedOutput = markGuidToCapturedOutput[capturedOutputMark.guid];
                capturedOutput.mark = capturedOutputMark;
            } else if ([object isKindOfClass:[PTYAnnotation class]]) {
                PTYAnnotation *note = (PTYAnnotation *)object;
                if (visible) {
                    [delegate_ screenDidAddNote:note focus:NO];
                }
            } else if ([object isKindOfClass:[iTermImageMark class]]) {
                iTermImageMark *imageMark = (iTermImageMark *)object;
                ScreenCharClearProvisionalFlagForImageWithCode(imageMark.imageCode.intValue);
            }
        }
    }
}

#pragma mark - Tmux Integration

- (void)mutSetTmuxState:(NSDictionary *)state {
    BOOL inAltScreen = [[self objectInDictionary:state
                                withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedGrid,
                                                  kStateDictSavedGrid,
                                                  nil]] intValue];
    if (inAltScreen) {
        // Alt and primary have been populated with each other's content.
        id<VT100GridReading> temp = _state.altGrid;
        _mutableState.altGrid = _state.primaryGrid;
        _mutableState.primaryGrid = temp;
    }

    NSNumber *altSavedX = [state objectForKey:kStateDictAltSavedCX];
    NSNumber *altSavedY = [state objectForKey:kStateDictAltSavedCY];
    if (altSavedX && altSavedY && inAltScreen) {
        self.mutablePrimaryGrid.cursor = VT100GridCoordMake([altSavedX intValue], [altSavedY intValue]);
        [_state.terminal setSavedCursorPosition:_state.primaryGrid.cursor];
    }

    _mutableState.currentGrid.cursorX = [[state objectForKey:kStateDictCursorX] intValue];
    _mutableState.currentGrid.cursorY = [[state objectForKey:kStateDictCursorY] intValue];
    int top = [[state objectForKey:kStateDictScrollRegionUpper] intValue];
    int bottom = [[state objectForKey:kStateDictScrollRegionLower] intValue];
    _mutableState.currentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);
    [self showCursor:[[state objectForKey:kStateDictCursorMode] boolValue]];

    [_mutableState.tabStops removeAllObjects];
    int maxTab = 0;
    for (NSNumber *n in [state objectForKey:kStateDictTabstops]) {
        [_mutableState.tabStops addObject:n];
        maxTab = MAX(maxTab, [n intValue]);
    }
    for (int i = 0; i < 1000; i += 8) {
        if (i > maxTab) {
            [_mutableState.tabStops addObject:[NSNumber numberWithInt:i]];
        }
    }

    NSNumber *cursorMode = [state objectForKey:kStateDictCursorMode];
    if (cursorMode) {
        [self terminalSetCursorVisible:!![cursorMode intValue]];
    }

    // Everything below this line needs testing
    NSNumber *insertMode = [state objectForKey:kStateDictInsertMode];
    if (insertMode) {
        [_mutableState.terminal setInsertMode:!![insertMode intValue]];
    }

    NSNumber *applicationCursorKeys = [state objectForKey:kStateDictKCursorMode];
    if (applicationCursorKeys) {
        [_mutableState.terminal setCursorMode:!![applicationCursorKeys intValue]];
    }

    NSNumber *keypad = [state objectForKey:kStateDictKKeypadMode];
    if (keypad) {
        [_mutableState.terminal setKeypadMode:!![keypad boolValue]];
    }

    NSNumber *mouse = [state objectForKey:kStateDictMouseStandardMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_NORMAL];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_ALL_MOTION];
    }

    // NOTE: You can get both SGR and UTF8 set. In that case SGR takes priority. See comment in
    // tmux's input_key_get_mouse()
    mouse = [state objectForKey:kStateDictMouseSGRMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseFormat:MOUSE_FORMAT_SGR];
    } else {
        mouse = [state objectForKey:kStateDictMouseUTF8Mode];
        if (mouse && [mouse intValue]) {
            [_mutableState.terminal setMouseFormat:MOUSE_FORMAT_XTERM_EXT];
        }
    }

    NSNumber *wrap = [state objectForKey:kStateDictWrapMode];
    if (wrap) {
        [_mutableState.terminal setWraparoundMode:!![wrap intValue]];
    }
}

- (id)objectInDictionary:(NSDictionary *)dict withFirstKeyFrom:(NSArray *)keys {
    for (NSString *key in keys) {
        NSObject *object = [dict objectForKey:key];
        if (object) {
            return object;
        }
    }
    return nil;
}

#pragma mark - Terminal Fundamentals

- (void)mutAppendNativeImageAtCursorWithName:(NSString *)name width:(int)width {
    VT100InlineImageHelper *helper = [[[VT100InlineImageHelper alloc] initWithNativeImageNamed:name
                                                                                 spanningWidth:width
                                                                                   scaleFactor:[delegate_ screenBackingScaleFactor]] autorelease];
    helper.delegate = self;
    [helper writeToGrid:_state.currentGrid];
}

- (void)mutSynchronizedUpdate:(BOOL)begin {
    if (begin) {
        [_mutableState.temporaryDoubleBuffer startExplicitly];
    } else {
        [_mutableState.temporaryDoubleBuffer resetExplicitly];
    }
}

- (void)mutSetProtectedMode:(VT100TerminalProtectedMode)mode {
    _mutableState.protectedMode = mode;
}

- (void)mutSetCursorVisible:(BOOL)visible {
    if (visible != _state.cursorVisible) {
        _mutableState.cursorVisible = visible;
        if (visible) {
            [self.mutableTemporaryDoubleBuffer reset];
        } else {
            [self.mutableTemporaryDoubleBuffer start];
        }
    }
    [delegate_ screenSetCursorVisible:visible];
}

- (void)mutSetCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode {
    if (lineDrawingMode) {
        [_mutableState.charsetUsesLineDrawingMode addObject:@(charset)];
    } else {
        [_mutableState.charsetUsesLineDrawingMode removeObject:@(charset)];
    }
}

- (void)mutSetInitialTabStops {
    [_mutableState.tabStops removeAllObjects];
    const int kInitialTabWindow = 1000;
    const int width = [iTermAdvancedSettingsModel defaultTabStopWidth];
    for (int i = 0; i < kInitialTabWindow; i += width) {
        [_mutableState.tabStops addObject:[NSNumber numberWithInt:i]];
    }
}

- (void)mutCrlf {
    [_mutableState appendCarriageReturnLineFeed];
}

- (void)mutLinefeed {
    [_mutableState appendLineFeed];
}

- (BOOL)cursorOutsideTopBottomMargin {
    return (_state.currentGrid.cursorY < _state.currentGrid.topMargin ||
            _state.currentGrid.cursorY > _state.currentGrid.bottomMargin);
}

- (void)mutCursorToX:(int)x Y:(int)y {
    [self mutCursorToX:x];
    [self mutCursorToY:y];
    DebugLog(@"cursorToX:Y");
}

- (void)mutCursorToX:(int)x {
    const int leftMargin = [_state.currentGrid leftMargin];
    const int rightMargin = [_state.currentGrid rightMargin];

    int xPos = x - 1;

    if ([_state.terminal originMode]) {
        xPos += leftMargin;
        xPos = MAX(leftMargin, MIN(rightMargin, xPos));
    }

    _mutableState.currentGrid.cursorX = xPos;

    DebugLog(@"cursorToX");
}

- (void)mutCursorToY:(int)y {
    int yPos;
    int topMargin = _state.currentGrid.topMargin;
    int bottomMargin = _state.currentGrid.bottomMargin;

    yPos = y - 1;

    if ([_state.terminal originMode]) {
        yPos += topMargin;
        yPos = MAX(topMargin, MIN(bottomMargin, yPos));
    }
    _mutableState.currentGrid.cursorY = yPos;

    DebugLog(@"cursorToY");

}

- (void)mutDoBackspace {
    int leftMargin = _state.currentGrid.leftMargin;
    int rightMargin = _state.currentGrid.rightMargin;
    int cursorX = _state.currentGrid.cursorX;
    int cursorY = _state.currentGrid.cursorY;

    if (cursorX >= self.width && _state.terminal.reverseWraparoundMode && _state.terminal.wraparoundMode) {
        // Reverse-wrap when past the screen edge is a special case.
        _mutableState.currentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY);
    } else if ([self shouldReverseWrap]) {
        _mutableState.currentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY - 1);
    } else if (cursorX > leftMargin ||  // Cursor can move back without hitting the left margin: normal case
               (cursorX < leftMargin && cursorX > 0)) {  // Cursor left of left margin, right of left edge.
        if (cursorX >= _state.currentGrid.size.width) {
            // Cursor right of right edge, move back twice.
            _mutableState.currentGrid.cursorX = cursorX - 2;
        } else {
            // Normal case.
            _mutableState.currentGrid.cursorX = cursorX - 1;
        }
    }

    // It is OK to land on the right half of a double-width character (issue 3475).
}

// Reverse wrap is allowed when the cursor is on the left margin or left edge, wraparoundMode is
// set, the cursor is not at the top margin/edge, and:
// 1. reverseWraparoundMode is set (xterm's rule), or
// 2. there's no left-right margin and the preceding line has EOL_SOFT (Terminal.app's rule)
- (BOOL)shouldReverseWrap {
    if (!_state.terminal.wraparoundMode) {
        return NO;
    }

    // Cursor must be at left margin/edge.
    int leftMargin = _state.currentGrid.leftMargin;
    int cursorX = _state.currentGrid.cursorX;
    if (cursorX != leftMargin && cursorX != 0) {
        return NO;
    }

    // Cursor must not be at top margin/edge.
    int topMargin = _state.currentGrid.topMargin;
    int cursorY = _state.currentGrid.cursorY;
    if (cursorY == topMargin || cursorY == 0) {
        return NO;
    }

    // If reverseWraparoundMode is reset, then allow only if there's a soft newline on previous line
    if (!_state.terminal.reverseWraparoundMode) {
        if (_state.currentGrid.useScrollRegionCols) {
            return NO;
        }

        screen_char_t *line = [self getLineAtScreenIndex:cursorY - 1];
        unichar c = line[self.width].code;
        return (c == EOL_SOFT || c == EOL_DWC);
    }

    return YES;
}

- (void)convertHardNewlineToSoftOnGridLine:(int)line {
    screen_char_t *aLine = [_mutableState.currentGrid screenCharsAtLineNumber:line];
    if (aLine[_state.currentGrid.size.width].code == EOL_HARD) {
        aLine[_state.currentGrid.size.width].code = EOL_SOFT;
    }
}

// Remove soft eol on previous line, provided the cursor is on the first column. This is useful
// because zsh likes to ED 0 after wrapping around before drawing the prompt. See issue 8938.
// For consistency, EL uses it, too.
- (void)removeSoftEOLBeforeCursor {
    if (_state.currentGrid.cursor.x != 0) {
        return;
    }
    if (_state.currentGrid.haveScrollRegion) {
        return;
    }
    if (_state.currentGrid.cursor.y > 0) {
        [_mutableState.currentGrid setContinuationMarkOnLine:_state.currentGrid.cursor.y - 1 to:EOL_HARD];
    } else {
        [self.mutableLineBuffer setPartial:NO];
    }
}

- (void)softWrapCursorToNextLineScrollingIfNeeded {
    if (_state.currentGrid.rightMargin + 1 == _state.currentGrid.size.width) {
        [self convertHardNewlineToSoftOnGridLine:_state.currentGrid.cursorY];
    }
    if (_state.currentGrid.cursorY == _state.currentGrid.bottomMargin) {
        [_mutableState incrementOverflowBy:[_mutableState.currentGrid scrollUpIntoLineBuffer:_mutableState.linebuffer
                                                                         unlimitedScrollback:_state.unlimitedScrollback
                                                                     useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                                   softBreak:YES]];
    }
    _mutableState.currentGrid.cursorX = _state.currentGrid.leftMargin;
    _mutableState.currentGrid.cursorY++;
}

- (int)tabStopAfterColumn:(int)lowerBound {
    for (int i = lowerBound + 1; i < self.width - 1; i++) {
        if ([_state.tabStops containsObject:@(i)]) {
            return i;
        }
    }
    return self.width - 1;
}

// See issue 6592 for why `setBackgroundColors` exists. tl;dr ncurses makes weird assumptions.
- (void)mutAppendTabAtCursor:(BOOL)setBackgroundColors {
    int rightMargin;
    if (_state.currentGrid.useScrollRegionCols) {
        rightMargin = _state.currentGrid.rightMargin;
        if (_state.currentGrid.cursorX > rightMargin) {
            rightMargin = self.width - 1;
        }
    } else {
        rightMargin = self.width - 1;
    }

    if (_state.terminal.moreFix && _mutableState.cursorX > self.width && _state.terminal.wraparoundMode) {
        [self terminalLineFeed];
        [self mutCarriageReturn];
    }

    int nextTabStop = MIN(rightMargin, [self tabStopAfterColumn:_state.currentGrid.cursorX]);
    if (nextTabStop <= _state.currentGrid.cursorX) {
        // This happens when the cursor can't advance any farther.
        if ([iTermAdvancedSettingsModel tabsWrapAround]) {
            nextTabStop = [self tabStopAfterColumn:_state.currentGrid.leftMargin];
            [self softWrapCursorToNextLineScrollingIfNeeded];
        } else {
            return;
        }
    }
    const int y = _state.currentGrid.cursorY;
    screen_char_t *aLine = [_mutableState.currentGrid screenCharsAtLineNumber:y];
    BOOL allNulls = YES;
    for (int i = _state.currentGrid.cursorX; i < nextTabStop; i++) {
        if (aLine[i].code) {
            allNulls = NO;
            break;
        }
    }
    if (allNulls) {
        screen_char_t filler;
        InitializeScreenChar(&filler, [_state.terminal foregroundColorCode], [_state.terminal backgroundColorCode]);
        filler.code = TAB_FILLER;
        const int startX = _state.currentGrid.cursorX;
        const int limit = nextTabStop - 1;
        iTermExternalAttribute *ea = [_state.terminal externalAttributes];
        [_mutableState.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(startX, y, limit + 1, y)
                                                     block:^(screen_char_t *c,
                                                             iTermExternalAttribute **eaOut,
                                                             VT100GridCoord coord,
                                                             BOOL *stop) {
            if (coord.x < limit) {
                if (setBackgroundColors) {
                    *c = filler;
                    *eaOut = ea;
                } else {
                    c->image = NO;
                    c->complexChar = NO;
                    c->code = TAB_FILLER;
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

        [delegate_ screenAppendScreenCharArray:aLine + _state.currentGrid.cursorX
                                      metadata:iTermImmutableMetadataDefault()
                                        length:nextTabStop - startX];
    }
    _mutableState.currentGrid.cursorX = nextTabStop;
}

- (void)mutCursorLeft:(int)n {
    [_mutableState.currentGrid moveCursorLeft:n];
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [_mutableState.currentGrid moveCursorDown:n];
    if (toStart) {
        [_mutableState.currentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorRight:(int)n {
    [_mutableState.currentGrid moveCursorRight:n];
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [_mutableState.currentGrid moveCursorUp:n];
    if (toStart) {
        [_mutableState.currentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutShowTestPattern {
    screen_char_t ch = [_state.currentGrid defaultChar];
    ch.code = 'E';
    [_mutableState.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                         to:VT100GridCoordMake(_state.currentGrid.size.width - 1,
                                                               _state.currentGrid.size.height - 1)
                                     toChar:ch
                         externalAttributes:nil];
    [_mutableState.currentGrid resetScrollRegions];
    _mutableState.currentGrid.cursor = VT100GridCoordMake(0, 0);
}

- (void)mutSetScrollRegionTop:(int)top bottom:(int)bottom {
    if (top >= 0 &&
        top < _state.currentGrid.size.height &&
        bottom >= 0 &&
        bottom < _state.currentGrid.size.height &&
        bottom > top) {
        _mutableState.currentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([_state.terminal originMode]) {
            _mutableState.currentGrid.cursor = VT100GridCoordMake(_state.currentGrid.leftMargin,
                                                                  _state.currentGrid.topMargin);
        } else {
            _mutableState.currentGrid.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

- (void)scrollScreenIntoHistory {
    // Scroll the top lines of the screen into history, up to and including the last non-
    // empty line.
    LineBuffer *lineBuffer;
    if (_state.currentGrid == _state.altGrid && !_state.saveToScrollbackInAlternateScreen) {
        lineBuffer = nil;
    } else {
        lineBuffer = _mutableState.linebuffer;
    }
    const int n = [_state.currentGrid numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:YES];
    for (int i = 0; i < n; i++) {
        [_mutableState incrementOverflowBy:
         [_mutableState.currentGrid scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                                  unlimitedScrollback:_state.unlimitedScrollback]];
    }
}

- (void)mutEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    int x1, yStart, x2, y2;
    BOOL shouldHonorProtected = NO;
    switch (_state.protectedMode) {
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
        [delegate_ screenRemoveSelection];
        if (!shouldHonorProtected) {
            [self scrollScreenIntoHistory];
        }
        x1 = 0;
        yStart = 0;
        x2 = _state.currentGrid.size.width - 1;
        y2 = _state.currentGrid.size.height - 1;
    } else if (before) {
        x1 = 0;
        yStart = 0;
        x2 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
        y2 = _state.currentGrid.cursor.y;
    } else if (after) {
        x1 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
        yStart = _state.currentGrid.cursor.y;
        x2 = _state.currentGrid.size.width - 1;
        y2 = _state.currentGrid.size.height - 1;
        if (x1 == 0 && yStart == 0 && [iTermAdvancedSettingsModel saveScrollBufferWhenClearing] && self.terminal.softAlternateScreenMode) {
            // Save the whole screen. This helps the "screen" terminal, where CSI H CSI J is used to
            // clear the screen.
            // Only do it in alternate screen mode to avoid doing this for zsh (issue 8822)
            // And don't do it if in a protection mode since that would defeat the purpose.
            [delegate_ screenRemoveSelection];
            if (!shouldHonorProtected) {
                [self scrollScreenIntoHistory];
            }
        } else if (_mutableState.cursorX == 1 && _mutableState.cursorY == 1 && _state.terminal.lastToken.type == VT100CSI_CUP) {
            // This is important for tmux integration with shell integration enabled. The screen
            // terminal uses ED 0 instead of ED 2 to clear the screen (e.g., when you do ^L at the shell).
            [self removePromptMarksBelowLine:yStart + _mutableState.numberOfScrollbackLines];
        }
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }
    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, yStart),
                                                 VT100GridCoordMake(x2, y2),
                                                 _state.currentGrid.size.width);
    if (shouldHonorProtected) {
        const BOOL foundProtected = [self mutSelectiveEraseRange:VT100GridCoordRangeMake(x1, yStart, x2, y2)
                                                 eraseAttributes:YES];
        const BOOL eraseAll = (x1 == 0 && yStart == 0 && x2 == _state.currentGrid.size.width - 1 && y2 == _state.currentGrid.size.height - 1);
        if (!foundProtected && eraseAll) {  // xterm has this logic, so we do too. My guess is that it's an optimization.
            _mutableState.protectedMode = VT100TerminalProtectedModeNone;
        }
    } else {
        [_mutableState.currentGrid setCharsInRun:theRun
                                          toChar:0
                              externalAttributes:nil];
    }
    [delegate_ screenTriggerableChangeDidOccur];

}

- (void)mutEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    BOOL shouldHonorProtected = NO;
    switch (_state.protectedMode) {
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
        x2 = _state.currentGrid.size.width - 1;
    } else if (before) {
        x1 = 0;
        x2 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
    } else if (after) {
        x1 = _state.currentGrid.cursor.x;
        x2 = _state.currentGrid.size.width - 1;
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }

    if (shouldHonorProtected) {
        [self mutSelectiveEraseRange:VT100GridCoordRangeMake(x1,
                                                             _state.currentGrid.cursor.y,
                                                             x2,
                                                             _state.currentGrid.cursor.y)
                     eraseAttributes:YES];
    } else {
        VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, _state.currentGrid.cursor.y),
                                                     VT100GridCoordMake(x2, _state.currentGrid.cursor.y),
                                                     _state.currentGrid.size.width);
        [_mutableState.currentGrid setCharsInRun:theRun
                                          toChar:0
                              externalAttributes:nil];
    }
}

- (void)mutCarriageReturn {
    if (_state.currentGrid.useScrollRegionCols && _state.currentGrid.cursorX < _state.currentGrid.leftMargin) {
        _mutableState.currentGrid.cursorX = 0;
    } else {
        [_mutableState.currentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [self mutDidUpdatePromptLocation];
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutReverseIndex {
    if (_state.currentGrid.cursorY == _state.currentGrid.topMargin) {
        if ([self cursorOutsideLeftRightMargin]) {
            return;
        } else {
            [_mutableState.currentGrid scrollDown];
        }
    } else {
        _mutableState.currentGrid.cursorY = MAX(0, _state.currentGrid.cursorY - 1);
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutForwardIndex {
    if ((_state.currentGrid.cursorX == _state.currentGrid.rightMargin && ![self cursorOutsideLeftRightMargin] )||
         _state.currentGrid.cursorX == _state.currentGrid.size.width) {
        [_mutableState.currentGrid moveContentLeft:1];
    } else {
        _mutableState.currentGrid.cursorX += 1;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutBackIndex {
    if ((_state.currentGrid.cursorX == _state.currentGrid.leftMargin && ![self cursorOutsideLeftRightMargin] )||
         _state.currentGrid.cursorX == 0) {
        [_mutableState.currentGrid moveContentRight:1];
    } else if (_state.currentGrid.cursorX > 0) {
        _mutableState.currentGrid.cursorX -= 1;
    } else {
        return;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutBackTab:(int)n {
    for (int i = 0; i < n; i++) {
        // TODO: respect left-right margins
        if (_state.currentGrid.cursorX > 0) {
            _mutableState.currentGrid.cursorX = _state.currentGrid.cursorX - 1;
            while (![self haveTabStopAt:_state.currentGrid.cursorX] && _state.currentGrid.cursorX > 0) {
                _mutableState.currentGrid.cursorX = _state.currentGrid.cursorX - 1;
            }
            [delegate_ screenTriggerableChangeDidOccur];
        }
    }
}

- (BOOL)haveTabStopAt:(int)x {
    return [_state.tabStops containsObject:[NSNumber numberWithInt:x]];
}

- (void)mutAdvanceCursorPastLastColumn {
    if (_state.currentGrid.cursorX == self.width - 1) {
        _mutableState.currentGrid.cursorX = self.width;
    }
}

- (void)mutEraseCharactersAfterCursor:(int)j {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        if (j <= 0) {
            return;
        }

        switch (_state.protectedMode) {
            case VT100TerminalProtectedModeNone:
            case VT100TerminalProtectedModeDEC: {
                // Do not honor protected mode.
                int limit = MIN(_state.currentGrid.cursorX + j, _state.currentGrid.size.width);
                [_mutableState.currentGrid setCharsFrom:VT100GridCoordMake(_state.currentGrid.cursorX, _state.currentGrid.cursorY)
                                                     to:VT100GridCoordMake(limit - 1, _state.currentGrid.cursorY)
                                                 toChar:[_state.currentGrid defaultChar]
                                     externalAttributes:nil];
                // TODO: This used to always set the continuation mark to hard, but I think it should only do that if the last char in the line is erased.
                [delegate_ screenTriggerableChangeDidOccur];
                break;
            }
            case VT100TerminalProtectedModeISO:
                // honor protected mode.
                [self mutSelectiveEraseRange:VT100GridCoordRangeMake(_state.currentGrid.cursorX,
                                                                     _state.currentGrid.cursorY,
                                                                     MIN(_state.currentGrid.size.width, _state.currentGrid.cursorX + j),
                                                                     _state.currentGrid.cursorY)
                             eraseAttributes:YES];
                break;
        }
    }
}

- (void)mutInsertEmptyCharsAtCursor:(int)n {
    [_mutableState.currentGrid insertChar:[_state.currentGrid defaultChar]
                       externalAttributes:nil
                                       at:_state.currentGrid.cursor
                                    times:n];
}

- (void)mutShiftLeft:(int)n {
    if (n < 1) {
        return;
    }
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    [_mutableState.currentGrid moveContentLeft:n];
}

- (void)mutShiftRight:(int)n {
    if (n < 1) {
        return;
    }
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    [_mutableState.currentGrid moveContentRight:n];
}

- (void)mutInsertBlankLinesAfterCursor:(int)n {
    VT100GridRect scrollRegionRect = [_state.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == _state.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(_state.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        // xterm appears to ignore INSLN if the cursor is outside the scroll region.
        // See insln-* files in tests/.
        int top = _state.currentGrid.cursorY;
        int left = _state.currentGrid.leftMargin;
        int width = _state.currentGrid.rightMargin - _state.currentGrid.leftMargin + 1;
        int height = _state.currentGrid.bottomMargin - top + 1;
        [_mutableState.currentGrid scrollRect:VT100GridRectMake(left, top, width, height)
                                       downBy:n
                                    softBreak:NO];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)mutDeleteCharactersAtCursor:(int)n {
    [_mutableState.currentGrid deleteChars:n startingAt:_state.currentGrid.cursor];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutDeleteLinesAtCursor:(int)n {
    if (n <= 0) {
        return;
    }
    VT100GridRect scrollRegionRect = [_state.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == _state.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(_state.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        [_mutableState.currentGrid scrollRect:VT100GridRectMake(_state.currentGrid.leftMargin,
                                                                _state.currentGrid.cursorY,
                                                                _state.currentGrid.rightMargin - _state.currentGrid.leftMargin + 1,
                                                                _state.currentGrid.bottomMargin - _state.currentGrid.cursorY + 1)
                                       downBy:-n
                                    softBreak:NO];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)mutScrollUp:(int)n {
    [delegate_ screenRemoveSelection];
    for (int i = 0;
         i < MIN(_state.currentGrid.size.height, n);
         i++) {
        [_mutableState incrementOverflowBy:[_mutableState.currentGrid scrollUpIntoLineBuffer:_mutableState.linebuffer
                                                                         unlimitedScrollback:_state.unlimitedScrollback
                                                                     useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                                   softBreak:NO]];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutScrollDown:(int)n {
    [delegate_ screenRemoveSelection];
    [_mutableState.currentGrid scrollRect:[_state.currentGrid scrollRegionRect]
                                   downBy:MIN(_state.currentGrid.size.height, n)
                                softBreak:NO];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutInsertColumns:(int)n {
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = _state.currentGrid.topMargin; y <= _state.currentGrid.bottomMargin; y++) {
        [_mutableState.currentGrid insertChar:_state.currentGrid.defaultChar
                           externalAttributes:nil
                                           at:VT100GridCoordMake(_state.currentGrid.cursor.x, y)
                                        times:n];
    }
}

- (void)mutDeleteColumns:(int)n {
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = _state.currentGrid.topMargin; y <= _state.currentGrid.bottomMargin; y++) {
        [_mutableState.currentGrid deleteChars:n
                                    startingAt:VT100GridCoordMake(_state.currentGrid.cursor.x, y)];
    }
}

- (void)mutSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
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
    if (_state.terminal.decsaceRectangleMode) {
        [_mutableState.currentGrid mutateCellsInRect:rect
                                               block:^(VT100GridCoord coord,
                                                       screen_char_t *sct,
                                                       iTermExternalAttribute **eaOut,
                                                       BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [_mutableState.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
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

- (void)mutToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
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
    if (_state.terminal.decsaceRectangleMode) {
        [_mutableState.currentGrid mutateCellsInRect:rect
                                               block:^(VT100GridCoord coord,
                                                       screen_char_t *sct,
                                                       iTermExternalAttribute **eaOut,
                                                       BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [_mutableState.currentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
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

- (void)mutFillRectangle:(VT100GridRect)rect with:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    [_mutableState.currentGrid setCharsFrom:rect.origin
                                         to:VT100GridRectMax(rect)
                                     toChar:c
                         externalAttributes:ea];
}

static inline void VT100ScreenEraseCell(screen_char_t *sct, iTermExternalAttribute **eaOut, BOOL eraseAttributes, const screen_char_t *defaultChar) {
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
                                                               urlCode:0];
    }
}

// Note: this does not erase attributes! It just sets the character to space.
- (void)mutSelectiveEraseRectangle:(VT100GridRect)rect {
    const screen_char_t dc = _state.currentGrid.defaultChar;
    [_mutableState.currentGrid mutateCellsInRect:rect
                                           block:^(VT100GridCoord coord,
                                                   screen_char_t *sct,
                                                   iTermExternalAttribute **eaOut,
                                                   BOOL *stop) {
        if (_state.protectedMode == VT100TerminalProtectedModeDEC && sct->guarded) {
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, NO, &dc);
    }];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (BOOL)mutSelectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes {
    __block BOOL foundProtected = NO;
    const screen_char_t dc = _state.currentGrid.defaultChar;
    [_mutableState.currentGrid mutateCharactersInRange:range
                                                 block:^(screen_char_t *sct,
                                                         iTermExternalAttribute **eaOut,
                                                         VT100GridCoord coord,
                                                         BOOL *stop) {
        if (_state.protectedMode != VT100TerminalProtectedModeNone && sct->guarded) {
            foundProtected = YES;
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, eraseAttributes, &dc);
    }];
    [delegate_ screenTriggerableChangeDidOccur];
    return foundProtected;
}

- (void)setCursorX:(int)x Y:(int)y {
    DLog(@"Move cursor to %d,%d", x, y);
    _mutableState.currentGrid.cursor = VT100GridCoordMake(x, y);
}

- (void)mutSetUseColumnScrollRegion:(BOOL)mode {
    _mutableState.currentGrid.useScrollRegionCols = mode;
    self.mutableAltGrid.useScrollRegionCols = mode;
    if (!mode) {
        _mutableState.currentGrid.scrollRegionCols = VT100GridRangeMake(0, _state.currentGrid.size.width);
    }
}

- (void)mutCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    id<VT100GridReading> copy = [[_state.currentGrid copy] autorelease];
    const VT100GridSize size = _state.currentGrid.size;
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
        [_mutableState.currentGrid setCharsFrom:destCoord
                                             to:destCoord
                                         toChar:sct
                             externalAttributes:ea];
    }];
}

- (void)mutSetTabStopAtCursor {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        [_mutableState.tabStops addObject:[NSNumber numberWithInt:_state.currentGrid.cursorX]];
    }
}

- (void)mutRemoveAllTabStops {
    [_mutableState.tabStops removeAllObjects];
}

- (void)mutRemoveTabStopAtCursor {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        [_mutableState.tabStops removeObject:[NSNumber numberWithInt:_state.currentGrid.cursorX]];
    }
}

- (void)mutSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [_mutableState.tabStops removeAllObjects];
    [tabStops enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [_mutableState.tabStops addObject:@(obj.intValue - 1)];
    }];
}

#pragma mark - DVR

- (void)mutSetFromFrame:(screen_char_t*)s
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
    [_mutableState.currentGrid setContentsFromDVRFrame:s metadataArray:md info:info];
    for (int i = 0; i < info.height; i++) {
        iTermMetadataRelease(md[i]);
    }
    [self resetScrollbackOverflow];
    _mutableState.savedFindContextAbsPos = 0;
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
    [_mutableState.currentGrid markAllCharsDirty:YES];
}

#pragma mark - Find on Page

- (void)mutSaveFindContextAbsPos {
    int linesPushed;
    linesPushed = [_mutableState.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                                            toLineBuffer:_mutableState.linebuffer];

    [self mutSaveFindContextPosition];
    [self mutPopScrollbackLines:linesPushed];
}

- (void)mutRestorePreferredCursorPositionIfPossible {
    [_mutableState.currentGrid restorePreferredCursorPositionIfPossible];
}

- (void)mutRestoreSavedPositionToFindContext:(FindContext *)context {
    int linesPushed;
    linesPushed = [_mutableState.currentGrid appendLines:[_mutableState.currentGrid numberOfLinesUsed]
                                            toLineBuffer:_mutableState.linebuffer];

    [_mutableState.linebuffer storeLocationOfAbsPos:_mutableState.savedFindContextAbsPos
                                          inContext:context];

    [self mutPopScrollbackLines:linesPushed];
}

- (void)mutSetFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults {
    DLog(@"begin self=%@ aString=%@", self, aString);
    LineBuffer *tempLineBuffer = [[_mutableState.linebuffer copy] autorelease];
    [tempLineBuffer seal];

    // Append the screen contents to the scrollback buffer so they are included in the search.
    [_mutableState.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                              toLineBuffer:tempLineBuffer];

    // Get the start position of (x,y)
    LineBufferPosition *startPos;
    startPos = [tempLineBuffer positionForCoordinate:VT100GridCoordMake(x, y)
                                               width:_state.currentGrid.size.width
                                              offset:offset * (direction ? 1 : -1)];
    if (!startPos) {
        // x,y wasn't a real position in the line buffer, probably a null after the end.
        if (direction) {
            DLog(@"Search from first position");
            startPos = [tempLineBuffer firstPosition];
        } else {
            DLog(@"Search from last position");
            startPos = [[tempLineBuffer lastPosition] predecessor];
        }
    } else {
        DLog(@"Search from %@", startPos);
        // Make sure startPos is not at or after the last cell in the line buffer.
        BOOL ok;
        VT100GridCoord startPosCoord = [tempLineBuffer coordinateForPosition:startPos
                                                                       width:_state.currentGrid.size.width
                                                                extendsRight:YES
                                                                          ok:&ok];
        LineBufferPosition *lastValidPosition = [[tempLineBuffer lastPosition] predecessor];
        if (!ok) {
            startPos = lastValidPosition;
        } else {
            VT100GridCoord lastPositionCoord = [tempLineBuffer coordinateForPosition:lastValidPosition
                                                                               width:_state.currentGrid.size.width
                                                                        extendsRight:YES
                                                                                  ok:&ok];
            assert(ok);
            long long s = startPosCoord.y;
            s *= _state.currentGrid.size.width;
            s += startPosCoord.x;

            long long l = lastPositionCoord.y;
            l *= _state.currentGrid.size.width;
            l += lastPositionCoord.x;

            if (s >= l) {
                startPos = lastValidPosition;
            }
        }
    }

    // Set up the options bitmask and call findSubstring.
    FindOptions opts = 0;
    if (!direction) {
        opts |= FindOptBackwards;
    }
    if (multipleResults) {
        opts |= FindMultipleResults;
    }
    [tempLineBuffer prepareToSearchFor:aString startingAt:startPos options:opts mode:mode withContext:context];
    context.hasWrapped = NO;
}

- (void)mutSaveFindContextPosition {
    _mutableState.savedFindContextAbsPos = [_mutableState.linebuffer absPositionOfFindContext:_mutableState.findContext];
}

- (void)mutStoreLastPositionInLineBufferAsFindContextSavedPosition {
    _mutableState.savedFindContextAbsPos = [[_mutableState.linebuffer lastPosition] absolutePosition];
}

- (BOOL)mutContinueFindResultsInContext:(FindContext *)context
                                toArray:(NSMutableArray *)results {
    // Append the screen contents to the scrollback buffer so they are included in the search.
    LineBuffer *temporaryLineBuffer = [[_mutableState.linebuffer copy] autorelease];
    [temporaryLineBuffer seal];

#warning TODO: This is an unusual use of mutation since it is only temporary. But probably Find should happen off-thread anyway.
    [_mutableState.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                              toLineBuffer:temporaryLineBuffer];

    // Search one block.
    LineBufferPosition *stopAt;
    if (context.dir > 0) {
        stopAt = [temporaryLineBuffer lastPosition];
    } else {
        stopAt = [temporaryLineBuffer firstPosition];
    }

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    BOOL keepSearching = NO;
    int iterations = 0;
    int ms_diff = 0;
    do {
        if (context.status == Searching) {
            [temporaryLineBuffer findSubstring:context stopAt:stopAt];
        }

        // Handle the current state
        switch (context.status) {
            case Matched: {
                // NSLog(@"matched");
                // Found a match in the text.
                NSArray *allPositions = [temporaryLineBuffer convertPositions:context.results
                                                                    withWidth:_state.currentGrid.size.width];
                for (XYRange *xyrange in allPositions) {
                    SearchResult *result = [[[SearchResult alloc] init] autorelease];

                    result.startX = xyrange->xStart;
                    result.endX = xyrange->xEnd;
                    result.absStartY = xyrange->yStart + _mutableState.cumulativeScrollbackOverflow;
                    result.absEndY = xyrange->yEnd + _mutableState.cumulativeScrollbackOverflow;

                    [results addObject:result];

                    if (!(context.options & FindMultipleResults)) {
                        assert([context.results count] == 1);
                        [context reset];
                        keepSearching = NO;
                    } else {
                        keepSearching = YES;
                    }
                }
                [context.results removeAllObjects];
                break;
            }

            case Searching:
                // NSLog(@"searching");
                // No result yet but keep looking
                keepSearching = YES;
                break;

            case NotFound:
                // NSLog(@"not found");
                // Reached stopAt point with no match.
                if (context.hasWrapped) {
                    [context reset];
                    keepSearching = NO;
                } else {
                    // NSLog(@"...wrapping");
                    // wrap around and resume search.
                    FindContext *tempFindContext = [[[FindContext alloc] init] autorelease];
                    [temporaryLineBuffer prepareToSearchFor:_mutableState.findContext.substring
                                                 startingAt:(_mutableState.findContext.dir > 0 ? [temporaryLineBuffer firstPosition] : [[temporaryLineBuffer lastPosition] predecessor])
                                                    options:_mutableState.findContext.options
                                                       mode:_mutableState.findContext.mode
                                                withContext:tempFindContext];
                    [_mutableState.findContext reset];
                    // TODO test this!
                    [context copyFromFindContext:tempFindContext];
                    context.hasWrapped = YES;
                    keepSearching = YES;
                }
                break;

            default:
                assert(false);  // Bogus status
        }

        struct timeval endtime;
        if (keepSearching) {
            gettimeofday(&endtime, NULL);
            ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
            (endtime.tv_usec - begintime.tv_usec) / 1000;
            context.status = Searching;
        }
        ++iterations;
    } while (keepSearching && ms_diff < context.maxTime * 1000);

    switch (context.status) {
        case Searching: {
            int numDropped = [temporaryLineBuffer numberOfDroppedBlocks];
            double current = context.absBlockNum - numDropped;
            double max = [temporaryLineBuffer largestAbsoluteBlockNumber] - numDropped;
            double p = MAX(0, current / max);
            if (context.dir > 0) {
                context.progress = p;
            } else {
                context.progress = 1.0 - p;
            }
            break;
        }
        case Matched:
        case NotFound:
            context.progress = 1;
            break;
    }
    // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

    return keepSearching;
}

#pragma mark - Color Map

- (void)mutSetColor:(NSColor *)color forKey:(int)key {
    [_mutableState.colorMap setColor:color forKey:key];
}

- (void)mutSetDimOnlyText:(BOOL)dimOnlyText {
    _mutableState.colorMap.dimOnlyText = dimOnlyText;
}

- (void)mutSetDarkMode:(BOOL)darkMode {
    _mutableState.colorMap.darkMode = darkMode;
}

- (void)mutSetUseSeparateColorsForLightAndDarkMode:(BOOL)value {
    _mutableState.colorMap.useSeparateColorsForLightAndDarkMode = value;
}

- (void)mutSetMinimumContrast:(float)value {
    _mutableState.colorMap.minimumContrast = value;
}

- (void)mutSetMutingAmount:(double)value {
    _mutableState.colorMap.mutingAmount = value;
}

- (void)mutSetDimmingAmount:(double)value {
    _mutableState.colorMap.dimmingAmount = value;
}

#pragma mark - Accessors

- (void)mutSetShouldExpectPromptMarks:(BOOL)value {
    _mutableState.shouldExpectPromptMarks = value;
}

- (void)mutSetLastPromptLine:(long long)value {
    _mutableState.lastPromptLine = value;
}

- (void)mutSetDelegate:(id<VT100ScreenDelegate>)delegate {
    _mutableState.colorMap.delegate = delegate;
    delegate_ = delegate;
}

- (void)mutSetLastCommandMark:(VT100ScreenMark *)mark {
    _mutableState.lastCommandMark = mark;
}

- (void)mutSetIntervalTreeObserver:(id<iTermIntervalTreeObserver>)intervalTreeObserver {
    _mutableState.intervalTreeObserver = intervalTreeObserver;
}

- (void)mutSetNormalization:(iTermUnicodeNormalization)value {
    _mutableState.normalization = value;
}

- (void)mutSetShellIntegrationInstalled:(BOOL)shellIntegrationInstalled {
    _mutableState.shellIntegrationInstalled = shellIntegrationInstalled;
}

- (void)mutSetAppendToScrollbackWithStatusBar:(BOOL)value {
    _mutableState.appendToScrollbackWithStatusBar = value;
}

- (void)mutSetTrackCursorLineMovement:(BOOL)trackCursorLineMovement {
    _mutableState.trackCursorLineMovement = trackCursorLineMovement;
}

- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value {
    _mutableState.saveToScrollbackInAlternateScreen = value;
}

- (void)mutInvalidateCommandStartCoord {
    [self mutSetCommandStartCoord:VT100GridAbsCoordMake(-1, -1)];
}

- (void)mutInvalidateCommandStartCoordWithoutSideEffects {
    [self mutSetCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake(-1, -1)];
}

- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord {
    _mutableState.commandStartCoord = coord;
    [self mutDidUpdatePromptLocation];
    [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
}

- (void)mutSetCommandStartCoordWithoutSideEffects:(VT100GridAbsCoord)coord {
    _mutableState.commandStartCoord = coord;
}

- (void)mutResetScrollbackOverflow {
    _mutableState.scrollbackOverflow = 0;
}

- (void)mutSetWraparoundMode:(BOOL)newValue {
    _mutableState.wraparoundMode = newValue;
}

- (void)mutUpdateTerminalType {
    _mutableState.ansi = [_state.terminal isAnsi];
}

- (void)mutSetInsert:(BOOL)newValue {
    _mutableState.insert = newValue;
}

- (void)mutSetUnlimitedScrollback:(BOOL)newValue {
    _mutableState.unlimitedScrollback = newValue;
}

// Gets a line on the screen (0 = top of screen)
- (screen_char_t *)mutGetLineAtScreenIndex:(int)theIndex {
    return [_mutableState.currentGrid screenCharsAtLineNumber:theIndex];
}

- (void)mutSetTerminal:(VT100Terminal *)terminal {
    _mutableState.terminal = terminal;
    _mutableState.ansi = [terminal isAnsi];
    _mutableState.wraparoundMode = [terminal wraparoundMode];
    _mutableState.insert = [terminal insertMode];
}

#pragma mark - Dirty

- (void)mutResetAllDirty {
    _mutableState.currentGrid.allDirty = NO;
}

- (void)mutSetLineDirtyAtY:(int)y {
    if (y >= 0) {
        [_mutableState.currentGrid markCharsDirty:YES
                                       inRectFrom:VT100GridCoordMake(0, y)
                                               to:VT100GridCoordMake(self.width - 1, y)];
    }
}

- (void)mutSetCharDirtyAtCursorX:(int)x Y:(int)y {
    if (y < 0) {
        DLog(@"Warning: cannot set character dirty at y=%d", y);
        return;
    }
    int xToMark = x;
    int yToMark = y;
    if (xToMark == _state.currentGrid.size.width && yToMark < _state.currentGrid.size.height - 1) {
        xToMark = 0;
        yToMark++;
    }
    if (xToMark < _state.currentGrid.size.width && yToMark < _state.currentGrid.size.height) {
        [_mutableState.currentGrid markCharDirty:YES
                                              at:VT100GridCoordMake(xToMark, yToMark)
                                 updateTimestamp:NO];
        if (xToMark < _state.currentGrid.size.width - 1) {
            // Just in case the cursor was over a double width character
            [_mutableState.currentGrid markCharDirty:YES
                                                  at:VT100GridCoordMake(xToMark + 1, yToMark)
                                     updateTimestamp:NO];
        }
    }
}

- (void)mutResetDirty {
    [_mutableState.currentGrid markAllCharsDirty:NO];
}

- (void)mutMarkWholeScreenDirty {
    [_mutableState.currentGrid markAllCharsDirty:YES];
}

- (void)mutRedrawGrid {
    [_mutableState.currentGrid setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [delegate_ screenUpdateDisplay:YES];
}

#pragma mark - Alternate Screen

// Swap onscreen notes between intervalTree_ and savedIntervalTree_.
// IMPORTANT: Call -mutReloadMarkCache after this.
- (void)mutSwapNotes {
    int historyLines = _mutableState.numberOfScrollbackLines;
    Interval *origin = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                               historyLines,
                                                                               1,
                                                                               historyLines)];
    IntervalTree *temp = [[[IntervalTree alloc] init] autorelease];
    DLog(@"mutSwapNotes: moving onscreen notes into savedNotes");
    [self moveNotesOnScreenFrom:_mutableState.intervalTree
                             to:temp
                         offset:-origin.location
                   screenOrigin:_mutableState.numberOfScrollbackLines];
    DLog(@"mutSwapNotes: moving onscreen savedNotes into notes");
    [self moveNotesOnScreenFrom:_mutableState.savedIntervalTree
                             to:_mutableState.intervalTree
                         offset:origin.location
                   screenOrigin:0];
    _mutableState.savedIntervalTree = temp;
}

- (void)mutShowAltBuffer {
    if (_state.currentGrid == _state.altGrid) {
        return;
    }
    [delegate_ screenRemoveSelection];
    if (!_state.altGrid) {
        _mutableState.altGrid = [[[VT100Grid alloc] initWithSize:_state.primaryGrid.size delegate:self] autorelease];
    }

    [self.mutableTemporaryDoubleBuffer reset];
    self.mutablePrimaryGrid.savedDefaultChar = [_state.primaryGrid defaultChar];
    [self hideOnScreenNotesAndTruncateSpanners];
    _mutableState.currentGrid = _state.altGrid;
    _mutableState.currentGrid.cursor = _state.primaryGrid.cursor;

    [self mutSwapNotes];
    [self mutReloadMarkCache];

    [_mutableState.currentGrid markAllCharsDirty:YES];
    [delegate_ screenScheduleRedrawSoon];
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
}

- (void)mutShowPrimaryBuffer {
    if (_state.currentGrid == _state.altGrid) {
        [self.mutableTemporaryDoubleBuffer reset];
        [delegate_ screenRemoveSelection];
        [self hideOnScreenNotesAndTruncateSpanners];
        _mutableState.currentGrid = _state.primaryGrid;
        [self mutInvalidateCommandStartCoordWithoutSideEffects];
        [self mutSwapNotes];
        [self mutReloadMarkCache];

        [_mutableState.currentGrid markAllCharsDirty:YES];
        [delegate_ screenScheduleRedrawSoon];
    }
}

- (void)hideOnScreenNotesAndTruncateSpanners {
    int screenOrigin = _mutableState.numberOfScrollbackLines;
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
#warning TODO: This should be a side-effect. Moreover, I risk unchecked interations with mutable state through interval tree downcasts like this. I need a good solution to make the interval tree safe.
        PTYAnnotation *annotation = [PTYAnnotation castFrom:note];
        [annotation hide];
    }
    // Force annotations frames to be updated.
    [delegate_ screenNeedsRedraw];
}

#pragma mark - URLs

- (void)mutLinkRun:(VT100GridRun)run
       withURLCode:(unsigned int)code {

    for (NSValue *value in [_state.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [_mutableState.currentGrid setURLCode:code
                                   inRectFrom:rect.origin
                                           to:VT100GridRectMax(rect)];
    }
}

#pragma mark - Highlighting

// Set the color of prototypechar to all chars between startPoint and endPoint on the screen.
- (void)mutHighlightRun:(VT100GridRun)run
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

    for (NSValue *value in [_state.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [_mutableState.currentGrid setBackgroundColor:bg
                                      foregroundColor:fg
                                           inRectFrom:rect.origin
                                                   to:VT100GridRectMax(rect)];
    }
}

#pragma mark - Scrollback

// sets scrollback lines.
- (void)mutSetMaxScrollbackLines:(unsigned int)lines {
    _mutableState.maxScrollbackLines = lines;
    [self.mutableLineBuffer setMaxLines: lines];
    if (!_state.unlimitedScrollback) {
        [_mutableState incrementOverflowBy:[self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width]];
    }
    [delegate_ screenDidChangeNumberOfScrollbackLines];
}

- (void)mutPopScrollbackLines:(int)linesPushed {
    // Undo the appending of the screen to scrollback
    int i;
    screen_char_t* dummy = iTermCalloc(_state.currentGrid.size.width, sizeof(screen_char_t));
    for (i = 0; i < linesPushed; ++i) {
        int cont;
        BOOL isOk __attribute__((unused)) =
        [self.mutableLineBuffer popAndCopyLastLineInto:dummy
                                                 width:_state.currentGrid.size.width
                                     includesEndOfLine:&cont
                                              metadata:NULL
                                          continuation:NULL];
        ITAssertWithMessage(isOk, @"Pop shouldn't fail");
    }
    free(dummy);
}

#pragma mark - Miscellaneous State

- (BOOL)mutGetAndResetHasScrolled {
    const BOOL result = _state.currentGrid.haveScrolled;
    _mutableState.currentGrid.haveScrolled = NO;
    return result;
}

#pragma mark - Synchronized Drawing

- (iTermTemporaryDoubleBufferedGridController *)mutableTemporaryDoubleBuffer {
    if ([delegate_ screenShouldReduceFlicker] || _mutableState.temporaryDoubleBuffer.explicit) {
        return _mutableState.temporaryDoubleBuffer;
    } else {
        return nil;
    }
}

- (PTYTextViewSynchronousUpdateState *)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    if (useSavedGrid && !_state.realCurrentGrid && self.mutableTemporaryDoubleBuffer.savedState) {
        _mutableState.realCurrentGrid = _state.currentGrid;
        _mutableState.currentGrid = self.mutableTemporaryDoubleBuffer.savedState.grid;
        self.mutableTemporaryDoubleBuffer.drewSavedGrid = YES;
        return self.mutableTemporaryDoubleBuffer.savedState;
    } else if (!useSavedGrid && _state.realCurrentGrid) {
        _mutableState.currentGrid = _state.realCurrentGrid;
        _mutableState.realCurrentGrid = nil;
    }
    return nil;
}

#pragma mark - File Transfer

- (void)mutStopTerminalReceivingFile {
    [_mutableState.terminal stopReceivingFile];
    [self mutFileReceiptEndedUnexpectedly];
}

- (void)mutFileReceiptEndedUnexpectedly {
    _mutableState.inlineImageHelper = nil;
    [delegate_ screenFileReceiptEndedUnexpectedly];
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
        [self mutDidUpdatePromptLocation];
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
        [self mutDidUpdatePromptLocation];
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
    if (![self remoteHostOnLine:_mutableState.numberOfScrollbackLines + self.height]) {
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
    [self mutSynchronizedUpdate:begin];
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

- (void)terminalShowPrimaryBuffer {
    [self mutShowPrimaryBuffer];
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    [self mutSetRemoteHost:remoteHost];
}

- (void)mutSetRemoteHost:(NSString *)remoteHost {
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
    [self mutSetPromptStartLine:_mutableState.numberOfScrollbackLines + _mutableState.cursorY - 1];
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
        [self mutSaveCursorLine];
    }
}

- (void)mutSaveCursorLine {
    const int scrollbackLines = [_mutableState.linebuffer numLinesWithWidth:_mutableState.currentGrid.size.width];
    [self mutAddMarkOnLine:scrollbackLines + _mutableState.currentGrid.cursor.y
                   ofClass:[VT100ScreenMark class]];
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
    [self mutCurrentDirectoryDidChangeTo:dir];
}

- (void)mutCurrentDirectoryDidChangeTo:(NSString *)dir {
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
    [self mutSetWorkingDirectory:dir onLine:cursorLine pushed:YES token:nil];
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
        PTYAnnotation *note = [[[PTYAnnotation alloc] init] autorelease];
        note.stringValue = message;
        [self addNote:note
              inRange:VT100GridCoordRangeMake(location.x,
                                              location.y + _mutableState.numberOfScrollbackLines,
                                              end.x,
                                              end.y + _mutableState.numberOfScrollbackLines)
                focus:NO];
        if (!show) {
            [note hide];
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

- (void)addURLMarkAtLineAfterCursorWithCode:(unsigned int)code {
    long long absLine = (self.totalScrollbackOverflow +
                         _mutableState.numberOfScrollbackLines +
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
    [_mutableState appendCarriageReturnLineFeed];
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
    return _state.cursorVisible;
}

- (NSColor *)terminalColorForIndex:(VT100TerminalColorIndex)index {
    const int key = [self colorMapKeyForTerminalColorIndex:index];
    if (key < 0) {
        return nil;
    }
    return [_state.colorMap colorForKey:key];
}

- (int)terminalCursorX {
    return MIN(_mutableState.cursorX, [self width]);
}

- (int)terminalCursorY {
    return _mutableState.cursorY;
}

- (BOOL)terminalWillAutoWrap {
    return _mutableState.cursorX > self.width;
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    [self mutSetCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    [delegate_ screenSetHighlightCursorLine:highlight];
}

- (void)terminalClearCapturedOutput {
    [delegate_ screenClearCapturedOutput];
}

- (void)terminalPromptDidStart {
    [self promptDidStartAt:VT100GridAbsCoordMake(_state.currentGrid.cursor.x,
                                                 _state.currentGrid.cursor.y + _mutableState.numberOfScrollbackLines + self.totalScrollbackOverflow)];
}

- (NSArray<NSNumber *> *)terminalTabStops {
    return [[_state.tabStops.allObjects sortedArrayUsingSelector:@selector(compare:)] mapWithBlock:^NSNumber *(NSNumber *ts) {
        return @(ts.intValue + 1);
    }];
}

- (void)terminalSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [self mutSetTabStops:tabStops];
}

- (void)terminalCommandDidStart {
    [self mutCommandDidStart];
}

- (void)terminalCommandDidEnd {
    [self mutCommandDidEnd];
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

- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode {
    [self mutSetReturnCodeOfLastCommand:returnCode];
}

- (void)mutSetReturnCodeOfLastCommand:(int)returnCode {
    DLog(@"FinalTerm: terminalReturnCodeOfLastCommandWas:%d", returnCode);
    VT100ScreenMark *mark = [[self.lastCommandMark retain] autorelease];
    if (mark) {
        DLog(@"FinalTerm: setting code on mark %@", mark);
        const NSInteger line = [self coordRangeForInterval:mark.entry.interval].start.y + self.totalScrollbackOverflow;
        [_state.intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:mark]
                                                                onLine:line];
        mark.code = returnCode;
        [_state.intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:mark]
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

- (NSArray<NSString *> *)terminalSGRCodesInRectangle:(VT100GridRect)screenRect {
    __block NSMutableSet<NSString *> *codes = nil;
    VT100GridRect rect = screenRect;
    rect.origin.y += [_state.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
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
    return [[[VT100SavedColorsSlot alloc] initWithTextColor:[_state.colorMap colorForKey:kColorMapForeground]
                                            backgroundColor:[_state.colorMap colorForKey:kColorMapBackground]
                                         selectionTextColor:[_state.colorMap colorForKey:kColorMapSelectedText]
                                   selectionBackgroundColor:[_state.colorMap colorForKey:kColorMapSelection]
                                       indexedColorProvider:^NSColor *(NSInteger index) {
        return [_state.colorMap colorForKey:kColorMap8bitBase + index] ?: [NSColor clearColor];
    }] autorelease];
}

- (void)terminalRestoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    for (int i = 0; i < MIN(kColorMapNumberOf8BitColors, slot.indexedColors.count); i++) {
        if (i >= 16) {
            [self setColor:slot.indexedColors[i] forKey:kColorMap8bitBase + i];
        }
    }
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
    [self mutSetProtectedMode:mode];
}

- (VT100TerminalProtectedMode)terminalProtectedMode {
    return _state.protectedMode;
}

#pragma mark - Printing

- (void)doPrint {
    if ([_state.printBuffer length] > 0) {
        [delegate_ screenPrintString:_state.printBuffer];
    } else {
        [delegate_ screenPrintVisibleArea];
    }
    _mutableState.printBuffer = nil;
    _mutableState.collectInputForPrinting = NO;
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        [self mutSetLastCommandMark:mark];
    }
}

@end

@implementation VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value {
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = value;
}

- (void)destructivelySetScreenWidth:(int)width height:(int)height {
    width = MAX(width, kVT100ScreenMinColumns);
    height = MAX(height, kVT100ScreenMinRows);

    self.mutablePrimaryGrid.size = VT100GridSizeMake(width, height);
    self.mutableAltGrid.size = VT100GridSizeMake(width, height);
    self.mutablePrimaryGrid.cursor = VT100GridCoordMake(0, 0);
    self.mutableAltGrid.cursor = VT100GridCoordMake(0, 0);
    [self.mutablePrimaryGrid resetScrollRegions];
    [self.mutableAltGrid resetScrollRegions];
    [_state.terminal resetSavedCursorPositions];

    _mutableState.findContext.substring = nil;

    _mutableState.scrollbackOverflow = 0;
    [delegate_ screenRemoveSelection];

    [self.mutablePrimaryGrid markAllCharsDirty:YES];
    [self.mutableAltGrid markAllCharsDirty:YES];
}

@end
