//
//  iTermLogicalMovementHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/23/19.
//

#import "iTermLogicalMovementHelper.h"

#import "DebugLogging.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"

@implementation iTermLogicalMovementHelper {
    iTermSelection *_selection;
    iTermTextExtractor *_textExtractor;
    VT100GridAbsCoord _cursorCoord;
    int _width;
    long long _numberOfLines;
    long long _totalScrollbackOverflow;
}

- (instancetype)initWithTextExtractor:(iTermTextExtractor *)textExtractor
                            selection:(iTermSelection *)selection
                     cursorCoordinate:(VT100GridAbsCoord)cursorCoord
                                width:(int)width
                        numberOfLines:(long long)numberOfLines
              totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    self = [super init];
    if (self) {
        _textExtractor = textExtractor;
        _selection = selection;
        _cursorCoord = cursorCoord;
        _width = width;
        _numberOfLines = numberOfLines;
        _totalScrollbackOverflow = totalScrollbackOverflow;
    }
    return self;
}

- (VT100GridAbsCoordRange)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                                    inDirection:(PTYTextViewSelectionExtensionDirection)direction
                                             by:(PTYTextViewSelectionExtensionUnit)unit {
    // Ensure the unit is valid, since it comes from preferences.
    if (![self unitIsValid:unit]) {
        XLog(@"ERROR: Unrecognized unit enumerated value %@, treating as character.", @(unit));
        unit = kPTYTextViewSelectionExtensionUnitCharacter;
    }

    // Cancel a live selection if one is ongoing.
    if (_selection.live) {
        [_selection endLiveSelection];
    }
    iTermSubSelection *sub = _selection.allSubSelections.lastObject;
    VT100GridAbsWindowedRange existingRange;
    // Create a selection at the cursor if none exists.
    if (!sub) {
        const VT100GridAbsCoord coord = _cursorCoord;
        const VT100GridRange columnWindow = _textExtractor.logicalWindow;
        existingRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(coord.x,
                                                                                 coord.y,
                                                                                 coord.x,
                                                                                 coord.y),
                                                      columnWindow.location,
                                                      columnWindow.length);
    } else {
        const VT100GridRange columnWindow = sub.absRange.columnWindow;
        existingRange = sub.absRange;
        if (columnWindow.length > 0) {
            _textExtractor.logicalWindow = columnWindow;
        }
    }


    VT100GridAbsWindowedRange newRange = [self absRangeByExtendingRange:existingRange
                                                               endpoint:endpoint
                                                              direction:direction
                                                              extractor:_textExtractor
                                                                   unit:unit];

    // Convert the mode into an iTermSelectionMode. Only a subset of iTermSelectionModes are
    // possible which is why this uses its own enum.
    const iTermSelectionMode mode = [self selectionModeForExtensionUnit:unit];

    if (!sub) {
        [_selection beginSelectionAtAbsCoord:newRange.coordRange.start
                                        mode:mode
                                      resume:NO
                                      append:NO];
        if (unit == kPTYTextViewSelectionExtensionUnitCharacter ||
            unit == kPTYTextViewSelectionExtensionUnitMark) {
            [_selection moveSelectionEndpointTo:newRange.coordRange.end];
        } else {
            [_selection moveSelectionEndpointTo:newRange.coordRange.start];
        }
        [_selection endLiveSelection];
    } else if ([_selection absCoord:newRange.coordRange.start isBeforeAbsCoord:newRange.coordRange.end]) {
        // Is a valid range
        [_selection setLastAbsRange:newRange mode:mode];
    } else {
        // Select a single character if the range is empty or flipped. This lets you move the
        // selection around like a cursor.
        switch (endpoint) {
            case kPTYTextViewSelectionEndpointStart: {
                newRange.coordRange.end =
                [_textExtractor successorOfAbsCoordSkippingContiguousNulls:newRange.coordRange.start];
                break;
            }
            case kPTYTextViewSelectionEndpointEnd:
                newRange.coordRange.start =
                [_textExtractor predecessorOfAbsCoordSkippingContiguousNulls:newRange.coordRange.end];
                break;
        }
        [_selection setLastAbsRange:newRange mode:mode];
    }

    VT100GridAbsCoordRange range = _selection.lastAbsRange.coordRange;
    long long start = range.start.y;
    int end = range.end.y;
    static const NSInteger kExtraLinesToMakeVisible = 2;
    switch (endpoint) {
        case kPTYTextViewSelectionEndpointStart:
            end = start;
            start = MAX(0, start - kExtraLinesToMakeVisible);
            break;

        case kPTYTextViewSelectionEndpointEnd:
            start = end;
            end += kExtraLinesToMakeVisible + 1;  // plus one because of the excess region
            break;
    }

    return VT100GridAbsCoordRangeMake(range.start.x,
                                      start,
                                      range.end.x,
                                      end);
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                                       toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.start = VT100GridAbsCoordMake(0, _totalScrollbackOverflow);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                                    toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    long long maxY = MAX(0, _totalScrollbackOverflow + _numberOfLines - 1);
    newRange.coordRange.start = VT100GridAbsCoordMake(MAX(0, _width - 1), maxY);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                               toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                                 toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor lengthOfAbsLine:newRange.coordRange.start.y];
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                        toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor startOfIndentationOnAbsLine:existingRange.coordRange.start.y];
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                                          upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.start.y = MAX(_totalScrollbackOverflow, existingRange.coordRange.start.y - 1);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRange:(VT100GridAbsWindowedRange)existingRange
                                        downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    const long long maxY = _numberOfLines + _totalScrollbackOverflow;
    newRange.coordRange.start.y = MIN(maxY - 1, existingRange.coordRange.start.y + 1);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                                     toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.end = VT100GridAbsCoordMake(0, _totalScrollbackOverflow);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                                  toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    const long long maxY = MAX(_totalScrollbackOverflow, _totalScrollbackOverflow + _numberOfLines - 1);
    newRange.coordRange.end = VT100GridAbsCoordMake(MAX(0, _width - 1), maxY);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                             toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                               toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor lengthOfAbsLine:newRange.coordRange.end.y];
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                      toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor startOfIndentationOnAbsLine:existingRange.coordRange.end.y];
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                                        upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    newRange.coordRange.end.y = MAX(_totalScrollbackOverflow, existingRange.coordRange.end.y - 1);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRange:(VT100GridAbsWindowedRange)existingRange
                                      downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridAbsWindowedRange newRange = existingRange;
    const long long maxY = _numberOfLines + _totalScrollbackOverflow;
    newRange.coordRange.end.y = MIN(maxY - 1, existingRange.coordRange.end.y + 1);
    return newRange;
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRangeBack:(VT100GridAbsWindowedRange)existingRange
                                                    extractor:(iTermTextExtractor *)extractor
                                                         unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridAbsCoord coordBeforeStart =
    [extractor predecessorOfAbsCoordSkippingContiguousNulls:VT100GridAbsWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridAbsWindowedRange rangeWithCharacterBeforeStart = existingRange;
            rangeWithCharacterBeforeStart.coordRange.start = coordBeforeStart;
            return rangeWithCharacterBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridAbsWindowedRange rangeWithWordBeforeStart =
            [extractor rangeForWordAtAbsCoord:coordBeforeStart maximumLength:kLongMaximumWordLength];
            rangeWithWordBeforeStart.coordRange.end = existingRange.coordRange.end;
            rangeWithWordBeforeStart.columnWindow = existingRange.columnWindow;
            return rangeWithWordBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridAbsWindowedRange rangeWithWordBeforeStart =
            [extractor rangeForBigWordAtAbsCoord:coordBeforeStart maximumLength:kLongMaximumWordLength];
            rangeWithWordBeforeStart.coordRange.end = existingRange.coordRange.end;
            rangeWithWordBeforeStart.columnWindow = existingRange.columnWindow;
            return rangeWithWordBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridAbsWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > _totalScrollbackOverflow) {
                if (rangeWithLineBeforeStart.coordRange.start.x > rangeWithLineBeforeStart.columnWindow.location) {
                    rangeWithLineBeforeStart.coordRange.start.x = rangeWithLineBeforeStart.columnWindow.location;
                } else {
                    rangeWithLineBeforeStart.coordRange.start.y--;
                }
            }
            return rangeWithLineBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridAbsWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > _totalScrollbackOverflow) {
                long long previousMark = [self absoluteLineNumberOfMarkBeforeAbsLine:existingRange.coordRange.start.y];
                if (previousMark != -1) {
                    rangeWithLineBeforeStart.coordRange.start.y = previousMark + 1;
                    if (rangeWithLineBeforeStart.coordRange.start.y == existingRange.coordRange.start.y) {
                        previousMark = [self absoluteLineNumberOfMarkBeforeAbsLine:existingRange.coordRange.start.y - 1];
                        if (previousMark != -1) {
                            rangeWithLineBeforeStart.coordRange.start.y = previousMark + 1;
                        }
                    }
                }
                rangeWithLineBeforeStart.coordRange.start.x = existingRange.columnWindow.location;
            }
            return rangeWithLineBeforeStart;
        }
    }
    assert(false);
}

