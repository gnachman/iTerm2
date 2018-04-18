//
//  iTermTextViewAccessibilityHelper.m
//  iTerm2
//
//  Created by George Nachman on 6/22/15.
//
//

#import "iTermTextViewAccessibilityHelper.h"
#import "DebugLogging.h"

@implementation iTermTextViewAccessibilityHelper {
    // This is a giant string with the entire scrollback buffer plus screen
    // concatenated with newlines for hard eol's.
    NSMutableString *_allText;
    // This is the indices at which soft newlines occur in _allText.
    NSMutableArray *_lineBreakIndexOffsets;
}

#pragma mark - Parameterized attributes

// Range in _allText of the given line.
- (NSRange)rangeOfLine:(NSUInteger)lineNumber {
    NSRange range;
    [self allText];  // Refresh _lineBreakIndexOffsets
    if (lineNumber == 0) {
        range.location = 0;
    } else {
        range.location = [[_lineBreakIndexOffsets objectAtIndex:lineNumber-1] unsignedLongValue];
    }
    if (lineNumber >= [_lineBreakIndexOffsets count]) {
        range.length = [_allText length] - range.location;
    } else {
        range.length = [[_lineBreakIndexOffsets objectAtIndex:lineNumber] unsignedLongValue] - range.location;
    }
    return range;
}

// Range in _allText of the given index.
- (NSUInteger)lineNumberOfIndex:(NSUInteger)theIndex {
    NSUInteger lineNum = 0;
    for (NSNumber *n in _lineBreakIndexOffsets) {
        NSUInteger offset = [n unsignedLongValue];
        if (offset > theIndex) {
            break;
        }
        lineNum++;
    }
    return lineNum;
}

// Line number of a location (respecting compositing chars) in _allText.
- (NSUInteger)lineNumberOfChar:(NSUInteger)location {
    NSUInteger lineNum = 0;
    for (NSNumber *n in _lineBreakIndexOffsets) {
        NSUInteger offset = [n unsignedLongValue];
        if (offset > location) {
            break;
        }
        lineNum++;
    }
    return lineNum;
}

// Number of unichar a character uses (normally 1 in English).
- (int)lengthOfChar:(screen_char_t)sct {
    return [ScreenCharToStr(&sct) length];
}

// Position, respecting compositing chars, in _allText of a line.
- (NSUInteger)offsetOfLine:(NSUInteger)accessibilityLineNumber {
    if (accessibilityLineNumber == 0) {
        return 0;
    }
    assert(accessibilityLineNumber < [_lineBreakIndexOffsets count] + 1);
    return [_lineBreakIndexOffsets[accessibilityLineNumber - 1] unsignedLongValue];
}

// Onscreen X-position of a location (respecting compositing chars) in _allText.
- (NSUInteger)columnOfChar:(NSUInteger)location inLine:(NSUInteger)accessibilityLineNumber {
    NSUInteger lineStart = [self offsetOfLine:accessibilityLineNumber];
    screen_char_t* theLine = [_delegate accessibilityHelperLineAtIndex:accessibilityLineNumber];
    assert(location >= lineStart);
    int remaining = location - lineStart;
    int i = 0;
    while (remaining > 0 && i < [_delegate accessibilityHelperWidth]) {
        remaining -= [self lengthOfChar:theLine[i++]];
    }
    return i;
}

// Index (ignoring compositing chars) of a line in _allText.
- (NSUInteger)startingIndexOfLineNumber:(NSUInteger)lineNumber {
    if (lineNumber < [_lineBreakIndexOffsets count]) {
        return [_lineBreakIndexOffsets[lineNumber] unsignedLongValue];
    } else if ([_lineBreakIndexOffsets count] > 0) {
        return [[_lineBreakIndexOffsets lastObject] unsignedLongValue];
    } else {
        return 0;
    }
}

