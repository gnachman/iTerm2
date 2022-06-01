//
//  VT100ScreenMutableState+TerminalDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/13/22.
//

#import "VT100ScreenMutableState+TerminalDelegate.h"
#import "VT100ScreenMutableState+Private.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "VT100ScreenConfiguration.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"

@implementation VT100ScreenMutableState (TerminalDelegate)

- (void)terminalAppendString:(NSString *)string {
    DLog(@"begin %@", string);
    if (self.collectInputForPrinting) {
        [self.printBuffer appendString:string];
    } else {
        // else display string on screen
        [self appendStringAtCursor:string];
    }
    [self appendStringToTriggerLine:string];
    if (self.config.loggingEnabled) {
        const screen_char_t foregroundColorCode = self.terminal.foregroundColorCode;
        const screen_char_t backgroundColorCode = self.terminal.backgroundColorCode;
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenDidAppendStringToCurrentLine:string
                                              isPlainText:YES
                                              foreground:foregroundColorCode
                                              background:backgroundColorCode];
        }];
    }
}

- (void)terminalAppendAsciiData:(AsciiData *)asciiData {
    DLog(@"begin");
    if (self.collectInputForPrinting) {
        NSString *string = [[NSString alloc] initWithBytes:asciiData->buffer
                                                    length:asciiData->length
                                                  encoding:NSASCIIStringEncoding];
        [self terminalAppendString:string];
        return;
    }
    // else display string on screen
    [self appendAsciiDataAtCursor:asciiData];

    if (![self appendAsciiDataToTriggerLine:asciiData] && self.config.loggingEnabled) {
        const screen_char_t foregroundColorCode = self.terminal.foregroundColorCode;
        const screen_char_t backgroundColorCode = self.terminal.backgroundColorCode;
        NSData *data = [NSData dataWithBytes:asciiData->buffer
                                      length:asciiData->length];
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenDidAppendAsciiDataToCurrentLine:data
                                                 foreground:foregroundColorCode
                                                 background:backgroundColorCode];
        }];
    }
}

- (void)terminalRingBell {
    DLog(@"begin");
    [self appendStringToTriggerLine:@"\a"];

    [self activateBell];

    if (self.config.loggingEnabled) {
        const screen_char_t foregroundColorCode = self.terminal.foregroundColorCode;
        const screen_char_t backgroundColorCode = self.terminal.backgroundColorCode;
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenDidAppendStringToCurrentLine:@"\a"
                                             isPlainText:NO
                                              foreground:foregroundColorCode
                                              background:backgroundColorCode];
        }];
    }
}

- (void)terminalBackspace {
    DLog(@"begin");
    const int cursorX = self.currentGrid.cursorX;
    const int cursorY = self.currentGrid.cursorY;

    [self backspace];

    if (self.commandStartCoord.x != -1 && (self.currentGrid.cursorX != cursorX ||
                                           self.currentGrid.cursorY != cursorY)) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (void)terminalAppendTabAtCursor:(BOOL)setBackgroundColors {
    DLog(@"begin");
    [self appendTabAtCursor:setBackgroundColors];
}

- (void)terminalCarriageReturn {
    DLog(@"begin");
    [self carriageReturn];
}

- (void)terminalLineFeed {
    DLog(@"begin");
    if (self.currentGrid.cursor.y == VT100GridRangeMax(self.currentGrid.scrollRegionRows) &&
        self.cursorOutsideLeftRightMargin) {
        DLog(@"Ignore linefeed/formfeed/index because cursor outside left-right margin.");
        return;
    }

    if (self.collectInputForPrinting) {
        [self.printBuffer appendString:@"\n"];
    } else {
        [self appendLineFeed];
    }
    [self clearTriggerLine];
}

- (void)terminalCursorLeft:(int)n {
    DLog(@"begin %@", @(n));
    [self cursorLeft:n];
}

- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    DLog(@"begin n=%@ toStart=%@", @(n), @(toStart));
    [self cursorDown:n andToStartOfLine:toStart];
}

- (void)terminalCursorRight:(int)n {
    DLog(@"begin %@", @(n));
    [self cursorRight:n];
}

- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    DLog(@"begin n=%@ toStart=%@", @(n), @(toStart));
    [self cursorUp:n andToStartOfLine:toStart];
}

- (void)terminalMoveCursorToX:(int)x y:(int)y {
    DLog(@"begin x=%@ y=%@", @(x), @(y));
    [self cursorToX:x Y:y];
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

// This is a complicated little mess.
// In issue 10206 we see that the cursor is drawn while hidden on every keystroke. The reason is that
// emacs hides the cursor, resets blink, and then shows the cursor. The blink reset used to pause and
// sync because it's reportable state (using VT100CSI_DECRQM_DEC).
// That was dumb because it didn't do anything 99% of the time (emacs never turns blink on, it just
// repeatedly turns it off). To avoid the unnecessary syncs and undesirable ill-timed draws, we don't
// want to pause & sync when mutating reportable state. Instead, pause and sync before sending a
// report becuse reports are pretty rare compared to decset and friends.
//
// All reports go through -terminalShouldSendReport. I know this because any that don't will break
// tmux integration.
//
// When you get a report, roll back the token (so it will be executed again later) and pause. Force
// a sync and unpause. The allowNextReport flag is temporarily set to allow the report to go through.
- (BOOL)terminalShouldSendReport {
    DLog(@"begin");
    if (self.config.isTmuxClient) {
        DLog(@"no - is tmux client");
        return NO;
    }
    if (self.allowNextReport) {
        DLog(@"Allowing report to go through");
        self.allowNextReport = NO;
        return YES;
    }
    DLog(@"Will send a report. Rollback and pause");
    [self.tokenExecutor rollBackCurrentToken];
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    __weak __typeof(self) weakSelf = self;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"Now that I have synced, unpause and allow the report to go through");
        [unpauser unpause];
        weakSelf.allowNextReport = YES;
    }];
    DLog(@"Decline report");
    return NO;
}

- (void)terminalReportVariableNamed:(NSString *)variable {
    DLog(@"begin %@", variable);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenReportVariableNamed:variable];
    }];
}

- (void)terminalSendReport:(NSData *)report {
    DLog(@"begin %@", report);
    if (!self.config.isTmuxClient && report) {
        DLog(@"report %@", [report stringWithEncoding:NSUTF8StringEncoding]);
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenWriteDataToTask:report];
        }];
    }
}

- (void)terminalShowTestPattern {
    DLog(@"begin");
    screen_char_t ch = [self.currentGrid defaultChar];
    ch.code = 'E';
    [self.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                to:VT100GridCoordMake(self.currentGrid.size.width - 1,
                                                      self.currentGrid.size.height - 1)
                            toChar:ch
                externalAttributes:nil];
    [self.currentGrid resetScrollRegions];
    self.currentGrid.cursor = VT100GridCoordMake(0, 0);
}

- (int)terminalRelativeCursorX {
    DLog(@"begin");
    return self.currentGrid.cursorX - self.currentGrid.leftMargin + 1;
}

- (int)terminalRelativeCursorY {
    DLog(@"begin");
    return self.currentGrid.cursorY - self.currentGrid.topMargin + 1;
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom {
    DLog(@"begin top=%@ bottom=%@", @(top), @(bottom));
    [self setScrollRegionTop:top bottom:bottom];
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    DLog(@"begin before=%@ after=%@", @(before), @(after));
    [self eraseInDisplayBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    DLog(@"begin before=%@ after=%@", @(before), @(after));
    [self eraseLineBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalSetTabStopAtCursor {
    DLog(@"begin");
    [self setTabStopAtCursor];
}

- (void)terminalReverseIndex {
    DLog(@"begin");
    [self reverseIndex];
}

- (void)terminalForwardIndex {
    DLog(@"begin");
    [self forwardIndex];
}

- (void)terminalBackIndex {
    DLog(@"begin");
    [self backIndex];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    DLog(@"begin preservePrompt=%@ modifyContent=%@", @(preservePrompt), @(modifyContent));
    [self resetPreservingPrompt:preservePrompt modifyContent:modifyContent];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    DLog(@"begin cursorType=%@", @(cursorType));
    if (self.currentGrid.cursor.x < self.currentGrid.size.width) {
        [self.currentGrid markCharDirty:YES at:self.currentGrid.cursor updateTimestamp:NO];
    }
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetCursorType:cursorType];
    }];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    DLog(@"begin blinking=%@", @(blinking));
    if (!self.config.terminalCanChangeBlink) {
        DLog(@"not allowed");
        return;
    }
    [self addDeferredSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetCursorBlinking:blinking];
    }];
}

- (iTermPromise<NSNumber *> *)terminalCursorIsBlinkingPromise {
    DLog(@"begin");
    // Pause to avoid processing any more tokens since this is used for a report.
    dispatch_queue_t queue = _queue;
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        DLog(@"will add side effect");
        [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
            DLog(@"begin side-effect");
            const BOOL value = [delegate screenCursorIsBlinking];
            DLog(@"value=%@", @(value));
            // VT100Terminal is blithely unaware of dispatch queues so make sure to give it a result
            // on the queue it expects to run on.
            dispatch_async(queue, ^{
                DLog(@"fulfill");
                [seal fulfill:@(value)];
                [unpauser unpause];
            });
        }];
    }];
}