- (VT100GridAbsWindowedRange)absRangeByMovingStartOfRangeForward:(VT100GridAbsWindowedRange)existingRange
                                                       extractor:(iTermTextExtractor *)extractor
                                                            unit:(PTYTextViewSelectionExtensionUnit)unit {
    const VT100GridAbsCoord coordAfterStart =
    [extractor successorOfAbsCoordSkippingContiguousNulls:VT100GridAbsWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridAbsWindowedRange rangeExcludingFirstCharacter = existingRange;
            rangeExcludingFirstCharacter.coordRange.start = coordAfterStart;
            return rangeExcludingFirstCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridAbsCoord startCoord = VT100GridAbsWindowedRangeStart(existingRange);
            const BOOL startWasOnNull = [extractor characterAtAbsCoord:startCoord].code == 0;
            VT100GridAbsWindowedRange rangeExcludingWordAtStart = existingRange;
            rangeExcludingWordAtStart.coordRange.start =
            [extractor rangeForWordAtAbsCoord:startCoord
                                maximumLength:kLongMaximumWordLength].coordRange.end;
            // If the start of range moved from a null to a null, skip to the end of the line or past all the nulls.
            if (startWasOnNull &&
                [extractor characterAtAbsCoord:rangeExcludingWordAtStart.coordRange.start].code == 0) {
                rangeExcludingWordAtStart.coordRange.start =
                [extractor successorOfAbsCoordSkippingContiguousNulls:rangeExcludingWordAtStart.coordRange.start];
            }
            return rangeExcludingWordAtStart;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridAbsCoord startCoord = VT100GridAbsWindowedRangeStart(existingRange);
            const BOOL startWasOnNull = [extractor characterAtAbsCoord:startCoord].code == 0;
            VT100GridAbsWindowedRange rangeExcludingWordAtStart = existingRange;
            rangeExcludingWordAtStart.coordRange.start =
            [extractor rangeForBigWordAtAbsCoord:startCoord
                                   maximumLength:kLongMaximumWordLength].coordRange.end;
            // If the start of range moved from a null to a null, skip to the end of the line or past all the nulls.
            if (startWasOnNull &&
                [extractor characterAtAbsCoord:rangeExcludingWordAtStart.coordRange.start].code == 0) {
                rangeExcludingWordAtStart.coordRange.start =
                [extractor successorOfAbsCoordSkippingContiguousNulls:rangeExcludingWordAtStart.coordRange.start];
            }
            return rangeExcludingWordAtStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridAbsWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            rangeExcludingFirstLine.coordRange.start.y =
            MIN(_numberOfLines + _totalScrollbackOverflow,
                rangeExcludingFirstLine.coordRange.start.y + 1);
            return rangeExcludingFirstLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridAbsWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            const long long nextMark = [self absoluteLineNumberOfMarkAfterAbsLine:rangeExcludingFirstLine.coordRange.start.y - 1];
            if (nextMark != -1) {
                rangeExcludingFirstLine.coordRange.start.y =
                MIN(_numberOfLines + _totalScrollbackOverflow, nextMark + 1);
            }
            return rangeExcludingFirstLine;
        }
    }
    assert(false);
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRangeBack:(VT100GridAbsWindowedRange)existingRange
                                                  extractor:(iTermTextExtractor *)extractor
                                                       unit:(PTYTextViewSelectionExtensionUnit)unit {
    const VT100GridAbsCoord coordBeforeEnd =
    [extractor predecessorOfAbsCoordSkippingContiguousNulls:VT100GridAbsWindowedRangeEnd(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridAbsWindowedRange rangeExcludingLastCharacter = existingRange;
            rangeExcludingLastCharacter.coordRange.end = coordBeforeEnd;
            return rangeExcludingLastCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridAbsWindowedRange rangeExcludingWordAtEnd = existingRange;
            rangeExcludingWordAtEnd.coordRange.end =
            [extractor rangeForWordAtAbsCoord:coordBeforeEnd
                                maximumLength:kLongMaximumWordLength].coordRange.start;
            rangeExcludingWordAtEnd.columnWindow = existingRange.columnWindow;
            return rangeExcludingWordAtEnd;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridAbsWindowedRange rangeExcludingWordAtEnd = existingRange;
            rangeExcludingWordAtEnd.coordRange.end =
            [extractor rangeForBigWordAtAbsCoord:coordBeforeEnd
                                   maximumLength:kLongMaximumWordLength].coordRange.start;
            rangeExcludingWordAtEnd.columnWindow = existingRange.columnWindow;
            return rangeExcludingWordAtEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridAbsWindowedRange rangeExcludingLastLine = existingRange;
            if (existingRange.coordRange.end.x > existingRange.columnWindow.location) {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
            } else {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
                rangeExcludingLastLine.coordRange.end.y = MAX(1 + _totalScrollbackOverflow,
                                                              existingRange.coordRange.end.y - 1);
            }
            return rangeExcludingLastLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridAbsWindowedRange rangeExcludingLastLine = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _width;
            }
            rangeExcludingLastLine.coordRange.end.x = rightMargin;
            long long n = [self absoluteLineNumberOfMarkBeforeAbsLine:rangeExcludingLastLine.coordRange.end.y + 1];
            if (n != -1) {
                rangeExcludingLastLine.coordRange.end.y = MAX(1 + _totalScrollbackOverflow, n - 1);
            }
            return rangeExcludingLastLine;
        }
    }
    assert(false);
}