// Range in _allText of an index (ignoring compositing chars).
- (NSRange)rangeOfIndex:(NSUInteger)theIndex {
    NSUInteger accessibilityLineNumber = [self lineNumberOfIndex:theIndex];
    screen_char_t* theLine = [_delegate accessibilityHelperLineAtIndex:accessibilityLineNumber];
    NSUInteger startingIndexOfLine = [self startingIndexOfLineNumber:accessibilityLineNumber];
    if (theIndex < startingIndexOfLine) {
        return NSMakeRange(NSNotFound, 0);
    }
    int x = theIndex - startingIndexOfLine;
    NSRange rangeOfLine = [self rangeOfLine:accessibilityLineNumber];
    NSRange range;
    range.location = rangeOfLine.location;
    for (int i = 0; i < x; i++) {
        range.location += [self lengthOfChar:theLine[i]];
    }
    range.length = [self lengthOfChar:theLine[x]];
    return range;
}

// Range, respecting compositing chars, of a character at an x,y position where 0,0 is the
// first char of the first line in the scrollback buffer.
- (NSRange)rangeOfCharAtX:(int)x y:(int)accessibilityY {
    screen_char_t *theLine = [_delegate accessibilityHelperLineAtIndex:accessibilityY];
    NSRange lineRange = [self rangeOfLine:accessibilityY];
    NSRange result = lineRange;
    for (int i = 0; i < x; i++) {
        result.location += [self lengthOfChar:theLine[i]];
    }
    result.length = [self lengthOfChar:theLine[x]];
    return result;
}

- (VT100GridCoordRange)coordRangeForAccessibilityRange:(NSRange)range {
    VT100GridCoordRange coordRange;
    coordRange.start.y = [self lineNumberOfIndex:range.location];
    coordRange.start.x = [self columnOfChar:range.location inLine:coordRange.start.y];
    if (range.length == 0) {
        coordRange.end = coordRange.start;
    } else {
        range.length--;
        coordRange.end.y = [self lineNumberOfIndex:NSMaxRange(range)];
        coordRange.end.x = [self columnOfChar:NSMaxRange(range) inLine:coordRange.end.y];
        ++coordRange.end.x;
        if (coordRange.end.x == [_delegate accessibilityHelperWidth]) {
            coordRange.end.x = 0;
            coordRange.end.y++;
        }
    }

    return coordRange;
}

- (NSRange)accessibilityRangeForCoordRange:(VT100GridCoordRange)coordRange {
    NSUInteger location1 = [self rangeOfCharAtX:coordRange.start.x y:coordRange.start.y].location;
    NSUInteger location2 = [self rangeOfCharAtX:coordRange.end.x y:coordRange.end.y].location;

    NSUInteger start = MIN(location1, location2);
    NSUInteger end = MAX(location1, location2);

    return NSMakeRange(start, end - start);
}

- (NSInteger)lineForIndex:(NSUInteger)theIndex {
    return [self lineNumberOfIndex:theIndex];
}

- (NSRange)rangeForLine:(NSUInteger)lineNumber {
    if (lineNumber >= [_lineBreakIndexOffsets count]) {
        return NSMakeRange(NSNotFound, 0);
    } else {
        return [self rangeOfLine:lineNumber];
    }
}

- (NSString *)stringForRange:(NSRange)range {
    return [_allText substringWithRange:range];
}

- (NSRange)rangeForPosition:(NSPoint)screenPosition {
    VT100GridCoord point = [_delegate accessibilityHelperCoordForPoint:screenPosition];
    if (point.y < 0) {
        return NSMakeRange(0, 0);
    } else {
        return [self rangeOfCharAtX:point.x y:point.y];
    }
}

- (NSRect)boundsForRange:(NSRange)range {
    int yStart = [self lineNumberOfChar:range.location];
    int y2 = [self lineNumberOfChar:range.location + range.length - 1];
    int xStart = [self columnOfChar:range.location inLine:yStart];
    int x2 = [self columnOfChar:range.location + range.length - 1 inLine:y2];
    ++x2;
    if (x2 == [_delegate accessibilityHelperWidth]) {
        x2 = 0;
        ++y2;
    }
    int yMin = MIN(yStart, y2);
    int yMax = MAX(yStart, y2);
    int xMin = MIN(xStart, x2);
    int xMax = MAX(xStart, x2);
    NSRect result =
        [_delegate accessibilityHelperFrameForCoordRange:VT100GridCoordRangeMake(xMin, yMin, xMax, yMax)];
    return result;
}

