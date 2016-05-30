//
//  iTermTextExtractor.m
//  iTerm
//
//  Created by George Nachman on 2/17/14.
//
//

#import "iTermTextExtractor.h"
#import "DebugLogging.h"
#import "iTermPreferences.h"
#import "NSStringITerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "RegexKitLite.h"
#import "PreferencePanel.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"

// Must find at least this many divider chars in a row for it to count as a divider.
static const int kNumCharsToSearchForDivider = 8;

@implementation iTermTextExtractor {
    id<iTermTextDataSource> _dataSource;
    VT100GridRange _logicalWindow;
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

- (VT100GridWindowedRange)rangeForWordAt:(VT100GridCoord)location {
    location = [self coordLockedToWindow:location];
    iTermTextExtractorClass theClass =
        [self classForCharacter:[self characterAt:location]];
    if (theClass == kTextExtractorClassDoubleWidthPlaceholder) {
        VT100GridCoord predecessor = [self predecessorOfCoord:location];
        if (predecessor.x != location.x || predecessor.y != location.y) {
            return [self rangeForWordAt:predecessor];
        }
    }
    if (theClass == kTextExtractorClassOther) {
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
    // Search forward for the end of the word.
    [self enumerateCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                           _logicalWindow.location,
                                                           _logicalWindow.length)
                      charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                          iTermTextExtractorClass newClass = [self classForCharacter:theChar];
                          BOOL isInWord = (newClass == kTextExtractorClassDoubleWidthPlaceholder ||
                                           newClass == theClass);
                          if (isInWord) {
                              if (theChar.complexChar ||
                                  theChar.code < ITERM2_PRIVATE_BEGIN ||
                                  theChar.code > ITERM2_PRIVATE_END) {
                                  [indexesInSuffix addObject:@(stringFromLocation.length)];
                                  [stringFromLocation appendString:ScreenCharToStr(&theChar)];
                                  [coords addObject:[NSValue valueWithGridCoord:coord]];
                              }
                          }
                          return !isInWord;
                      }
                       eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                           return [self shouldStopEnumeratingWithCode:code
                                                             numNulls:numPreceedingNulls
                                              windowTouchesLeftMargin:windowTouchesLeftMargin
                                             windowTouchesRightMargin:windowTouchesRightMargin
                                                     ignoringNewlines:NO];
                       }];

    // Search backward for the start of the word.
    theRange = VT100GridCoordRangeMake(0, 0, location.x, location.y);
    NSMutableString *stringBeforeLocation = [NSMutableString string];
    [self enumerateInReverseCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                    _logicalWindow.location,
                                                                    _logicalWindow.length)
                               charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                                   iTermTextExtractorClass newClass = [self classForCharacter:theChar];
                                   BOOL isInWord = (newClass == kTextExtractorClassDoubleWidthPlaceholder ||
                                                    newClass == theClass);
                                   if (isInWord) {
                                       if (theChar.complexChar ||
                                           theChar.code < ITERM2_PRIVATE_BEGIN || theChar.code > ITERM2_PRIVATE_END) {
                                           NSString *theString = ScreenCharToStr(&theChar);
                                           [stringBeforeLocation insertString:theString atIndex:0];
                                           [coords insertObject:[NSValue valueWithGridCoord:coord] atIndex:0];
                                           [stringLengthsInPrefix insertObject:@(theString.length) atIndex:0];
                                       }
                                   }
                                   return !isInWord;
                               }
                                eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                                    return [self shouldStopEnumeratingWithCode:code
                                                                      numNulls:numPreceedingNulls
                                                       windowTouchesLeftMargin:windowTouchesLeftMargin
                                                      windowTouchesRightMargin:windowTouchesRightMargin
                                                              ignoringNewlines:NO];

                                }];

    if (!coords.count) {
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                    location.y,
                                                                    location.x,
                                                                    location.y)];
    }

    if (theClass != kTextExtractorClassWord) {
        VT100GridCoord start = [[coords firstObject] gridCoordValue];
        VT100GridCoord end = [[coords lastObject] gridCoordValue];
        return [self windowedRangeWithRange:VT100GridCoordRangeMake(start.x,
                                                                    start.y,
                                                                    end.x + 1,
                                                                    end.y)];
    }
    
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

    // Set end to an index that is not in the middle of an OS-defined-word. It will be at the start
    // of a word or on a whitelisted character.
    BOOL previousCharacterWasWhitelisted = YES;

    // `end` can index into `coords` and `indexes`.
    NSInteger end = stringLengthsInPrefix.count;
    while (end < coords.count) {
        if ([self isWhitelistedAlphanumericAtCoord:[coords[end] gridCoordValue]]) {
            ++end;
            previousCharacterWasWhitelisted = YES;
        } else if (previousCharacterWasWhitelisted) {
            NSInteger index = [indexes[end] integerValue];
            NSRange range = [attributedString doubleClickAtIndex:index];

            end = [self indexInSortedArray:indexes
                 withValueGreaterOrEqualTo:NSMaxRange(range)
                      searchingForwardFrom:end];
            previousCharacterWasWhitelisted = NO;
        } else {
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

    // First, ensure that start is either at the start of a word (as defined by the OS) or on a
    // whitelisted character.
    if ([self isWhitelistedAlphanumericAtCoord:[coords[provisionalStart] gridCoordValue]]) {
        // On a whitelisted character. We'll search back past all of them.
        previousCharacterWasWhitelisted = YES;
        start = provisionalStart;
    } else {
        // Not on a whitelisted character. Set start to the index of the cell of the first character
        // of the word enclosing the cell indexed to by `provisionalStart`.
        previousCharacterWasWhitelisted = NO;
        NSUInteger location = [attributedString doubleClickAtIndex:[indexes[provisionalStart] integerValue]].location;
        start = [self indexInSortedArray:indexes
              withValueLessThanOrEqualTo:location
                   searchingBackwardFrom:provisionalStart];
    }
    
    //  Move back until two consecutive OS-defined words are found or we reach the start of the string.
    while (start > 0) {
        if ([self isWhitelistedAlphanumericAtCoord:[coords[start - 1] gridCoordValue]]) {
            --start;
            previousCharacterWasWhitelisted = YES;
        } else if (previousCharacterWasWhitelisted) {
            NSUInteger location = [attributedString doubleClickAtIndex:[indexes[start - 1] integerValue]].location;
            start = [self indexInSortedArray:indexes
                  withValueLessThanOrEqualTo:location
                       searchingBackwardFrom:provisionalStart];
            previousCharacterWasWhitelisted = NO;
        } else {
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

    return [self windowedRangeWithRange:VT100GridCoordRangeMake(startCoord.x,
                                                                startCoord.y,
                                                                endCoord.x,
                                                                endCoord.y)];
}

// Returns 0 if no value can be found less than or equal to `maximumValue`.
// This could be a binary search but it's better to keep it simple.
- (NSInteger)indexInSortedArray:(NSArray<NSNumber *> *)indexes
     withValueLessThanOrEqualTo:(NSInteger)maximumValue
          searchingBackwardFrom:(NSInteger)start {
    NSInteger i = start;
    while (i > 0 && [indexes[i] integerValue] > maximumValue) {
        i--;
    }
    return i;
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
    return [self characterShouldBeTreatedAsAlphanumeric:ScreenCharToStr(&theChar)];
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
        *range = [self rangeForWordAt:location];
        return nil;
    }
}

// Returns the class for a character.
- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter {
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
        [self characterShouldBeTreatedAsAlphanumeric:asString]) {
        return kTextExtractorClassWord;
    }

    return kTextExtractorClassOther;
}

- (BOOL)characterIsAlphanumeric:(NSString *)characterAsString {
    NSRange range = [characterAsString rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]];
    return (range.length == characterAsString.length);
}

