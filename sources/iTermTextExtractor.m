//
//  iTermTextExtractor.m
//  iTerm
//
//  Created by George Nachman on 2/17/14.
//
//

#import "iTermTextExtractor.h"
#import "DebugLogging.h"
#import "iTermImageInfo.h"
#import "iTermPreferences.h"
#import "iTermSystemVersion.h"
#import "iTermURLStore.h"
#import "NSStringITerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "RegexKitLite.h"
#import "PreferencePanel.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"

typedef NS_ENUM(NSUInteger, iTermAlphaNumericDefinition) {
    iTermAlphaNumericDefinitionNarrow,
    iTermAlphaNumericDefinitionUserDefined,
    iTermAlphaNumericDefinitionUnixCommands,
};

// Must find at least this many divider chars in a row for it to count as a divider.
static const int kNumCharsToSearchForDivider = 8;

const NSInteger kReasonableMaximumWordLength = 1000;
const NSInteger kLongMaximumWordLength = 100000;

@implementation iTermTextExtractor {
    id<iTermTextDataSource> _dataSource;
    VT100GridRange _logicalWindow;

    BOOL _shouldCacheLines;
    int _cachedLineNumber;
    screen_char_t *_cachedLine;
}

+ (instancetype)textExtractorWithDataSource:(id<iTermTextDataSource>)dataSource {
    return [[[self alloc] initWithDataSource:dataSource] autorelease];
}

+ (NSCharacterSet *)wordSeparatorCharacterSet
{
    NSMutableCharacterSet *charset = [[[NSMutableCharacterSet alloc] init] autorelease];
    [charset formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];

    NSMutableCharacterSet *complement = [[[NSMutableCharacterSet alloc] init] autorelease];
    [complement formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
    [complement addCharactersInString:[iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]];
    [complement addCharactersInRange:NSMakeRange(DWC_RIGHT, 1)];
    [complement addCharactersInRange:NSMakeRange(DWC_SKIP, 1)];
    [charset formUnionWithCharacterSet:[complement invertedSet]];

    return charset;
}

- (instancetype)initWithDataSource:(id<iTermTextDataSource>)dataSource {
    self = [super init];
    if (self) {
        _dataSource = dataSource;
        _logicalWindow = VT100GridRangeMake(0, [dataSource width]);
    }
    return self;
}

- (BOOL)hasLogicalWindow {
    return !(_logicalWindow.location == 0 && [self xLimit] == [_dataSource width]);
}

- (void)restrictToLogicalWindowIncludingCoord:(VT100GridCoord)coord {
    NSIndexSet *possibleDividers = [self possibleColumnDividerIndexesAround:coord];
    __block int dividerBefore = 0;
    __block int dividerAfter = -1;
    [possibleDividers enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if ([self coordContainsColumnDivider:VT100GridCoordMake(idx, coord.y)]) {
            if (idx < coord.x && idx > dividerBefore) {
                dividerBefore = (int)idx + 1;
            } else if (idx > coord.x) {
                dividerAfter = (int)idx;
                *stop = YES;
            }
        }
    }];
    if (dividerAfter == -1) {
        dividerAfter = [_dataSource width];
    }
    _logicalWindow.location = dividerBefore;
    _logicalWindow.length = dividerAfter - dividerBefore;
}

- (NSString *)fastWordAt:(VT100GridCoord)location {
    location = [self coordLockedToWindow:location];
    iTermTextExtractorClass theClass =
        [self classForCharacter:[self characterAt:location]];
    if (theClass == kTextExtractorClassDoubleWidthPlaceholder) {
        VT100GridCoord predecessor = [self predecessorOfCoord:location];
        if (predecessor.x != location.x || predecessor.y != location.y) {
            return [self fastWordAt:predecessor];
        }
    } else if (theClass == kTextExtractorClassOther) {
        return nil;
    }

    const int xLimit = [self xLimit];
    const int width = [_dataSource width];
    int numberOfLines = [_dataSource numberOfLines];
    if (location.y >= numberOfLines) {
        return nil;
    }
    __block int iterations = 0;
    const int maxLength = 20;
    const BOOL windowTouchesLeftMargin = (_logicalWindow.location == 0);
    const BOOL windowTouchesRightMargin = (xLimit == width);
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(location.x,
                                                           location.y,
                                                           width,
                                                           location.y + 1);
    __block BOOL foundWord = (theClass = kTextExtractorClassWord);
    NSMutableString *word = [NSMutableString string];
    if (theClass == kTextExtractorClassWord) {
        // Search forward for the end of the word if the cursor was over a letter.
        [self enumerateCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                               _logicalWindow.location,
                                                               _logicalWindow.length)
                          charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
                              if (++iterations == maxLength) {
                                  return YES;
                              }
                              iTermTextExtractorClass newClass = [self classForCharacter:theChar definitionOfAlphanumeric:iTermAlphaNumericDefinitionUnixCommands];
                              if (newClass == kTextExtractorClassWord) {
                                  foundWord = YES;
                                  if (theChar.complexChar ||
                                      theChar.code < ITERM2_PRIVATE_BEGIN ||
                                      theChar.code > ITERM2_PRIVATE_END) {
                                      NSString *s = [self stringForCharacter:theChar];
                                      [word appendString:s];
                                  }
                                  return NO;
                              } else {
                                  return foundWord;
                              }
                          }
                           eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                               return [self shouldStopEnumeratingWithCode:code
                                                                 numNulls:numPrecedingNulls
                                                  windowTouchesLeftMargin:windowTouchesLeftMargin
                                                 windowTouchesRightMargin:windowTouchesRightMargin
                                                         ignoringNewlines:NO];
                           }];
    }
    if (iterations == maxLength) {
        return nil;
    }

    // Search backward for the beginning of the word
    theRange = VT100GridCoordRangeMake(0, 0, location.x, location.y);
    [self enumerateInReverseCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                    _logicalWindow.location,
                                                                    _logicalWindow.length)
                               charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                                   if (++iterations == maxLength) {
                                       return YES;
                                   }
                                   iTermTextExtractorClass newClass = [self classForCharacter:theChar definitionOfAlphanumeric:iTermAlphaNumericDefinitionUnixCommands];
                                   if (newClass == kTextExtractorClassWord) {
                                       foundWord = YES;
                                       if (theChar.complexChar ||
                                           theChar.code < ITERM2_PRIVATE_BEGIN ||
                                           theChar.code > ITERM2_PRIVATE_END) {
                                           NSString *s = [self stringForCharacter:theChar];
                                           [word insertString:s atIndex:0];
                                       }
                                       return NO;
                                   } else {
                                       return foundWord;
                                   }

                               }
                                eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                                    return [self shouldStopEnumeratingWithCode:code
                                                                      numNulls:numPrecedingNulls
                                                       windowTouchesLeftMargin:windowTouchesLeftMargin
                                                      windowTouchesRightMargin:windowTouchesRightMargin
                                                              ignoringNewlines:NO];
                                }];
    if (iterations == maxLength) {
        return nil;
    }
    if (foundWord && word.length) {
        return word;
    } else {
        return nil;
    }
}

- (NSURL *)urlOfHypertextLinkAt:(VT100GridCoord)coord urlId:(out NSString **)urlId {
    screen_char_t c = [self characterAt:coord];
    *urlId = [[iTermURLStore sharedInstance] paramWithKey:@"id" forCode:c.urlCode];
    return [[iTermURLStore sharedInstance] urlForCode:c.urlCode];
}

- (VT100GridWindowedRange)rangeOfCoordinatesAround:(VT100GridCoord)origin
                                   maximumDistance:(int)maximumDistance
                                       passingTest:(BOOL(^)(screen_char_t *c, VT100GridCoord coord))block {
    VT100GridCoord coord = origin;
    VT100GridCoord previousCoord = origin;
    coord = [self predecessorOfCoord:coord];
    screen_char_t c = [self characterAt:coord];
    int distanceLeft = maximumDistance;
    while (distanceLeft > 0 && !VT100GridCoordEquals(coord, previousCoord) && block(&c, coord)) {
        previousCoord = coord;
        coord = [self predecessorOfCoord:coord];
        c = [self characterAt:coord];
        distanceLeft--;
    }

    VT100GridWindowedRange range;
    range.columnWindow = _logicalWindow;
    range.coordRange.start = previousCoord;

    coord = origin;
    previousCoord = origin;
    coord = [self successorOfCoord:coord];
    c = [self characterAt:coord];
    distanceLeft = maximumDistance;
    while (distanceLeft > 0 && !VT100GridCoordEquals(coord, previousCoord) && block(&c, coord)) {
        previousCoord = coord;
        coord = [self successorOfCoord:coord];
        c = [self characterAt:coord];
        distanceLeft--;
    }

    range.coordRange.end = coord;

    return range;
}

- (int)startOfIndentationOnLine:(int)line {
    if (line >= [_dataSource numberOfLines]) {
        return 0;
    }
    __block int result = 0;
    [self enumerateCharsInRange:VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, line, [_dataSource width], line), _logicalWindow.location, _logicalWindow.length) charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
        if (!theChar.complexChar && (theChar.code == ' ' || theChar.code == '\t' || theChar.code == 0 || theChar.code == TAB_FILLER)) {
            result++;
            return NO;
        } else {
            return YES;
        }
    } eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
        return YES;
    }];
    return result;
}

