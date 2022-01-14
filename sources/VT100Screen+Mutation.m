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
#import "VT100ScreenMutableState+Resizing.h"
#import "VT100ScreenMutableState+TerminalDelegate.h"
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
    _mutableState.config = _nextConfig;
}

#pragma mark - FinalTerm

- (void)mutPromptDidStartAt:(VT100GridAbsCoord)coord {
    [_mutableState promptDidStartAt:coord];
}

- (void)mutSetLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange {
    _mutableState.lastCommandOutputRange = lastCommandOutputRange;
}

#pragma mark - Interval Tree

- (id<iTermMark>)mutAddMarkOnLine:(int)line ofClass:(Class)markClass {
    return [_mutableState addMarkOnLine:line ofClass:markClass];
}

- (void)mutSetPromptStartLine:(int)line {
    [_mutableState setPromptStartLine:line];
}

- (void)mutDidUpdatePromptLocation {
    [_mutableState didUpdatePromptLocation];
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
    if ([_mutableState commandDidEndAtAbsCoord:coord]) {
        _mutableState.fakePromptDetectedAbsLine = -2;
    } else {
        // Screen didn't think we were in a command.
        _mutableState.fakePromptDetectedAbsLine = -1;
    }
}

- (PTYAnnotation *)mutAddNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange {
    return [_mutableState addNoteWithText:text inAbsoluteRange:absRange];
}


- (void)mutSetWorkingDirectory:(NSString *)workingDirectory
#warning TODO: I need to use an absolute line number here to avoid race conditions between main thread and mutation thread.
                     onAbsLine:(long long)line
                        pushed:(BOOL)pushed
                         token:(id<iTermOrderedToken>)token {
    [_mutableState setWorkingDirectory:workingDirectory
                             onAbsLine:line
                                pushed:pushed
                                 token:token];
}

- (id<iTermMark>)mutAddMarkStartingAtAbsoluteLine:(long long)line
                                          oneLine:(BOOL)oneLine
                                          ofClass:(Class)markClass {
    return [_mutableState addMarkStartingAtAbsoluteLine:line
                                                oneLine:oneLine
                                                ofClass:markClass];
}

- (void)mutReloadMarkCache {
    [_mutableState reloadMarkCache];
}

- (void)mutAddNote:(PTYAnnotation *)annotation
           inRange:(VT100GridCoordRange)range
             focus:(BOOL)focus {
    [_mutableState addAnnotation:annotation inRange:range focus:focus];
}

- (void)mutRemoveAnnotation:(PTYAnnotation *)annotation {
    [_mutableState removeAnnotation:annotation];
}

#pragma mark - Clearing

- (void)mutClearBuffer {
    [self mutClearBufferSavingPrompt:YES];
}

- (void)mutClearBufferSavingPrompt:(BOOL)savePrompt {
    [_mutableState clearBufferSavingPrompt:savePrompt];
}

- (void)mutClearScrollbackBuffer {
    [_mutableState clearScrollbackBuffer];
}

- (void)clearScrollbackBufferFromLine:(int)line {
    const int width = _mutableState.width;
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
    const int preHocNumberOfLines = [_mutableState.linebuffer numberOfWrappedLinesWithWidth:_mutableState.width];
    const int numberOfLinesAppended = [_mutableState.currentGrid appendLines:self.currentGrid.numberOfLinesUsed
                                                                toLineBuffer:_mutableState.linebuffer];
    if (numberOfLinesAppended <= 0) {
        return;
    }
    [_mutableState.currentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                         to:VT100GridCoordMake(_mutableState.width - 1,
                                                               _mutableState.height - 1)
                                     toChar:self.currentGrid.defaultChar
                         externalAttributes:nil];
    [self.mutableLineBuffer removeLastRawLine];
    const int postHocNumberOfLines = [_mutableState.linebuffer numberOfWrappedLinesWithWidth:_mutableState.width];
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
    const long long totalScrollbackOverflow = _mutableState.cumulativeScrollbackOverflow;
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

    [self clearScrollbackBufferFromLine:absLine - _mutableState.cumulativeScrollbackOverflow];
    const VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                                                   absLine - totalScrollbackOverflow,
                                                                   _mutableState.width,
                                                                   _mutableState.numberOfScrollbackLines + _mutableState.height);

    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [_mutableState removeIntervalTreeObjectsInRange:coordRange
                                                                                         exceptCoordRange:cursorLineRange.coordRange];
    if (absCursorCoord.y >= absLine) {
        Interval *cursorLineInterval = [_mutableState intervalForGridCoordRange:cursorLineRange.coordRange];
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
                VT100GridCoordRange range = [_mutableState coordRangeForInterval:obj.entry.interval];
                range.start.y -= numberOfLinesRemoved;
                range.end.y -= numberOfLinesRemoved;
                Interval *interval = [_mutableState intervalForGridCoordRange:range];

                // Remove and re-add the object with the new interval.
                [_mutableState removeObjectFromIntervalTree:obj];
                [_mutableState.intervalTree addObject:obj withInterval:interval];

                // Re-adding an annotation requires telling the delegate so it can create a vc
                PTYAnnotation *annotation = [PTYAnnotation castFrom:obj];
                if (annotation) {
                    [_mutableState addSideEffect:^(id<VT100ScreenDelegate> delegate) {
                        [delegate screenDidAddNote:annotation focus:NO];
                    }];
                }
                // TODO: This needs to be a side effect.
                [self.intervalTreeObserver intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeForObject(obj)
                                                                   onLine:range.start.y + totalScrollbackOverflow];
            }];
        }
    } else {
        [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [_mutableState removeObjectFromIntervalTree:obj];
        }];
    }
    [self mutReloadMarkCache];
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
}