- (BOOL)characterShouldBeTreatedAsAlphanumeric:(NSString *)characterAsString {
    NSRange range = [[iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]
                        rangeOfString:characterAsString];
    return (range.length == characterAsString.length);
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
                                eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                                    return [self shouldStopEnumeratingWithCode:code
                                                                      numNulls:numPreceedingNulls
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
                              NSString* string = CharToStr(theChar.code, theChar.complexChar);
                              [joinedLines appendString:string];
                              for (int i = 0; i < [string length]; i++) {
                                  [coords addObject:[NSValue valueWithGridCoord:charCoord]];
                              }
                          }
                          return NO;
                      }
                       eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                           return [self shouldStopEnumeratingWithCode:code
                                                             numNulls:numPreceedingNulls
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
                                     respectContinuations:(BOOL)respectContinuations {
    int start = [self lineNumberWithStartOfWholeLineIncludingLine:coord.y
                                             respectContinuations:respectContinuations];
    int end = [self lineNumberWithEndOfWholeLineIncludingLine:coord.y
                                             respectContinuations:respectContinuations];
    return [self windowedRangeWithRange:VT100GridCoordRangeMake(_logicalWindow.location,
                                                                start,
                                                                [self xLimit],
                                                                end)];
}

- (id)contentInRange:(VT100GridWindowedRange)windowedRange
   attributeProvider:(NSDictionary *(^)(screen_char_t))attributeProvider
          nullPolicy:(iTermTextExtractorNullPolicy)nullPolicy
                 pad:(BOOL)pad
  includeLastNewline:(BOOL)includeLastNewline
    trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces
              cappedAtSize:(int)maxBytes
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
            [coords addObject:[NSValue valueWithGridCoord:coord]];
        };

    if (attributeProvider) {
        result = [[[NSMutableAttributedString alloc] init] autorelease];
    } else {
        result = [NSMutableString string];
    }

    if (maxBytes < 0) {
        maxBytes = INT_MAX;
    }
    int width = [_dataSource width];
    __block NSIndexSet *tabFillerOrphans =
        [self tabFillerOrphansOnRow:windowedRange.coordRange.start.y];
    [self enumerateCharsInRange:windowedRange
                      charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                          if (theChar.code == TAB_FILLER && !theChar.complexChar) {
                              // Convert orphan tab fillers (those without a subsequent
                              // tab character) into spaces.
                              if ([tabFillerOrphans containsIndex:coord.x]) {
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
                          return [result length] >= maxBytes;
                      }
                       eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                           tabFillerOrphans =
                               [self tabFillerOrphansOnRow:line + 1];
                           int right;
                           if (windowedRange.columnWindow.length) {
                               right = windowedRange.columnWindow.location + windowedRange.columnWindow.length;
                           } else {
                               right = width;
                           }
                           // If there is no text after this, insert a hard line break.
                           if (pad) {
                               for (int i = 0; i < numPreceedingNulls; i++) {
                                   VT100GridCoord coord =
                                      VT100GridCoordMake(right - numPreceedingNulls + i, line);
                                   appendString(@" ", [self defaultChar], coord);
                               }
                           } else if (numPreceedingNulls > 0) {
                               switch (nullPolicy) {
                                   case kiTermTextExtractorNullPolicyFromLastToEnd:
                                       [result deleteCharactersInRange:NSMakeRange(0, [result length])];
                                       [coords removeAllObjects];
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
                           return [result length] >= maxBytes;
                       }];

    if (trimSelectionTrailingSpaces) {
        NSInteger lengthBeforeTrimming = [result length];
        [result trimTrailingWhitespace];
        [coords removeObjectsInRange:NSMakeRange([result length],
                                                 lengthBeforeTrimming - [result length])];
    }
    return result;
}

- (VT100GridAbsCoordRange)rangeByTrimmingWhitespaceFromRange:(VT100GridAbsCoordRange)range {
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
    [self enumerateCharsInRange:windowedRange
                      charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
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
                       eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                           return NO;
                       }];
    if (!foundNonWhitespace) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    [self enumerateInReverseCharsInRange:windowedRange
                               charBlock:^BOOL(screen_char_t theChar, VT100GridCoord coord) {
                                   NSString *string = ScreenCharToStr(&theChar);
                                   if ([string rangeOfCharacterFromSet:whitespace].location != NSNotFound) {
                                       trimmedRange.end.x = coord.x;
                                       trimmedRange.end.y = coord.y + totalScrollbackOverflow;
                                       return NO;
                                   } else {
                                       return YES;
                                   }
                               }
                                eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                                    return NO;
                                }];

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