- (void)terminalGetCursorInfoWithCompletion:(void (^)(ITermCursorType type, BOOL blinking))completion {
    DLog(@"begin");
    // Pause to avoid processing any more tokens since this is used for a report.
    dispatch_queue_t queue = _queue;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        ITermCursorType type = CURSOR_BOX;
        BOOL blinking = YES;
        [delegate screenGetCursorType:&type blinking:&blinking];
        DLog(@"type=%@ blinking=%@", @(type), @(blinking));
        dispatch_async(queue, ^{
            DLog(@"fulfill");
            completion(type, blinking);
            [unpauser unpause];
        });
    }];
}

- (void)terminalResetCursorTypeAndBlink {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenResetCursorTypeAndBlink];
    }];
}

- (BOOL)terminalLineDrawingFlagForCharset:(int)charset {
    DLog(@"begin charset=%@", @(charset));
    return [self.charsetUsesLineDrawingMode containsObject:@(charset)];
}

- (void)terminalRemoveTabStops {
    DLog(@"begin");
    [self.tabStops removeAllObjects];
}

- (void)terminalSetWidth:(int)width
          preserveScreen:(BOOL)preserveScreen
           updateRegions:(BOOL)updateRegions
            moveCursorTo:(VT100GridCoord)newCursorCoord
              completion:(void (^)(void))completion {
    DLog(@"begin width=%@ preserveScreen=%@ updateRegions=%@ newCursorCoord=%@",
         @(width), @(preserveScreen), @(updateRegions), VT100GridCoordDescription(newCursorCoord));
    __weak __typeof(self) weakSelf = self;
    const int height = self.currentGrid.size.height;
    dispatch_queue_t queue = _queue;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        DLog(@"side effect starts");
        const BOOL shouldResize = ([delegate screenShouldInitiateWindowResize] &&
                                   ![delegate screenWindowIsFullscreen]);
        if (shouldResize) {
            DLog(@"shouldResize is true");
            [delegate screenResizeToWidth:width
                                   height:height];
        }
        dispatch_async(queue, ^{
            DLog(@"begin async");
            __strong __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                DLog(@"strongSelf is nil");
                [unpauser unpause];
                if (completion) {
                    completion();
                }
                return;
            }
            [strongSelf finishAfterResizing:shouldResize
                             preserveScreen:preserveScreen
                              updateRegions:updateRegions
                               moveCursorTo:newCursorCoord
                                   delegate:delegate
                                 completion:^{
                DLog(@"completed");
                if (completion) {
                    completion();
                }
                [unpauser unpause];
            }];
        });
    }];
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    DLog(@"begin rows=%@ columns=%@", @(rows), @(columns));
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetSize:VT100GridSizeMake(rows, columns)];
        [unpauser unpause];
    }];
}

// This runs on the mutation queue.
- (void)finishAfterResizing:(BOOL)didResize
             preserveScreen:(BOOL)preserveScreen
              updateRegions:(BOOL)updateRegions
               moveCursorTo:(VT100GridCoord)newCursorCoord
                   delegate:(id<VT100ScreenDelegate>)delegate
                 completion:(void (^)(void))completion {
    DLog(@"begin didResize=%@ preserveScreen=%@ updateRegions=%@ newCursorCoord=%@",
         @(didResize), @(preserveScreen), @(updateRegions),
         VT100GridCoordDescription(newCursorCoord));;
    if (didResize && !preserveScreen) {
        DLog(@"erase screen");
        [self eraseInDisplayBeforeCursor:YES afterCursor:YES decProtect:NO];  // erase the screen
        self.currentGrid.cursorX = 0;
        self.currentGrid.cursorY = 0;
    }
    if (updateRegions) {
        DLog(@"reset regions");
        [self setUseColumnScrollRegion:NO];
        [self setLeftMargin:0 rightMargin:self.width - 1];
        [self setScrollRegionTop:0
                          bottom:self.height - 1];
    }
    if (newCursorCoord.x >= 0 && newCursorCoord.y >= 0) {
        DLog(@"move cursor");
        [self cursorToX:newCursorCoord.x];
        [self clearTriggerLine];
        [self cursorToY:newCursorCoord.y];
        [self clearTriggerLine];
    }
    if (completion) {
        DLog(@"Invoke completion block");
        completion();
    }
    DLog(@"done");
}

- (void)terminalSetUseColumnScrollRegion:(BOOL)use {
    DLog(@"begin use=%@", @(use));
    [self setUseColumnScrollRegion:use];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    DLog(@"begin scrollLeft=%@ scrollRight=%@", @(scrollLeft), @(scrollRight));
    [self setLeftMargin:scrollLeft rightMargin:scrollRight];
}

- (void)terminalSetCursorX:(int)x {
    DLog(@"begin %@", @(x));
    [self cursorToX:x];
    [self clearTriggerLine];
}

- (void)terminalSetCursorY:(int)y {
    DLog(@"begin %@", @(y));
    [self cursorToY:y];
    [self clearTriggerLine];
}

- (void)terminalRemoveTabStopAtCursor {
    DLog(@"begin");
    [self removeTabStopAtCursor];
}

- (void)terminalBackTab:(int)n {
    DLog(@"begin %@", @(n));
    [self backTab:n];
}

- (void)terminalAdvanceCursorPastLastColumn {
    DLog(@"begin");
    [self advanceCursorPastLastColumn];
}

- (void)terminalEraseCharactersAfterCursor:(int)j {
    DLog(@"begin %@", @(j));
    [self eraseCharactersAfterCursor:j];
}

- (void)terminalPrintBuffer {
    DLog(@"begin");
    if (self.printBuffer.length == 0) {
        DLog(@"empty buffer");
        return;
    }
    NSString *string = [self.printBuffer copy];
    DLog(@"string is: %@", string);
    self.printBuffer = nil;
    self.collectInputForPrinting = NO;
    // Pause so that attributes like colors don't change until printing (which is async) can begin.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenPrintStringIfAllowed:string completion:^{
            DLog(@"unpause");
            [unpauser unpause];
        }];
    }];
}

- (void)terminalPrintScreen {
    DLog(@"begin");
    // Print out the whole screen
    self.printBuffer = nil;
    self.collectInputForPrinting = NO;

    // Pause so we print the current state and not future updates.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenPrintVisibleAreaIfAllowed];
        [unpauser unpause];
    }];
}

- (void)terminalBeginRedirectingToPrintBuffer {
    DLog(@"begin");
    if (!self.config.printingAllowed) {
        DLog(@"disallowed");
        return;
    }
    DLog(@"allowed");
    // allocate a string for the stuff to be printed
    self.printBuffer = [[NSMutableString alloc] init];
    self.collectInputForPrinting = YES;
}

- (void)terminalSetWindowTitle:(NSString *)title {
    DLog(@"begin %@", title);

    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        if ([delegate screenAllowTitleSetting]) {
            DLog(@"calling screenSetWindowTitle:%@", title);
            [delegate screenSetWindowTitle:title];
        }
    }];

    // If you know to use RemoteHost then assume you also use CurrentDirectory. Innocent window title
    // changes shouldn't override CurrentDirectory.
    if ([self remoteHostOnLine:self.numberOfScrollbackLines + self.height]) {
        DLog(@"Already have a remote host so not updating working directory because of title change");
        return;
    }
    DLog(@"Don't have a remote host, so changing working directory");
    // TODO: There's a bug here where remote host can scroll off the end of history, causing the
    // working directory to come from PTYTask (which is what happens when nil is passed here).
    //
    // NOTE: Even though this is kind of a pull, it happens at a good
    // enough rate (not too common, not too rare when part of a prompt)
    // that I'm comfortable calling it a push. I want it to do things like
    // update the list of recently used directories.
    [self setWorkingDirectory:nil
                    onAbsLine:self.lineNumberOfCursor + self.cumulativeScrollbackOverflow
                       pushed:YES
                        token:[self.setWorkingDirectoryOrderEnforcer newToken]];
}

- (void)terminalSetIconTitle:(NSString *)title {
    DLog(@"begin %@", title);
    // Pause because this changes the profile
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenSetIconName:title];
        }
        [unpauser unpause];
    }];
}

- (void)terminalSetSubtitle:(NSString *)subtitle {
    DLog(@"begin %@", subtitle);
    // Paused because it can change the profile.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenSetSubtitle:subtitle];
        }
        [unpauser unpause];
    }];
}

- (void)terminalCopyStringToPasteboard:(NSString *)string {
    DLog(@"begin %@", string);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenCopyStringToPasteboard:string];
    }];
}

- (void)terminalReportPasteboard:(NSString *)pasteboard {
    DLog(@"begin");
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"running");
        [delegate screenReportPasteboard:pasteboard completion:^{
            DLog(@"unpausing");
            [unpauser unpause];
        }];
    }];
}

- (void)terminalBeginCopyToPasteboard {
    DLog(@"begin");
    if (self.config.clipboardAccessAllowed) {
        DLog(@"allowed");
        self.pasteboardString = [[NSMutableString alloc] init];
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenTerminalAttemptedPasteboardAccess];
    }];
}

- (void)terminalDidReceiveBase64PasteboardString:(NSString *)string {
    DLog(@"begin");
    if (self.config.clipboardAccessAllowed) {
        DLog(@"allowed");
        [self.pasteboardString appendString:string];
    }
}

