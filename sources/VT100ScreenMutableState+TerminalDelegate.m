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
    if (self.collectInputForPrinting) {
        [self.printBuffer appendString:string];
    } else {
        // else display string on screen
        [self appendStringAtCursor:string];
    }
    [self appendStringToTriggerLine:string];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidAppendStringToCurrentLine:string
                                          isPlainText:YES];
    }];
}

- (void)terminalAppendAsciiData:(AsciiData *)asciiData {
    if (self.collectInputForPrinting) {
        NSString *string = [[NSString alloc] initWithBytes:asciiData->buffer
                                                    length:asciiData->length
                                                  encoding:NSASCIIStringEncoding];
        [self terminalAppendString:string];
        return;
    }
    // else display string on screen
    [self appendAsciiDataAtCursor:asciiData];

    if (![self appendAsciiDataToTriggerLine:asciiData]) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenDidAppendAsciiDataToCurrentLine:asciiData];
        }];
    }
}

- (void)terminalRingBell {
    DLog(@"Terminal rang the bell");
    [self appendStringToTriggerLine:@"\a"];

    [self activateBell];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidAppendStringToCurrentLine:@"\a" isPlainText:NO];
    }];
}

- (void)terminalBackspace {
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
    [self appendTabAtCursor:setBackgroundColors];
}

- (void)terminalCarriageReturn {
    [self carriageReturn];
}

- (void)terminalLineFeed {
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
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidReceiveLineFeed];
    }];
}

- (void)terminalCursorLeft:(int)n {
    [self cursorLeft:n];
}

- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [self cursorDown:n andToStartOfLine:toStart];
}

- (void)terminalCursorRight:(int)n {
    [self cursorRight:n];
}

- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [self cursorUp:n andToStartOfLine:toStart];
}

- (void)terminalMoveCursorToX:(int)x y:(int)y {
    [self cursorToX:x Y:y];
    [self clearTriggerLine];
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandRangeDidChange];
    }
}

- (BOOL)terminalShouldSendReport {
    return !self.config.isTmuxClient;
}

- (void)terminalReportVariableNamed:(NSString *)variable {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenReportVariableNamed:variable];
    }];
}

- (void)terminalSendReport:(NSData *)report {
    if (!self.config.isTmuxClient && report) {
        DLog(@"report %@", [report stringWithEncoding:NSUTF8StringEncoding]);
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenWriteDataToTask:report];
        }];
    }
}

- (void)terminalShowTestPattern {
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
    return self.currentGrid.cursorX - self.currentGrid.leftMargin + 1;
}

- (int)terminalRelativeCursorY {
    return self.currentGrid.cursorY - self.currentGrid.topMargin + 1;
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom {
    [self setScrollRegionTop:top bottom:bottom];
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [self eraseInDisplayBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [self eraseLineBeforeCursor:before afterCursor:after decProtect:NO];
}

- (void)terminalSetTabStopAtCursor {
    [self setTabStopAtCursor];
}

- (void)terminalReverseIndex {
    [self reverseIndex];
}

- (void)terminalForwardIndex {
    [self forwardIndex];
}

- (void)terminalBackIndex {
    [self backIndex];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    [self resetPreservingPrompt:preservePrompt modifyContent:modifyContent];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    // Pause because cursor type and blink are reportable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self.currentGrid markCharDirty:YES at:self.currentGrid.cursor updateTimestamp:NO];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetCursorType:cursorType];
        [unpauser unpause];
    }];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    // Pause because cursor type and blink are reportable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetCursorBlinking:blinking];
        [unpauser unpause];
    }];
}

- (iTermPromise<NSNumber *> *)terminalCursorIsBlinkingPromise {
    // Pause to avoid processing any more tokens since this is used for a report.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    dispatch_queue_t queue = _queue;
    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            const BOOL value = [delegate screenCursorIsBlinking];
            // VT100Terminal is blithely unaware of dispatch queues so make sure to give it a result
            // on the queue it expects to run on.
            dispatch_async(queue, ^{
                [seal fulfill:@(value)];
                [unpauser unpause];
            });
        }];
    }];
}

- (void)terminalGetCursorInfoWithCompletion:(void (^)(ITermCursorType type, BOOL blinking))completion {
    // Pause to avoid processing any more tokens since this is used for a report.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    dispatch_queue_t queue = _queue;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        ITermCursorType type = CURSOR_BOX;
        BOOL blinking = YES;
        [delegate screenGetCursorType:&type blinking:&blinking];
        dispatch_async(queue, ^{
            completion(type, blinking);
            [unpauser unpause];
        });
    }];
}

