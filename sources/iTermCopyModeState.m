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

- (BOOL)pageDown {
    BOOL moved = NO;
    for (int i = 0; i < _textView.dataSource.height; i++) {
        if ([self moveDown]) {
            moved = YES;
        }
    }
    return moved;
}

- (BOOL)moveToBottomOfVisibleArea {
    BOOL moved = NO;
    VT100GridRange range = [_textView rangeOfVisibleLines];
    int destination = range.location + range.length;
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
        [_textView.selection beginSelectionAt:_start
                                         mode:_mode
                                       resume:NO
                                       append:NO];
        [_textView.selection moveSelectionEndpointTo:_coord];
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
    if (endpoint == kPTYTextViewSelectionEndpointEnd) {
        return sub.range.coordRange.end;
    } else {
        return sub.range.coordRange.start;
    }
}

- (BOOL)moveInDirection:(PTYTextViewSelectionExtensionDirection)direction
                   unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord before = _coord;

    // Move coord
    iTermTextExtractor *extractor = [self extractor];
    [extractor restrictToLogicalWindowIncludingCoord:_coord];
    VT100GridWindowedRange windowedRange = [self trivialRange];
    windowedRange.columnWindow = [extractor logicalWindow];
    VT100GridWindowedRange range = [_textView rangeByExtendingRange:windowedRange
                                                           endpoint:kPTYTextViewSelectionEndpointStart
                                                          direction:direction
                                                          extractor:extractor
                                                               unit:unit];
    _coord = range.coordRange.start;

    // Make a new selection
    if (_selecting) {
        [_textView.selection beginSelectionAt:_start
                                         mode:_mode
                                       resume:NO
                                       append:NO];
        [_textView.selection moveSelectionEndpointTo:_coord];
        [_textView.selection endLiveSelection];
    }
    return !VT100GridCoordEquals(before, _coord);
}

@end