- (void)terminalDidFinishReceivingPasteboard {
    DLog(@"begin");
    if (self.pasteboardString && self.config.clipboardAccessAllowed) {
        DLog(@"have string and allowed");
        NSData *data = [NSData dataWithBase64EncodedString:self.pasteboardString];
        if (data) {
            DLog(@"data=%@", data);
            NSString *string = [[NSString alloc] initWithData:data
                                                     encoding:self.terminal.encoding];
            if (!string) {
                DLog(@"nil string");
                string = [[NSString alloc] initWithData:data
                                               encoding:[NSString defaultCStringEncoding]];
            }

            if (string) {
                NSLog(@"string=%@", string);
                [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                    DLog(@"begin side-effect");
                    [delegate screenCopyStringToPasteboard:string];
                }];
            }
        }
    }
    self.pasteboardString = nil;
}

- (void)terminalInsertEmptyCharsAtCursor:(int)n {
    DLog(@"begin %@", @(n));
    [self.currentGrid insertChar:[self.currentGrid defaultChar]
              externalAttributes:nil
                              at:self.currentGrid.cursor
                           times:n];
}

- (void)terminalShiftLeft:(int)n {
    DLog(@"begin %@", @(n));
    if (n < 1) {
        return;
    }
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        DLog(@"outside margin");
        return;
    }
    [self.currentGrid moveContentLeft:n];
}

- (void)terminalShiftRight:(int)n {
    DLog(@"begin %@", @(n));
    if (n < 1) {
        return;
    }
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        DLog(@"outside margin");
        return;
    }
    [self.currentGrid moveContentRight:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    DLog(@"begin %@", @(n));
    VT100GridRect scrollRegionRect = [self.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == self.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
        DLog(@"In right margin");
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(self.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        DLog(@"in scroll region");
        // xterm appears to ignore INSLN if the cursor is outside the scroll region.
        // See insln-* files in tests/.
        int top = self.currentGrid.cursorY;
        int left = self.currentGrid.leftMargin;
        int width = self.currentGrid.rightMargin - self.currentGrid.leftMargin + 1;
        int height = self.currentGrid.bottomMargin - top + 1;
        [self.currentGrid scrollRect:VT100GridRectMake(left, top, width, height)
                              downBy:n
                           softBreak:NO];
        [self clearTriggerLine];
    }
}

- (void)terminalDeleteCharactersAtCursor:(int)n {
    DLog(@"begin %@", @(n));
    [self.currentGrid deleteChars:n startingAt:self.currentGrid.cursor];
    [self clearTriggerLine];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    DLog(@"begin %@", @(n));
    if (n <= 0) {
        return;
    }
    VT100GridRect scrollRegionRect = [self.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == self.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
        DLog(@"In right margin");
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(self.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        DLog(@"In scroll region");
        [self.currentGrid scrollRect:VT100GridRectMake(self.currentGrid.leftMargin,
                                                       self.currentGrid.cursorY,
                                                       self.currentGrid.rightMargin - self.currentGrid.leftMargin + 1,
                                                       self.currentGrid.bottomMargin - self.currentGrid.cursorY + 1)
                              downBy:-n
                           softBreak:NO];
        [self clearTriggerLine];
    }
}

- (void)terminalSetPixelWidth:(int)width height:(int)height {
    DLog(@"begin width=%@ height=%@", @(width), @(height));
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenSetPointSize:NSMakeSize(width, height)];
        [unpauser unpause];
    }];
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    DLog(@"begin %@", NSStringFromPoint(point));
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        if ([delegate screenShouldInitiateWindowResize] &&
            ![delegate screenWindowIsFullscreen]) {
            // TODO: Only allow this if there is a single session in the tab.
            DLog(@"doing it");
            [delegate screenMoveWindowTopLeftPointTo:point];
        }
    }];
}

- (void)terminalMiniaturize:(BOOL)mini {
    DLog(@"begin %@", @(mini));
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        // TODO: Only allow this if there is a single session in the tab.
        if ([delegate screenShouldInitiateWindowResize] &&
            ![delegate screenWindowIsFullscreen]) {
            [delegate screenMiniaturizeWindow:mini];
        }
    }];
}

- (void)terminalRaise:(BOOL)raise {
    DLog(@"begin %@", @(raise));
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        if ([delegate screenShouldInitiateWindowResize]) {
            [delegate screenRaise:raise];
        }
    }];
}

- (void)terminalScrollDown:(int)n {
    DLog(@"begin %@", @(n));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenRemoveSelection];
    }];
    [self.currentGrid scrollRect:[self.currentGrid scrollRegionRect]
                          downBy:MIN(self.currentGrid.size.height, n)
                       softBreak:NO];
    [self clearTriggerLine];
}

- (void)terminalScrollUp:(int)n {
    DLog(@"begin %@", @(n));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenRemoveSelection];
    }];

    for (int i = 0;
         i < MIN(self.currentGrid.size.height, n);
         i++) {
        [self incrementOverflowBy:[self.currentGrid scrollUpIntoLineBuffer:self.linebuffer
                                                       unlimitedScrollback:self.unlimitedScrollback
                                                   useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                 softBreak:NO]];
    }
    [self clearTriggerLine];
}

- (BOOL)terminalWindowIsMiniaturized {
    DLog(@"begin");
    return self.config.miniaturized;
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    DLog(@"begin");
    return self.config.windowFrame.origin;
}

- (int)terminalWindowWidthInPixels {
    DLog(@"begin");
    return round(self.config.windowFrame.size.width);
}

- (int)terminalWindowHeightInPixels {
    DLog(@"begin");
    return round(self.config.windowFrame.size.height);
}

- (int)terminalScreenHeightInCells {
    DLog(@"begin");
    return self.config.theoreticalGridSize.height;
}

- (int)terminalScreenWidthInCells {
    DLog(@"begin");
    return self.config.theoreticalGridSize.width;
}

- (NSString *)terminalIconTitle {
    DLog(@"begin");
    if (self.allowTitleReporting && [self terminalIsTrusted]) {
        return self.config.iconTitle ?: @"";
    } else {
        DLog(@"not allowed");
        return @"";
    }
}

- (NSString *)terminalWindowTitle {
    DLog(@"begin");
    if (self.allowTitleReporting && [self terminalIsTrusted]) {
        return self.config.windowTitle ?: @"";
    } else {
        DLog(@"not allowed");
        return @"";
    }
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    DLog(@"begin %@", @(isWindow));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        if ([delegate screenAllowTitleSetting]) {
            DLog(@"allowed");
            [delegate screenPushCurrentTitleForWindow:isWindow];
        }
    }];
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    DLog(@"begin %@", @(isWindow));
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        if ([delegate screenAllowTitleSetting]) {
            DLog(@"allowed");
            [delegate screenPopCurrentTitleForWindow:isWindow];
        }
    }];
}

- (void)terminalPostUserNotification:(NSString *)message {
    DLog(@"begin %@", message);
    if (!self.postUserNotifications) {
        DLog(@"Declining to allow terminal to post user notification %@", message);
        return;
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        DLog(@"Post %@", message);
        [delegate screenPostUserNotification:message];
    }];
}

- (void)terminalStartTmuxModeWithDCSIdentifier:(NSString *)dcsID {
    DLog(@"begin %@", dcsID);
    if (!_tmuxGroup) {
        DLog(@"create tmux group");
        _tmuxGroup = dispatch_group_create();
    }
    // Use the group to ensure all tmux tokens are handled completely before the first token that
    // follows them.
    dispatch_group_enter(_tmuxGroup);
    dispatch_group_t group = _tmuxGroup;

    // Force a sync.
    __weak __typeof(self) weakSelf = self;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"start side effect %@", dcsID);
        // Use an unmanaged side effect to avoid reentrancy. It's safe to assume the delegate will
        // do basically anything here so we want to keep it simple. We'll keep it paused so that
        // tmux tokens get get handled.
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            DLog(@"dealloced");
            dispatch_group_leave(group);
            return;
        }
        [strongSelf addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate, iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            DLog(@"start unmanaged side erffect %@", dcsID);
            [delegate screenStartTmuxModeWithDCSIdentifier:dcsID];
            dispatch_group_leave(group);
            [unpauser unpause];
        }];
    }];
}

