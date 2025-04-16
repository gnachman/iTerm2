//
//  iTermBackgroundColorRun.m
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import "iTermBackgroundColorRun.h"
#import "iTerm2SharedARC-Swift.h"

static void iTermMakeBackgroundColorRun(iTermBackgroundColorRun *run,
                                        const screen_char_t *theLine,
                                        VT100GridCoord coord,
                                        int visualColumn,
                                        NSIndexSet *selectedIndexes,
                                        NSData *matches,
                                        int width) {
    if (ScreenCharIsDWC_SKIP(theLine[coord.x])) {
        run->selected = NO;
    } else {
        run->selected = [selectedIndexes containsIndex:visualColumn];
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
    if (theLine[coord.x].image && !theLine[coord.x].virtualPlaceholder) {
        run->bgColor = run->bgGreen = run->bgBlue = ALTSEM_DEFAULT;
        run->bgColorMode = ColorModeAlternate;
    } else {
        run->bgColor = theLine[coord.x].backgroundColor;
        run->bgGreen = theLine[coord.x].bgGreen;
        run->bgBlue = theLine[coord.x].bgBlue;
        run->bgColorMode = theLine[coord.x].backgroundColorMode;
        run->beneathFaintText = !!theLine[coord.x].faint;
    }
}

@implementation iTermBackgroundColorRunsInLine

static NSRange NSMakeRangeFromEndpointsInclusive(NSUInteger start, NSUInteger inclusiveEnd) {
    if (start > inclusiveEnd) {
        return NSMakeRangeFromEndpointsInclusive(inclusiveEnd, start);
    }
    return NSMakeRange(start, inclusiveEnd - start + 1);
}

+ (void)addBackgroundRun:(iTermBackgroundColorRun *)run
                 toArray:(NSMutableArray *)runs
           endingAtModel:(int)modelEnd // modelEnd is the location after the last location in the run
                  visual:(int)visualEnd {  // visualEnd could be before or after the existing visualEnd. This one *is* included.
    // Update the range's length. We assume that model locations increase monotonically.
    NSRange modelRange = run->modelRange;
    modelRange.length = modelEnd - modelRange.location;
    run->modelRange = modelRange;

    if (!NSLocationInRange(visualEnd, run->visualRange)) {
        if (visualEnd < run->visualRange.location) {
            run->visualRange = NSMakeRangeFromEndpointsInclusive(visualEnd, NSMaxRange(run->visualRange) - 1);
        } else {
            run->visualRange = NSMakeRangeFromEndpointsInclusive(run->visualRange.location, visualEnd);
        }
    }

    // Add it to the array.
    iTermBoxedBackgroundColorRun *box = [[[iTermBoxedBackgroundColorRun alloc] init] autorelease];
    memcpy(box.valuePointer, run, sizeof(*run));
    [runs addObject:box];
}

+ (instancetype)backgroundRunsInLine:(const screen_char_t *)theLine
                          lineLength:(int)width
                    sourceLineNumber:(int)sourceLineNumber
                   displayLineNumber:(int)displayLineNumber
                     selectedIndexes:(NSIndexSet *)selectedIndexes
                         withinRange:(NSRange)charRange
                             matches:(NSData *)matches
                            anyBlink:(BOOL *)anyBlinkPtr
                                   y:(CGFloat)y
                                bidi:(iTermBidiDisplayInfo *)bidi {
    NSMutableArray *runs = [NSMutableArray array];
    iTermBackgroundColorRun previous;
    iTermBackgroundColorRun current;
    BOOL first = YES;
    int j;
    const int32_t *bidiLUT = bidi.lut;
    const int32_t bidiLUTLength = bidi.numberOfCells;

    int lastVisualColumn = -1;
    int visualColumnForSelection = -1;  // visual column, but for DWC_RIGHT is the preceding cell. Used to make selection extend into DWC_RIGHT.
    int visualColumn = -1;
    for (j = charRange.location; j < charRange.location + charRange.length; j++) {
        lastVisualColumn = visualColumn;
        int x = j;
        if (ScreenCharIsDWC_RIGHT(theLine[j])) {
            x = j - 1;
            if (x < 0) {
                // AFAIK this only happens in tests, but it's a nice safety in case things go sideways.
                continue;
            }
        }
        if (x < bidiLUTLength) {
            visualColumnForSelection = bidiLUT[x];
        } else {
            visualColumnForSelection = x;
        }
        if (j < bidiLUTLength) {
            visualColumn = bidiLUT[j];
        } else {
            visualColumn = j;
        }
        iTermMakeBackgroundColorRun(&current,
                                    theLine,
                                    VT100GridCoordMake(x, displayLineNumber),
                                    visualColumnForSelection,
                                    selectedIndexes,
                                    matches,
                                    width);
        if (theLine[x].blink) {
            *anyBlinkPtr = YES;
        }
        if (first) {
            current.modelRange = NSMakeRange(j, 0);
            current.visualRange = NSMakeRange(visualColumn, 1);
            first = NO;
        } else if (!iTermBackgroundColorRunsEqual(&current, &previous)) {
            // Color changed so start a new run.
            [self addBackgroundRun:&previous toArray:runs endingAtModel:j visual:lastVisualColumn];

            current.modelRange = NSMakeRange(j, 0);
            current.visualRange = NSMakeRange(visualColumn, 1);
        } else if (visualColumn != lastVisualColumn + 1) {
            // Might need to extend an existing range.
            if (![self extendRunInRuns:runs logicalIndex:j visualColumn:visualColumn value:&current]) {
                // Have to start a new range.
                [self addBackgroundRun:&previous toArray:runs endingAtModel:j visual:lastVisualColumn];

                current.modelRange = NSMakeRange(j, 0);
                current.visualRange = NSMakeRange(visualColumn, 1);
            }
        }

        previous = current;
    }
    if (!first) {
        [self addBackgroundRun:&current toArray:runs endingAtModel:j visual:lastVisualColumn];
    }

    iTermBackgroundColorRunsInLine *backgroundColorRuns =
        [[[iTermBackgroundColorRunsInLine alloc] init] autorelease];
    backgroundColorRuns.array = runs;
    backgroundColorRuns.y = y;
    backgroundColorRuns.line = displayLineNumber;
    backgroundColorRuns.sourceLine = sourceLineNumber;
    return backgroundColorRuns;
}

+ (BOOL)extendRunInRuns:(NSMutableArray<iTermBoxedBackgroundColorRun *> *)runs
           logicalIndex:(int)logicalIndex
           visualColumn:(int)visualColumn
                  value:(const iTermBackgroundColorRun *)run {
    const NSInteger i = [runs indexOfObjectPassingTest:^BOOL(iTermBoxedBackgroundColorRun *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj isAdjacentToVisualColumn:visualColumn] && iTermBackgroundColorRunsEqual(run, obj.valuePointer);
    }];
    if (i == NSNotFound) {
        return NO;
    }
    [runs[i] extendWithVisualColumn:visualColumn];
    return YES;
}