// The maximum length is a rough guideline. You might get a word up to twice as long.
- (VT100GridWindowedRange)rangeForWordAt:(VT100GridCoord)location
                           maximumLength:(NSInteger)maximumLength {
    ITBetaAssert(location.y >= 0, @"Location has negative Y");
    if (location.y < 0) {
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1),
                                          _logicalWindow.location, _logicalWindow.length);
    }

    DLog(@"Compute range for word at %@, max length %@", VT100GridCoordDescription(location), @(maximumLength));
    DLog(@"These special chars will be treated as alphanumeric: %@", [iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]);

    location = [self coordLockedToWindow:location];
    iTermTextExtractorClass theClass =
        [self classForCharacter:[self characterAt:location]];
    DLog(@"Initial class for '%@' at %@ is %@",
         [self stringForCharacter:[self characterAt:location]], VT100GridCoordDescription(location), @(theClass));
    if (theClass == kTextExtractorClassDoubleWidthPlaceholder) {
        DLog(@"Location is a DWC placeholder. Try again with predecessor");
        VT100GridCoord predecessor = [self predecessorOfCoord:location];
        if (predecessor.x != location.x || predecessor.y != location.y) {
            return [self rangeForWordAt:predecessor maximumLength:maximumLength];
        }
    }

    if (theClass == kTextExtractorClassOther) {
        DLog(@"Character class is other, select one character.");
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                    location.y,
                                                                    location.x + 1,
                                                                    location.y)];
    }

    // String composed of the characters found to be in the word, excluding private range characters.
    NSMutableString *stringFromLocation = [NSMutableString string];
    NSMutableArray *coords = [NSMutableArray array];

    // Has one entry for each cell in the word before `location`. Stores the
    // length of the string at that cell. Typically 1, but can be long for
    // surrogate pair and composed characters.
    NSMutableArray<NSNumber *> *stringLengthsInPrefix = [NSMutableArray array];

    // Has one entry for each cell in the word after `location`. Stores the
    // index into `stringFromLocation` where that cell's string begins.
    NSMutableArray<NSNumber *> *indexesInSuffix = [NSMutableArray array];

    const int xLimit = [self xLimit];
    const int width = [_dataSource width];
    const BOOL windowTouchesLeftMargin = (_logicalWindow.location == 0);
    const BOOL windowTouchesRightMargin = (xLimit == width);
    int numberOfLines = [_dataSource numberOfLines];
    if (location.y >= numberOfLines) {
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1),
                                          _logicalWindow.location, _logicalWindow.length);
    }
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(location.x,
                                                           location.y,
                                                           width,
                                                           [_dataSource numberOfLines] - 1);
    __block NSInteger iterations = 0;
    // Search forward for the end of the word.
    DLog(@"** Begin searching forward for the end of the word");
    [self enumerateCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                           _logicalWindow.location,
                                                           _logicalWindow.length)
                      charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
                          DLog(@"Character at %@ is '%@'", VT100GridCoordDescription(coord), [self stringForCharacter:theChar]);
                          ++iterations;
                          if (iterations > maximumLength) {
                              DLog(@"Max length hit when searching forwards");
                              return YES;
                          }
                          iTermTextExtractorClass newClass = [self classForCharacter:theChar];
                          DLog(@"Class is %@", @(newClass));

                          BOOL isInWord = (newClass == kTextExtractorClassDoubleWidthPlaceholder ||
                                           newClass == theClass);
                          if (isInWord) {
                              DLog(@"Is in word");
                              if (theChar.complexChar ||
                                  theChar.code < ITERM2_PRIVATE_BEGIN ||
                                  theChar.code > ITERM2_PRIVATE_END) {
                                  [indexesInSuffix addObject:@(stringFromLocation.length)];
                                  [stringFromLocation appendString:(ScreenCharToStr(&theChar) ?: @"")];
                                  [coords addObject:[NSValue valueWithGridCoord:coord]];
                              }
                          }
                          return !isInWord;
                      }
                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                           return [self shouldStopEnumeratingWithCode:code
                                                             numNulls:numPrecedingNulls
                                              windowTouchesLeftMargin:windowTouchesLeftMargin
                                             windowTouchesRightMargin:windowTouchesRightMargin
                                                     ignoringNewlines:NO];
                       }];

    // Search backward for the start of the word.
    theRange = VT100GridCoordRangeMake(0, 0, location.x, location.y);

    // We want to iterate backward over the string and concatenate characters in reverse order.
    // Appending to the start of a NSMutableString is very slow, but appending to the start of
    // a NSMutableArray is fast. So we build an array of tiny strings in the reverse order of how
    // they appear and then concatenate them after the enumeration.
    NSMutableArray *substrings = [NSMutableArray array];
    DLog(@"** Begin searching backward for the end of the word");
    iterations = 0;
    [self enumerateInReverseCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                    _logicalWindow.location,
                                                                    _logicalWindow.length)
                               charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                                   DLog(@"Character at %@ is '%@'", VT100GridCoordDescription(coord), [self stringForCharacter:theChar]);
                                   ++iterations;
                                   if (iterations > maximumLength) {
                                       DLog(@"Max length hit when searching backwards");
                                       return YES;
                                   }
                                   iTermTextExtractorClass newClass = [self classForCharacter:theChar];
                                   DLog(@"Class is %@", @(newClass));
                                   BOOL isInWord = (newClass == kTextExtractorClassDoubleWidthPlaceholder ||
                                                    newClass == theClass);
                                   if (isInWord) {
                                       DLog(@"Is in word");
                                       if (theChar.complexChar ||
                                           theChar.code < ITERM2_PRIVATE_BEGIN || theChar.code > ITERM2_PRIVATE_END) {
                                           NSString *theString = ScreenCharToStr(&theChar);
                                           if (theString) {
                                               [substrings insertObject:theString atIndex:0];
                                               [coords insertObject:[NSValue valueWithGridCoord:coord] atIndex:0];
                                               [stringLengthsInPrefix insertObject:@(theString.length) atIndex:0];
                                           }
                                       }
                                   }
                                   return !isInWord;
                               }
                                eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                                    return [self shouldStopEnumeratingWithCode:code
                                                                      numNulls:numPrecedingNulls
                                                       windowTouchesLeftMargin:windowTouchesLeftMargin
                                                      windowTouchesRightMargin:windowTouchesRightMargin
                                                              ignoringNewlines:NO];

                                }];
    NSString *stringBeforeLocation = [substrings componentsJoinedByString:@""];

    if (!coords.count) {
        DLog(@"Found no coords");
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                    location.y,
                                                                    location.x,
                                                                    location.y)];
    }

    if (theClass != kTextExtractorClassWord) {
        DLog(@"Not word class");
        VT100GridCoord start = [[coords firstObject] gridCoordValue];
        VT100GridCoord end = [[coords lastObject] gridCoordValue];
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(start.x,
                                                                    start.y,
                                                                    end.x + 1,
                                                                    end.y)];
    }

    __block VT100GridWindowedRange result;
    [self performBlockWithLineCache:^{
        DLog(@"An alphanumeric character was selected. Begin language-specific logic");

        // An alphanumeric character was selected. This is where it gets interesting.

        // We have now retrieved the longest possible string that could have a word. This is because we
        // are more permissive than the OS about what can be in a word (the user can add punctuation,
        // for example, making foo/bar a word if / belongs to the “characters considered part of a
        // word.”) Now we want to shrink the range. For non-English languages, there is an added
        // wrinkle: in issue 4325 we see that 翻真的 consists of two words: 翻 and 真的. The OS
        // (presumably by using ICU's text boundary analysis code) knows how to do the segmentation.

        NSString *string = [stringBeforeLocation stringByAppendingString:stringFromLocation];
        NSAttributedString *attributedString = [[[NSAttributedString alloc] initWithString:string attributes:@{}] autorelease];

        // Will be in 1:1 correspondence with `coords`.
        // The string in the cell at `coords[i]` starts at index `indexes[i]`.
        NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
        NSInteger prefixLength = 0;
        for (NSNumber *length in stringLengthsInPrefix) {
            [indexes addObject:@(prefixLength)];
            prefixLength += length.integerValue;
        }
        for (NSNumber *index in indexesInSuffix) {
            [indexes addObject:@(prefixLength + index.integerValue)];
        }

        DLog(@"indexes: %@", indexes);

        // Set end to an index that is not in the middle of an OS-defined-word. It will be at the start
        // of a word or on a whitelisted character.
        BOOL previousCharacterWasWhitelisted = YES;

        // `end` can index into `coords` and `indexes`.
        NSInteger end = stringLengthsInPrefix.count;
        while (end < coords.count) {
            DLog(@"Consider end=%@ at %@", @(end), VT100GridCoordDescription([coords[end] gridCoordValue]));
            if ([self isWhitelistedAlphanumericAtCoord:[coords[end] gridCoordValue]]) {
                DLog(@"Is whitelisted");
                ++end;
                previousCharacterWasWhitelisted = YES;
            } else if (previousCharacterWasWhitelisted) {
                DLog(@"Previous character was whitelisted");
                NSInteger index = [indexes[end] integerValue];
                NSRange range = [attributedString doubleClickAtIndex:index];

                end = [self indexInSortedArray:indexes
                     withValueGreaterOrEqualTo:NSMaxRange(range)
                          searchingForwardFrom:end];
                previousCharacterWasWhitelisted = NO;
            } else {
                DLog(@"Not whitelisted, previous character not whitelisted");
                break;
            }
        }

        // Same thing but in reverse.

        NSInteger start;
        const NSUInteger numberOfCellsInPrefix = stringLengthsInPrefix.count;

        // `provisionalStart` is an initial place to begin looking for the start of the word. This is
        // used to compute the initial value of `start`, later on. If there is a suffix it is the index
        // of the first character of the suffix. Otherwise it is the index of the last character of
        // the prefix.
        NSUInteger provisionalStart = numberOfCellsInPrefix;
        if (coords.count == numberOfCellsInPrefix) {
            // Earlier, we bailed out if `coords.count` was 0. Since `coords.count` > 0 and
            // `coords.count` equals `numberOfCellsInPrefix` and
            // `numberOfCellsInPrefix` equals `provisionalStart`,
           //  then transitively `provisionalStart` > 0.
            provisionalStart -= 1;
        }

        DLog(@"Provisional start is %@", @(provisionalStart));

        // First, ensure that start is either at the start of a word (as defined by the OS) or on a
        // whitelisted character.
        if ([self isWhitelistedAlphanumericAtCoord:[coords[provisionalStart] gridCoordValue]]) {
            // On a whitelisted character. We'll search back past all of them.
            DLog(@"Starting on a whitelisted character");
            previousCharacterWasWhitelisted = YES;
            start = provisionalStart;
        } else {
            // Not on a whitelisted character. Set start to the index of the cell of the first character
            // of the word enclosing the cell indexed to by `provisionalStart`.
            DLog(@"Not starting on a whitelisted character");
            previousCharacterWasWhitelisted = NO;
            NSUInteger location = [attributedString doubleClickAtIndex:[indexes[provisionalStart] integerValue]].location;
            start = [self indexInSortedArray:indexes
                  withValueLessThanOrEqualTo:location
                       searchingBackwardFrom:provisionalStart];
        }

        //  Move back until two consecutive OS-defined words are found or we reach the start of the string.
        while (start > 0) {
            DLog(@"Consider start=%@ at %@", @(start-1), VT100GridCoordDescription([coords[start - 1] gridCoordValue]));
            if ([self isWhitelistedAlphanumericAtCoord:[coords[start - 1] gridCoordValue]]) {
                DLog(@"Is whitelisted");
                --start;
                previousCharacterWasWhitelisted = YES;
            } else if (previousCharacterWasWhitelisted) {
                DLog(@"Previous character was whitelisted");
                NSUInteger location = [attributedString doubleClickAtIndex:[indexes[start - 1] integerValue]].location;
                start = [self indexInSortedArray:indexes
                      withValueLessThanOrEqualTo:location
                           searchingBackwardFrom:provisionalStart];
                previousCharacterWasWhitelisted = NO;
            } else {
                DLog(@"Not whitelisted, previous character not whitelisted");
                break;
            }
        }

        VT100GridCoord startCoord = [coords[start] gridCoordValue];
        VT100GridCoord endCoord = [coords[end - 1] gridCoordValue];

        // It's a half open interval so advance endCoord by one.
        endCoord.x += 1;

        // Make sure to include the DWC_RIGHT after the last character to be selected.
        if (endCoord.x < [self xLimit] && [self haveDoubleWidthExtensionAt:endCoord]) {
            endCoord.x += 1;
        }
            result = [self windowedRangeWithRange:VT100GridCoordRangeMake(startCoord.x,
                                                                          startCoord.y,
                                                                          endCoord.x,
                                                                          endCoord.y)];
    }];
    return result;
}

