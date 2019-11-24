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
    VT100GridCoord _cursorCoord;
    int _width;
    int _numberOfLines;
}

- (instancetype)initWithTextExtractor:(iTermTextExtractor *)textExtractor
                            selection:(iTermSelection *)selection
                     cursorCoordinate:(VT100GridCoord)cursorCoord
                                width:(int)width
                        numberOfLines:(int)numberOfLines {
    self = [super init];
    if (self) {
        _textExtractor = textExtractor;
        _selection = selection;
        _cursorCoord = cursorCoord;
        _width = width;
        _numberOfLines = numberOfLines;
    }
    return self;
}

- (VT100GridCoordRange)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
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
    VT100GridWindowedRange existingRange;
    // Create a selection at the cursor if none exists.
    if (!sub) {
        VT100GridCoord coord = _cursorCoord;
        VT100GridRange columnWindow = _textExtractor.logicalWindow;
        existingRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y),
                                                   columnWindow.location,
                                                   columnWindow.length);
    } else {
        VT100GridRange columnWindow = sub.range.columnWindow;
        existingRange = sub.range;
        if (columnWindow.length > 0) {
            _textExtractor.logicalWindow = columnWindow;
        }
    }


    VT100GridWindowedRange newRange = [self rangeByExtendingRange:existingRange
                                                         endpoint:endpoint
                                                        direction:direction
                                                        extractor:_textExtractor
                                                             unit:unit];

    // Convert the mode into an iTermSelectionMode. Only a subset of iTermSelectionModes are
    // possible which is why this uses its own enum.
    iTermSelectionMode mode = [self selectionModeForExtensionUnit:unit];

    if (!sub) {
        [_selection beginSelectionAt:newRange.coordRange.start
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
    } else if ([_selection coord:newRange.coordRange.start isBeforeCoord:newRange.coordRange.end]) {
        // Is a valid range
        [_selection setLastRange:newRange mode:mode];
    } else {
        // Select a single character if the range is empty or flipped. This lets you move the
        // selection around like a cursor.
        switch (endpoint) {
            case kPTYTextViewSelectionEndpointStart:
                newRange.coordRange.end =
                    [_textExtractor successorOfCoordSkippingContiguousNulls:newRange.coordRange.start];
                break;
            case kPTYTextViewSelectionEndpointEnd:
                newRange.coordRange.start =
                    [_textExtractor predecessorOfCoordSkippingContiguousNulls:newRange.coordRange.end];
                break;
        }
        [_selection setLastRange:newRange mode:mode];
    }

    VT100GridCoordRange range = _selection.lastRange.coordRange;
    int start = range.start.y;
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

    return VT100GridCoordRangeMake(range.start.x,
                                   start,
                                   range.end.x,
                                   end);
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                 toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start = VT100GridCoordMake(0, 0);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                              toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = MAX(0, _numberOfLines - 1);
    newRange.coordRange.start = VT100GridCoordMake(MAX(0, _width - 1), maxY);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                         toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                         toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor lengthOfLine:newRange.coordRange.start.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                  toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor startOfIndentationOnLine:existingRange.coordRange.start.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                    upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.y = MAX(0, existingRange.coordRange.start.y - 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                  downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = _numberOfLines;
    newRange.coordRange.start.y = MIN(maxY - 1, existingRange.coordRange.start.y + 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                               toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end = VT100GridCoordMake(0, 0);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                            toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = MAX(0, _numberOfLines - 1);
    newRange.coordRange.end = VT100GridCoordMake(MAX(0, _width - 1), maxY);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                       toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                         toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor lengthOfLine:newRange.coordRange.end.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor startOfIndentationOnLine:existingRange.coordRange.end.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                                  upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.y = MAX(0, existingRange.coordRange.end.y - 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                                downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = _numberOfLines;
    newRange.coordRange.end.y = MIN(maxY - 1, existingRange.coordRange.end.y + 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRangeBack:(VT100GridWindowedRange)existingRange
                                              extractor:(iTermTextExtractor *)extractor
                                                   unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordBeforeStart =
        [extractor predecessorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeWithCharacterBeforeStart = existingRange;
            rangeWithCharacterBeforeStart.coordRange.start = coordBeforeStart;
            return rangeWithCharacterBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeWithWordBeforeStart =
                [extractor rangeForWordAt:coordBeforeStart maximumLength:kLongMaximumWordLength];
            rangeWithWordBeforeStart.coordRange.end = existingRange.coordRange.end;
            rangeWithWordBeforeStart.columnWindow = existingRange.columnWindow;
            return rangeWithWordBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridWindowedRange rangeWithWordBeforeStart =
                [extractor rangeForBigWordAt:coordBeforeStart maximumLength:kLongMaximumWordLength];
            rangeWithWordBeforeStart.coordRange.end = existingRange.coordRange.end;
            rangeWithWordBeforeStart.columnWindow = existingRange.columnWindow;
            return rangeWithWordBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > 0) {
                if (rangeWithLineBeforeStart.coordRange.start.x > rangeWithLineBeforeStart.columnWindow.location) {
                    rangeWithLineBeforeStart.coordRange.start.x = rangeWithLineBeforeStart.columnWindow.location;
                } else {
                    rangeWithLineBeforeStart.coordRange.start.y--;
                }
            }
            return rangeWithLineBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > 0) {
                int previousMark = [self lineNumberOfMarkBeforeLine:existingRange.coordRange.start.y];
                if (previousMark != -1) {
                    rangeWithLineBeforeStart.coordRange.start.y = previousMark + 1;
                    if (rangeWithLineBeforeStart.coordRange.start.y == existingRange.coordRange.start.y) {
                        previousMark = [self lineNumberOfMarkBeforeLine:existingRange.coordRange.start.y - 1];
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

- (VT100GridWindowedRange)rangeByMovingStartOfRangeForward:(VT100GridWindowedRange)existingRange
                                                 extractor:(iTermTextExtractor *)extractor
                                                      unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordAfterStart =
        [extractor successorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeExcludingFirstCharacter = existingRange;
            rangeExcludingFirstCharacter.coordRange.start = coordAfterStart;
            return rangeExcludingFirstCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridCoord startCoord = VT100GridWindowedRangeStart(existingRange);
            BOOL startWasOnNull = [extractor characterAt:startCoord].code == 0;
            VT100GridWindowedRange rangeExcludingWordAtStart = existingRange;
            rangeExcludingWordAtStart.coordRange.start =
            [extractor rangeForWordAt:startCoord  maximumLength:kLongMaximumWordLength].coordRange.end;
            // If the start of range moved from a null to a null, skip to the end of the line or past all the nulls.
            if (startWasOnNull &&
                [extractor characterAt:rangeExcludingWordAtStart.coordRange.start].code == 0) {
                rangeExcludingWordAtStart.coordRange.start =
                [extractor successorOfCoordSkippingContiguousNulls:rangeExcludingWordAtStart.coordRange.start];
            }
            return rangeExcludingWordAtStart;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridCoord startCoord = VT100GridWindowedRangeStart(existingRange);
            BOOL startWasOnNull = [extractor characterAt:startCoord].code == 0;
            VT100GridWindowedRange rangeExcludingWordAtStart = existingRange;
            rangeExcludingWordAtStart.coordRange.start =
            [extractor rangeForBigWordAt:startCoord  maximumLength:kLongMaximumWordLength].coordRange.end;
            // If the start of range moved from a null to a null, skip to the end of the line or past all the nulls.
            if (startWasOnNull &&
                [extractor characterAt:rangeExcludingWordAtStart.coordRange.start].code == 0) {
                rangeExcludingWordAtStart.coordRange.start =
                [extractor successorOfCoordSkippingContiguousNulls:rangeExcludingWordAtStart.coordRange.start];
            }
            return rangeExcludingWordAtStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            rangeExcludingFirstLine.coordRange.start.y =
            MIN(_numberOfLines,
                rangeExcludingFirstLine.coordRange.start.y + 1);
            return rangeExcludingFirstLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            int nextMark = [self lineNumberOfMarkAfterLine:rangeExcludingFirstLine.coordRange.start.y - 1];
            if (nextMark != -1) {
                rangeExcludingFirstLine.coordRange.start.y =
                    MIN(_numberOfLines, nextMark + 1);
            }
            return rangeExcludingFirstLine;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByMovingEndOfRangeBack:(VT100GridWindowedRange)existingRange
                                            extractor:(iTermTextExtractor *)extractor
                                                 unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordBeforeEnd =
    [extractor predecessorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeEnd(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeExcludingLastCharacter = existingRange;
            rangeExcludingLastCharacter.coordRange.end = coordBeforeEnd;
            return rangeExcludingLastCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeExcludingWordAtEnd = existingRange;
            rangeExcludingWordAtEnd.coordRange.end =
            [extractor rangeForWordAt:coordBeforeEnd maximumLength:kLongMaximumWordLength].coordRange.start;
            rangeExcludingWordAtEnd.columnWindow = existingRange.columnWindow;
            return rangeExcludingWordAtEnd;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridWindowedRange rangeExcludingWordAtEnd = existingRange;
            rangeExcludingWordAtEnd.coordRange.end =
            [extractor rangeForBigWordAt:coordBeforeEnd maximumLength:kLongMaximumWordLength].coordRange.start;
            rangeExcludingWordAtEnd.columnWindow = existingRange.columnWindow;
            return rangeExcludingWordAtEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeExcludingLastLine = existingRange;
            if (existingRange.coordRange.end.x > existingRange.columnWindow.location) {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
            } else {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
                rangeExcludingLastLine.coordRange.end.y = MAX(1, existingRange.coordRange.end.y - 1);
            }
            return rangeExcludingLastLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeExcludingLastLine = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _width;
            }
            rangeExcludingLastLine.coordRange.end.x = rightMargin;
            int n = [self lineNumberOfMarkBeforeLine:rangeExcludingLastLine.coordRange.end.y + 1];
            if (n != -1) {
                rangeExcludingLastLine.coordRange.end.y = MAX(1, n - 1);
            }
            return rangeExcludingLastLine;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByMovingEndOfRangeForward:(VT100GridWindowedRange)existingRange
                                               extractor:(iTermTextExtractor *)extractor
                                                    unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord endCoord = VT100GridWindowedRangeEnd(existingRange);
    VT100GridCoord coordAfterEnd =
        [extractor successorOfCoordSkippingContiguousNulls:endCoord];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeWithCharacterAfterEnd = existingRange;
            rangeWithCharacterAfterEnd.coordRange.end = coordAfterEnd;
            return rangeWithCharacterAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeWithWordAfterEnd;
            if (endCoord.x > VT100GridRangeMax(existingRange.columnWindow)) {
                rangeWithWordAfterEnd = [extractor rangeForWordAt:coordAfterEnd maximumLength:kLongMaximumWordLength];
            } else {
                rangeWithWordAfterEnd = [extractor rangeForWordAt:endCoord maximumLength:kLongMaximumWordLength];
            }
            rangeWithWordAfterEnd.coordRange.start = existingRange.coordRange.start;
            rangeWithWordAfterEnd.columnWindow = existingRange.columnWindow;
            return rangeWithWordAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitBigWord: {
            VT100GridWindowedRange rangeWithWordAfterEnd;
            if (endCoord.x > VT100GridRangeMax(existingRange.columnWindow)) {
                rangeWithWordAfterEnd = [extractor rangeForBigWordAt:coordAfterEnd maximumLength:kLongMaximumWordLength];
            } else {
                rangeWithWordAfterEnd = [extractor rangeForBigWordAt:endCoord maximumLength:kLongMaximumWordLength];
            }
            rangeWithWordAfterEnd.coordRange.start = existingRange.coordRange.start;
            rangeWithWordAfterEnd.columnWindow = existingRange.columnWindow;
            return rangeWithWordAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeWithLineAfterEnd = existingRange;
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
                MIN(_numberOfLines,
                    rangeWithLineAfterEnd.coordRange.end.y + 1);
            }
            return rangeWithLineAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeWithLineAfterEnd = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _width;
            }
            rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
            int nextMark =
                [self lineNumberOfMarkAfterLine:rangeWithLineAfterEnd.coordRange.end.y];
            if (nextMark != -1) {
                rangeWithLineAfterEnd.coordRange.end.y =
                    MIN(_numberOfLines,
                        nextMark - 1);
            }
            if (rangeWithLineAfterEnd.coordRange.end.y == existingRange.coordRange.end.y) {
                int nextMark =
                    [self lineNumberOfMarkAfterLine:rangeWithLineAfterEnd.coordRange.end.y + 1];
                if (nextMark != -1) {
                    rangeWithLineAfterEnd.coordRange.end.y =
                        MIN(_numberOfLines, nextMark - 1);
                }
            }
            return rangeWithLineAfterEnd;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByExtendingRange:(VT100GridWindowedRange)existingRange
                                       endpoint:(PTYTextViewSelectionEndpoint)endpoint
                                      direction:(PTYTextViewSelectionExtensionDirection)direction
                                      extractor:(iTermTextExtractor *)extractor
                                           unit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (endpoint) {
        case kPTYTextViewSelectionEndpointStart:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self rangeByMovingStartOfRange:existingRange
                                           upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self rangeByMovingStartOfRangeBack:existingRange
                                                     extractor:extractor
                                                          unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self rangeByMovingStartOfRange:existingRange
                                         downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self rangeByMovingStartOfRangeForward:existingRange
                                                        extractor:extractor
                                                             unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self rangeByMovingStartOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self rangeByMovingStartOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self rangeByMovingStartOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self rangeByMovingStartOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self rangeByMovingStartOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
            }
            assert(false);
            break;

        case kPTYTextViewSelectionEndpointEnd:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self rangeByMovingEndOfRange:existingRange
                                         upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self rangeByMovingEndOfRangeBack:existingRange
                                                   extractor:extractor
                                                        unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self rangeByMovingEndOfRange:existingRange
                                       downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self rangeByMovingEndOfRangeForward:existingRange
                                                      extractor:extractor
                                                           unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self rangeByMovingEndOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self rangeByMovingEndOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self rangeByMovingEndOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self rangeByMovingEndOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self rangeByMovingEndOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
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

- (int)lineNumberOfMarkAfterLine:(int)line {
    if (!self.delegate) {
        return -1;
    }
    return [self.delegate lineNumberOfMarkAfterLine:line];
}

- (int)lineNumberOfMarkBeforeLine:(int)line {
    if (!self.delegate) {
        return -1;
    }
    return [self.delegate lineNumberOfMarkAfterLine:line];
}

@end