- (VT100GridAbsWindowedRange)absRangeByMovingEndOfRangeForward:(VT100GridAbsWindowedRange)existingRange
                                                     extractor:(iTermTextExtractor *)extractor
                                                          unit:(PTYTextViewSelectionExtensionUnit)unit {
    const VT100GridAbsCoord endCoord = VT100GridAbsWindowedRangeEnd(existingRange);
    VT100GridAbsCoord coordAfterEnd =
    [extractor successorOfAbsCoordSkippingContiguousNulls:endCoord];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridAbsWindowedRange rangeWithCharacterAfterEnd = existingRange;
            rangeWithCharacterAfterEnd.coordRange.end = coordAfterEnd;
            return rangeWithCharacterAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridAbsWindowedRange rangeWithWordAfterEnd;
            if (endCoord.x > VT100GridRangeMax(existingRange.columnWindow)) {
                rangeWithWordAfterEnd = [extractor rangeForWordAtAbsCoord:coordAfterEnd
                                                            maximumLength:kLongMaximumWordLength];
            } else {
                rangeWithWordAfterEnd = [extractor rangeForWordAtAbsCoord:endCoord
                                                            maximumLength:kLongMaximumWordLength];
            }
            rangeWithWordAfterEnd.coordRange.start = existingRange.coordRange.start;
            rangeWithWordAfterEnd.columnWindow = existingRange.columnWindow;
            return rangeWithWordAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridAbsWindowedRange rangeWithWordAfterEnd;
            if (endCoord.x > VT100GridRangeMax(existingRange.columnWindow)) {
                rangeWithWordAfterEnd = [extractor rangeForBigWordAtAbsCoord:coordAfterEnd
                                                               maximumLength:kLongMaximumWordLength];
            } else {
                rangeWithWordAfterEnd = [extractor rangeForBigWordAtAbsCoord:endCoord
                                                               maximumLength:kLongMaximumWordLength];
            }
            rangeWithWordAfterEnd.coordRange.start = existingRange.coordRange.start;
            rangeWithWordAfterEnd.columnWindow = existingRange.columnWindow;
            return rangeWithWordAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridAbsWindowedRange rangeWithLineAfterEnd = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _width;
            }
            if (existingRange.coordRange.end.x < rightMargin) {
                rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
            } else {
                rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
                rangeWithLineAfterEnd.coordRange.end.y =
                MIN(_numberOfLines + _totalScrollbackOverflow,
                    rangeWithLineAfterEnd.coordRange.end.y + 1);
            }
            return rangeWithLineAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridAbsWindowedRange rangeWithLineAfterEnd = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _width;
            }
            rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
            const long long nextMark =
            [self absoluteLineNumberOfMarkAfterAbsLine:rangeWithLineAfterEnd.coordRange.end.y];
            if (nextMark != -1) {
                rangeWithLineAfterEnd.coordRange.end.y =
                MIN(_numberOfLines + _totalScrollbackOverflow,
                    nextMark - 1);
            }
            if (rangeWithLineAfterEnd.coordRange.end.y == existingRange.coordRange.end.y) {
                const long long nextMark =
                [self absoluteLineNumberOfMarkAfterAbsLine:rangeWithLineAfterEnd.coordRange.end.y + 1];
                if (nextMark != -1) {
                    rangeWithLineAfterEnd.coordRange.end.y =
                    MIN(_numberOfLines + _totalScrollbackOverflow, nextMark - 1);
                }
            }
            return rangeWithLineAfterEnd;
        }
    }
    assert(false);
}