// Make characterAt: much faster when called with the same line number over and over again. Assumes
// the line buffer won't be mutated while it's running.
- (void)performBlockWithLineCache:(void (^)(void))block {
    assert(!_shouldCacheLines);
    _shouldCacheLines = YES;
    block();
    _shouldCacheLines = NO;
    _cachedLine = nil;
}

// Returns 0 if no value can be found less than or equal to `maximumValue`.
// This could be a binary search but it's better to keep it simple.
- (NSInteger)indexInSortedArray:(NSArray<NSNumber *> *)indexes
     withValueLessThanOrEqualTo:(NSInteger)maximumValue
          searchingBackwardFrom:(NSInteger)start {
    if (start <= 0) {
        return 0;
    }
    NSInteger index = [indexes indexOfObject:@(maximumValue)
             inSortedRange:NSMakeRange(0, start + 1)
                   options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
           usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
               return [obj1 compare:obj2];
           }];
    if (index == start + 1) {
        // maximumValue is larger than all values. The last value is the largest one <= maximumValue.
        return MAX(0, index - 1);
    } else {
        // maximumValue is less than or equal to largest value
        NSInteger value = [indexes[index] integerValue];
        if (value <= maximumValue) {
            return index;
        } else {
            return MAX(0, index - 1);
        }
    }
    return index;
//    // This is the naïve algorithm the code above attempts to implement.
//    NSInteger i = start;
//    while (i > 0 && [indexes[i] integerValue] > maximumValue) {
//        i--;
//    }
//    return i;
}

// Returns indexes.count if no value can be found greater or equal to `minimumValue`.
// This could be a binary search but it's better to keep it simple.
- (NSInteger)indexInSortedArray:(NSArray<NSNumber *> *)indexes
      withValueGreaterOrEqualTo:(NSInteger)minimumValue
           searchingForwardFrom:(NSInteger)startIndex {
    NSUInteger i = startIndex;
    while (i < indexes.count && [indexes[i] integerValue] < minimumValue) {
        ++i;
    }
    return i;
}

- (BOOL)isWhitelistedAlphanumericAtCoord:(VT100GridCoord)coord {
    screen_char_t theChar = [self characterAt:coord];
    return [self characterShouldBeTreatedAsAlphanumeric:ScreenCharToStr(&theChar) definitionOfAlphanumeric:iTermAlphaNumericDefinitionUserDefined];
}

- (NSString *)stringForCharacter:(screen_char_t)theChar {
    unichar temp[kMaxParts];
    int length = ExpandScreenChar(&theChar, temp);
    return [NSString stringWithCharacters:temp length:length];
}

- (NSString *)stringForCharacterAt:(VT100GridCoord)location {
    screen_char_t *theLine = [_dataSource getLineAtIndex:location.y];
    unichar temp[kMaxParts];
    int length = ExpandScreenChar(theLine + location.x, temp);
    return [NSString stringWithCharacters:temp length:length];
}

- (NSIndexSet *)indexesOnLine:(int)line containingCharacter:(unichar)c inRange:(NSRange)range {
    screen_char_t *theLine;
    theLine = [_dataSource getLineAtIndex:line];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (int i = range.location; i < range.location + range.length; i++) {
        if (theLine[i].code == c && !theLine[i].complexChar) {
            [indexes addIndex:i];
        }
    }
    return indexes;
}

