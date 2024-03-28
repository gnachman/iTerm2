//
//  iTermBackgroundColorRun.m
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import "iTermBackgroundColorRun.h"

static void iTermMakeBackgroundColorRun(iTermBackgroundColorRun *run,
                                        const screen_char_t *theLine,
                                        VT100GridCoord coord,
                                        NSIndexSet *selectedIndexes,
                                        NSData *matches,
                                        int width,
                                        BOOL nonSelectedCommand) {
    if (ScreenCharIsDWC_SKIP(theLine[coord.x])) {
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
        run->beneathFaintText = !!theLine[coord.x].faint;
    }
    run->nonSelectedCommand = nonSelectedCommand;
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


+ (instancetype)backgroundRunsInLine:(const screen_char_t *)theLine
                          lineLength:(int)width
                    sourceLineNumber:(int)sourceLineNumber
                   displayLineNumber:(int)displayLineNumber
                     selectedIndexes:(NSIndexSet *)selectedIndexes
                         withinRange:(NSRange)charRange
                             matches:(NSData *)matches
                            anyBlink:(BOOL *)anyBlinkPtr
                                   y:(CGFloat)y
                  nonSelectedCommand:(BOOL)nonSelectedCommand {
    NSMutableArray *runs = [NSMutableArray array];
    iTermBackgroundColorRun previous;
    iTermBackgroundColorRun current;
    BOOL first = YES;
    int j;
    for (j = charRange.location; j < charRange.location + charRange.length; j++) {
        int x = j;
        if (ScreenCharIsDWC_RIGHT(theLine[j])) {
            x = j - 1;
            if (x < 0) {
                // AFAIK this only happens in tests, but it's a nice safety in case things go sideways.
                continue;
            }
        }
        iTermMakeBackgroundColorRun(&current,
                                    theLine,
                                    VT100GridCoordMake(x, displayLineNumber),
                                    selectedIndexes,
                                    matches,
                                    width,
                                    nonSelectedCommand);
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
    backgroundColorRuns.line = displayLineNumber;
    backgroundColorRuns.sourceLine = sourceLineNumber;
    return backgroundColorRuns;
}

+ (instancetype)defaultRunOfLength:(int)width
                               row:(int)row
                                 y:(CGFloat)y
                nonSelectedCommand:(BOOL)nonSelectedCommand {
    const screen_char_t defaultCharacter = { 0 };

    iTermBackgroundColorRun run;
    iTermMakeBackgroundColorRun(&run,
                                &defaultCharacter,
                                VT100GridCoordMake(0, 0),
                                nil,
                                nil,
                                width,
                                nonSelectedCommand);
    run.range = NSMakeRange(0, width);
    NSMutableArray *runs = [NSMutableArray array];
    [self addBackgroundRun:&run toArray:runs endingAt:width];

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

- (iTermBackgroundColorRun *)runAtIndex:(int)x {
    for (iTermBoxedBackgroundColorRun *box in self.array) {
        if (x >= box.valuePointer->range.location && x < NSMaxRange(box.valuePointer->range)) {
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
    return [NSString stringWithFormat:@"<%@: %p selected=%@ range=%@ backgroundColor=%@>",
            self.class,
            self,
            @(_value.selected),
            NSStringFromRange(_value.range),
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
            NSEqualRanges(other->_value.range, _value.range));
}

@end