- (int)lineNumberWithStartOfWholeLineIncludingLine:(int)y
                              respectContinuations:(BOOL)respectContinuations
{
    int i = y;
    while (i > 0 && [self lineHasSoftEol:i - 1 respectContinuations:respectContinuations]) {
        i--;
    }
    return i;
}

- (int)lineNumberWithEndOfWholeLineIncludingLine:(int)y
                            respectContinuations:(BOOL)respectContinuations
{
    int i = y + 1;
    int maxY = [_dataSource numberOfLines];
    while (i < maxY && [self lineHasSoftEol:i - 1 respectContinuations:respectContinuations]) {
        i++;
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
        return (theLine[width].code == EOL_SOFT ||
                (theLine[width - 1].code == '\\' && !theLine[width - 1].complexChar));
    } else {
        return theLine[width].code == EOL_SOFT;
    }
}

// A tab filler orphan is a tab filler that is followed by a tab filler orphan or a
// non-tab character.
- (NSIndexSet *)tabFillerOrphansOnRow:(int)row {
    if (row < 0) {
        return nil;
    }
    NSMutableIndexSet *orphans = [NSMutableIndexSet indexSet];
    screen_char_t *line = [_dataSource getLineAtIndex:row];
    if (!line) {
        return nil;
    }
    BOOL haveTab = NO;
    for (int i = [self xLimit] - 1; i >= 0; i--) {
        if (line[i].code == '\t' && !line[i].complexChar) {
            haveTab = YES;
        } else if (line[i].code == TAB_FILLER && !line[i].complexChar) {
            if (!haveTab) {
                [orphans addIndex:i];
            }
        } else {
            haveTab = NO;
        }
    }
    return orphans;
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
        range = [self rangeForWrappedLineEncompassing:coord respectContinuations:YES];
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
               continuationChars:continuationChars
                          coords:coords];
    if (!respectHardNewlines) {
        content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    }
    return content;
}