// Tmux tokens are *not* side effects because it's basically impossible to avoid them having runloops.
// See the note about reentrant runloops in -reallyPerformBlockWithJoinedThreads:delegate:topmost:.
// This is OK because tmux token execution is not ordered meaningfully relative to the execution
// of any other token. As long as TMUX_LINE and TMUX_EXIT are handled in order w/r/t each other then
// all is well. The trick we play is that when we get a non-tmux token after a tmux token, we pause
// token execution until all previous tmux tokens are done being executed.
//
// Here is a sample token stream:
//
// VT100_ASCIISTRING("tmux -CC")
// DCS_TMUX_HOOK
// TMUX_LINE
// …many more
// TMUX_LINE("%output hello")
// TMUX_LINE("%output world")
// TMUX_EXIT("%exit")
// VT100_ASCIISTRING
//
// It would produce the following side-effects and other main-thread blocks:
// TokenExecutor.executeSideEffects(syncFirst:) {
//   [delegate screenDidAppendAsciiDataToCurrentLine:@"tmux -CC"]
//   [delegate screenStartTmuxModeWithDCSIdentifier:dcsID]
// }
// DispatchQueue.main.async { [delegate screenHandleTmuxInput:@"%output hello"] }
// DispatchQueue.main.async { [delegate screenHandleTmuxInput:@"%output world"] }
// DispatchQueue.main.async { [delegate screenHandleTmuxInput:@"%exit"] }
//
// Since starting tmux mode pauses token execution, there is no race. THe side-effect gets to run
// before the manually dispatched calls to screenHandleTmuxInput and all is well.
//
// Similarly, the first non-tmux token won't be executed until we know (via the dispatch group)
// that all previously dispatched screenHandleTmuxInput calls have completed.
- (void)terminalHandleTmuxInput:(VT100Token *)token {
    DLog(@"begin %@", token);
    if (!_tmuxGroup) {
        _tmuxGroup = dispatch_group_create();
    }
    dispatch_group_enter(_tmuxGroup);
    if (token->type == TMUX_EXIT) {
        // Pause so that the "Detached" message can be appended before any more tokens
        // are handled. That's added as a high-pri task and will therefore run before
        // the token executor handles another token post-unpause.
        iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"finish handling exit");
            id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
            [delegate screenHandleTmuxInput:token];
            [unpauser unpause];
            dispatch_group_leave(self->_tmuxGroup);
        });
        return;
    }

    // For performance, non-exit tmux lines are handled as side-effects. If tmux mode
    // is exited because of an unexpected token, some number of subsequent tokens may take
    // this path since the call to forceUnhookDCS happens concurrent to future token
    // execution. But weird things always happens when tmux mode unexpectedly exits and
    // it's worth the perf win.
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"on main queue for %@", token);
        id<VT100ScreenDelegate> delegate = self.sideEffectPerformer.sideEffectPerformingScreenDelegate;
        [delegate screenHandleTmuxInput:token];
        DLog(@"leave group");
        dispatch_group_leave(self->_tmuxGroup);
    });
}

- (void)terminalDidTransitionOutOfTmuxMode {
    DLog(@"begin");
    // Let's try this token again next time.
    [self.tokenExecutor rollBackCurrentToken];

    // Unpause when all pending tmux handlers are done. These were enqueued with dispatch_async
    // rather than as side-effects.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    dispatch_group_notify(_tmuxGroup, _queue, ^{
        DLog(@"All tmux handlers are done");
        [unpauser unpause];
    });
}

- (void)terminalSynchronizedUpdate:(BOOL)begin {
    DLog(@"begin %@", @(begin));
    if (begin) {
        [self.unconditionalTemporaryDoubleBuffer startExplicitly];
    } else {
        [self.unconditionalTemporaryDoubleBuffer resetExplicitly];
    }
}

- (VT100GridSize)terminalSizeInCells {
    DLog(@"begin");
    return self.currentGrid.size;
}

- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenMouseModeDidChange];
    }];
}

- (void)terminalShowAltBuffer {
    DLog(@"begin");
    [self showAltBuffer];
}

- (BOOL)terminalUseColumnScrollRegion {
    DLog(@"begin");
    return self.currentGrid.useScrollRegionCols;
}

- (BOOL)terminalIsShowingAltBuffer {
    DLog(@"begin");
    return self.currentGrid == self.altGrid;
}

- (void)terminalShowPrimaryBuffer {
    DLog(@"begin");
    [self showPrimaryBuffer];
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    DLog(@"begin");
    [self setRemoteHostFromString:remoteHost];
}

- (void)terminalSetWorkingDirectoryURL:(NSString *)URLString {
    DLog(@"begin");
    [self setWorkingDirectoryFromURLString:URLString];
}

- (void)terminalWillStartLinkWithCode:(unsigned int)code {
    DLog(@"begin");
    [self addURLMarkAtLineAfterCursorWithCode:code];
}

- (void)terminalWillEndLinkWithCode:(unsigned int)code {
    DLog(@"begin");
    [self addURLMarkAtLineAfterCursorWithCode:code];
}

- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)dir {
    DLog(@"begin");
    [self currentDirectoryDidChangeTo:dir completion:^{}];
}

- (void)terminalClearScreen {
    DLog(@"begin");
    [self eraseScreenAndRemoveSelection];
}

- (void)terminalSaveScrollPositionWithArgument:(NSString *)argument {
    DLog(@"begin %@", argument);
    // The difference between an argument of saveScrollPosition and saveCursorLine (the default) is
    // subtle. When saving the scroll position, the entire region of visible lines is recorded and
    // will be restored exactly. When saving only the line the cursor is on, when restored, that
    // line will be made visible but no other aspect of the scroll position must be restored. This
    // is often preferable because when setting a mark as part of the prompt, we wouldn't want the
    // prompt to be the last line on the screen (such lines are scrolled to the center of
    // the screen).
    if ([argument isEqualToString:@"saveScrollPosition"]) {
        // Unmanaged because it will call refresh and then perform a joined block.
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                             iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            [delegate screenSaveScrollPosition];
            [unpauser unpause];
        }];
    } else {  // implicitly "saveCursorLine"
        DLog(@"saveCursorLine");
        [self saveCursorLine];
    }
}

- (void)terminalStealFocus {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenStealFocus];
    }];
}

- (void)terminalSetProxyIcon:(NSString *)value {
    DLog(@"begin %@", value);
    NSString *path = [value length] ? value : nil;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetPreferredProxyIcon:path];
    }];
}

- (void)terminalClearScrollbackBuffer {
    DLog(@"begin");
    if (!self.config.clearScrollbackAllowed) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenAskAboutClearingScrollback];
        }];
        return;
    }
    [self clearScrollbackBuffer];
}

- (void)terminalClearBuffer {
    DLog(@"begin");
    [self clearBufferSavingPrompt:YES];
}

- (void)terminalProfileShouldChangeTo:(NSString *)value {
    DLog(@"begin %@", value);
    [self forceCheckTriggers];
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenSetProfileToProfileNamed:value];
        [unpauser unpause];
    }];
}

- (void)terminalAddNote:(NSString *)value show:(BOOL)show {
    DLog(@"begin");
    NSArray *parts = [value componentsSeparatedByString:@"|"];
    VT100GridCoord location = self.currentGrid.cursor;
    NSString *message = nil;
    int length = self.currentGrid.size.width - self.currentGrid.cursorX - 1;
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
        PTYAnnotation *note = [[PTYAnnotation alloc] init];
        note.stringValue = message;
        [self addAnnotation:note
                    inRange:VT100GridCoordRangeMake(location.x,
                                                    location.y + self.numberOfScrollbackLines,
                                                    end.x,
                                                    end.y + self.numberOfScrollbackLines)
                      focus:NO
                    visible:show];
    }
}

- (void)terminalSetPasteboard:(NSString *)value {
    DLog(@"begin %@", value);
    // Don't pause because there will never be a code to get the pasteboard value.
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetPasteboard:value];
    }];
}

- (void)terminalAppendDataToPasteboard:(NSData *)data {
    DLog(@"begin %@", data);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenAppendDataToPasteboard:data];
    }];
}

- (void)terminalCopyBufferToPasteboard {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenCopyBufferToPasteboard];
    }];
}

- (BOOL)terminalIsTrusted {
    DLog(@"begin");
    return [super terminalIsTrusted];
}

- (BOOL)terminalCanUseDECRQCRA {
    DLog(@"begin");
    if (![iTermAdvancedSettingsModel disableDECRQCRA]) {
        DLog(@"not disabled");
        return YES;
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenDidTryToUseDECRQCRA];
    }];
    DLog(@"fail by default");
    return NO;
}

- (void)terminalRequestAttention:(VT100AttentionRequestType)request {
    DLog(@"begin %@", @(request));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenRequestAttention:request];
    }];
}

- (void)terminalDisinterSession {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenDisinterSession];
    }];
}

- (void)terminalSetBackgroundImageFile:(NSString *)filename {
    DLog(@"begin %@", filename);
    // Paused because it may modify the profile.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenSetBackgroundImageFile:filename];
        [unpauser unpause];
    }];
}

- (void)terminalSetBadgeFormat:(NSString *)badge {
    DLog(@"begin %@", badge);
    // Pause because this changes the profile.
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenSetBadgeFormat:badge];
        [unpauser unpause];
    }];
}

- (void)terminalSetUserVar:(NSString *)kvp {
    DLog(@"begin %@", kvp);
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetUserVar:kvp];
    }];
}

