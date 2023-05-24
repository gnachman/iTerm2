//
//  iTermCopyModeState.m
//  iTerm2
//
//  Created by George Nachman on 4/29/17.
//
//

#import "iTermCopyModeState.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "PTYTextView.h"
#import "PTYTextViewDataSource.h"

@implementation iTermCopyModeState

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = kiTermSelectionModeCharacter;
    }
    return self;
}

- (void)dealloc {
    [_textView release];
    [super dealloc];
}

- (BOOL)moveBackwardWord {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionLeft unit:kPTYTextViewSelectionExtensionUnitWord];
}

- (BOOL)moveForwardWord {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionRight unit:kPTYTextViewSelectionExtensionUnitWord];
}

- (BOOL)moveBackwardBigWord {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionLeft unit:kPTYTextViewSelectionExtensionUnitBigWord];
}

- (BOOL)moveForwardBigWord {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionRight unit:kPTYTextViewSelectionExtensionUnitBigWord];
}

- (BOOL)moveLeft {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionLeft unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveRight {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionRight unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveUp {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionUp unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveDown {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionDown unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)scrollUpIfPossible {
    return [self scroll:kPTYTextViewSelectionExtensionDirectionUp];
}

- (BOOL)scrollDownIfPossible {
    return [self scroll:kPTYTextViewSelectionExtensionDirectionDown];
}

- (BOOL)moveToStartOfNextLine {
    BOOL moved = [self moveDown];
    if (moved) {
        [self moveToStartOfLine];
    }
    return moved;
}

- (BOOL)moveToStartOfLine {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionStartOfLine unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveToEndOfLine {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionEndOfLine unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)pageUp {
    BOOL moved = NO;
    for (int i = 0; i < _textView.dataSource.height; i++) {
        if ([self moveUp]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)pageUpHalfScreen {
    BOOL moved = NO;
    for (int i = 0; i < _textView.dataSource.height / 2; i++) {
        [self scrollUpIfPossible];
        if ([self moveUp]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)pageDown {
    BOOL moved = NO;
    for (int i = 0; i < _textView.dataSource.height; i++) {
        if ([self moveDown]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)pageDownHalfScreen {
    BOOL moved = NO;
    for (int i = 0; i < _textView.dataSource.height; i++) {
        [self scrollUpIfPossible];
        if ([self moveDown]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)scrollUp {
    if ([_textView rangeOfVisibleLines].location == 0) {
        // Can't scroll up.
        return NO;
    }
    if ([self scrollUpIfPossible]) {
        return NO;
    }
    const BOOL moved = [self moveUp];
    if (moved) {
        [self scrollUpIfPossible];
    }
    return moved;
}

- (BOOL)scrollDown {
    const VT100GridRange visibleLines = [_textView rangeOfVisibleLines];
    if (visibleLines.location + visibleLines.length == _textView.dataSource.numberOfLines) {
        // Can't scroll down.
        return NO;
    }
    if ([self scrollDownIfPossible]) {
        return NO;
    }
    const BOOL moved = [self moveDown];
    if (moved) {
        [self scrollDownIfPossible];
    }
    return moved;
}

- (BOOL)moveToBottomOfVisibleArea {
    BOOL moved = NO;
    VT100GridRange range = [_textView rangeOfVisibleLines];
    int destination = range.location + range.length - 1;
    int n = MAX(0, destination - _coord.y);
    for (int i = 0; i < n; i++) {
        if ([self moveDown]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)moveToMiddleOfVisibleArea {
    BOOL moved = NO;
    VT100GridRange range = [_textView rangeOfVisibleLines];
    int destination = range.location + range.length / 2;
    int n = destination - _coord.y;

    for (int i = 0; i < abs(n); i++) {
        BOOL result;
        if (n < 0) {
            result = [self moveUp];
        } else {
            result = [self moveDown];
        }
        if (result) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)moveToTopOfVisibleArea {
    BOOL moved = NO;
    VT100GridRange range = [_textView rangeOfVisibleLines];
    int destination = range.location;
    int n = MAX(0, _coord.y - destination);
    for (int i = 0; i < n; i++) {
        if ([self moveUp]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)previousMark {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionLeft unit:kPTYTextViewSelectionExtensionUnitMark];
}

- (BOOL)nextMark {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionRight unit:kPTYTextViewSelectionExtensionUnitMark];
}

- (BOOL)moveToStart {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionTop unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveToEnd {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionBottom unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (BOOL)moveToStartOfIndentation {
    return [self moveInDirection:kPTYTextViewSelectionExtensionDirectionStartOfIndentation unit:kPTYTextViewSelectionExtensionUnitCharacter];
}

- (void)setSelecting:(BOOL)selecting {
    if (selecting == _selecting) {
        return;
    }
    _selecting = selecting;
    if (selecting) {
        _start = _coord;
    }
}

- (void)swap {
    VT100GridCoord temp = _coord;
    _coord = _start;
    _start = temp;
}

- (void)setMode:(iTermSelectionMode)mode {
    _mode = mode;
    if (_selecting && mode == kiTermSelectionModeLine) {
        const long long overflow = _textView.dataSource.totalScrollbackOverflow;
        [_textView.selection beginSelectionAtAbsCoord:VT100GridAbsCoordFromCoord(_start, overflow)
                                         mode:_mode
                                       resume:NO
                                       append:NO];
        [_textView.selection moveSelectionEndpointTo:VT100GridAbsCoordFromCoord(_coord, overflow)];
        [_textView.selection endLiveSelection];
    }
}

#pragma mark - Private

- (PTYTextViewSelectionEndpoint)endpointWithDirection:(PTYTextViewSelectionExtensionDirection)direction {
    switch (VT100GridCoordOrder(_start, _coord)) {
        case NSOrderedSame:
            if (direction == kPTYTextViewSelectionExtensionDirectionLeft || direction == kPTYTextViewSelectionExtensionDirectionUp) {
                return kPTYTextViewSelectionEndpointStart;
            } else {
                return kPTYTextViewSelectionEndpointEnd;
            }
        case NSOrderedAscending:
            return kPTYTextViewSelectionEndpointEnd;
        case NSOrderedDescending:
            return kPTYTextViewSelectionEndpointStart;
    }
}

- (VT100GridWindowedRange)trivialRange {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(_coord.x, _coord.y, 0, 0), 0, 0);
}

- (iTermTextExtractor *)extractor {
    return [[[iTermTextExtractor alloc] initWithDataSource:_textView.dataSource] autorelease];
}

- (VT100GridCoord)coordFromSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint {
    iTermSubSelection *sub = _textView.selection.allSubSelections.firstObject;
    const long long overflow = _textView.dataSource.totalScrollbackOverflow;
    if (endpoint == kPTYTextViewSelectionEndpointEnd) {
        return VT100GridCoordFromAbsCoord(sub.absRange.coordRange.end, overflow, NULL);
    } else {
        return VT100GridCoordFromAbsCoord(sub.absRange.coordRange.start, overflow, NULL);
    }
}

- (BOOL)scroll:(PTYTextViewSelectionExtensionDirection)direction {
    const VT100GridRange visibleLines = _textView.rangeOfVisibleLines;
    switch (direction) {
        case kPTYTextViewSelectionExtensionDirectionUp:
            if (_coord.y + 1 == visibleLines.location + visibleLines.length) {
                return NO;
            }
            [_textView lockScroll];
            [_textView scrollLineUp:nil];
            return YES;

        case kPTYTextViewSelectionExtensionDirectionDown:
            if (_coord.y == visibleLines.location) {
                return NO;
            }
            [_textView lockScroll];
            [_textView scrollLineDown:nil];
            return YES;

        case kPTYTextViewSelectionExtensionDirectionLeft:
        case kPTYTextViewSelectionExtensionDirectionRight:
        case kPTYTextViewSelectionExtensionDirectionStartOfLine:
        case kPTYTextViewSelectionExtensionDirectionEndOfLine:
        case kPTYTextViewSelectionExtensionDirectionTop:
        case kPTYTextViewSelectionExtensionDirectionBottom:
        case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
            assert(NO);
            break;
    }
    return NO;
}

- (BOOL)moveInDirection:(PTYTextViewSelectionExtensionDirection)direction
                   unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord before = _coord;

    // Move coord
    iTermTextExtractor *extractor = [self extractor];
    [extractor restrictToLogicalWindowIncludingCoord:_coord];
    VT100GridWindowedRange windowedRange = [self trivialRange];
    windowedRange.columnWindow = [extractor logicalWindow];
    const long long overflow = _textView.dataSource.totalScrollbackOverflow;
    const VT100GridAbsWindowedRange absWindowedRange = VT100GridAbsWindowedRangeFromWindowedRange(windowedRange, overflow);
    iTermLogicalMovementHelper *helper = [_textView logicalMovementHelperForCursorCoordinate:_textView.cursorCoord];
    const VT100GridAbsWindowedRange range = [helper absRangeByExtendingRange:absWindowedRange
                                                                    endpoint:kPTYTextViewSelectionEndpointStart
                                                                   direction:direction
                                                                   extractor:extractor
                                                                        unit:unit];
    _coord = VT100GridCoordFromAbsCoord(range.coordRange.start, overflow, nil);

    // Make a new selection
    if (_selecting) {
        [_textView.selection beginSelectionAtAbsCoord:VT100GridAbsCoordFromCoord(_start, overflow)
                                                 mode:_mode
                                               resume:NO
                                               append:NO];
        [_textView.selection moveSelectionEndpointTo:VT100GridAbsCoordFromCoord(_coord, overflow)];
        [_textView.selection endLiveSelection];
    }
    [_textView scrollLineNumberRangeIntoView:VT100GridRangeMake(_coord.y, 1)];
    return !VT100GridCoordEquals(before, _coord);
}

@end