- (VT100GridAbsWindowedRange)absRangeByExtendingRange:(VT100GridAbsWindowedRange)existingRange
                                             endpoint:(PTYTextViewSelectionEndpoint)endpoint
                                            direction:(PTYTextViewSelectionExtensionDirection)direction
                                            extractor:(iTermTextExtractor *)extractor
                                                 unit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (endpoint) {
        case kPTYTextViewSelectionEndpointStart:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self absRangeByMovingStartOfRange:existingRange
                                              upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self absRangeByMovingStartOfRangeBack:existingRange
                                                        extractor:extractor
                                                             unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self absRangeByMovingStartOfRange:existingRange
                                            downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self absRangeByMovingStartOfRangeForward:existingRange
                                                           extractor:extractor
                                                                unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self absRangeByMovingStartOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self absRangeByMovingStartOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self absRangeByMovingStartOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self absRangeByMovingStartOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self absRangeByMovingStartOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
            }
            assert(false);
            break;

        case kPTYTextViewSelectionEndpointEnd:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self absRangeByMovingEndOfRange:existingRange
                                            upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self absRangeByMovingEndOfRangeBack:existingRange
                                                      extractor:extractor
                                                           unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self absRangeByMovingEndOfRange:existingRange
                                          downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self absRangeByMovingEndOfRangeForward:existingRange
                                                         extractor:extractor
                                                              unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self absRangeByMovingEndOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self absRangeByMovingEndOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self absRangeByMovingEndOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self absRangeByMovingEndOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self absRangeByMovingEndOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
            }
            assert(false);
            break;
    }
    assert(false);
}