- (void)terminalResetColor:(VT100TerminalColorIndex)n {
    DLog(@"begin %@", @(n));
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }
    if (key >= kColorMap8bitBase && key < kColorMap8bitBase + 256) {
        if (key >= kColorMap8bitBase + 16 && key < kColorMap8bitBase + 256) {
            // ANSI colors above 16 don't come from the profile. They have hard-coded defaults.
            NSColor *theColor = [NSColor colorForAnsi256ColorIndex:key - kColorMap8bitBase];
            [self mutateColorMap:^(iTermColorMap * _Nonnull colorMap) {
                [colorMap setColor:theColor forKey:key];
            }];
            return;
        }
        // If you get here then it's one of the 16 ANSI colors and it is allowed to be changed.
    } else {
        // Non-ANSI color. Only some of them may be reset.
        DLog(@"Reset dynamic color with colormap key %d", key);
        NSArray<NSNumber *> *allowed = @[
            @(kColorMapForeground),
            @(kColorMapBackground),
            @(kColorMapCursor),
            @(kColorMapSelection),
            @(kColorMapSelectedText),
        ];
        if (![allowed containsObject:@(key)]) {
            DLog(@"Unexpected key");
            return;
        }
    }
    iTermColorMap *colorMap = self.colorMap;
    NSString *profileKey = [self.colorMap profileKeyForColorMapKey:key];
    const BOOL darkMode = colorMap.darkMode;
    __weak __typeof(self) weakSelf = self;
    dispatch_queue_t queue = _queue;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate, iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        DLog(@"side effect running");
        // If we're lucky we get back a dictionary and it's fast. Otherwise the delegate will
        // need to change the profile and it's slow. In that case, it has to be unmanaged.
        NSDictionary<NSNumber *, id> *mutations = [delegate screenResetColorWithColorMapKey:key
                                                                                 profileKey:profileKey
                                                                                       dark:darkMode];
        if (mutations.count) {
            DLog(@"have mutations");
            // I think this is unreachable. You're only called with inputs in [-5,255].
            // The negatives and 0-15 map to profile keys.
            // 16-255 cause an early return.
            dispatch_async(queue, ^{
                DLog(@"finishing");
                [weakSelf setColorsFromDictionary:mutations];
                [unpauser unpause];
            });
        } else {
            [unpauser unpause];
        }
    }];
}

// These calls to `screenSetColor:` will modify the profile and will themselves join the mutation
// thread so don't bother trying to make them regular side-effects.
- (void)terminalSetForegroundColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapForeground];
}

- (void)terminalSetBackgroundColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapBackground];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapBold];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapSelection];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapSelectedText];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapCursor];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self makeDelegateSetColor:color forKey:kColorMapCursorText];
}

- (void)makeDelegateSetColor:(NSColor *)color forKey:(int)key {
    DLog(@"begin %@ key=%@", color, @(key));
    VT100ScreenState *state = self.mainThreadCopy;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate, iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        NSString *profileKey = [state.colorMap profileKeyForColorMapKey:key];
        [delegate screenSetColor:color forKey:key profileKey:profileKey];
        [unpauser unpause];
    }];
}

- (void)terminalSetColorTableEntryAtIndex:(VT100TerminalColorIndex)n color:(NSColor *)color {
    DLog(@"begin %@ n=%@", color, @(n));
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }

    VT100ScreenState *state = self.mainThreadCopy;
    __weak __typeof(self) weakSelf = self;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        NSString *profileKey = [state.colorMap profileKeyForColorMapKey:key];
        const BOOL assign = [delegate screenSetColor:color forKey:key profileKey:profileKey];
        if (assign) {
            [weakSelf setColor:color forKey:key];
        }
        [unpauser unpause];
    }];
}

- (void)terminalSetCurrentTabColor:(NSColor *)color {
    DLog(@"begin %@", color);
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetCurrentTabColor:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorRedComponentTo:(CGFloat)color {
    DLog(@"begin %f", color);
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetTabColorRedComponentTo:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color {
    DLog(@"begin %f", color);
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetTabColorGreenComponentTo:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color {
    DLog(@"begin %f", color);
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetTabColorBlueComponentTo:color];
        [unpauser unpause];
    }];
}

- (BOOL)terminalFocusReportingAllowed {
    DLog(@"begin");
    return [iTermAdvancedSettingsModel focusReportingEnabled];
}

- (BOOL)terminalCursorVisible {
    DLog(@"begin");
    return self.cursorVisible;
}

- (NSColor *)terminalColorForIndex:(VT100TerminalColorIndex)index {
    DLog(@"begin %@", @(index));
    const int key = [self colorMapKeyForTerminalColorIndex:index];
    if (key < 0) {
        return nil;
    }
    return [self.colorMap colorForKey:key];
}


- (int)terminalCursorX {
    DLog(@"begin");
    return MIN(self.cursorX, self.width);
}

- (int)terminalCursorY {
    DLog(@"begin");
    return self.cursorY;
}

- (BOOL)terminalWillAutoWrap {
    DLog(@"begin");
    return self.cursorX > self.width;
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    DLog(@"begin %@", @(visible));
    [self setCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    DLog(@"begin %@", @(highlight));
    self.trackCursorLineMovement = highlight;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetHighlightCursorLine:highlight];
    }];
}

- (void)terminalClearCapturedOutput {
    DLog(@"begin");
    id<VT100ScreenMarkReading> commandMark = self.lastCommandMark;
    if (commandMark.capturedOutput.count) {
        [self incrementClearCountForCommandMark:commandMark];
    }
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenClearCapturedOutput];
    }];
}

- (void)terminalPromptDidStart {
    DLog(@"begin");
    [self promptDidStartAt:VT100GridAbsCoordMake(self.currentGrid.cursor.x,
                                                 self.currentGrid.cursor.y + self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow)];
}

- (NSArray<NSNumber *> *)terminalTabStops {
    DLog(@"begin");
    return [[self.tabStops.allObjects sortedArrayUsingSelector:@selector(compare:)] mapWithBlock:^NSNumber *(NSNumber *ts) {
        return @(ts.intValue + 1);
    }];
}

- (void)terminalSetTabStops:(NSArray<NSNumber *> *)tabStops {
    DLog(@"begin %@", tabStops);
    [self.tabStops removeAllObjects];
    [tabStops enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self.tabStops addObject:@(obj.intValue - 1)];
    }];
}

- (void)terminalCommandDidStart {
    DLog(@"begin");
    [self commandDidStart];
}

- (void)terminalCommandDidEnd {
    DLog(@"begin");
    [self commandDidEnd];
}

- (void)terminalAbortCommand {
    DLog(@"FinalTerm: terminalAbortCommand");
    [self commandWasAborted];
}

- (void)terminalSemanticTextDidStartOfType:(VT100TerminalSemanticTextType)type {
    DLog(@"begin");
    // TODO
}

- (void)terminalSemanticTextDidEndOfType:(VT100TerminalSemanticTextType)type {
    DLog(@"begin");
    // TODO
}

- (void)terminalProgressAt:(double)fraction label:(NSString *)label {
    DLog(@"begin");
     // TODO
}

- (void)terminalProgressDidFinish {
    DLog(@"begin");
    // TODO
}

- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode {
    DLog(@"begin");
    [self setReturnCodeOfLastCommand:returnCode];
}

- (void)terminalFinalTermCommand:(NSArray *)argv {
    DLog(@"begin %@", argv);
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
    DLog(@"begin %@", version);
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
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        if (shell) {
            DLog(@"shell=%@", shell);
            [delegate screenDidDetectShell:shell];
        }
        if (!shell || versionNumber < latestKnownVersion) {
            DLog(@"suggest upgrade");
            [delegate screenSuggestShellIntegrationUpgrade];
        }
    }];
}

- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue {
    DLog(@"begin %@", @(newValue));
    self.wraparoundMode = newValue;
}

- (void)terminalTypeDidChange {
    DLog(@"begin");
    self.ansi = [self.terminal isAnsi];
}

- (void)terminalInsertModeDidChangeTo:(BOOL)newValue {
    DLog(@"begin %@", @(newValue));
    self.insert = newValue;
}

- (int)terminalChecksumInRectangle:(VT100GridRect)rect {
    DLog(@"begin %@", VT100GridRectDescription(rect));
    int result = 0;
    for (int y = rect.origin.y; y < rect.origin.y + rect.size.height; y++) {
        const screen_char_t *theLine = [self.currentGrid screenCharsAtLineNumber:y];
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

- (NSString *)terminalProfileName {
    DLog(@"begin");
    return self.config.profileName;
}

- (VT100GridRect)terminalScrollRegion {
    DLog(@"begin");
    return self.currentGrid.scrollRegionRect;
}

- (NSArray<NSString *> *)terminalSGRCodesInRectangle:(VT100GridRect)screenRect {
    DLog(@"begin %@", VT100GridRectDescription(screenRect));
    __block NSMutableOrderedSet<NSString *> *codes = nil;
    VT100GridRect rect = screenRect;
    rect.origin.y += [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
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
            NSOrderedSet<NSString *> *charCodes = [VT100Terminal sgrCodesForCharacter:c
                                                                   externalAttributes:eaIndex[x]];
            if (!codes) {
                codes = [charCodes mutableCopy];
            } else {
                [codes intersectSet:charCodes.set];
                if (!codes.count) {
                    *stop = YES;
                    return;
                }
            }
        }
    }];
    return codes.array ?: @[];
}

- (void)terminalWillReceiveFileNamed:(NSString *)name
                              ofSize:(NSInteger)size
                          completion:(void (^)(BOOL ok))completion {
    DLog(@"begin name=%@ size=%@", name, @(size));
    dispatch_queue_t queue = _queue;
    __weak __typeof(self) weakSelf = self;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            DLog(@"dealloced");
            [unpauser unpause];
            return;
        }
        BOOL promptIfBig = YES;
        // This has a runloop
        const BOOL ok = [delegate screenConfirmDownloadAllowed:name
                                                          size:size
                                                 displayInline:NO
                                                   promptIfBig:&promptIfBig];
        if (ok) {
            DLog(@"ok");
            [delegate screenWillReceiveFileNamed:name ofSize:size preconfirmed:!promptIfBig];
        }
        dispatch_async(queue, ^{
            DLog(@"finish");
            completion(ok);
            [unpauser unpause];
        });
    }];
};