- (void)terminalResetCursorTypeAndBlink {
    // Pause because cursor type and blink are reportable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenResetCursorTypeAndBlink];
        [unpauser unpause];
    }];
}

- (BOOL)terminalLineDrawingFlagForCharset:(int)charset {
    return [self.charsetUsesLineDrawingMode containsObject:@(charset)];
}

- (void)terminalRemoveTabStops {
    [self.tabStops removeAllObjects];
}

- (void)terminalSetWidth:(int)width
          preserveScreen:(BOOL)preserveScreen
           updateRegions:(BOOL)updateRegions
            moveCursorTo:(VT100GridCoord)newCursorCoord
              completion:(void (^)(void))completion {
    const int height = self.currentGrid.size.height;
    __weak __typeof(self) weakSelf = self;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [weakSelf reallySetWidth:width
                          height:height
                  preserveScreen:preserveScreen
                   updateRegions:updateRegions
                    moveCursorTo:newCursorCoord
                        delegate:delegate
                      completion:completion];
    }];
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetSize:VT100GridSizeMake(rows, columns)];
        [unpauser unpause];
    }];
}


- (void)reallySetWidth:(int)width
                height:(int)height
        preserveScreen:(BOOL)preserveScreen
         updateRegions:(BOOL)updateRegions
          moveCursorTo:(VT100GridCoord)newCursorCoord
              delegate:(id<VT100ScreenDelegate>)delegate
            completion:(void (^)(void))completion {
    assert(self.performingJoinedBlock);
    if ([delegate screenShouldInitiateWindowResize] &&
        ![delegate screenWindowIsFullscreen]) {
        // set the column
        [delegate screenResizeToWidth:width
                               height:height];
        if (!preserveScreen) {
            [self eraseInDisplayBeforeCursor:YES afterCursor:YES decProtect:NO];  // erase the screen
            self.currentGrid.cursorX = 0;
            self.currentGrid.cursorY = 0;
        }
    }
    if (updateRegions) {
        [self setUseColumnScrollRegion:NO];
        [self setLeftMargin:0 rightMargin:self.width - 1];
        [self setScrollRegionTop:0
                          bottom:self.height - 1];
    }
    if (newCursorCoord.x >= 0 && newCursorCoord.y >= 0) {
        [self cursorToX:newCursorCoord.x];
        [self clearTriggerLine];
        [self cursorToY:newCursorCoord.y];
        [self clearTriggerLine];
    }
    if (completion) {
        completion();
    }
}

- (void)terminalSetUseColumnScrollRegion:(BOOL)use {
    [self setUseColumnScrollRegion:use];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    [self setLeftMargin:scrollLeft rightMargin:scrollRight];
}

- (void)terminalSetCursorX:(int)x {
    [self cursorToX:x];
    [self clearTriggerLine];
}

- (void)terminalSetCursorY:(int)y {
    [self cursorToY:y];
    [self clearTriggerLine];
}

- (void)terminalRemoveTabStopAtCursor {
    [self removeTabStopAtCursor];
}

- (void)terminalBackTab:(int)n {
    [self backTab:n];
}

- (void)terminalAdvanceCursorPastLastColumn {
    [self advanceCursorPastLastColumn];
}

- (void)terminalEraseCharactersAfterCursor:(int)j {
    [self eraseCharactersAfterCursor:j];
}

- (void)terminalPrintBuffer {
    if (self.printBuffer.length == 0) {
        return;
    }
    NSString *string = [self.printBuffer copy];
    self.printBuffer = nil;
    self.collectInputForPrinting = NO;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenPrintStringIfAllowed:string];
    }];
}

- (void)terminalPrintScreen {
    // Print out the whole screen
    self.printBuffer = nil;
    self.collectInputForPrinting = NO;

    // Pause so we print the current state and not future updates.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenPrintVisibleAreaIfAllowed];
        [unpauser unpause];
    }];
}

- (void)terminalBeginRedirectingToPrintBuffer {
    if (!self.config.printingAllowed) {
        return;
    }
    // allocate a string for the stuff to be printed
    self.printBuffer = [[NSMutableString alloc] init];
    self.collectInputForPrinting = YES;
}