- (SmartMatch *)smartSelectionAt:(VT100GridCoord)location
                       withRules:(NSArray *)rules
                  actionRequired:(BOOL)actionRequired
                           range:(VT100GridWindowedRange *)range
                ignoringNewlines:(BOOL)ignoringNewlines {
    location = [self coordLockedToWindow:location];
    int targetOffset;
    const int numLines = 2;
    NSMutableArray* coords = [NSMutableArray arrayWithCapacity:numLines * _logicalWindow.length];
    NSString *textWindow = [self textAround:location
                                     radius:2
                               targetOffset:&targetOffset
                                     coords:coords
                           ignoringNewlines:ignoringNewlines || [self hasLogicalWindow]];

    NSArray* rulesArray = rules ?: [SmartSelectionController defaultRules];
    const int numRules = [rulesArray count];

    NSMutableDictionary* matches = [NSMutableDictionary dictionaryWithCapacity:13];
    int numCoords = [coords count];

    BOOL debug = [SmartSelectionController logDebugInfo];
    if (debug) {
        NSLog(@"Perform smart selection on text: %@", textWindow);
    }
    for (int j = 0; j < numRules; j++) {
        NSDictionary *rule = [rulesArray objectAtIndex:j];
        if (actionRequired && [[SmartSelectionController actionsInRule:rule] count] == 0) {
            DLog(@"Ignore smart selection rule because it has no action: %@", rule);
            continue;
        }
        NSString *regex = [SmartSelectionController regexInRule:rule];
        double precision = [SmartSelectionController precisionInRule:rule];
        if (debug) {
            NSLog(@"Try regex %@", regex);
        }
        for (int i = 0; i <= targetOffset; i++) {
            NSString* substring = [textWindow substringWithRange:NSMakeRange(i, [textWindow length] - i)];
            NSError* regexError = nil;
            NSRange temp = [substring rangeOfRegex:regex
                                           options:0
                                           inRange:NSMakeRange(0, [substring length])
                                           capture:0
                                             error:&regexError];
            if (temp.location != NSNotFound) {
                if (i + temp.location <= targetOffset && i + temp.location + temp.length > targetOffset) {
                    NSString* result = [substring substringWithRange:temp];
                    double score = precision * (double) temp.length;
                    SmartMatch* oldMatch = [matches objectForKey:result];
                    if (!oldMatch || score > oldMatch.score) {
                        SmartMatch* match = [[[SmartMatch alloc] init] autorelease];
                        match.score = score;
                        VT100GridCoord startCoord = [coords[i + temp.location] gridCoordValue];
                        VT100GridCoord endCoord = [coords[MIN(numCoords - 1,
                                                              i + temp.location + temp.length - 1)] gridCoordValue];
                        endCoord = [self successorOfCoord:endCoord];
                        match.startX = startCoord.x;
                        match.absStartY = startCoord.y + [_dataSource totalScrollbackOverflow];
                        match.endX = endCoord.x;
                        match.absEndY = endCoord.y + [_dataSource totalScrollbackOverflow];
                        match.rule = rule;
                        match.components = [substring captureComponentsMatchedByRegex:regex
                                                                              options:0
                                                                                range:NSMakeRange(0, [substring length])
                                                                                error:&regexError];
                        [matches setObject:match forKey:result];

                        if (debug) {
                            NSLog(@"Regex matched. Add result %@ at %d,%lld -> %d,%lld with score %lf", result,
                                  match.startX, match.absStartY, match.endX, match.absEndY,
                                  match.score);
                        }
                    }
                    i += temp.location + temp.length - 1;
                } else {
                    i += temp.location;
                }
            } else {
                break;
            }
        }
    }

    if ([matches count]) {
        NSArray* sortedMatches = [[matches allValues] sortedArrayUsingSelector:@selector(compare:)];
        SmartMatch* bestMatch = [sortedMatches lastObject];
        if (debug) {
            NSLog(@"Select match with score %lf", bestMatch.score);
        }
        VT100GridCoordRange theRange =
            VT100GridCoordRangeMake(bestMatch.startX,
                                    bestMatch.absStartY - [_dataSource totalScrollbackOverflow],
                                    bestMatch.endX,
                                    bestMatch.absEndY - [_dataSource totalScrollbackOverflow]);
        *range = [self windowedRangeWithRange:theRange];
        return bestMatch;
    } else {
        if (debug) {
            NSLog(@"No matches. Fall back on word selection.");
        }
        // Fall back on word selection
        if (actionRequired) {
            // There is no match when using word selection and rangeForWordAt:maximumLength: can be slow.
            *range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), -1, -1);
        } else if (location.y >= 0) {
            *range = [self rangeForWordAt:location maximumLength:kReasonableMaximumWordLength];
        } else {
            *range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1),
                                                _logicalWindow.location, _logicalWindow.length);
        }
        return nil;
    }
}

// Returns the class for a character.
- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter {
    return [self classForCharacter:theCharacter definitionOfAlphanumeric:iTermAlphaNumericDefinitionUserDefined];
}

- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter
                    definitionOfAlphanumeric:(iTermAlphaNumericDefinition)definition {
    if (!theCharacter.complexChar) {
        if (theCharacter.code == TAB_FILLER) {
            return kTextExtractorClassWhitespace;
        } else if (theCharacter.code == DWC_RIGHT || theCharacter.complexChar == DWC_SKIP) {
            return kTextExtractorClassDoubleWidthPlaceholder;
        }
    }

    if (!theCharacter.code) {
        return kTextExtractorClassNull;
    }

    NSString *asString = [self stringForCharacter:theCharacter];
    NSRange range;
    range = [asString rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
    if (range.length == asString.length) {
        return kTextExtractorClassWhitespace;
    }

    if ([self characterIsAlphanumeric:asString] ||
        [self characterShouldBeTreatedAsAlphanumeric:asString definitionOfAlphanumeric:definition]) {
        return kTextExtractorClassWord;
    }

    return kTextExtractorClassOther;
}

- (BOOL)characterIsAlphanumeric:(NSString *)characterAsString {
    NSRange range = [characterAsString rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]];
    return (range.length == characterAsString.length);
}

- (BOOL)characterShouldBeTreatedAsAlphanumeric:(NSString *)characterAsString
                      definitionOfAlphanumeric:(iTermAlphaNumericDefinition)definition {
    switch (definition) {
        case iTermAlphaNumericDefinitionUserDefined: {
            NSRange range = [[iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]
                             rangeOfString:characterAsString];
            return (range.length == characterAsString.length);
        }
        case iTermAlphaNumericDefinitionUnixCommands: {
            NSRange range = [@"_-" rangeOfString:characterAsString];
            return (range.length == characterAsString.length);
        }
        case iTermAlphaNumericDefinitionNarrow:
            // The narrow definition only allows hyphen.
            return [characterAsString isEqualToString:@"-"];
    }
}

- (VT100GridWindowedRange)rangeOfParentheticalSubstringAtLocation:(VT100GridCoord)location {
    NSString *paren = [self stringForCharacterAt:location];
    NSDictionary *forwardMatches = @{ @"(": @")",
                                      @"[": @"]",
                                      @"{": @"}" };
    NSString *match = nil;
    BOOL forward = YES;
    for (NSString *open in forwardMatches) {
        NSString *close = forwardMatches[open];
        if ([paren isEqualToString:open]) {
            match = close;
            forward = YES;
            break;
        }
        if ([paren isEqualToString:close]) {
            match = open;
            forward = NO;
            break;
        }
    }
    if (!match) {
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
    }

    __block int level = 0;
    __block int left = 10000;
    VT100GridCoord end = [self searchFrom:location
                                  forward:forward
                             forCharacterMatchingFilter:^BOOL (screen_char_t theChar,
                                                               VT100GridCoord coord) {
                                 if (--left == 0) {
                                     return YES;
                                 }
                                 NSString *string = [self stringForCharacter:theChar];
                                 if ([string isEqualToString:match]) {
                                     level--;
                                 } else if ([string isEqualToString:paren]) {
                                     level++;
                                 }
                                 return level == 0;
                             }];
    if (left == 0) {
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
    } else if (forward) {
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                    location.y,
                                                                    end.x + 1,
                                                                    end.y)];
    } else {
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(end.x,
                                                                    end.y,
                                                                    location.x + 1,
                                                                    location.y)];
    }
}

- (VT100GridCoord)successorOfCoord:(VT100GridCoord)coord {
    coord.x++;
    int xLimit = [self xLimit];
    BOOL checkedForDWC = NO;
    if (coord.x < xLimit && [self haveDoubleWidthExtensionAt:coord]) {
        coord.x++;
        checkedForDWC = YES;
    }
    if (coord.x >= xLimit) {
        coord.x = _logicalWindow.location;
        coord.y++;
        if (coord.y >= [_dataSource numberOfLines]) {
            return VT100GridCoordMake(xLimit - 1, [_dataSource numberOfLines] - 1);
        }
        if (!checkedForDWC && [self haveDoubleWidthExtensionAt:coord]) {
            coord.x++;
        }
    }
    return coord;
}

- (VT100GridCoord)successorOfCoordSkippingContiguousNulls:(VT100GridCoord)coord {
    do {
        coord.x++;
        int xLimit = [self xLimit];
        if (coord.x >= xLimit) {
            coord.x = _logicalWindow.location;
            coord.y++;
            if (coord.y >= [_dataSource numberOfLines]) {
                return VT100GridCoordMake(xLimit - 1, [_dataSource numberOfLines] - 1);
            } else {
                return coord;
            }
        }
    } while ([self characterAt:coord].code == 0);
    return coord;
}

- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord {
    coord.x--;
    BOOL checkedForDWC = NO;
    if (coord.x >= 0 && [self haveDoubleWidthExtensionAt:coord]) {
        checkedForDWC = YES;
        coord.x--;
    }
    if (coord.x < _logicalWindow.location) {
        coord.x = [self xLimit] - 1;
        coord.y--;
        if (coord.y < 0) {
            return VT100GridCoordMake(_logicalWindow.location, 0);
        }
        if (!checkedForDWC && [self haveDoubleWidthExtensionAt:coord]) {
            coord.x--;
        }
    }

    return coord;
}

- (VT100GridCoord)predecessorOfCoordSkippingContiguousNulls:(VT100GridCoord)coord {
    int moved = 0;
    VT100GridCoord prev;
    do {
        prev = coord;
        coord.x--;
        if (coord.x == _logicalWindow.location) {
            return coord;
        }
        if (coord.x < _logicalWindow.location) {
            coord.x = [self xLimit] - 1;
            coord.y--;
            if (coord.y < 0) {
                return VT100GridCoordMake(_logicalWindow.location, 0);
            } else if (moved > 0) {
                return coord;
            }
        }
        moved++;
    } while ([self characterAt:coord].code == 0);
    if (moved > 1) {
        return prev;
    } else {
        return coord;
    }
}