- (void)terminalWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(NSInteger)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset
                                      type:(NSString *)type
                                completion:(void (^)(BOOL ok))completion {
    DLog(@"begin name=%@ size=%@ width=%@ widthUnits=%@ height=%@ heightUnits=%@ preserveAR=%@ inset=%f,%f,%f,%f type=%@",
         name, @(size), @(width), @(widthUnits), @(height), @(heightUnits), @(preserveAspectRatio), inset.top, inset.bottom, inset.left, inset.right, type);
    __weak __typeof(self) weakSelf = self;
    dispatch_queue_t queue = _queue;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(NO);
            [unpauser unpause];
            DLog(@"dealloced");
            return;
        }
        [weakSelf reallyWillReceiveInlineFileNamed:name
                                            ofSize:size
                                             width:width
                                             units:widthUnits
                                            height:height
                                             units:heightUnits
                               preserveAspectRatio:preserveAspectRatio
                                             inset:inset
                                              type:type
                                          delegate:delegate
                                             queue:queue
                                        completion:^(BOOL ok) {
            // Runs on queue
            completion(ok);
            [unpauser unpause];
        }];
    }];
}

// Main queue, unmanaged
- (void)reallyWillReceiveInlineFileNamed:(NSString *)name
                                  ofSize:(NSInteger)size
                                   width:(int)width
                                   units:(VT100TerminalUnits)widthUnits
                                  height:(int)height
                                   units:(VT100TerminalUnits)heightUnits
                     preserveAspectRatio:(BOOL)preserveAspectRatio
                                   inset:(NSEdgeInsets)inset
                                    type:(NSString *)type
                                delegate:(id<VT100ScreenDelegate>)delegate
                                   queue:(dispatch_queue_t)queue
                              completion:(void (^)(BOOL ok))completion {
    DLog(@"begin name=%@ size=%@ width=%@ widthUnits=%@ height=%@ heightUnits=%@ preserveAR=%@ inset=%f,%f,%f,%f type=%@",
         name, @(size), @(width), @(widthUnits), @(height), @(heightUnits), @(preserveAspectRatio), inset.top, inset.bottom, inset.left, inset.right, type);
    BOOL promptIfBig = YES;
    const BOOL allowed = [delegate screenConfirmDownloadAllowed:name
                                                           size:size
                                                  displayInline:YES
                                                    promptIfBig:&promptIfBig];
    DLog(@"allowed=%@", @(allowed));
    __weak __typeof(self) weakSelf = self;
    dispatch_async(queue, ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !allowed) {
            completion(NO);
            DLog(@"dealloced");
            return;
        }
        DLog(@"make helper");
        const CGFloat scale = strongSelf.config.backingScaleFactor;
        strongSelf.inlineImageHelper = [[VT100InlineImageHelper alloc] initWithName:name
                                                                              width:width
                                                                         widthUnits:widthUnits
                                                                             height:height
                                                                        heightUnits:heightUnits
                                                                        scaleFactor:scale
                                                                preserveAspectRatio:preserveAspectRatio
                                                                              inset:inset
                                                                               type:type
                                                                       preconfirmed:!promptIfBig];
        strongSelf.inlineImageHelper.delegate = self;
        completion(YES);
    });
}

- (void)terminalFileReceiptEndedUnexpectedly {
    DLog(@"begin");
    [self fileReceiptEndedUnexpectedly];
}

- (void)terminalDidReceiveBase64FileData:(NSString *)data {
    DLog(@"begin");
    if (self.inlineImageHelper) {
        DLog(@"append");
        [self.inlineImageHelper appendBase64EncodedData:data];
    } else {
        dispatch_queue_t queue = _queue;
        __weak __typeof(self) weakSelf = self;
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                             iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            DLog(@"call out to delegate");
            [delegate screenDidReceiveBase64FileData:data
                                             confirm:^void(NSString *name,
                                                           NSInteger lengthBefore,
                                                           NSInteger lengthAfter) {
                __strong __typeof(self) strongSelf = weakSelf;
                if (!strongSelf) {
                    [unpauser unpause];
                    DLog(@"dealloced");
                    return;
                }
                DLog(@"confirm");
                [strongSelf confirmBigDownloadWithBeforeSize:lengthBefore
                                                   afterSize:lengthAfter
                                                        name:name
                                                    delegate:delegate
                                                       queue:queue
                                                    unpauser:unpauser];
            }];
        }];
    }
}

- (void)terminalAppendSixelData:(NSData *)data {
    DLog(@"begin");
    VT100InlineImageHelper *helper = [[VT100InlineImageHelper alloc] initWithSixelData:data
                                                                           scaleFactor:self.config.backingScaleFactor];
    helper.delegate = self;
    [helper writeToGrid:self.currentGrid];
    [self appendCarriageReturnLineFeed];
}

- (NSSize)terminalCellSizeInPoints:(double *)scaleOut {
    DLog(@"begin");
    *scaleOut = self.config.backingScaleFactor;
    return self.config.cellSize;
}

- (void)terminalSetUnicodeVersion:(NSInteger)unicodeVersion {
    DLog(@"begin %@", @(unicodeVersion));
    // This will change the profile. Use unmanaged+paused to avoid reentrancy.
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        [delegate screenSetUnicodeVersion:unicodeVersion];
        [unpauser unpause];
    }];
}

- (NSInteger)terminalUnicodeVersion {
    DLog(@"begin");
    return self.config.unicodeVersion;
}

- (void)terminalSetLabel:(NSString *)label forKey:(NSString *)keyName {
    DLog(@"begin label=%@ keyName=%@", label, keyName);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSetLabel:label forKey:keyName];
    }];
}

- (void)terminalPushKeyLabels:(NSString *)value {
    DLog(@"begin %@", value);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenPushKeyLabels:value];
    }];
}

- (void)terminalPopKeyLabels:(NSString *)value {
    DLog(@"begin %@", value);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenPopKeyLabels:value];
    }];
}

// fg=ff0080,bg=srgb:808080
- (void)terminalSetColorNamed:(NSString *)name to:(NSString *)colorString {
    DLog(@"begin name=%@ colorString=%@", name, colorString);
    if ([name isEqualToString:@"preset"]) {
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                             iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            DLog(@"handle preset");
            [delegate screenSelectColorPresetNamed:colorString];
            [unpauser unpause];
        }];
        return;
    }
    if ([colorString isEqualToString:@"default"] && [name isEqualToString:@"tab"]) {
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                             iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            DLog(@"handle default");
            [delegate screenSetCurrentTabColor:nil];
            [unpauser unpause];
        }];
        return;
    }

    NSInteger colon = [colorString rangeOfString:@":"].location;
    NSString *cs;
    NSString *hex;
    if (colon != NSNotFound && colon + 1 != colorString.length && colon != 0) {
        DLog(@"found color space");
        cs = [colorString substringToIndex:colon];
        hex = [colorString substringFromIndex:colon + 1];
    } else {
        DLog(@"use default color space");
        if ([iTermAdvancedSettingsModel p3]) {
            cs = @"p3";
        } else {
            cs = @"srgb";
        }
        hex = colorString;
    }
    NSDictionary *colorSpaces = @{ @"srgb": [NSColorSpace sRGBColorSpace],
                                   @"rgb": [NSColorSpace genericRGBColorSpace],
                                   @"p3": [NSColorSpace displayP3ColorSpace] };
    NSColorSpace *colorSpace = colorSpaces[cs] ?: [NSColorSpace it_defaultColorSpace];
    if (!colorSpace) {
        DLog(@"failed to make colorspace from %@", cs);
        return;
    }

    DLog(@"hex=%@", hex);
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
        DLog(@"fail");
        return;
    }
    CGFloat components[4] = { r / 255.0, g / 255.0, b / 255.0, 1.0 };
    NSColor *color = [NSColor colorWithColorSpace:colorSpace
                                       components:components
                                            count:sizeof(components) / sizeof(*components)];
    DLog(@"color=%@", color);
    if (!color) {
        return;
    }

    if ([name isEqualToString:@"tab"]) {
        [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                             iTermTokenExecutorUnpauser * _Nonnull unpauser) {
            DLog(@"tab");
            [delegate screenSetCurrentTabColor:color];
            [unpauser unpause];
        }];
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
    DLog(@"name=%@", name);
    if (!keyNumber) {
        DLog(@"fail");
        return;
    }
    NSInteger key = [keyNumber integerValue];
    DLog(@"key=%@", @(key));
    __weak __typeof(self) weakSelf = self;
    [self addUnmanagedPausedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate,
                                         iTermTokenExecutorUnpauser * _Nonnull unpauser) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            DLog(@"dealloced");
            return;
        }
        DLog(@"set %@ aka %@=%@", @(key), [strongSelf.mainThreadCopy.colorMap profileKeyForColorMapKey:key], color);
        [delegate screenSetColor:color
                          forKey:key
                      profileKey:[strongSelf.mainThreadCopy.colorMap profileKeyForColorMapKey:key]];
        [unpauser unpause];
    }];
}

- (void)terminalCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                                           payload:(NSString *)payload {
    DLog(@"begin params=%@ payload=%@", parameters, payload);
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenDidReceiveCustomEscapeSequenceWithParameters:parameters
                                                             payload:payload];
    }];
}