- (void)enumerateCharsInRange:(VT100GridWindowedRange)range
                    charBlock:(BOOL (^)(screen_char_t theChar, VT100GridCoord coord))charBlock
                     eolBlock:(BOOL (^)(unichar code, int numPreceedingNulls, int line))eolBlock {
    int width = [_dataSource width];
    int startx = VT100GridWindowedRangeStart(range).x;
    int endx = range.columnWindow.length ? range.columnWindow.location + range.columnWindow.length
                                         : [_dataSource width];
    int bound = [_dataSource numberOfLines] - 1;
    BOOL fullWidth = ((range.columnWindow.location == 0 && range.columnWindow.length == width) ||
                      range.columnWindow.length <= 0);
    BOOL rightAligned = (range.columnWindow.location + range.columnWindow.length == width &&
                         range.columnWindow.location > 0);
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
            BOOL isNull;
            // If right-aligned then treat terminal spaces as nulls.
            if (rightAligned) {
                isNull = theLine[x].code == 0 || theLine[x].code == ' ';
            } else {
                isNull = theLine[x].code == 0;
            }
            if (!theLine[x].complexChar && isNull) {
                ++numNulls;
            } else {
                break;
            }
        }

        // Iterate over characters up to terminal nulls.
        for (int x = MAX(range.columnWindow.location, startx); x < endx - numNulls; x++) {
            if (charBlock) {
                if (charBlock(theLine[x], VT100GridCoordMake(x, y))) {
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
                              eolBlock:(BOOL (^)(unichar code, int numPreceedingNulls, int line))eolBlock {
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
                      charBlock:^BOOL(screen_char_t theChar, VT100GridCoord theCoord) {
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
    screen_char_t *theLine = [_dataSource getLineAtIndex:coord.y];
    return theLine[coord.x];
}

@end