// Returns an integer that uniquely identifies a coordinate in a grid with the passed-in |width|.
- (NSUInteger)indexForCoord:(VT100GridCoord)coord width:(int)width {
    NSUInteger i = coord.y;
    i *= width;
    i += coord.x;
    return i;
}

// Not inclusive of coord2
- (int)numberOfCoordsInIndexSet:(NSIndexSet *)coords
                        between:(VT100GridCoord)coord1
                            and:(VT100GridCoord)coord2 {
    NSUInteger coord1Index = [self indexForCoord:coord1 width:[_dataSource width]];
    NSUInteger coord2Index = [self indexForCoord:coord2 width:[_dataSource width]];
    NSUInteger minIndex = MIN(coord1Index, coord2Index);
    NSUInteger maxIndex = MAX(coord1Index, coord2Index);

    __block int n = 0;
    [coords enumerateIndexesInRange:NSMakeRange(minIndex, maxIndex - minIndex)
                            options:0
                         usingBlock:^(NSUInteger idx, BOOL *stop) {
                             n++;
                         }];
    return n;
}

- (VT100GridCoord)coord:(VT100GridCoord)coord
                   plus:(int)n
         skippingCoords:(NSIndexSet *)coordsToSkip
                forward:(BOOL)forward {
    int left = _logicalWindow.length >= 0 ? _logicalWindow.location : 0;
    int right = [self xLimit];
    int span = right - left;
    VT100GridCoord prevCoord;

    // Advance it by n.
    while (n) {
        prevCoord = coord;
        coord.x += n;
        n = 0;
        if (coord.x >= left && coord.x < right) {
            int extra = [self numberOfCoordsInIndexSet:coordsToSkip
                                               between:coord
                                                   and:prevCoord];
            if (forward) {
                coord.x += extra;
            } else {
                coord.x -= extra;
            }
        }
        // If n was negative, move it right and up until it's legal.
        if (coord.x < left) {
            while (coord.x < left) {
                coord.y--;
                coord.x += span;
                n -= [self numberOfCoordsInIndexSet:coordsToSkip
                                            between:coord
                                                and:prevCoord];
                prevCoord = coord;
            }
        } else {
            // If n was positive, move it left and down until it's legal.
            while (coord.x >= right) {
                coord.x -= span;
                coord.y++;
                n += [self numberOfCoordsInIndexSet:coordsToSkip
                                            between:coord
                                                and:prevCoord];
                prevCoord = coord;
            }
        }
    }

    // Make sure y value is legit.
    coord.y = MAX(0, MIN([_dataSource numberOfLines] - 1, coord.y));

    return coord;
}

- (VT100GridCoord)searchFrom:(VT100GridCoord)start
                     forward:(BOOL)forward
  forCharacterMatchingFilter:(BOOL (^)(screen_char_t, VT100GridCoord))block {
    VT100GridCoord coord = start;
    screen_char_t *theLine;
    int y = coord.y;
    theLine = [_dataSource getLineAtIndex:coord.y];
    while (1) {
        if (y != coord.y) {
            theLine = [_dataSource getLineAtIndex:coord.y];
            y = coord.y;
        }
        BOOL stop = block(theLine[coord.x], coord);
        if (stop) {
            return coord;
        }
        VT100GridCoord prev = coord;
        if (forward) {
            coord = [self successorOfCoord:coord];
        } else {
            coord = [self predecessorOfCoord:coord];
        }
        if (VT100GridCoordEquals(coord, prev)) {
            return VT100GridCoordMake(-1, -1);
        }
    }
}

- (BOOL)shouldStopEnumeratingWithCode:(unichar)code
                             numNulls:(int)numNulls
              windowTouchesLeftMargin:(BOOL)windowTouchesLeftMargin
             windowTouchesRightMargin:(BOOL)windowTouchesRightMargin
                     ignoringNewlines:(BOOL)ignoringNewlines {
    if (windowTouchesRightMargin && windowTouchesLeftMargin) {
        return numNulls || (code == EOL_HARD && !ignoringNewlines);
    } else {
        return numNulls > 0;
    }
}

- (NSString *)textAround:(VT100GridCoord)coord
                  radius:(int)radius
            targetOffset:(int *)targetOffset
                  coords:(NSMutableArray *)coords
        ignoringNewlines:(BOOL)ignoringNewlines {
    BOOL ignoreContinuations = (_logicalWindow.length > 0);
    int xLimit = [self xLimit];
    int trueWidth = [_dataSource width];
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(0,
                                                           coord.y - radius,
                                                           coord.x,
                                                           coord.y);
    NSMutableString* joinedLines =
        [NSMutableString stringWithCapacity:radius * _logicalWindow.length];
    VT100GridWindowedRange windowedRange = VT100GridWindowedRangeMake(theRange,
                                                                      _logicalWindow.location,
                                                                      _logicalWindow.length);
    [self enumerateInReverseCharsInRange:windowedRange
                               charBlock:^BOOL(screen_char_t theChar, VT100GridCoord charCoord) {
                                   if (!theChar.code) {
                                       return YES;
                                   }
                                   if (ignoreContinuations &&
                                       windowedRange.columnWindow.length > 0 &&
                                       charCoord.x == windowedRange.columnWindow.location + windowedRange.columnWindow.length - 1 &&
                                       theChar.code == '\\' &&
                                       !theChar.complexChar) {
                                       // Is a backslash at the right edge of a window.
                                       // no-op
                                   } else if (theChar.complexChar ||
                                              theChar.code < ITERM2_PRIVATE_BEGIN ||
                                              theChar.code > ITERM2_PRIVATE_END) {
                                       NSString* string = CharToStr(theChar.code, theChar.complexChar) ?: @"";
                                       [joinedLines insertString:string atIndex:0];
                                       for (int i = 0; i < [string length]; i++) {
                                         [coords insertObject:[NSValue valueWithGridCoord:charCoord] atIndex:0];
                                       }
                                   }
                                   return NO;
                               }
                                eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                                    return [self shouldStopEnumeratingWithCode:code
                                                                      numNulls:numPrecedingNulls
                                                       windowTouchesLeftMargin:(_logicalWindow.location == 0)
                                                      windowTouchesRightMargin:xLimit == trueWidth
                                                              ignoringNewlines:ignoringNewlines];
                                }];

    theRange = VT100GridCoordRangeMake(coord.x,
                                       coord.y,
                                       [_dataSource width],
                                       coord.y + radius);
    windowedRange = VT100GridWindowedRangeMake(theRange,
                                               _logicalWindow.location,
                                               _logicalWindow.length);

    [self enumerateCharsInRange:windowedRange
                      charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord charCoord) {
                          if (!theChar.code) {
                              return YES;
                          }
                          if (ignoreContinuations &&
                              windowedRange.columnWindow.length > 0 &&
                              charCoord.x == windowedRange.columnWindow.location + windowedRange.columnWindow.length - 1 &&
                              theChar.code == '\\' &&
                              !theChar.complexChar) {
                              // Is a backslash at the right edge of a window.
                              // no-op
                          } else if (theChar.complexChar ||
                                     theChar.code < ITERM2_PRIVATE_BEGIN ||
                                     theChar.code > ITERM2_PRIVATE_END) {
                              NSString* string = CharToStr(theChar.code, theChar.complexChar) ?: @"";
                              [joinedLines appendString:string];
                              for (int i = 0; i < [string length]; i++) {
                                  [coords addObject:[NSValue valueWithGridCoord:charCoord]];
                              }
                          }
                          return NO;
                      }
                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                           return [self shouldStopEnumeratingWithCode:code
                                                             numNulls:numPrecedingNulls
                                              windowTouchesLeftMargin:(_logicalWindow.location == 0)
                                             windowTouchesRightMargin:xLimit == trueWidth
                                                     ignoringNewlines:ignoringNewlines];
                       }];

    *targetOffset = -1;
    for (int i = 0; i < coords.count; i++) {
        NSComparisonResult order = VT100GridCoordOrder(coord, [coords[i] gridCoordValue]);
        if (order != NSOrderedDescending) {
            *targetOffset = i;
            break;
        }
    }
    return joinedLines;
}

- (VT100GridWindowedRange)rangeForWrappedLineEncompassing:(VT100GridCoord)coord
                                     respectContinuations:(BOOL)respectContinuations
                                                 maxChars:(int)maxChars {
    int start = [self lineNumberWithStartOfWholeLineIncludingLine:coord.y
                                             respectContinuations:respectContinuations
                                                         maxChars:maxChars];
    int end = [self lineNumberWithEndOfWholeLineIncludingLine:coord.y
                                             respectContinuations:respectContinuations
                                                     maxChars:maxChars];
    return [self windowedRangeWithRange:VT100GridCoordRangeMake(_logicalWindow.location,
                                                                start,
                                                                [self xLimit],
                                                                end)];
}