- (void)clearGridFromLineToEnd:(int)line {
    assert(line >= 0 && line < _mutableState.height);
    const VT100GridCoord savedCursor = self.currentGrid.cursor;
    _mutableState.currentGrid.cursor = VT100GridCoordMake(0, line);
    [_mutableState removeSoftEOLBeforeCursor];
    const VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(0, line),
                                                    VT100GridCoordMake(_mutableState.width, _mutableState.height),
                                                    _mutableState.width);
    [_mutableState.currentGrid setCharsInRun:run toChar:0 externalAttributes:nil];
    [_mutableState clearTriggerLine];
    _mutableState.currentGrid.cursor = savedCursor;
}

#pragma mark - Appending

- (void)mutAppendStringAtCursor:(NSString *)string {
    [_mutableState appendStringAtCursor:string];
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
    [_mutableState eraseLineBeforeCursor:YES afterCursor:YES decProtect:NO];
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *message = [NSString stringWithFormat:@"Session Contents Restored on %@", [dateFormatter stringFromDate:[NSDate date]]];
    [_mutableState appendStringAtCursor:message];
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
    [_mutableState appendScreenCharArrayAtCursor:line
                                          length:length
                          externalAttributeIndex:externalAttributeIndex];
    if (continuation.code == EOL_HARD) {
        [_mutableState carriageReturn];
        [_mutableState appendLineFeed];
    }
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
    const int numberOfLines = _mutableState.numberOfLines;
    [_mutableState.currentGrid restoreScreenFromLineBuffer:_mutableState.linebuffer
                                           withDefaultChar:[self.currentGrid defaultChar]
                                         maxLinesToRestore:MIN(numberOfLines, _mutableState.height)];
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
    const int effectiveWidth = _mutableState.width ?: 80;
    const int maxArea = maxLines80 * (includeGrid ? 80 : effectiveWidth);
    const int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [[_mutableState.linebuffer copyWithMinimumLines:maxLines
                                                               atWidth:effectiveWidth] autorelease];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([_mutableState.linebuffer numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
        -(linesDroppedForBrevity + _mutableState.cumulativeScrollbackOverflow) * (_mutableState.width + 1);

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
        [lineBuffer setMaxLines:_state.maxScrollbackLines + _mutableState.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:_mutableState.width];
        }
        _mutableState.linebuffer = [lineBuffer autorelease];
        int maxLinesToRestore;
        if ([iTermAdvancedSettingsModel runJobsInServers] && reattached) {
            maxLinesToRestore = _state.currentGrid.size.height;
        } else {
            maxLinesToRestore = _state.currentGrid.size.height - 1;
        }
        const int linesRestored = MIN(MAX(0, maxLinesToRestore),
                                [lineBuffer numLinesWithWidth:_mutableState.width]);
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
                    coord.x <= _mutableState.width &&
                    coord.y < _mutableState.height) {
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
            [lineBuffer dropExcessLinesWithWidth:_mutableState.width];
        }
    } else if (screenState) {
        // New format
        [_mutableState restoreFromDictionary:dictionary
                    includeRestorationBanner:includeRestorationBanner];

        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary[@"LineBuffer"]];
        [lineBuffer setMaxLines:_state.maxScrollbackLines + _mutableState.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:_mutableState.width];
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
            [_mutableState setCharacterSet:i usesLineDrawingMode:array[i].boolValue];
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
            [_mutableState setCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake([screenState[kScreenStateCommandStartXKey] intValue],
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
            [self mutSetSize:savedSize
                visibleLines:[self.delegate screenRangeOfVisibleLines]
                   selection:[self.delegate screenSelection]
                     hasView:[self.delegate screenHasView]];
        }
        _mutableState.intervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.intervalTree
                                    visible:YES
                      guidOfLastCommandMark:guidOfLastCommandMark];

        _mutableState.savedIntervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateSavedIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.savedIntervalTree
                                    visible:NO
                      guidOfLastCommandMark:guidOfLastCommandMark];

        Interval *interval = [self lastPromptMark].entry.interval;
        if (interval) {
            const VT100GridRange gridRange = [_mutableState lineNumberRangeOfInterval:interval];
            _mutableState.lastPromptLine = gridRange.location + _mutableState.cumulativeScrollbackOverflow;
        }

        [self mutReloadMarkCache];
        [self.delegate screenSendModifiersDidChange];

        if (gDebugLogging) {
            DLog(@"Notes after restoring with width=%@", @(_mutableState.width));
            for (id<IntervalTreeObject> object in _mutableState.intervalTree.allObjects) {
                if (![object isKindOfClass:[PTYAnnotation class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([_mutableState coordRangeForInterval:object.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }
}

// Link references to marks in CapturedOutput (for the lines where output was captured) to the deserialized mark.
// Link marks for commands to CommandUse objects in command history.
// Notify delegate of annotations so they get added as subviews, and set the delegate of not view controllers to self.
- (void)fixUpDeserializedIntervalTree:(IntervalTree *)intervalTree
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
    [_mutableState addSideEffect:^(id<VT100ScreenDelegate>  _Nonnull delegate) {
        [delegate screenSetCursorVisible:[[state objectForKey:kStateDictCursorMode] boolValue]];
#warning TODO: Maybe need to mark the grid dirty to force the cursor to be redrawn.
    }];

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

- (void)mutCrlf {
    [_mutableState appendCarriageReturnLineFeed];
}

- (void)mutLinefeed {
    [_mutableState appendLineFeed];
}

- (void)setCursorX:(int)x Y:(int)y {
    DLog(@"Move cursor to %d,%d", x, y);
    _mutableState.currentGrid.cursor = VT100GridCoordMake(x, y);
}

- (void)mutRemoveAllTabStops {
    [_mutableState.tabStops removeAllObjects];
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

- (void)mutLoadInitialColorTable {
    [_mutableState loadInitialColorTable];
}

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

- (void)mutSetExited:(BOOL)exited {
    [_mutableState setExited:exited];
}

// WARNING: This is called on PTYTask's thread.
- (void)mutAddTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority {
    [_mutableState addTokens:vector length:length highPriority:highPriority];
}

- (void)mutScheduleTokenExecution {
    [_mutableState scheduleTokenExecution];
}

- (void)mutSetShouldExpectPromptMarks:(BOOL)value {
    _mutableState.shouldExpectPromptMarks = value;
}

- (void)mutSetLastPromptLine:(long long)value {
    _mutableState.lastPromptLine = value;
}

- (void)mutSetDelegate:(id<VT100ScreenDelegate>)delegate {
    _mutableState.colorMap.delegate = delegate;
#warning TODO: This is temporary. Mutable state should be the delegate.
    [_mutableState setTokenExecutorDelegate:delegate];
    delegate_ = delegate;
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

- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord {
    [_mutableState setCoordinateOfCommandStart:coord];
}

- (void)mutResetScrollbackOverflow {
    [_mutableState resetScrollbackOverflow];
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
                                               to:VT100GridCoordMake(_mutableState.width - 1, y)];
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

- (void)mutRedrawGrid {
    [_mutableState.currentGrid setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [delegate_ screenUpdateDisplay:YES];
}

#pragma mark - URLs

- (void)mutLinkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                  URLCode:(unsigned int)code {
    [_mutableState linkTextInRange:range basedAtAbsoluteLineNumber:absoluteLineNumber URLCode:code];
}

#pragma mark - Highlighting

- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor {
    [_mutableState highlightRun:run withForegroundColor:fgColor backgroundColor:bgColor];
}

- (void)mutHighlightTextInRange:(NSRange)range
      basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                         colors:(NSDictionary *)colors {
    [_mutableState highlightTextInRange:range
              basedAtAbsoluteLineNumber:absoluteLineNumber
                                 colors:colors];
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

#pragma mark - Injection

- (void)mutInjectData:(NSData *)data {
    [_mutableState injectData:data];
}

#pragma mark - VT100TerminalDelegate

- (void)terminalAppendString:(NSString *)string {
    [_mutableState terminalAppendString:string];
}

- (void)terminalAppendAsciiData:(AsciiData *)asciiData {
    [_mutableState terminalAppendAsciiData:asciiData];
}

- (void)terminalRingBell {
    [_mutableState terminalRingBell];
}

- (void)terminalBackspace {
    [_mutableState terminalBackspace];
}

- (void)terminalAppendTabAtCursor:(BOOL)setBackgroundColors {
    [_mutableState terminalAppendTabAtCursor:setBackgroundColors];
}

- (void)terminalLineFeed {
    [_mutableState terminalLineFeed];
}

- (void)terminalCursorLeft:(int)n {
    [_mutableState terminalCursorLeft:n];
}

- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [_mutableState terminalCursorDown:n andToStartOfLine:toStart];
}

- (void)terminalCursorRight:(int)n {
    [_mutableState terminalCursorRight:n];
}

- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [_mutableState terminalCursorUp:n andToStartOfLine:toStart];
}

- (void)terminalMoveCursorToX:(int)x y:(int)y {
    [_mutableState terminalMoveCursorToX:x y:y];
}

- (BOOL)terminalShouldSendReport {
    return [_mutableState terminalShouldSendReport];
}

- (void)terminalReportVariableNamed:(NSString *)variable {
    [_mutableState terminalReportVariableNamed:variable];
}

- (void)terminalSendReport:(NSData *)report {
    [_mutableState terminalSendReport:report];
}

- (void)terminalShowTestPattern {
    [_mutableState terminalShowTestPattern];
}

- (int)terminalRelativeCursorX {
    return [_mutableState terminalRelativeCursorX];
}

- (int)terminalRelativeCursorY {
    return [_mutableState terminalRelativeCursorY];
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom {
    [_mutableState terminalSetScrollRegionTop:top bottom:bottom];
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [_mutableState terminalEraseInDisplayBeforeCursor:before afterCursor:after];
}

- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    [_mutableState terminalEraseLineBeforeCursor:before afterCursor:after];
}

- (void)terminalSetTabStopAtCursor {
    [_mutableState terminalSetTabStopAtCursor];
}

- (void)terminalCarriageReturn {
    [_mutableState terminalCarriageReturn];
}

- (void)terminalReverseIndex {
    [_mutableState terminalReverseIndex];
}

- (void)terminalForwardIndex {
    [_mutableState terminalForwardIndex];
}

- (void)terminalBackIndex {
    [_mutableState terminalBackIndex];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    [_mutableState terminalResetPreservingPrompt:preservePrompt modifyContent:modifyContent];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    [_mutableState terminalSetCursorType:cursorType];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    [_mutableState terminalSetCursorBlinking:blinking];
}

- (iTermPromise<NSNumber *> *)terminalCursorIsBlinkingPromise {
    return [_mutableState terminalCursorIsBlinkingPromise];
}

- (void)terminalGetCursorInfoWithCompletion:(void (^)(ITermCursorType type, BOOL blinking))completion {
    [_mutableState terminalGetCursorInfoWithCompletion:completion];
}

- (void)terminalResetCursorTypeAndBlink {
    [_mutableState terminalResetCursorTypeAndBlink];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    [_mutableState terminalSetLeftMargin:scrollLeft rightMargin:scrollRight];
}

- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode {
    [_mutableState terminalSetCharset:charset toLineDrawingMode:lineDrawingMode];
}

- (BOOL)terminalLineDrawingFlagForCharset:(int)charset {
    return [_mutableState terminalLineDrawingFlagForCharset:charset];
}

- (void)terminalRemoveTabStops {
    [_mutableState terminalRemoveTabStops];
}

- (void)terminalRemoveTabStopAtCursor {
    [_mutableState terminalRemoveTabStopAtCursor];
}

- (void)terminalSetWidth:(int)width
          preserveScreen:(BOOL)preserveScreen
           updateRegions:(BOOL)updateRegions
            moveCursorTo:(VT100GridCoord)newCursorCoord
              completion:(void (^)(void))completion {
    [_mutableState terminalSetWidth:width
                     preserveScreen:preserveScreen
                      updateRegions:updateRegions
                       moveCursorTo:newCursorCoord
                         completion:completion];
}

- (void)terminalBackTab:(int)n {
    [_mutableState terminalBackTab:n];
}

- (void)terminalSetCursorX:(int)x {
    [_mutableState terminalSetCursorX:x];
}

- (void)terminalAdvanceCursorPastLastColumn {
    [_mutableState terminalAdvanceCursorPastLastColumn];
}

- (void)terminalSetCursorY:(int)y {
    [_mutableState terminalSetCursorY:y];
}

- (void)terminalEraseCharactersAfterCursor:(int)j {
    [_mutableState terminalEraseCharactersAfterCursor:j];
}

- (void)terminalPrintBuffer {
    [_mutableState terminalPrintBuffer];
}

- (void)terminalBeginRedirectingToPrintBuffer {
    [_mutableState terminalBeginRedirectingToPrintBuffer];
}

- (void)terminalPrintScreen {
    [_mutableState terminalPrintScreen];
}

- (void)terminalSetWindowTitle:(NSString *)title {
    [_mutableState terminalSetWindowTitle:title];
}

- (void)terminalSetIconTitle:(NSString *)title {
    [_mutableState terminalSetIconTitle:title];
}

- (void)terminalSetSubtitle:(NSString *)subtitle {
    [_mutableState terminalSetSubtitle:subtitle];
}

- (void)terminalCopyStringToPasteboard:(NSString *)string {
    [_mutableState terminalCopyStringToPasteboard:string];
}

- (void)terminalInsertEmptyCharsAtCursor:(int)n {
    [_mutableState terminalInsertEmptyCharsAtCursor:n];
}

- (void)terminalShiftLeft:(int)n {
    [_mutableState terminalShiftLeft:n];
}

- (void)terminalShiftRight:(int)n {
    [_mutableState terminalShiftRight:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    [_mutableState terminalInsertBlankLinesAfterCursor:n];
}

- (void)terminalDeleteCharactersAtCursor:(int)n {
    [_mutableState terminalDeleteCharactersAtCursor:n];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    [_mutableState terminalDeleteLinesAtCursor:n];
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    [_mutableState terminalSetRows:rows andColumns:columns];
}

- (void)terminalSetPixelWidth:(int)width height:(int)height {
    [_mutableState terminalSetPixelWidth:width height:height];
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    [_mutableState terminalMoveWindowTopLeftPointTo:point];
}

- (void)terminalMiniaturize:(BOOL)mini {
    [_mutableState terminalMiniaturize:mini];
}

- (void)terminalRaise:(BOOL)raise {
    [_mutableState terminalRaise:raise];
}

- (void)terminalScrollDown:(int)n {
    [_mutableState terminalScrollDown:n];
}

- (void)terminalScrollUp:(int)n {
    [_mutableState terminalScrollUp:n];
}

- (BOOL)terminalWindowIsMiniaturized {
    return [_mutableState terminalWindowIsMiniaturized];
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    return [_mutableState terminalWindowTopLeftPixelCoordinate];
}

- (int)terminalWindowWidthInPixels {
    return [_mutableState terminalWindowWidthInPixels];
}

- (int)terminalWindowHeightInPixels {
    return [_mutableState terminalWindowHeightInPixels];
}

- (int)terminalScreenHeightInCells {
    return [_mutableState terminalScreenHeightInCells];
}

- (int)terminalScreenWidthInCells {
    return [_mutableState terminalScreenWidthInCells];
}

- (NSString *)terminalIconTitle {
    return [_mutableState terminalIconTitle];
}

- (NSString *)terminalWindowTitle {
    return [_mutableState terminalWindowTitle];
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    [_mutableState terminalPushCurrentTitleForWindow:isWindow];
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    [_mutableState terminalPopCurrentTitleForWindow:isWindow];
}

- (void)terminalPostUserNotification:(NSString *)message {
    [_mutableState terminalPostUserNotification:message];
}

- (void)terminalStartTmuxModeWithDCSIdentifier:(NSString *)dcsID {
    [_mutableState terminalStartTmuxModeWithDCSIdentifier:dcsID];
}

- (void)terminalHandleTmuxInput:(VT100Token *)token {
    [_mutableState terminalHandleTmuxInput:token];
}

- (void)terminalSynchronizedUpdate:(BOOL)begin {
    [_mutableState terminalSynchronizedUpdate:begin];
}

- (VT100GridSize)terminalSizeInCells {
    return [_mutableState terminalSizeInCells];
}

- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode {
    [_mutableState terminalMouseModeDidChangeTo:mouseMode];
}

- (void)terminalNeedsRedraw {
    [_mutableState terminalNeedsRedraw];
}

- (void)terminalSetUseColumnScrollRegion:(BOOL)use {
    [_mutableState terminalSetUseColumnScrollRegion:use];
}

- (BOOL)terminalUseColumnScrollRegion {
    return [_mutableState terminalUseColumnScrollRegion];
}

- (void)terminalShowAltBuffer {
    [_mutableState terminalShowAltBuffer];
}

- (BOOL)terminalIsShowingAltBuffer {
    return [_mutableState terminalIsShowingAltBuffer];
}

- (void)terminalShowPrimaryBuffer {
    [_mutableState terminalShowPrimaryBuffer];
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    [_mutableState terminalSetRemoteHost:remoteHost];
}

- (void)terminalSetWorkingDirectoryURL:(NSString *)URLString {
    [_mutableState terminalSetWorkingDirectoryURL:URLString];
}

- (void)terminalClearScreen {
    [_mutableState terminalClearScreen];
}

- (void)terminalSaveScrollPositionWithArgument:(NSString *)argument {
    [_mutableState terminalSaveScrollPositionWithArgument:argument];
}

- (void)terminalStealFocus {
    [_mutableState terminalStealFocus];
}

- (void)terminalSetProxyIcon:(NSString *)value {
    [_mutableState terminalSetProxyIcon:value];
}

- (void)terminalClearScrollbackBuffer {
    [_mutableState terminalClearScrollbackBuffer];
}

- (void)terminalClearBuffer {
    [_mutableState terminalClearBuffer];
}

// Shell integration or equivalent.
- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)dir {
    [_mutableState terminalCurrentDirectoryDidChangeTo:dir];
}

- (void)terminalProfileShouldChangeTo:(NSString *)value {
    [_mutableState terminalProfileShouldChangeTo:value];
}

- (void)terminalAddNote:(NSString *)value show:(BOOL)show {
    [_mutableState terminalAddNote:value show:show];
}

- (void)terminalSetPasteboard:(NSString *)value {
    [_mutableState terminalSetPasteboard:value];
}

- (void)terminalWillReceiveFileNamed:(NSString *)name
                              ofSize:(NSInteger)size
                          completion:(void (^)(BOOL ok))completion {
    [_mutableState terminalWillReceiveFileNamed:name ofSize:size completion:completion];
}

- (void)terminalWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(NSInteger)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset
                                completion:(void (^)(BOOL ok))completion {
    [_mutableState terminalWillReceiveInlineFileNamed:name
                                               ofSize:size
                                                width:width
                                                units:widthUnits
                                               height:height
                                                units:heightUnits
                                  preserveAspectRatio:preserveAspectRatio
                                                inset:inset
                                           completion:completion];
}

- (void)terminalWillStartLinkWithCode:(unsigned int)code {
    return [_mutableState terminalWillStartLinkWithCode:code];
}

- (void)terminalWillEndLinkWithCode:(unsigned int)code {
    [_mutableState terminalWillEndLinkWithCode:code];
}

- (void)terminalAppendSixelData:(NSData *)data {
    [_mutableState terminalAppendSixelData:data];
}

- (void)terminalDidChangeSendModifiers {
    [_mutableState terminalDidChangeSendModifiers];
}

- (void)terminalKeyReportingFlagsDidChange {
    [_mutableState terminalKeyReportingFlagsDidChange];
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
    [_mutableState terminalDidReceiveBase64FileData:data];
}

- (void)terminalFileReceiptEndedUnexpectedly {
    [_mutableState terminalFileReceiptEndedUnexpectedly];
}

- (void)terminalRequestUpload:(NSString *)args {
    [delegate_ screenRequestUpload:args];
}

- (void)terminalBeginCopyToPasteboard {
    [_mutableState terminalBeginCopyToPasteboard];
}

- (void)terminalDidReceiveBase64PasteboardString:(NSString *)string {
    [_mutableState terminalDidReceiveBase64PasteboardString:string];
}

- (void)terminalDidFinishReceivingPasteboard {
    [_mutableState terminalDidFinishReceivingPasteboard];
}

- (void)terminalPasteboardReceiptEndedUnexpectedly {
    _mutableState.pasteboardString = nil;
}

- (void)terminalCopyBufferToPasteboard {
    [_mutableState terminalCopyBufferToPasteboard];
}

- (void)terminalAppendDataToPasteboard:(NSData *)data {
    [_mutableState terminalAppendDataToPasteboard:data];
}

- (BOOL)terminalIsTrusted {
    return [_mutableState terminalIsTrusted];
}

- (BOOL)terminalCanUseDECRQCRA {
    return [_mutableState terminalCanUseDECRQCRA];
}

- (void)terminalRequestAttention:(VT100AttentionRequestType)request {
    [_mutableState terminalRequestAttention:request];
}

- (void)terminalDisinterSession {
    [_mutableState terminalDisinterSession];
}

- (void)terminalSetBackgroundImageFile:(NSString *)filename {
    [_mutableState terminalSetBackgroundImageFile:filename];
}

- (void)terminalSetBadgeFormat:(NSString *)badge {
    [_mutableState terminalSetBadgeFormat:badge];
}

- (void)terminalSetUserVar:(NSString *)kvp {
    [_mutableState terminalSetUserVar:kvp];
}

- (void)terminalResetColor:(VT100TerminalColorIndex)n {
    [_mutableState terminalResetColor:n];
}

- (void)terminalSetForegroundColor:(NSColor *)color {
    [_mutableState terminalSetForegroundColor:color];
}

- (void)terminalSetBackgroundColor:(NSColor *)color {
    [_mutableState terminalSetBackgroundColor:color];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    [_mutableState terminalSetBoldColor:color];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    [_mutableState terminalSetSelectionColor:color];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    [_mutableState terminalSetSelectedTextColor:color];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    [_mutableState terminalSetCursorColor:color];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    [_mutableState terminalSetCursorTextColor:color];
}

- (void)terminalSetColorTableEntryAtIndex:(VT100TerminalColorIndex)n color:(NSColor *)color {
    [_mutableState terminalSetColorTableEntryAtIndex:n color:color];
}

- (void)terminalSetCurrentTabColor:(NSColor *)color {
    [_mutableState terminalSetCurrentTabColor:color];
}

- (void)terminalSetTabColorRedComponentTo:(CGFloat)color {
    [_mutableState terminalSetTabColorRedComponentTo:color];
}

- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color {
    [_mutableState terminalSetTabColorGreenComponentTo:color];
}

- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color {
    [_mutableState terminalSetTabColorBlueComponentTo:color];
}

- (BOOL)terminalFocusReportingAllowed {
    return [_mutableState terminalFocusReportingAllowed];
}

- (BOOL)terminalCursorVisible {
    return [_mutableState terminalCursorVisible];
}

- (NSColor *)terminalColorForIndex:(VT100TerminalColorIndex)index {
    return [_mutableState terminalColorForIndex:index];
}

- (int)terminalCursorX {
    return [_mutableState terminalCursorX];
}

- (int)terminalCursorY {
    return [_mutableState terminalCursorY];
}

- (BOOL)terminalWillAutoWrap {
    return [_mutableState terminalWillAutoWrap];
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    [_mutableState terminalSetCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    [_mutableState terminalSetHighlightCursorLine:highlight];
}

- (void)terminalClearCapturedOutput {
    [_mutableState terminalClearCapturedOutput];
}

- (void)terminalPromptDidStart {
    [_mutableState terminalPromptDidStart];
}

- (NSArray<NSNumber *> *)terminalTabStops {
    return [_mutableState terminalTabStops];
}

- (void)terminalSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [_mutableState terminalSetTabStops:tabStops];
}

- (void)terminalCommandDidStart {
    [_mutableState terminalCommandDidStart];
}

- (void)terminalCommandDidEnd {
    [_mutableState terminalCommandDidEnd];
}

- (void)terminalAbortCommand {
    [_mutableState terminalAbortCommand];
}

- (void)terminalSemanticTextDidStartOfType:(VT100TerminalSemanticTextType)type {
    [_mutableState terminalSemanticTextDidStartOfType:type];
}

- (void)terminalSemanticTextDidEndOfType:(VT100TerminalSemanticTextType)type {
    [_mutableState terminalSemanticTextDidEndOfType:type];
}

- (void)terminalProgressAt:(double)fraction label:(NSString *)label {
    [_mutableState terminalProgressAt:fraction label:label];
}

- (void)terminalProgressDidFinish {
    [_mutableState terminalProgressDidFinish];
}

- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode {
    [_mutableState terminalReturnCodeOfLastCommandWas:returnCode];
}

- (void)terminalFinalTermCommand:(NSArray *)argv {
    [_mutableState terminalFinalTermCommand:argv];
}

- (void)terminalSetShellIntegrationVersion:(NSString *)version {
    [_mutableState terminalSetShellIntegrationVersion:version];
}

- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue {
    [_mutableState terminalWraparoundModeDidChangeTo:newValue];
}

- (void)terminalTypeDidChange {
    [_mutableState terminalTypeDidChange];
}

- (void)terminalInsertModeDidChangeTo:(BOOL)newValue {
    [_mutableState terminalInsertModeDidChangeTo:newValue];
}

- (NSString *)terminalProfileName {
    return [_mutableState terminalProfileName];
}

- (VT100GridRect)terminalScrollRegion {
    return [_mutableState terminalScrollRegion];
}

- (int)terminalChecksumInRectangle:(VT100GridRect)rect {
    return [_mutableState terminalChecksumInRectangle:rect];
}

- (NSArray<NSString *> *)terminalSGRCodesInRectangle:(VT100GridRect)screenRect {
    return [_mutableState terminalSGRCodesInRectangle:screenRect];
}

- (NSSize)terminalCellSizeInPoints:(double *)scaleOut {
    return [_mutableState terminalCellSizeInPoints:scaleOut];
}

- (void)terminalSetUnicodeVersion:(NSInteger)unicodeVersion {
    [_mutableState terminalSetUnicodeVersion:unicodeVersion];
}

- (NSInteger)terminalUnicodeVersion {
    return [_mutableState terminalUnicodeVersion];
}

- (void)terminalSetLabel:(NSString *)label forKey:(NSString *)keyName {
    [_mutableState terminalSetLabel:label forKey:keyName];
}

- (void)terminalPushKeyLabels:(NSString *)value {
    [_mutableState terminalPushKeyLabels:value];
}

- (void)terminalPopKeyLabels:(NSString *)value {
    [_mutableState terminalPopKeyLabels:value];
}

- (void)terminalSetColorNamed:(NSString *)name to:(NSString *)colorString {
    [_mutableState terminalSetColorNamed:name to:colorString];
}

- (void)terminalCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                                           payload:(NSString *)payload {
    [_mutableState terminalCustomEscapeSequenceWithParameters:parameters
                                                      payload:payload];
}

- (void)terminalRepeatPreviousCharacter:(int)times {
    [_mutableState terminalRepeatPreviousCharacter:times];
}

- (void)terminalReportFocusWillChangeTo:(BOOL)reportFocus {
    [_mutableState terminalReportFocusWillChangeTo:reportFocus];
}

- (void)terminalPasteBracketingWillChangeTo:(BOOL)bracket {
    [_mutableState terminalPasteBracketingWillChangeTo:bracket];
}

- (void)terminalSoftAlternateScreenModeDidChange {
    [_mutableState softAlternateScreenModeDidChange];
}

- (void)terminalReportKeyUpDidChange:(BOOL)reportKeyUp {
    [_mutableState terminalReportKeyUpDidChange:reportKeyUp];
}

- (BOOL)terminalIsInAlternateScreenMode {
    return [_mutableState terminalIsInAlternateScreenMode];
}

- (NSString *)terminalTopBottomRegionString {
    return [_mutableState terminalTopBottomRegionString];
}

- (NSString *)terminalLeftRightRegionString {
    return [_mutableState terminalLeftRightRegionString];
}

- (iTermPromise<NSString *> *)terminalStringForKeypressWithCode:(unsigned short)keyCode
                                                          flags:(NSEventModifierFlags)flags
                                                     characters:(NSString *)characters
                                    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    return [_mutableState terminalStringForKeypressWithCode:keyCode
                                                      flags:flags
                                                 characters:characters
                                charactersIgnoringModifiers:charactersIgnoringModifiers];
}

- (dispatch_queue_t)terminalQueue {
    return [_mutableState terminalQueue];
}

- (iTermTokenExecutorUnpauser *)terminalPause {
    return [_mutableState terminalPause];
}

- (void)terminalApplicationKeypadModeDidChange:(BOOL)mode {
    [_mutableState terminalApplicationKeypadModeDidChange:mode];
}

- (VT100SavedColorsSlot *)terminalSavedColorsSlot {
    return [_mutableState terminalSavedColorsSlot];
}

- (void)terminalRestoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    [_mutableState terminalRestoreColorsFromSlot:slot];
}

- (int)terminalMaximumTheoreticalImageDimension {
    return [_mutableState terminalMaximumTheoreticalImageDimension];
}

- (void)terminalInsertColumns:(int)n {
    [_mutableState terminalInsertColumns:n];
}

- (void)terminalDeleteColumns:(int)n {
    [_mutableState terminalDeleteColumns:n];
}

- (void)terminalSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    [_mutableState terminalSetAttribute:sgrAttribute inRect:rect];
}

- (void)terminalToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    [_mutableState terminalToggleAttribute:sgrAttribute inRect:rect];
}

- (void)terminalCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    [_mutableState terminalCopyFrom:source to:dest];
}

- (void)terminalFillRectangle:(VT100GridRect)rect withCharacter:(unichar)inputChar {
    [_mutableState terminalFillRectangle:rect withCharacter:inputChar];
}

- (void)terminalEraseRectangle:(VT100GridRect)rect {
    [_mutableState terminalEraseRectangle:rect];
}

- (void)terminalSelectiveEraseRectangle:(VT100GridRect)rect {
    [_mutableState terminalSelectiveEraseRectangle:rect];
}

- (void)terminalSelectiveEraseInDisplay:(int)mode {
    [_mutableState terminalSelectiveEraseInDisplay:mode];
}

- (void)terminalSelectiveEraseInLine:(int)mode {
    [_mutableState terminalSelectiveEraseInLine:mode];
}

- (void)terminalProtectedModeDidChangeTo:(VT100TerminalProtectedMode)mode {
    [_mutableState terminalProtectedModeDidChangeTo:mode];
}

- (VT100TerminalProtectedMode)terminalProtectedMode {
    return [_mutableState terminalProtectedMode];
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    if (mark.entry.interval.location > _mutableState.lastCommandMark.entry.interval.location) {
        _mutableState.lastCommandMark = mark;
    }
}

#pragma mark - Triggers

- (void)mutForceCheckTriggers {
    [_mutableState forceCheckTriggers];
}

- (void)mutPerformPeriodicTriggerCheck {
    [_mutableState performPeriodicTriggerCheck];
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
