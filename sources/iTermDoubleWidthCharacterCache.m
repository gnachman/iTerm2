//
//  iTermDoubleWidthCharacterCache.m
//  iTerm2
//
//  Created by George Nachman on 11/26/24.
//

#import "iTermDoubleWidthCharacterCache.h"

#import "DebugLogging.h"

@interface iTermTrivialDoubleWidthCharacterCache: iTermDoubleWidthCharacterCache
@end

@implementation iTermTrivialDoubleWidthCharacterCache

- (int)offsetForWrappedLine:(int)n totalLines:(out int *)linesPtr {
    if (linesPtr) {
        *linesPtr = 0;
    }
    return n * self.width;
}

@end
@implementation iTermDoubleWidthCharacterCache

+ (NSIndexSet *)indexSetForCharacters:(const screen_char_t *)characters
                               length:(int)length
                                width:(int)width {
    NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];

    int lines = 0;
    int i = 0;
    const screen_char_t *p = characters;

    while (i + width < length) {
        // Advance i to the start of the next line
        i += width;
        ++lines;
        screen_char_t c;
        c = p[i];
        if (ScreenCharIsDWC_RIGHT(c)) {
            // Oops, the line starts with the second half of a double-width
            // character. Wrap the last character of the previous line on to
            // this line.
            i--;
            [indexSet addIndex:lines];
        }
    }
    return indexSet;
}

- (instancetype)initWithLength:(int)length
                         width:(int)width
                      indexSet:(NSIndexSet *)indexSet {
    self = [super init];
    if (self) {
        _length = length;
        _width = width;
        _indexSet = indexSet;
    }
    return self;
}

- (instancetype)initWithCharacters:(const screen_char_t *)characters
                            length:(int)length
                             width:(int)width {
    if (width < 2) {
        return nil;
    }

    NSIndexSet *indexSet = [iTermDoubleWidthCharacterCache indexSetForCharacters:characters
                                                                          length:length
                                                                           width:width];
    if (indexSet.count == 0) {
        return [[iTermTrivialDoubleWidthCharacterCache alloc] initWithLength:length
                                                                       width:width
                                                                    indexSet:indexSet];
    }

    return [self initWithLength:length width:width indexSet:indexSet];
}

- (BOOL)validForWidth:(int)width length:(int)length {
    return _width == width && _length == length;
}

- (int)offsetForWrappedLine:(int)n totalLines:(out nonnull int *)linesPtr {
    const int width = _width;
    const int length = _length;
    __block int lines = 0;
    __block int i = 0;
    __block NSUInteger lastIndex = 0;
    [_indexSet enumerateIndexesInRange:NSMakeRange(0, MAX(0, n + 1))
                               options:0
                            usingBlock:^(NSUInteger indexOfLineThatWouldStartWithRightHalf, BOOL * _Nonnull stop) {
        int numberOfLines = indexOfLineThatWouldStartWithRightHalf - lastIndex;
        lines += numberOfLines;
        i += width * numberOfLines;
        i--;
        lastIndex = indexOfLineThatWouldStartWithRightHalf;
    }];
    ITAssertWithMessage(i <= length, @"[1] i=%@ exceeds length=%@, n=%@, width=%@, cache=%@",
                        @(i),
                        @(length),
                        @(n),
                        @(width),
                        _indexSet);
    if (lines < n) {
        i += (n - lines) * width;
    }
    if (linesPtr) {
        *linesPtr = lines;
    }
    return i;
}

- (void)sanityCheckWithCharacters:(const screen_char_t *)characters length:(int)length {
    if (_width < 2) {
        return;
    }
    NSIndexSet *actual = [_indexSet copy];
    if (!actual) {
        return;
    }
    ITAssertWithMessage(length == _length, @"Length changed from %@ to %@", @(_length), @(length));
    NSIndexSet *expected = [iTermDoubleWidthCharacterCache indexSetForCharacters:characters length:length width:_width];
    ITAssertWithMessage([actual isEqualToIndexSet:expected], @"actual=%@ expected=%@", actual, expected);
}

@end