- (BOOL)haveNonWhitespaceInFirstLineOfRange:(VT100GridWindowedRange)windowedRange {
    __block BOOL result = NO;
    NSMutableCharacterSet *whitespaceCharacterSet = [NSMutableCharacterSet whitespaceCharacterSet];
    [whitespaceCharacterSet addCharactersInRange:NSMakeRange(TAB_FILLER, 1)];

    [self enumerateCharsInRange:windowedRange
                      charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
                          if (theChar.image) {
                              return NO;
                          }
                          if (theChar.complexChar) {
                              NSString *string = ScreenCharToStr(&theChar);
                              if ([string rangeOfCharacterFromSet:whitespaceCharacterSet].location != NSNotFound) {
                                  result = YES;
                                  return YES;
                              } else {
                                  return NO;
                              }
                          }
                          if ([whitespaceCharacterSet characterIsMember:theChar.code]) {
                              return NO;
                          } else {
                              result = YES;
                              return YES;
                          }
                      }
                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                           return (code == EOL_HARD);
                       }];
    return result;
}

- (id)contentInRange:(VT100GridWindowedRange)windowedRange
   attributeProvider:(NSDictionary *(^)(screen_char_t))attributeProvider
          nullPolicy:(iTermTextExtractorNullPolicy)nullPolicy
                 pad:(BOOL)pad
  includeLastNewline:(BOOL)includeLastNewline
    trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces
              cappedAtSize:(int)maxBytes
              truncateTail:(BOOL)truncateTail
         continuationChars:(NSMutableIndexSet *)continuationChars
              coords:(NSMutableArray *)coords {
    DLog(@"Find selected text in range %@ pad=%d, includeLastNewline=%d, trim=%d",
         VT100GridWindowedRangeDescription(windowedRange), (int)pad, (int)includeLastNewline,
         (int)trimSelectionTrailingSpaces);
    __block id result;
    // Appends a string to |result|, either attributed or not, as appropriate.
    void (^appendString)(NSString *, screen_char_t, VT100GridCoord) =
        ^void(NSString *string, screen_char_t theChar, VT100GridCoord coord) {
            if (attributeProvider) {
                [result iterm_appendString:string
                            withAttributes:attributeProvider(theChar)];
            } else {
                [result appendString:string];
            }
            for (NSInteger i = 0; i < string.length; i++) {
                [coords addObject:[NSValue valueWithGridCoord:coord]];
            }
        };

    if (attributeProvider) {
        result = [[[NSMutableAttributedString alloc] init] autorelease];
    } else {
        result = [NSMutableString string];
    }

    if (maxBytes < 0) {
        maxBytes = INT_MAX;
    }
    const NSUInteger kMaximumOversizeAmountWhenTruncatingHead = 1024 * 100;
    int width = [_dataSource width];
    __block BOOL lineContainsNonImage = NO;
    __block BOOL lineContainsImage = NO;
    __block BOOL copiedImage = NO;
    [self enumerateCharsInRange:windowedRange
                      charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
                          if (theChar.image) {
                              lineContainsImage = YES;
                          } else {
                              lineContainsNonImage = YES;
                          }
                          if (theChar.image) {
                              if (attributeProvider && theChar.foregroundColor == 0 && theChar.backgroundColor == 0) {
                                  iTermImageInfo *imageInfo = GetImageInfo(theChar.code);
                                  NSImage *image = imageInfo.image.images.firstObject;
                                  if (image) {
                                      copiedImage = YES;
                                      NSTextAttachment *textAttachment = [[[NSTextAttachment alloc] init] autorelease];
                                      textAttachment.image = imageInfo.image.images.firstObject;
                                      NSAttributedString *attributedStringWithAttachment = [NSAttributedString attributedStringWithAttachment:textAttachment];
                                      [result appendAttributedString:attributedStringWithAttachment];
                                      [coords addObject:[NSValue valueWithGridCoord:coord]];
                                  }
                              }
                          } else if (theChar.code == TAB_FILLER && !theChar.complexChar) {
                              // Convert orphan tab fillers (those without a subsequent
                              // tab character) into spaces.
                              if ([self tabFillerAtIndex:coord.x isOrphanInLine:currentLine]) {
                                  appendString(@" ", theChar, coord);
                              }
                          } else if (theChar.code == 0 && !theChar.complexChar) {
                              // This is only reached for midline nulls; nulls at the end of the
                              // line end up in eolBlock.
                              switch (nullPolicy) {
                                  case kiTermTextExtractorNullPolicyFromLastToEnd:
                                      [result deleteCharactersInRange:NSMakeRange(0, [result length])];
                                      [coords removeAllObjects];
                                      break;
                                  case kiTermTextExtractorNullPolicyFromStartToFirst:
                                      return YES;
                                  case kiTermTextExtractorNullPolicyTreatAsSpace:
                                  case kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal:
                                      appendString(@" ", theChar, coord);
                                      break;
                              }
                          } else if (theChar.code != DWC_RIGHT &&
                                     theChar.code != DWC_SKIP) {
                              // Normal character. Add it unless it's a backslash at the right edge
                              // of a window.
                              if (continuationChars &&
                                  windowedRange.columnWindow.length > 0 &&
                                  coord.x == windowedRange.columnWindow.location + windowedRange.columnWindow.length - 1 &&
                                  theChar.code == '\\' &&
                                  !theChar.complexChar) {
                                  // Is a backslash at the right edge of a window.
                                  [continuationChars addIndex:[self indexForCoord:coord width:width]];
                              } else {
                                  // Normal character.
                                  appendString(ScreenCharToStr(&theChar) ?: @"", theChar, coord);
                              }
                          }
                          if (truncateTail) {
                              return [result length] >= maxBytes;
                          } else if ([result length] > maxBytes + kMaximumOversizeAmountWhenTruncatingHead) {
                              // Truncate from head when significantly oversize.
                              //
                              // Removing byte from the beginning of the string is slow. The only reason to do it is to save
                              // memory. Remove a big chunk periodically. After enumeration is done we'll cut it to the
                              // exact size it needs to be.
                              [result replaceCharactersInRange:NSMakeRange(0, [result length] - maxBytes) withString:@""];
                          }
                          return NO;
                      }
                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                           BOOL ignore = (!copiedImage && !lineContainsNonImage && lineContainsImage);
                           copiedImage = lineContainsNonImage = lineContainsImage = NO;
                           if (ignore) {
                               return NO;
                           }
                           int right;
                           if (windowedRange.columnWindow.length) {
                               right = windowedRange.columnWindow.location + windowedRange.columnWindow.length;
                           } else {
                               right = width;
                           }
                           // If there is no text after this, insert a hard line break.
                           BOOL shouldAppendNewline = YES;
                           if (pad) {
                               for (int i = 0; i < numPrecedingNulls; i++) {
                                   VT100GridCoord coord =
                                      VT100GridCoordMake(right - numPrecedingNulls + i, line);
                                   appendString(@" ", [self defaultChar], coord);
                               }
                           } else if (numPrecedingNulls > 0) {
                               switch (nullPolicy) {
                                   case kiTermTextExtractorNullPolicyFromLastToEnd:
                                       [result deleteCharactersInRange:NSMakeRange(0, [result length])];
                                       [coords removeAllObjects];
                                       shouldAppendNewline = NO;
                                       break;
                                   case kiTermTextExtractorNullPolicyFromStartToFirst:
                                       return YES;
                                   case kiTermTextExtractorNullPolicyTreatAsSpace:
                                       appendString(@" ",
                                                    [self defaultChar],
                                                    VT100GridCoordMake(right - 1, line));
                                       break;
                                   case kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal:
                                       break;
                               }
                           }
                           if (code == EOL_HARD &&
                               shouldAppendNewline &&
                               (includeLastNewline || line < windowedRange.coordRange.end.y)) {
                               if (trimSelectionTrailingSpaces) {
                                   NSInteger lengthBeforeTrimming = [result length];
                                   [result trimTrailingWhitespace];
                                   [coords removeObjectsInRange:NSMakeRange([result length],
                                                                            lengthBeforeTrimming - [result length])];
                               }
                               appendString(@"\n",
                                            [self defaultChar],
                                            VT100GridCoordMake(right, line));
                           }
                           if (truncateTail) {
                               return [result length] >= maxBytes;
                           } else if ([result length] > maxBytes + kMaximumOversizeAmountWhenTruncatingHead) {
                               // Truncate from head when significantly oversize.
                               //
                               // Removing byte from the beginning of the string is slow. The only reason to do it is to save
                               // memory. Remove a big chunk periodically. After enumeration is done we'll cut it to the
                               // exact size it needs to be.
                               [result replaceCharactersInRange:NSMakeRange(0, [result length] - maxBytes) withString:@""];
                           }
                           return NO;
                       }];

    if (!truncateTail && [result length] > maxBytes) {
        // Truncate the head to the exact size.
        [result replaceCharactersInRange:NSMakeRange(0, [result length] - maxBytes) withString:@""];
    }

    if (trimSelectionTrailingSpaces) {
        NSInteger lengthBeforeTrimming = [result length];
        [result trimTrailingWhitespace];
        [coords removeObjectsInRange:NSMakeRange([result length],
                                                 lengthBeforeTrimming - [result length])];
    }
    return result;
}


- (VT100GridAbsCoordRange)rangeByTrimmingWhitespaceFromRange:(VT100GridAbsCoordRange)range {
    return [self rangeByTrimmingWhitespaceFromRange:range leading:YES trailing:iTermTextExtractorTrimTrailingWhitespaceAll];
}