- (void)terminalRepeatPreviousCharacter:(int)times {
    DLog(@"begin %@", @(times));
    if (![iTermAdvancedSettingsModel supportREPCode]) {
        DLog(@"Unsupported");
        return;
    }
    if (self.lastCharacter.code) {
        DLog(@"Have last character");
        int length = 1;
        screen_char_t chars[2];
        chars[0] = self.lastCharacter;
        if (self.lastCharacterIsDoubleWidth) {
            length++;
            chars[1] = self.lastCharacter;
            ScreenCharSetDWC_RIGHT(&chars[1]);
            chars[1].complexChar = NO;
        }

        const screen_char_t foregroundColorCode = self.terminal.foregroundColorCode;
        const screen_char_t backgroundColorCode = self.terminal.backgroundColorCode;
        NSString *string = ScreenCharToStr(chars);
        for (int i = 0; i < times; i++) {
            [self appendScreenCharArrayAtCursor:chars
                                         length:length
                         externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:self.lastExternalAttribute]];
            [self appendStringToTriggerLine:string];
            if (self.config.loggingEnabled) {
                [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                    DLog(@"begin side-effect");
                    [delegate screenDidAppendStringToCurrentLine:string
                                                     isPlainText:(self.lastCharacter.complexChar ||
                                                                  self.lastCharacter.code >= ' ')
                                                      foreground:foregroundColorCode
                                                      background:backgroundColorCode];
                }];
            }
        }
    }
}

- (void)terminalReportFocusWillChangeTo:(BOOL)reportFocus {
    DLog(@"begin %@", @(reportFocus));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenReportFocusWillChangeTo:reportFocus];
    }];
}

- (void)terminalPasteBracketingWillChangeTo:(BOOL)bracket {
    DLog(@"begin %@", @(bracket));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenReportPasteBracketingWillChangeTo:bracket];
    }];
}

- (void)terminalReportKeyUpDidChange:(BOOL)reportKeyUp {
    DLog(@"begin %@", @(reportKeyUp));
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenReportKeyUpDidChange:reportKeyUp];
    }];
}

- (BOOL)terminalIsInAlternateScreenMode {
    DLog(@"begin");
    return self.currentGrid == self.altGrid;
}

- (NSString *)terminalTopBottomRegionString {
    DLog(@"begin");
    if (!self.currentGrid.haveRowScrollRegion) {
        DLog(@"No region");
        return @"";
    }
    return [NSString stringWithFormat:@"%d;%d", self.currentGrid.topMargin + 1, self.currentGrid.bottomMargin + 1];
}

- (NSString *)terminalLeftRightRegionString {
    DLog(@"begin");
    if (!self.currentGrid.haveColumnScrollRegion) {
        DLog(@"no region");
        return @"";
    }
    return [NSString stringWithFormat:@"%d;%d", self.currentGrid.leftMargin + 1, self.currentGrid.rightMargin + 1];
}

- (iTermPromise<NSString *> *)terminalStringForKeypressWithCode:(unsigned short)keyCode
                                                          flags:(NSEventModifierFlags)flags
                                                     characters:(NSString *)characters
                                    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    DLog(@"begin keyCode=%@ flags=%@ chars=%@ cim=%@", @(keyCode), @(flags), characters, charactersIgnoringModifiers);
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
            DLog(@"begin side-effect");
            NSString *value = [delegate screenStringForKeypressWithCode:keyCode
                                                                  flags:flags
                                                             characters:characters
                                            charactersIgnoringModifiers:charactersIgnoringModifiers];
            DLog(@"value=%@", value);
            if (value) {
                [seal fulfill:value];
            } else {
                [seal rejectWithDefaultError];
            }
            [unpauser unpause];
        }];
    }];
}

- (dispatch_queue_t)terminalQueue {
    DLog(@"begin");
    return _queue;
}

- (id)terminalPause {
    DLog(@"begin");
    return [self.tokenExecutor pause];
}

- (void)terminalApplicationKeypadModeDidChange:(BOOL)mode {
    DLog(@"begin %@", @(mode));
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        DLog(@"begin side-effect");
        [delegate screenApplicationKeypadModeDidChange:mode];
    }];
}

- (VT100SavedColorsSlot *)terminalSavedColorsSlot {
    DLog(@"begin");
    iTermColorMap *colorMap = self.colorMap;
    return [[VT100SavedColorsSlot alloc] initWithTextColor:[colorMap colorForKey:kColorMapForeground]
                                            backgroundColor:[colorMap colorForKey:kColorMapBackground]
                                         selectionTextColor:[colorMap colorForKey:kColorMapSelectedText]
                                   selectionBackgroundColor:[colorMap colorForKey:kColorMapSelection]
                                       indexedColorProvider:^NSColor *(NSInteger index) {
        return [colorMap colorForKey:kColorMap8bitBase + index] ?: [NSColor clearColor];
    }];
}

- (void)terminalRestoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    DLog(@"begin %@", slot);
    [self restoreColorsFromSlot:slot];
}

- (int)terminalMaximumTheoreticalImageDimension {
    DLog(@"begin");
    return self.config.maximumTheoreticalImageDimension;
}

- (void)terminalInsertColumns:(int)n {
    DLog(@"begin %@", @(n));
    [self insertColumns:n];
}

- (void)terminalDeleteColumns:(int)n {
    DLog(@"begin %@", @(n));
    [self deleteColumns:n];
}

- (void)terminalSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    DLog(@"begin attr=%@ rect=%@", @(sgrAttribute), VT100GridRectDescription(rect));
    [self setAttribute:sgrAttribute inRect:rect];
}

- (void)terminalToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    DLog(@"begin attr=%@ rect=%@", @(sgrAttribute), VT100GridRectDescription(rect));
    [self toggleAttribute:sgrAttribute inRect:rect];
}

- (void)terminalCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    DLog(@"begin %@ -> %@", VT100GridRectDescription(source), VT100GridCoordDescription(dest));
    [self copyFrom:source to:dest];
}

- (void)terminalFillRectangle:(VT100GridRect)rect withCharacter:(unichar)inputChar {
    DLog(@"begin rect=%@ char=%@", VT100GridRectDescription(rect), @(inputChar));
    screen_char_t c = {
        .code = inputChar
    };
    if ([self.charsetUsesLineDrawingMode containsObject:@(self.terminal.charset)]) {
        ConvertCharsToGraphicsCharset(&c, 1);
    }
    CopyForegroundColor(&c, [self.terminal foregroundColorCode]);
    CopyBackgroundColor(&c, [self.terminal backgroundColorCode]);

    // Only preserve SGR attributes. image is OSC, not SGR.
    c.image = 0;

    [self fillRectangle:rect
                   with:c
     externalAttributes:[self.terminal externalAttributes]];
}

- (void)terminalEraseRectangle:(VT100GridRect)rect {
    DLog(@"begin %@", VT100GridRectDescription(rect));
    screen_char_t c = [self.currentGrid defaultChar];
    c.code = ' ';
    [self fillRectangle:rect with:c externalAttributes:nil];
}

- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode {
    DLog(@"begin charset=%@ lineDrawingMode=%@", @(charset), @(lineDrawingMode));
    [self setCharacterSet:charset usesLineDrawingMode:lineDrawingMode];
}

- (void)terminalNeedsRedraw {
    DLog(@"begin");
    [self.currentGrid markAllCharsDirty:YES updateTimestamps:NO];
}

- (void)terminalDidChangeSendModifiers {
    DLog(@"begin");
    // CSI u is too different from xterm's modifyOtherKeys to allow the terminal to change it with
    // xterm's control sequences. Lots of strange problems appear with vim. For example, mailing
    // list thread with subject "Control Keys Failing After System Bell".
    // TODO: terminal_.sendModifiers[i] holds the settings. See xterm's modifyOtherKeys and friends.
    // Use a joined side effect so that this object gets an updated config, which is used to report
    // keystrokes via DCS_REQUEST_TERMCAP_TERMINFO.
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenSendModifiersDidChange];
    }];
}

- (void)terminalKeyReportingFlagsDidChange {
    DLog(@"begin");
    // It's safe to do this because it won't be reeentrant and it's necessary because it syncs
    // afterwards (this change is reporable). It's joined so we get the updated config and can
    // respond to DCS_REQUEST_TERMCAP_TERMINFO properly.
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenKeyReportingFlagsDidChange];
    }];
}

- (void)terminalDidFinishReceivingFile {
    DLog(@"begin");
    if (self.inlineImageHelper) {
        DLog(@"have helper");
        [self.inlineImageHelper writeToGrid:self.currentGrid];
        self.inlineImageHelper = nil;
        // TODO: Handle objects other than images.
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenDidFinishReceivingInlineFile];
        }];
    } else {
        DLog(@"Download finished");
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            DLog(@"begin side-effect");
            [delegate screenDidFinishReceivingFile];
        }];
    }
}

- (void)terminalRequestUpload:(NSString *)args {
    DLog(@"begin %@", args);
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        DLog(@"begin side-effect");
        [delegate screenRequestUpload:args completion:^{
            [unpauser unpause];
        }];
    }];
}

- (void)terminalPasteboardReceiptEndedUnexpectedly {
    DLog(@"begin");
    self.pasteboardString = nil;
}

- (void)terminalSoftAlternateScreenModeDidChange {
    DLog(@"begin");
    [self softAlternateScreenModeDidChange];
}