- (void)terminalSetWindowTitle:(NSString *)title {
    DLog(@"terminalSetWindowTitle:%@", title);

    // Pause because a title change affects a variable, and that is observable by token execution.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenSetWindowTitle:title];
        }
        [unpauser unpause];
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
    // Pause because a title change affects a variable, and that is observable by token execution.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenSetIconName:title];
        }
        [unpauser unpause];
    }];
}

- (void)terminalSetSubtitle:(NSString *)subtitle {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenSetSubtitle:subtitle];
        }
    }];
}

- (void)terminalCopyStringToPasteboard:(NSString *)string {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenCopyStringToPasteboard:string];
    }];
}

- (void)terminalBeginCopyToPasteboard {
    if (self.config.clipboardAccessAllowed) {
        self.pasteboardString = [[NSMutableString alloc] init];
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenTerminalAttemptedPasteboardAccess];
    }];
}

- (void)terminalDidReceiveBase64PasteboardString:(NSString *)string {
    if (self.config.clipboardAccessAllowed) {
        [self.pasteboardString appendString:string];
    }
}

- (void)terminalDidFinishReceivingPasteboard {
    if (self.pasteboardString && self.config.clipboardAccessAllowed) {
        NSData *data = [NSData dataWithBase64EncodedString:self.pasteboardString];
        if (data) {
            NSString *string = [[NSString alloc] initWithData:data
                                                     encoding:self.terminal.encoding];
            if (!string) {
                string = [[NSString alloc] initWithData:data
                                               encoding:[NSString defaultCStringEncoding]];
            }

            if (string) {
                [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                    [delegate screenCopyStringToPasteboard:string];
                }];
            }
        }
    }
    self.pasteboardString = nil;
}

- (void)terminalInsertEmptyCharsAtCursor:(int)n {
    [self.currentGrid insertChar:[self.currentGrid defaultChar]
              externalAttributes:nil
                              at:self.currentGrid.cursor
                           times:n];
}

- (void)terminalShiftLeft:(int)n {
    if (n < 1) {
        return;
    }
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        return;
    }
    [self.currentGrid moveContentLeft:n];
}

- (void)terminalShiftRight:(int)n {
    if (n < 1) {
        return;
    }
    if (self.cursorOutsideLeftRightMargin || self.cursorOutsideTopBottomMargin) {
        return;
    }
    [self.currentGrid moveContentRight:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    VT100GridRect scrollRegionRect = [self.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == self.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(self.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
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
    [self.currentGrid deleteChars:n startingAt:self.currentGrid.cursor];
    [self clearTriggerLine];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    if (n <= 0) {
        return;
    }
    VT100GridRect scrollRegionRect = [self.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == self.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(self.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
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
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetPointSize:NSMakeSize(width, height)];
        [unpauser unpause];
    }];
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    // Pause because you can query for window location.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenShouldInitiateWindowResize] &&
            ![delegate screenWindowIsFullscreen]) {
            // TODO: Only allow this if there is a single session in the tab.
            [delegate screenMoveWindowTopLeftPointTo:point];
            [unpauser unpause];
        }
    }];
}

- (void)terminalMiniaturize:(BOOL)mini {
    // Paseu becasue miniaturization status is reportable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        // TODO: Only allow this if there is a single session in the tab.
        if ([delegate screenShouldInitiateWindowResize] &&
            ![delegate screenWindowIsFullscreen]) {
            [delegate screenMiniaturizeWindow:mini];
        }
        [unpauser unpause];
    }];
}

- (void)terminalRaise:(BOOL)raise {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenShouldInitiateWindowResize]) {
            [delegate screenRaise:raise];
        }
        [unpauser unpause];
    }];
}

- (void)terminalScrollDown:(int)n {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenRemoveSelection];
    }];
    [self.currentGrid scrollRect:[self.currentGrid scrollRegionRect]
                          downBy:MIN(self.currentGrid.size.height, n)
                       softBreak:NO];
    [self clearTriggerLine];
}

- (void)terminalScrollUp:(int)n {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
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
    return self.config.miniaturized;
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    return self.config.windowFrame.origin;
}

- (int)terminalWindowWidthInPixels {
    return round(self.config.windowFrame.size.width);
}

- (int)terminalWindowHeightInPixels {
    return round(self.config.windowFrame.size.height);
}

- (int)terminalScreenHeightInCells {
    return self.config.theoreticalGridSize.height;
}

