//
//  iTermBackgroundColorRun.m
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import "iTermBackgroundColorRun.h"

static void iTermMakeBackgroundColorRun(iTermBackgroundColorRun *run,
                                        screen_char_t *theLine,
                                        VT100GridCoord coord,
                                        iTermTextExtractor *extractor,
                                        NSIndexSet *selectedIndexes,
                                        NSData *matches,
                                        int width) {
    if (theLine[coord.x].code == DWC_SKIP && !theLine[coord.x].complexChar) {
        run->selected = NO;
    } else {
        run->selected = [selectedIndexes containsIndex:coord.x];
    }
    if (matches) {
        // Test if this char is a highlighted match from a Find.
        const int theIndex = coord.x / 8;
        const int bitMask = 1 << (coord.x & 7);
        const char *matchBytes = (const char *)matches.bytes;
        run->isMatch = theIndex < [matches length] && (matchBytes[theIndex] & bitMask);
    } else {
        run->isMatch = NO;
    }
    if (theLine[coord.x].image) {
        run->bgColor = run->bgGreen = run->bgBlue = ALTSEM_DEFAULT;
        run->bgColorMode = ColorModeAlternate;
    } else {
        run->bgColor = theLine[coord.x].backgroundColor;
        run->bgGreen = theLine[coord.x].bgGreen;
        run->bgBlue = theLine[coord.x].bgBlue;
        run->bgColorMode = theLine[coord.x].backgroundColorMode;
    }
}

@implementation iTermBackgroundColorRunsInLine

+ (void)addBackgroundRun:(iTermBackgroundColorRun *)run
                 toArray:(NSMutableArray *)runs
                endingAt:(int)end {  // end is the location after the last location in the run
    // Update the range's length.
    NSRange range = run->range;
    range.length = end - range.location;
    run->range = range;

    // Add it to the array.
    iTermBoxedBackgroundColorRun *box = [[[iTermBoxedBackgroundColorRun alloc] init] autorelease];
    memcpy(box.valuePointer, run, sizeof(*run));
    [runs addObject:box];
}


+ (instancetype)backgroundRunsInLine:(screen_char_t *)theLine
                          lineLength:(int)width
                                 row:(int)row
                     selectedIndexes:(NSIndexSet *)selectedIndexes
                         withinRange:(NSRange)charRange
                             matches:(NSData *)matches
                            anyBlink:(BOOL *)anyBlinkPtr
                       textExtractor:(iTermTextExtractor *)extractor
                                   y:(CGFloat)y
                                line:(int)line {
    NSMutableArray *runs = [NSMutableArray array];
    iTermBackgroundColorRun previous;
    iTermBackgroundColorRun current;
    BOOL first = YES;
    int j;
    for (j = charRange.location; j < charRange.location + charRange.length; j++) {
        int x = j;
        if (theLine[j].code == DWC_RIGHT) {
            x = j - 1;
            if (x < 0) {
                // AFAIK this only happens in tests, but it's a nice safety in case things go sideways.
                continue;
            }
        }
        iTermMakeBackgroundColorRun(&current,
                                    theLine,
                                    VT100GridCoordMake(x, row),
                                    extractor,
                                    selectedIndexes,
                                    matches,
                                    width);
        if (theLine[x].blink) {
            *anyBlinkPtr = YES;
        }
        if (first) {
            current.range = NSMakeRange(j, 0);
            first = NO;
        } else if (!iTermBackgroundColorRunsEqual(&current, &previous)) {
            [self addBackgroundRun:&previous toArray:runs endingAt:j];

            current.range = NSMakeRange(j, 0);
        }

        previous = current;
    }
    if (!first) {
        [self addBackgroundRun:&current toArray:runs endingAt:j];
    }

    iTermBackgroundColorRunsInLine *backgroundColorRuns =
        [[[iTermBackgroundColorRunsInLine alloc] init] autorelease];
    backgroundColorRuns.array = runs;
    backgroundColorRuns.y = y;
    backgroundColorRuns.line = line;
    return backgroundColorRuns;
}

- (void)dealloc {
    [_array release];
    [super dealloc];
}

@end

@implementation iTermBoxedBackgroundColorRun {
    iTermBackgroundColorRun _value;
}

- (void)dealloc {
    [_backgroundColor release];
    [_unprocessedBackgroundColor release];
    [super dealloc];
}

- (iTermBackgroundColorRun *)valuePointer {
    return &_value;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToBoxedBackgroundColorRun:other];
}

- (BOOL)isEqualToBoxedBackgroundColorRun:(iTermBoxedBackgroundColorRun *)other {
    return (iTermBackgroundColorRunsEqual(&other->_value, &_value) &&
            NSEqualRanges(other->_value.range, _value.range));
}

@end