- (iTermSelectionMode)selectionModeForExtensionUnit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter:
            return kiTermSelectionModeCharacter;
        case kPTYTextViewSelectionExtensionUnitWord:
        case kPTYTextViewSelectionExtensionUnitBigWord:
            return kiTermSelectionModeWord;
        case kPTYTextViewSelectionExtensionUnitLine:
            return kiTermSelectionModeLine;
        case kPTYTextViewSelectionExtensionUnitMark:
            return kiTermSelectionModeLine;
    }

    return kiTermSelectionModeCharacter;
}

- (BOOL)unitIsValid:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter:
        case kPTYTextViewSelectionExtensionUnitWord:
        case kPTYTextViewSelectionExtensionUnitBigWord:
        case kPTYTextViewSelectionExtensionUnitLine:
        case kPTYTextViewSelectionExtensionUnitMark:
            return YES;
    }
    return NO;
}

- (long long)absoluteLineNumberOfMarkAfterAbsLine:(long long)line {
    if (!self.delegate) {
        return -1;
    }
    return [self.delegate lineNumberOfMarkAfterAbsLine:line];
}

- (long long)absoluteLineNumberOfMarkBeforeAbsLine:(long long)line {
    if (!self.delegate) {
        return -1;
    }
    return [self.delegate lineNumberOfMarkBeforeAbsLine:line];
}

@end