- (VT100GridAbsCoordRange)rangeByTrimmingWhitespaceFromRange:(VT100GridAbsCoordRange)range
                                                     leading:(BOOL)leading
                                                    trailing:(iTermTextExtractorTrimTrailingWhitespace)trailing {
    __block VT100GridAbsCoordRange trimmedRange = range;
    __block BOOL foundNonWhitespace = NO;
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *nonWhitespace = [whitespace invertedSet];
    long long totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    VT100GridCoordRange localRange = VT100GridCoordRangeMake(range.start.x,
                                                             range.start.y - totalScrollbackOverflow,
                                                             range.end.x,
                                                             range.end.y - totalScrollbackOverflow);
    if (range.start.y < totalScrollbackOverflow) {
        localRange.start.y = 0;
        localRange.start.x = 0;
    }
    if (range.end.y < totalScrollbackOverflow) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }

    VT100GridWindowedRange windowedRange =
            VT100GridWindowedRangeMake(localRange, _logicalWindow.location, _logicalWindow.length);
    if (leading) {
        [self enumerateCharsInRange:windowedRange
                          charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
                              NSString *string = ScreenCharToStr(&theChar);
                              if ([string rangeOfCharacterFromSet:nonWhitespace].location != NSNotFound) {
                                  trimmedRange.start.x = coord.x;
                                  trimmedRange.start.y = coord.y + totalScrollbackOverflow;
                                  foundNonWhitespace = YES;
                                  return YES;
                              } else {
                                  return NO;
                              }
                          }
                           eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                               return NO;
                           }];
        if (!foundNonWhitespace) {
            return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        }
    }

    if (trailing != iTermTextExtractorTrimTrailingWhitespaceNone) {
        __block BOOL haveSeenCharacter = NO;
        __block BOOL haveSeenNewline = NO;
        [self enumerateInReverseCharsInRange:windowedRange
                                   charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                                       NSString *string = ScreenCharToStr(&theChar);
                                       BOOL result = NO;
                                       if ([string rangeOfCharacterFromSet:whitespace].location != NSNotFound) {
                                           trimmedRange.end.x = coord.x;
                                           trimmedRange.end.y = coord.y + totalScrollbackOverflow;
                                       } else {
                                           if (!haveSeenCharacter && trailing == iTermTextExtractorTrimTrailingWhitespaceOneLine) {
                                               // Started with a newline and then hit a non-whitespace character.
                                               trimmedRange.end.x = coord.x + 1;
                                               trimmedRange.end.y = coord.y + totalScrollbackOverflow;
                                           }
                                           result = YES;
                                       }
                                       haveSeenCharacter = YES;
                                       return result;
                                   }
                                    eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
                                        if (trailing == iTermTextExtractorTrimTrailingWhitespaceOneLine) {
                                            BOOL result = haveSeenCharacter || haveSeenNewline;
                                            haveSeenNewline = YES;
                                            return result;
                                        } else {
                                            return NO;
                                        }
                                    }];
    }

    return trimmedRange;
}

- (BOOL)haveDoubleWidthExtensionAt:(VT100GridCoord)coord {
    screen_char_t sct = [self characterAt:coord];
    return !sct.complexChar && (sct.code == DWC_RIGHT || sct.code == DWC_SKIP);
}