- (int)terminalScreenWidthInCells {
    return self.config.theoreticalGridSize.width;
}

- (NSString *)terminalIconTitle {
    if (self.allowTitleReporting && [self terminalIsTrusted]) {
        return self.config.iconTitle ?: @"";
    } else {
        return @"";
    }
}

- (NSString *)terminalWindowTitle {
    if (self.allowTitleReporting && [self terminalIsTrusted]) {
        return self.config.windowTitle ?: @"";
    } else {
        return @"";
    }
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenPushCurrentTitleForWindow:isWindow];
        }
    }];
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    // Pause because this sets the title, which is observable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if ([delegate screenAllowTitleSetting]) {
            [delegate screenPopCurrentTitleForWindow:isWindow];
        }
        [unpauser unpause];
    }];
}

- (void)terminalPostUserNotification:(NSString *)message {
    if (!self.postUserNotifications) {
        DLog(@"Declining to allow terminal to post user notification %@", message);
        return;
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenPostUserNotification:message];
    }];
}

- (void)terminalStartTmuxModeWithDCSIdentifier:(NSString *)dcsID {
    // Pause becuase a ton of stuff happens here and it's too hard to reason about what would happen
    // otherwise.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenStartTmuxModeWithDCSIdentifier:dcsID];
        [unpauser unpause];
    }];
}

- (void)terminalHandleTmuxInput:(VT100Token *)token {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenHandleTmuxInput:token];
    }];
}

- (void)terminalSynchronizedUpdate:(BOOL)begin {
    if (begin) {
        [self.temporaryDoubleBuffer startExplicitly];
    } else {
        [self.temporaryDoubleBuffer resetExplicitly];
    }
}

- (VT100GridSize)terminalSizeInCells {
    return self.currentGrid.size;
}

- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode {
    // Pause because this updates a variable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenMouseModeDidChange];
        [unpauser unpause];
    }];
}

- (void)terminalShowAltBuffer {
    [self showAltBuffer];
}

- (BOOL)terminalUseColumnScrollRegion {
    return self.currentGrid.useScrollRegionCols;
}

- (BOOL)terminalIsShowingAltBuffer {
    return self.currentGrid == self.altGrid;
}

- (void)terminalShowPrimaryBuffer {
    [self showPrimaryBuffer];
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    [self setRemoteHostFromString:remoteHost];
}

- (void)terminalSetWorkingDirectoryURL:(NSString *)URLString {
    [self setWorkingDirectoryFromURLString:URLString];
}

- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)dir {
    [self currentDirectoryDidChangeTo:dir];
}

- (void)terminalClearScreen {
    [self eraseScreenAndRemoveSelection];
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
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenSaveScrollPosition];
        }];
    } else {  // implicitly "saveCursorLine"
        [self saveCursorLine];
    }
}

- (void)terminalStealFocus {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenStealFocus];
    }];
}

- (void)terminalSetProxyIcon:(NSString *)value {
    NSString *path = [value length] ? value : nil;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetPreferredProxyIcon:path];
    }];
}

- (void)terminalClearScrollbackBuffer {
    if (!self.config.clearScrollbackAllowed) {
        [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
            [delegate screenAskAboutClearingScrollback];
        }];
        return;
    }
    [self clearScrollbackBuffer];
}

- (void)terminalClearBuffer {
    [self clearBufferSavingPrompt:YES];
}

- (void)terminalProfileShouldChangeTo:(NSString *)value {
    [self forceCheckTriggers];
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetProfileToProfileNamed:value];
        [unpauser unpause];
    }];
}

- (void)terminalAddNote:(NSString *)value show:(BOOL)show {
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
                      focus:NO];
        if (!show) {
            [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
                [note hide];
            }];
        }
    }
}

- (void)terminalSetPasteboard:(NSString *)value {
    // Don't pause because there will never be a code to get the pasteboard value.
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetPasteboard:value];
    }];
}

- (void)terminalAppendDataToPasteboard:(NSData *)data {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenAppendDataToPasteboard:data];
    }];
}

- (void)terminalCopyBufferToPasteboard {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenCopyBufferToPasteboard];
    }];
}

- (BOOL)terminalIsTrusted {
    return [super terminalIsTrusted];
}

- (BOOL)terminalCanUseDECRQCRA {
    if (![iTermAdvancedSettingsModel disableDECRQCRA]) {
        return YES;
    }
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDidTryToUseDECRQCRA];
    }];
    return NO;
}