- (NSAttributedString *)attributedStringForRange:(NSRange)range {
    if (range.location == NSNotFound || range.length == 0) {
        return nil;
    } else {
        NSString *theString = [_allText substringWithRange:range];
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:theString];
        return attributedString;
    }
}

#pragma mark - Properties

// This is why it's slow. Unfortunately we need to unpack combining marks into
// one big string. The line buffer has one index per cell, so we can't just use
// it in place. It might be nice to ditch screen_char_t and use
// NSAttributedString's with custom attributes, but unfortunately that would
// have been a lot easier to do about five years ago.
- (NSString *)allText {
    _allText = [[NSMutableString alloc] init];
    _lineBreakIndexOffsets = [[NSMutableArray alloc] init];

    int width = [_delegate accessibilityHelperWidth];
    unichar chars[width * kMaxParts];
    int offset = 0;
    for (int i = 0; i < [_delegate accessibilityHelperNumberOfLines]; i++) {
        screen_char_t* line = [_delegate accessibilityHelperLineAtIndex:i];
        int k;
        // Get line width, store it in k
        for (k = width - 1; k >= 0; k--) {
            if (line[k].code) {
                break;
            }
        }
        int o = 0;
        // Add first width-k chars to the 'chars' array, expanding complex chars.
        for (int j = 0; j <= k; j++) {
            if (line[j].complexChar) {
                NSString* cs = ComplexCharToStr(line[j].code);
                for (int l = 0; l < [cs length]; ++l) {
                    chars[o++] = [cs characterAtIndex:l];
                }
            } else {
                if (line[j].code >= 0xf000) {
                    // Don't output private range chars to accessibility.
                    chars[o++] = 0;
                } else {
                    chars[o++] = line[j].code;
                }
            }
        }
        // Append this line to _allText.
        offset += o;
        if (k >= 0) {
            [_allText appendString:[NSString stringWithCharacters:chars length:o]];
        }
        if (line[width].code == EOL_HARD) {
            // Add a newline and update offsets arrays that track line break locations.
            [_allText appendString:@"\n"];
            ++offset;
        }
        [_lineBreakIndexOffsets addObject:[NSNumber numberWithUnsignedLong:offset]];
    }

    return _allText;
}

- (NSAccessibilityRole)role {
    return NSAccessibilityTextAreaRole;
}

- (NSString *)roleDescription {
    return NSAccessibilityRoleDescriptionForUIElement(self);
}

- (NSString *)help {
    return nil;
}

- (BOOL)focused {
    return YES;
}

- (NSString *)label {
    return @"shell";
}

- (NSInteger)numberOfCharacters {
    return [[self allText] length];
}

- (NSString *)selectedText {
    return [_delegate accessibilityHelperSelectedText];
}

- (NSRange)selectedTextRange {
    // quick fix for ZoomText for Mac - it does not query AXValue or other
    // attributes that (re)generate _allText and especially lineBreak{Char,Index}Offsets_
    // which are needed for rangeOfCharAtX:y:
    [self allText];

    VT100GridCoordRange coordRange = [_delegate accessibilityHelperSelectedRange];
    return [self accessibilityRangeForCoordRange:coordRange];
}

- (NSArray *)selectedTextRanges {
    NSRange range = [self selectedTextRange];
    return @[ [NSValue valueWithRange:range] ];
}

- (NSInteger)insertionPointLineNumber {
    VT100GridCoord coord = [_delegate accessibilityHelperCursorCoord];
    return coord.y;
}

- (NSRange)visibleCharacterRange {
    return NSMakeRange(0, [[self allText] length]);
}

- (NSURL *)currentDocumentURL {
    return [_delegate accessibilityHelperCurrentDocumentURL];
}

#pragma mark - Setters

- (void)setSelectedTextRange:(NSRange)range {
    VT100GridCoordRange coordRange = [self coordRangeForAccessibilityRange:range];
    [_delegate accessibilityHelperSetSelectedRange:coordRange];
}

@end