+ (instancetype)defaultRunOfLength:(int)width
                               row:(int)row
                                 y:(CGFloat)y {
    const screen_char_t defaultCharacter = { 0 };

    iTermBackgroundColorRun run;
    iTermMakeBackgroundColorRun(&run,
                                &defaultCharacter,
                                VT100GridCoordMake(0, 0),
                                0,
                                nil,
                                nil,
                                width);
    run.modelRange = NSMakeRange(0, width);
    run.visualRange = NSMakeRange(0, width);
    NSMutableArray *runs = [NSMutableArray array];
    [self addBackgroundRun:&run toArray:runs endingAtModel:width visual:width];

    iTermBackgroundColorRunsInLine *backgroundColorRuns =
    [[[iTermBackgroundColorRunsInLine alloc] init] autorelease];
    backgroundColorRuns.array = runs;
    backgroundColorRuns.y = y;
    backgroundColorRuns.line = row;
    backgroundColorRuns.sourceLine = row;
    return backgroundColorRuns;
}

- (void)dealloc {
    [_array release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p line=%@ numberEquiv=%@ runs:%@>",
            self.class, self, @(self.line), @(self.numberOfEquivalentRows), self.array];
}

- (iTermBackgroundColorRun *)runAtVisualIndex:(int)x {
    for (iTermBoxedBackgroundColorRun *box in self.array) {
        if (x >= box.valuePointer->visualRange.location && x < NSMaxRange(box.valuePointer->visualRange)) {
            return box.valuePointer;
        }
    }
    return nil;
}

- (iTermBackgroundColorRun *)lastRun {
    return self.array.lastObject.valuePointer;
}

@end

@implementation iTermBoxedBackgroundColorRun {
    iTermBackgroundColorRun _value;
}

+ (instancetype)boxedBackgroundColorRunWithValue:(iTermBackgroundColorRun)value {
    iTermBoxedBackgroundColorRun *run = [[[self alloc] init] autorelease];
    if (run) {
        run->_value = value;
    }
    return run;
}

- (void)dealloc {
    [_backgroundColor release];
    [_unprocessedBackgroundColor release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p findMatch=%@ selected=%@ modelRange=%@ visualRange=%@ backgroundColor=%@>",
            self.class,
            self,
            @(_value.isMatch),
            @(_value.selected),
            NSStringFromRange(_value.modelRange),
            NSStringFromRange(_value.visualRange),
            self.backgroundColor];
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
            NSEqualRanges(other->_value.modelRange, _value.modelRange) &&
            NSEqualRanges(other->_value.visualRange, _value.visualRange));
}

- (BOOL)isAdjacentToVisualColumn:(int)c {
    return _value.visualRange.location == c + 1 || NSMaxRange(_value.visualRange) == c;
}

- (void)extendWithVisualColumn:(int)c {
    NSRange range = NSMakeRange(c, 1);
    range = NSUnionRange(range, _value.visualRange);
    _value.visualRange = range;
}

@end