- (void)terminalRequestAttention:(VT100AttentionRequestType)request {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenRequestAttention:request];
    }];
}

- (void)terminalDisinterSession {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenDisinterSession];
    }];
}

- (void)terminalSetBackgroundImageFile:(NSString *)filename {
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetBackgroundImageFile:filename];
    }];
}

- (void)terminalSetBadgeFormat:(NSString *)badge {
    // Pause because this changes a variable.
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetBadgeFormat:badge];
        [unpauser unpause];
    }];
}

- (void)terminalSetUserVar:(NSString *)kvp {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetUserVar:kvp];
        [unpauser unpause];
    }];
}

- (void)terminalResetColor:(VT100TerminalColorIndex)n {
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenResetColorsWithColorMapKey:key colorMap:colorMap];
    }];
}

- (void)terminalSetForegroundColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapForeground colorMap:colorMap];
    }];
}

- (void)terminalSetBackgroundColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapBackground colorMap:colorMap];
    }];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapBold colorMap:colorMap];
    }];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapSelection colorMap:colorMap];
    }];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapSelectedText colorMap:colorMap];
    }];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapCursor colorMap:colorMap];
    }];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:kColorMapCursorText colorMap:colorMap];
    }];
}

- (void)terminalSetColorTableEntryAtIndex:(VT100TerminalColorIndex)n color:(NSColor *)color {
    const int key = [self colorMapKeyForTerminalColorIndex:n];
    DLog(@"Key for %@ is %@", @(n), @(key));
    if (key < 0) {
        return;
    }
    iTermColorMap *colorMap = self.colorMap;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetColor:color forKey:key colorMap:colorMap];
    }];
}

- (void)terminalSetCurrentTabColor:(NSColor *)color {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetCurrentTabColor:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorRedComponentTo:(CGFloat)color {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetTabColorRedComponentTo:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetTabColorGreenComponentTo:color];
        [unpauser unpause];
    }];
}

- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color {
    iTermTokenExecutorUnpauser *unpauser = [self.tokenExecutor pause];
    [self addSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetTabColorBlueComponentTo:color];
        [unpauser unpause];
    }];
}

- (BOOL)terminalFocusReportingAllowed {
    return [iTermAdvancedSettingsModel focusReportingEnabled];
}

- (BOOL)terminalCursorVisible {
    return self.cursorVisible;
}

- (NSColor *)terminalColorForIndex:(VT100TerminalColorIndex)index {
    const int key = [self colorMapKeyForTerminalColorIndex:index];
    if (key < 0) {
        return nil;
    }
    return [self.colorMap colorForKey:key];
}


- (int)terminalCursorX {
    return MIN(self.cursorX, self.width);
}

- (int)terminalCursorY {
    return self.cursorY;
}

- (BOOL)terminalWillAutoWrap {
    return self.cursorX > self.width;
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    [self setCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    self.trackCursorLineMovement = highlight;
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetHighlightCursorLine:highlight];
    }];
}

- (void)terminalClearCapturedOutput {
    // Join because delegate wants to change a mark.
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenClearCapturedOutput];
    }];
}

- (void)terminalPromptDidStart {
    [self promptDidStartAt:VT100GridAbsCoordMake(self.currentGrid.cursor.x,
                                                 self.currentGrid.cursor.y + self.numberOfScrollbackLines + self.cumulativeScrollbackOverflow)];
}

- (NSArray<NSNumber *> *)terminalTabStops {
    return [[self.tabStops.allObjects sortedArrayUsingSelector:@selector(compare:)] mapWithBlock:^NSNumber *(NSNumber *ts) {
        return @(ts.intValue + 1);
    }];
}

- (void)terminalSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [self.tabStops removeAllObjects];
    [tabStops enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self.tabStops addObject:@(obj.intValue - 1)];
    }];
}

- (void)terminalCommandDidStart {
    [self commandDidStart];
}

- (void)terminalCommandDidEnd {
    [self commandDidEnd];
}

- (void)terminalAbortCommand {
    DLog(@"FinalTerm: terminalAbortCommand");
    [self commandWasAborted];
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
    [self setReturnCodeOfLastCommand:returnCode];
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
    [self addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        if (shell) {
            [delegate screenDidDetectShell:shell];
        }
        if (!shell || versionNumber < latestKnownVersion) {
            [delegate screenSuggestShellIntegrationUpgrade];
        }
    }];
}

- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue {
    self.wraparoundMode = newValue;
}

- (void)terminalTypeDidChange {
    self.ansi = [self.terminal isAnsi];
}

- (void)terminalInsertModeDidChangeTo:(BOOL)newValue {
    self.insert = newValue;
}

- (int)terminalChecksumInRectangle:(VT100GridRect)rect {
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
    return self.config.profileName;
}

- (VT100GridRect)terminalScrollRegion {
    return self.currentGrid.scrollRegionRect;
}

- (NSArray<NSString *> *)terminalSGRCodesInRectangle:(VT100GridRect)screenRect {
    __block NSMutableSet<NSString *> *codes = nil;
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
            NSSet<NSString *> *charCodes = [self.terminal sgrCodesForCharacter:c
                                                            externalAttributes:eaIndex[x]];
            if (!codes) {
                codes = [charCodes mutableCopy];
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

- (void)terminalWillReceiveFileNamed:(NSString *)name
                              ofSize:(NSInteger)size
                          completion:(void (^)(BOOL ok))completion {
    // Use a joined side effect so we can safely call the completion block from the main thread.
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        BOOL promptIfBig = YES;
        const BOOL ok = [delegate screenConfirmDownloadAllowed:name
                                                          size:size
                                                 displayInline:NO
                                                   promptIfBig:&promptIfBig];
        if (!ok) {
            completion(NO);
            return;
        }

        [delegate screenWillReceiveFileNamed:name ofSize:size preconfirmed:!promptIfBig];
        completion(YES);
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
                                completion:(void (^)(BOOL ok))completion {
    __weak __typeof(self) weakSelf = self;
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(NO);
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
                                          delegate:delegate
                                        completion:completion];
    }];
}

- (void)reallyWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(NSInteger)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset
                                delegate:(id<VT100ScreenDelegate>)delegate
                                completion:(void (^)(BOOL ok))completion {
    assert(self.performingJoinedBlock);
    BOOL promptIfBig = YES;
    if (![delegate screenConfirmDownloadAllowed:name
                                           size:size
                                  displayInline:YES
                                    promptIfBig:&promptIfBig]) {
        completion(NO);
        return;
    }
    const CGFloat scale = self.config.backingScaleFactor;
    self.inlineImageHelper = [[VT100InlineImageHelper alloc] initWithName:name
                                                                    width:width
                                                               widthUnits:widthUnits
                                                                   height:height
                                                              heightUnits:heightUnits
                                                              scaleFactor:scale
                                                      preserveAspectRatio:preserveAspectRatio
                                                                    inset:inset
                                                             preconfirmed:!promptIfBig];
    self.inlineImageHelper.delegate = self;
    completion(YES);
}

- (void)terminalFileReceiptEndedUnexpectedly {
    [self fileReceiptEndedUnexpectedly];
}

- (void)terminalDidReceiveBase64FileData:(NSString *)data {
    if (self.inlineImageHelper) {
        [self.inlineImageHelper appendBase64EncodedData:data];
    } else {
        __weak __typeof(self) weakSelf = self;
        [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
            [delegate screenDidReceiveBase64FileData:data
                                             confirm:^void(NSString *name,
                                                           NSInteger lengthBefore,
                                                           NSInteger lengthAfter) {
                [weakSelf confirmBigDownloadWithBeforeSize:lengthBefore
                                                 afterSize:lengthAfter
                                                      name:name
                                                  delegate:delegate];
            }];
        }];
    }
}

- (void)terminalAppendSixelData:(NSData *)data {
    VT100InlineImageHelper *helper = [[VT100InlineImageHelper alloc] initWithSixelData:data
                                                                           scaleFactor:self.config.backingScaleFactor];
    helper.delegate = self;
    [helper writeToGrid:self.currentGrid];
    [self appendCarriageReturnLineFeed];
}

- (NSSize)terminalCellSizeInPoints:(double *)scaleOut {
    *scaleOut = self.config.backingScaleFactor;
    return self.config.cellSize;
}

- (void)terminalSetUnicodeVersion:(NSInteger)unicodeVersion {
    // This is joined mostly out of caution. It changes the profile and so could unexpectedly do
    // something observable.
    [self addJoinedSideEffect:^(id<VT100ScreenDelegate> delegate) {
        [delegate screenSetUnicodeVersion:unicodeVersion];
    }];
}

@end