- (void)terminalSelectiveEraseRectangle:(VT100GridRect)rect {
    DLog(@"begin %@", VT100GridRectDescription(rect));
    [self selectiveEraseRectangle:rect];
}

- (void)terminalSelectiveEraseInDisplay:(int)mode {
    DLog(@"begin %@", @(mode));
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
    [self eraseInDisplayBeforeCursor:before afterCursor:after decProtect:YES];
}

- (void)terminalSelectiveEraseInLine:(int)mode {
    DLog(@"begin %@", @(mode));
    switch (mode) {
        case 0:
            [self selectiveEraseRange:VT100GridCoordRangeMake(self.currentGrid.cursorX,
                                                              self.currentGrid.cursorY,
                                                              self.currentGrid.size.width,
                                                              self.currentGrid.cursorY)
                      eraseAttributes:YES];
            return;
        case 1:
            [self selectiveEraseRange:VT100GridCoordRangeMake(0,
                                                              self.currentGrid.cursorY,
                                                              self.currentGrid.cursorX + 1,
                                                              self.currentGrid.cursorY)
                      eraseAttributes:YES];
            return;
        case 2:
            [self selectiveEraseRange:VT100GridCoordRangeMake(0,
                                                              self.currentGrid.cursorY,
                                                              self.currentGrid.size.width,
                                                              self.currentGrid.cursorY)
                      eraseAttributes:YES];
    }
}

- (void)terminalProtectedModeDidChangeTo:(VT100TerminalProtectedMode)mode {
    DLog(@"begin %@", @(mode));
    self.protectedMode = mode;
}

- (VT100TerminalProtectedMode)terminalProtectedMode {
    DLog(@"begin");
    return self.protectedMode;
}

- (void)terminalSendCapabilitiesReport {
    DLog(@"begin");
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        DLog(@"begin side-effect");
        [delegate screenReportCapabilities];
    }];
}

- (NSArray<NSString *> *)parseHookSSHConductorParameter:(NSString *)param {
    DLog(@"%@", param);
    NSArray<NSString *> *parts = [param componentsSeparatedByString:@" "];
    if (parts.count < 5) {
        DLog(@"Bad param %@", param);
        return nil;
    }
    NSInteger i = 0;
    NSString *token = parts[i++];
    NSString *uniqueID = parts[i++];
    NSString *boolArgs = parts[i++];

    // Skip unrecognized arguments until you get to the separator
    while (i < parts.count && ![parts[i] isEqualToString:@"-"]) {
        i += 1;
    }
    if (i == parts.count) {
        DLog(@"Didn't find separator");
        return nil;
    }
    i += 1;
    if (i >= parts.count) {
        DLog(@"No sshargs");
        return nil;
    }
    NSString *dcsid = [parts lastObject];
    parts = [parts it_arrayByDroppingLastN:1];
    NSString *sshargs = [[parts subarrayFromIndex:i] componentsJoinedByString:@" "];

    return @[token, uniqueID, boolArgs, sshargs, dcsid];
}

- (void)terminalDidHookSSHConductorWithParams:(NSString *)params {
    NSArray<NSString *> *values = [self parseHookSSHConductorParameter:params];
    DLog(@"%@", values);
    if (!values) {
        return;
    }
    NSString *token = values[0];
    NSString *uniqueID = values[1];
    NSString *boolArgs = [values[2] stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
    if (!boolArgs) {
        DLog(@"Failed to base64 decode %@", values[2]);
        return;
    }
    NSString *sshargs = [values[3] stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
    if (!sshargs) {
        DLog(@"Failed to base64 decode %@", values[3]);
        return;
    }
    NSString *dcsID = values[4];
    [self appendBannerMessage:[NSString stringWithFormat:@"ssh %@", sshargs]];
    [self addSideEffect:^(id<VT100ScreenDelegate> _Nonnull delegate) {
        [delegate screenDidHookSSHConductorWithToken:token
                                            uniqueID:uniqueID
                                            boolArgs:boolArgs
                                             sshargs:sshargs
                                               dcsID:dcsID];
    }];
}

- (void)terminalDidReadSSHConductorLine:(NSString *)string depth:(int)depth {
    [self addSideEffect:^(id<VT100ScreenDelegate> _Nonnull delegate) {
        [delegate screenDidReadSSHConductorLine:string depth:(int)depth];
    }];

}
- (void)terminalDidUnhookSSHConductor {
    [self addSideEffect:^(id<VT100ScreenDelegate> _Nonnull delegate) {
        [delegate screenDidUnhookSSHConductor];
    }];
}

- (void)terminalDidBeginSSHConductorCommandWithIdentifier:(NSString *)identifier
                                                    depth:(int)depth {
    [self addSideEffect:^(id<VT100ScreenDelegate> _Nonnull delegate) {
        [delegate screenDidBeginSSHConductorCommandWithIdentifier:identifier
                                                            depth:depth];
    }];
}

- (void)terminalDidEndSSHConductorCommandWithIdentifier:(NSString *)identifier
                                                   type:(NSString *)type
                                                 status:(uint8_t)status
                                                  depth:(int)depth {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenDidEndSSHConductorCommandWithIdentifier:identifier
                                                           type:type
                                                         status:status
                                                          depth:depth];

        [unpauser unpause];
    }];
}

- (void)terminalHandleSSHSideChannelOutput:(NSString *)string
                                       pid:(int32_t)pid
                                   channel:(uint8_t)channel
                                     depth:(int)depth {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenHandleSSHSideChannelOutput:string pid:pid channel:channel depth:depth];
    }];
}

- (void)terminalHandleSSHTerminatePID:(int)pid withCode:(int)code depth:(int)depth {
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenDidTerminateSSHProcess:pid code:code depth:depth];
        [unpauser unpause];
    }];
}

- (void)terminalUpdateEnv:(NSString *)value {
    DLog(@"begin %@", value);
    const NSInteger colon = [value rangeOfString:@":"].location;
    if (colon == NSNotFound) {
        DLog(@"no colon");
        return;
    }
    NSString *paramString = [value substringToIndex:colon];
    NSString *payload = [value substringFromIndex:colon + 1];
    NSArray<NSString *> *parts = [paramString componentsSeparatedByString:@";"];
    NSArray<iTermTuple<NSString *, NSString *> *> *kvps = [parts mapWithBlock:^id _Nullable(NSString * _Nonnull string) {
        return [string keyValuePair] ?: [iTermTuple tupleWithObject:string andObject:@""];
    }];
    if (![kvps containsObject:[iTermTuple tupleWithObject:@"report" andObject:@"all"]]) {
        DLog(@"missing report=all");
        return;
    }
    NSString *decodedPayload = [payload stringByBase64DecodingStringWithEncoding:self.terminal.encoding];
    if (!decodedPayload) {
        DLog(@"failed to decode payload");
    }
    self.exfiltratedEnvironment = [[decodedPayload componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] mapWithBlock:^id _Nullable(NSString * _Nonnull string) {
        return [string keyValuePair] ?: [iTermTuple tupleWithObject:string andObject:@""];
    }];
}

- (void)terminalEndSSH:(NSString *)uniqueID {
    __weak __typeof(self) weakSelf = self;
    dispatch_queue_t queue = _queue;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        const NSInteger count = [delegate screenEndSSH:uniqueID];
        if (count <= 0) {
            [unpauser unpause];
            return;
        }
        NSString *preamble;
        if (count == 1) {
            preamble = @"ssh exited";
        } else if (count > 1) {
            preamble = [NSString stringWithFormat:@"%@ ssh sessions ended.", @(count)];
        }
        NSString *sshLocation = [delegate screenSSHLocation];
        NSString *banner;
        if (sshLocation) {
            banner = [NSString stringWithFormat:@"%@ — now at %@.", preamble, sshLocation];
        } else {
            banner = [NSString stringWithFormat:@"%@ — you’re now back at the local shell.", preamble];
        }
        dispatch_async(queue, ^{
            [weakSelf appendBanner:banner andUnpause:unpauser];
        });
    }];
}

- (void)appendBanner:(NSString *)banner andUnpause:(iTermTokenExecutorUnpauser *)unpauser {
    [self appendBannerMessage:banner];
    [unpauser unpause];
}

- (void)terminalBeginFramerRecovery {
    [self appendBannerMessage:@"Recovering ssh connection…"];
    self.terminal.framerRecoveryMode = VT100TerminalFramerRecoveryModeRecovering;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        [delegate screenBeginFramerRecovery];
        [unpauser unpause];
    }];
}

- (void)terminalHandleFramerRecoveryString:(NSString *)string {
    __weak __typeof(self) weakSelf = self;
    dispatch_queue_t queue = _queue;
    [self addPausedSideEffect:^(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser) {
        iTermConductorRecovery *recovery = [delegate screenHandleFramerRecoveryString:string];
        if (recovery) {
            weakSelf.terminal.framerRecoveryMode = VT100TerminalFramerRecoveryModeSyncing;
            [weakSelf.terminal.parser startConductorRecoveryModeWithID:recovery.dcsID
                                                                  tree:recovery.tree];
            [delegate screenFramerRecoveryDidFinish];
            dispatch_async(queue, ^{
                [weakSelf appendBanner:@"ssh connection recovered!" andUnpause:unpauser];
            });
        } else {
            [unpauser unpause];
        }
    }];
}

@end