- (BOOL)coord:(VT100GridCoord)coord1 isEqualToCoord:(VT100GridCoord)coord2 {
    if (coord1.x == coord2.x && coord1.y == coord2.y) {
        return YES;
    }
    if (coord1.y != coord2.y) {
        return NO;
    }
    if (abs(coord1.x - coord2.x) > 1) {
        return NO;
    }

    int large = MAX(coord1.x, coord2.x);
    if ([self haveDoubleWidthExtensionAt:VT100GridCoordMake(large, coord1.y)]) {
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Private

- (VT100GridCoord)canonicalizedLocation:(VT100GridCoord)location {
    int xLimit = [self xLimit];
    if (location.x >= xLimit) {
        location.x = xLimit - 1;
    }
    return location;
}

// maxChars is a rough guideline here. If the line is very long it will go over by up to the width
// of one windowed range.
- (int)lineNumberWithStartOfWholeLineIncludingLine:(int)y
                              respectContinuations:(BOOL)respectContinuations
                                          maxChars:(int)maxChars {
    const int width = [self widthOfWindowedRange];
    if (maxChars < 0) {
        maxChars = INT_MAX - width;
    }
    int i = y;
    NSInteger count = 0;
    while (count < maxChars + width && i > 0 && [self lineHasSoftEol:i - 1 respectContinuations:respectContinuations]) {
        count += width;
        i--;
    }
    return i;
}

// maxChars is a rough guideline here. If the line is very long it will go over by up to the width
// of one windowed range.
- (int)lineNumberWithEndOfWholeLineIncludingLine:(int)y
                            respectContinuations:(BOOL)respectContinuations
                                        maxChars:(int)maxChars {
    int i = y + 1;
    const int width = [self widthOfWindowedRange];
    if (maxChars < 0) {
        maxChars = INT_MAX - width;
    }
    int maxY = [_dataSource numberOfLines];
    NSInteger count = 0;
    while (count < maxChars + width && i < maxY && [self lineHasSoftEol:i - 1 respectContinuations:respectContinuations]) {
        i++;
        count += width;
    }
    return i - 1;
}

- (BOOL)lineHasSoftEol:(int)y respectContinuations:(BOOL)respectContinuations
{
    screen_char_t *theLine = [_dataSource getLineAtIndex:y];
    int width = [_dataSource width];
    int xLimit = [self xLimit];

    if ([self hasLogicalWindow]) {
        // If there are soft boundaries, it's impossible to detect soft line wraps so just
        // stop at whitespace.
        if (theLine[xLimit - 1].complexChar) {
            return YES;
        }
        unichar c = theLine[xLimit - 1].code;
        return !(c == 0 || c == ' ');
    }
    if (respectContinuations) {
        return (theLine[width].code != EOL_HARD ||
                (theLine[width - 1].code == '\\' && !theLine[width - 1].complexChar));
    } else {
        return theLine[width].code != EOL_HARD;
    }
}

- (BOOL)tabFillerAtIndex:(int)index isOrphanInLine:(screen_char_t *)line {
    // A tab filler orphan is a tab filler that is followed by a tab filler orphan or a
    // non-tab character.
    int xLimit = [self xLimit];
    for (int i = index + 1; i < xLimit; i++) {
        if (line[i].complexChar) {
            return YES;
        }
        unichar c = line[i].code;
        switch (c) {
            case TAB_FILLER:
                break;

            case '\t':
                return NO;

            default:
                return YES;
        }
    }
    return YES;
}

- (NSString *)wrappedStringAt:(VT100GridCoord)coord
                      forward:(BOOL)forward
          respectHardNewlines:(BOOL)respectHardNewlines
                     maxChars:(int)maxChars
            continuationChars:(NSMutableIndexSet *)continuationChars
          convertNullsToSpace:(BOOL)convertNullsToSpace
                       coords:(NSMutableArray *)coords {
    if ([self hasLogicalWindow]) {
        respectHardNewlines = NO;
    }
    VT100GridWindowedRange range;
    if (respectHardNewlines) {
        range = [self rangeForWrappedLineEncompassing:coord respectContinuations:YES maxChars:maxChars];
    } else {
        VT100GridCoordRange coordRange =
            VT100GridCoordRangeMake(_logicalWindow.location,
                                    MAX(0, coord.y - 10),
                                    [self xLimit],
                                    MIN([_dataSource numberOfLines] - 1, coord.y + 10));
        range = [self windowedRangeWithRange:coordRange];
    }
    iTermTextExtractorNullPolicy nullPolicy;
    if (forward) {
        nullPolicy = kiTermTextExtractorNullPolicyFromStartToFirst;
        range.coordRange.start = coord;
        if (VT100GridCoordOrder(range.coordRange.start,
                                range.coordRange.end) != NSOrderedAscending) {
            return @"";
        }
    } else {
        nullPolicy = kiTermTextExtractorNullPolicyFromLastToEnd;
        // This doesn't include the boundary character when returning a prefix because we don't
        // want it twice when getting the prefix and suffix at the same coord.
        range.coordRange.end = coord;
        if (VT100GridCoordOrder(range.coordRange.start,
                                range.coordRange.end) != NSOrderedAscending) {
            return @"";
        }
    }
    if (convertNullsToSpace) {
        nullPolicy = kiTermTextExtractorNullPolicyTreatAsSpace;
    }

    NSString *content =
            [self contentInRange:range
               attributeProvider:nil
                      nullPolicy:nullPolicy
                             pad:NO
              includeLastNewline:NO
          trimTrailingWhitespace:NO
                    cappedAtSize:maxChars
                    truncateTail:forward
               continuationChars:continuationChars
                          coords:coords];
    if (!respectHardNewlines) {
        if (coords == nil) {
            content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
        } else {
            NSMutableString *mutableContent = [[content mutableCopy] autorelease];
            [content reverseEnumerateSubstringsEqualTo:@"\n" block:^(NSRange range) {
                [mutableContent replaceCharactersInRange:range withString:@""];
                [coords removeObjectsInRange:range];
            }];
            content = mutableContent;
        }
    }
    return content;
}

- (void)enumerateCharsInRange:(VT100GridWindowedRange)range
                    charBlock:(BOOL (^)(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord))charBlock
                     eolBlock:(BOOL (^)(unichar code, int numPrecedingNulls, int line))eolBlock {
    int width = [_dataSource width];

    int startx = VT100GridWindowedRangeStart(range).x;
    if (startx < 0) {
        startx = 0;
    }
    int endx = range.columnWindow.length ? range.columnWindow.location + range.columnWindow.length
                                         : [_dataSource width];
    if (endx > width) {
        endx = width;
    }
    int bound = [_dataSource numberOfLines] - 1;
    BOOL fullWidth = ((range.columnWindow.location == 0 && range.columnWindow.length == width) ||
                      range.columnWindow.length <= 0);
    int left = range.columnWindow.length ? range.columnWindow.location : 0;
    for (int y = MAX(0, range.coordRange.start.y); y <= MIN(bound, range.coordRange.end.y); y++) {
        if (y == range.coordRange.end.y) {
            // Reduce endx for last line.
            endx = range.columnWindow.length ? VT100GridWindowedRangeEnd(range).x
                                             : range.coordRange.end.x;
        }
        screen_char_t *theLine = [_dataSource getLineAtIndex:y];

        // Count number of nulls at end of line.
        int numNulls = 0;
        for (int x = endx - 1; x >= range.columnWindow.location; x--) {
            ITAssertWithMessage(x >= 0 && x < width, @"Counting number of nulls. x=%@ range=%@ width=%@", @(x), VT100GridWindowedRangeDescription(range), @(width));
            BOOL isNull;
            // If not full-width then treat terminal spaces as nulls. This makes soft selection
            // find newlines more reliably, but can occasionally insert newlines where they
            // don't belong.
            if (fullWidth) {
                isNull = theLine[x].code == 0;
            } else {
                isNull = theLine[x].code == 0 || theLine[x].code == ' ';
            }
            if (!theLine[x].complexChar && isNull) {
                ++numNulls;
            } else {
                break;
            }
        }

        // Iterate over characters up to terminal nulls.
        for (int x = MIN(width - 1, MAX(range.columnWindow.location, startx)); x < endx - numNulls; x++) {
            ITAssertWithMessage(x >= 0 && x < width, @"Iterating terminal nulls. x=%@ range=%@ width=%@ numNulls=%@", @(x), VT100GridWindowedRangeDescription(range), @(width), @(numNulls));
            if (charBlock) {
                if (charBlock(theLine, theLine[x], VT100GridCoordMake(x, y))) {
                    return;
                }
            }
        }

        BOOL haveReachedEol = YES;
        if (y == range.coordRange.end.y) {
            haveReachedEol = numNulls > 0;
        }
        if (eolBlock && haveReachedEol) {
            BOOL stop;
            if (fullWidth) {
                stop = eolBlock(theLine[width].code, numNulls, y);
            } else {
                stop = eolBlock(numNulls ? EOL_HARD : EOL_SOFT, numNulls, y);
            }
            if (stop) {
                return;
            }
        }
        startx = left;
    }
}

- (void)enumerateInReverseCharsInRange:(VT100GridWindowedRange)range
                             charBlock:(BOOL (^)(screen_char_t theChar, VT100GridCoord coord))charBlock
                              eolBlock:(BOOL (^)(unichar code, int numPrecedingNulls, int line))eolBlock {
    int xLimit = range.columnWindow.length == 0 ? [_dataSource width] :
        (range.columnWindow.location + range.columnWindow.length);
    int initialX = MIN(xLimit - 1, range.coordRange.end.x - 1);
    int trueWidth = [_dataSource width];
    const int yLimit = MAX(0, range.coordRange.start.y);
    for (int y = MIN([_dataSource numberOfLines] - 1, range.coordRange.end.y);
         y >= yLimit;
         y--) {
        screen_char_t *theLine = [_dataSource getLineAtIndex:y];
        int x = initialX;
        int xmin;
        if (y == yLimit) {
            xmin = VT100GridWindowedRangeStart(range).x;
        } else {
            xmin = range.columnWindow.location;
        }
        if (x == xLimit - 1) {
            int numNulls = 0;
            while (x >= xmin && theLine[x].code == 0 && !theLine[x].complexChar) {
                ++numNulls;
                --x;
            }
            if (eolBlock) {
                if (xLimit == trueWidth) {
                    if (eolBlock(theLine[trueWidth].code, numNulls, y)) {
                        return;
                    }
                } else {
                    if (numNulls) {
                        if (eolBlock(EOL_HARD, numNulls, y)) {
                            return;
                        }
                    } else {
                        if (eolBlock(EOL_SOFT, 0, y)) {
                            return;
                        }
                    }
                }
            }
        }
        if (charBlock) {
            for (; x >= xmin; x--) {
                if (charBlock(theLine[x], VT100GridCoordMake(x, y))) {
                    return;
                }
            }
        }
        initialX = xLimit - 1;
    }
}

- (int)lengthOfLine:(int)line {
    screen_char_t *theLine = [_dataSource getLineAtIndex:line];
    int x;
    for (x = [_dataSource width] - 1; x >= 0; x--) {
        if (theLine[x].code || theLine[x].complexChar) {
            break;
        }
    }
    return x + 1;
}

- (NSIndexSet *)possibleColumnDividerIndexesAround:(VT100GridCoord)coord {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    VT100GridCoordRange theRange =
        VT100GridCoordRangeMake(0, coord.y, [_dataSource width], coord.y);
    NSCharacterSet *columnDividers = [self columnDividers];
    [self enumerateCharsInRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                      charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord theCoord) {
                          if (!theChar.complexChar &&
                              [columnDividers characterIsMember:theChar.code]) {
                              [indexes addIndex:theCoord.x];
                          }
                          return NO;
                      }
                       eolBlock:NULL];
    return indexes;
}

- (NSCharacterSet *)columnDividers {
    static NSMutableCharacterSet *charSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        charSet = [[NSMutableCharacterSet alloc] init];
        [charSet addCharactersInString:@"|\u2502"];
    });
    return charSet;
}

- (BOOL)characterAtCoordIsColumnDivider:(VT100GridCoord)coord {
    NSString *theString = [self stringForCharacterAt:coord];
    NSCharacterSet *columnDividers = [self columnDividers];
    if (!theString.length) {
        return NO;
    }
    unichar theChar = [theString characterAtIndex:0];
    if ([columnDividers characterIsMember:theChar]) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)coordContainsColumnDivider:(VT100GridCoord)coord {
    int n = 1;
    for (int y = coord.y - 1; y >= 0 && y > coord.y - kNumCharsToSearchForDivider; y--) {
        if ([self characterAtCoordIsColumnDivider:VT100GridCoordMake(coord.x, y)]) {
            n++;
        } else {
            break;
        }
    }
    int limit = [_dataSource numberOfLines];
    for (int y = coord.y + 1; y < limit && y < coord.y + kNumCharsToSearchForDivider; y++) {
        if ([self characterAtCoordIsColumnDivider:VT100GridCoordMake(coord.x, y)]) {
            n++;
        } else {
            break;
        }
    }
    return n >= kNumCharsToSearchForDivider;
}

- (int)xLimit {
    if (!_logicalWindow.length) {
        return [_dataSource width];
    } else {
        return _logicalWindow.location + _logicalWindow.length;
    }
}

- (int)widthOfWindowedRange {
    if (!_logicalWindow.length) {
        return [_dataSource width];
    } else {
        return _logicalWindow.length;
    }
}

- (screen_char_t)defaultChar {
    screen_char_t defaultChar = { 0 };
    defaultChar.foregroundColorMode = ColorModeAlternate;
    defaultChar.foregroundColor = ALTSEM_DEFAULT;
    defaultChar.backgroundColorMode = ColorModeAlternate;
    defaultChar.backgroundColor = ALTSEM_DEFAULT;
    return defaultChar;
}

- (VT100GridWindowedRange)windowedRangeWithRange:(VT100GridCoordRange)range {
    VT100GridWindowedRange windowedRange;
    windowedRange.coordRange = range;
    windowedRange.columnWindow = _logicalWindow;
    return windowedRange;
}

- (VT100GridCoord)coordLockedToWindow:(VT100GridCoord)coord {
    if (_logicalWindow.length == 0) {
        return coord;
    }
    coord.x = MIN(MAX(coord.x, _logicalWindow.location),
                  _logicalWindow.location + _logicalWindow.length - 1);
    return coord;
}

- (screen_char_t)characterAt:(VT100GridCoord)coord {
    if (_shouldCacheLines && coord.y == _cachedLineNumber && _cachedLine != nil) {
        return _cachedLine[coord.x];
    }
    screen_char_t *theLine = [_dataSource getLineAtIndex:coord.y];
    if (_shouldCacheLines) {
        _cachedLineNumber = coord.y;
        _cachedLine = theLine;
    }
    return theLine[coord.x];
}

@end
