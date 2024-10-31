//
//  iTermWordExtractor.m
//  iTerm2
//
//  Created by George Nachman on 11/11/24.
//

#import "iTermWordExtractor.h"

#import "DebugLogging.h"
#import "iTermPreferences.h"

typedef NS_ENUM(NSUInteger, iTermAlphaNumericDefinition) {
    iTermAlphaNumericDefinitionNarrow,
    iTermAlphaNumericDefinitionUserDefined,
    iTermAlphaNumericDefinitionUnixCommands,
    iTermAlphaNumericDefinitionBigWords
};

@implementation iTermWordExtractor {
    VT100GridRange _logicalWindow;
}

- (instancetype)initWithLocation:(VT100GridCoord)location
                   maximumLength:(NSInteger)maximumLength
                             big:(BOOL)big {
    self = [super init];
    if (self) {
        _location = location;
        _maximumLength = maximumLength;
        _big = big;
    }
    return self;
}

- (void)setDataSource:(id<iTermWordExtractorDataSource>)dataSource {
    _dataSource = dataSource;
    _logicalWindow = dataSource.wordExtractorLogicalWindow;
}

- (VT100GridCoord)coordLockedToWindow:(VT100GridCoord)coord {
    if (_logicalWindow.length == 0) {
        return coord;
    }
    coord.x = MIN(MAX(coord.x, _logicalWindow.location),
                  _logicalWindow.location + _logicalWindow.length - 1);
    return coord;
}

- (BOOL)locationIsValid {
    return _location.y >= 0;
}

- (VT100GridWindowedRange)errorLocation {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1),
                                      _logicalWindow.location, _logicalWindow.length);
}

- (VT100GridWindowedRange)windowedRangeForBigWord {
    VT100GridCoord unsafeLocation = _location;
    if (unsafeLocation.y < 0) {
        return [self errorLocation];
    }
    const VT100GridCoord location = [_dataSource successorOfCoord:[self coordLockedToWindow:unsafeLocation]];
    const VT100GridCoord predecessor = [_dataSource predecessorOfCoord:location];

    const iTermTextExtractorClass classAtLocation =
        [self classForCharacter:[_dataSource characterAt:predecessor]
                       bigWords:YES];

    iTermWordExtractor *subExtractor = [[iTermWordExtractor alloc] initWithLocation:predecessor maximumLength:_maximumLength big:YES];
    subExtractor.dataSource = _dataSource;
    VT100GridWindowedRange wordRange = [subExtractor windowedRange];
    if (classAtLocation == kTextExtractorClassWhitespace) {
        subExtractor.location = [_dataSource predecessorOfCoord:wordRange.coordRange.start];
        const VT100GridWindowedRange beforeRange = [subExtractor windowedRange];
        wordRange.coordRange.start = beforeRange.coordRange.start;
    } else {
        // wordRange is a half-open interval so end gives the successor
        subExtractor.location = wordRange.coordRange.end;
        subExtractor.big = NO;
        const VT100GridWindowedRange afterRange = [subExtractor windowedRange];
        wordRange.coordRange.end = afterRange.coordRange.end;
    }
    return wordRange;
}

- (VT100GridWindowedRange)windowedRange {
    if (![self locationIsValid] || !self.dataSource) {
        return [self errorLocation];
    }

    DLog(@"Compute range for word at %@, max length %@",
         VT100GridCoordDescription(_location), @(_maximumLength));
    DLog(@"These special chars will be treated as alphanumeric: %@",
         [iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]);

    VT100GridCoord location = [self coordLockedToWindow:_location];

    return [self windowedRangeForLocation:location];
}

- (VT100GridWindowedRange)windowedRangeForLocation:(VT100GridCoord)location {
    iTermTextExtractorClass theClass =
    [self classForCharacter:[_dataSource characterAt:location] bigWords:_big];
    DLog(@"Initial class for '%@' at %@ is %@",
         [_dataSource stringForCharacter:[_dataSource characterAt:location]], VT100GridCoordDescription(location), @(theClass));
    if (theClass == kTextExtractorClassDoubleWidthPlaceholder) {
        DLog(@"Location is a DWC placeholder. Try again with predecessor");
        VT100GridCoord predecessor = [_dataSource predecessorOfCoord:location];
        if (predecessor.x != location.x || predecessor.y != location.y) {
            return [self windowedRangeForLocation:predecessor];
        }
    }

    if (theClass == kTextExtractorClassOther) {
        DLog(@"Character class is other, select one character.");
        return [_dataSource windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                           location.y,
                                                                           location.x + 1,
                                                                           location.y)];
    }

    const int xLimit = [_dataSource xLimit];
    const int width = [_dataSource wordExtractorWidth];
    const BOOL windowTouchesLeftMargin = (_logicalWindow.location == 0);
    const BOOL windowTouchesRightMargin = (xLimit == width);
    int numberOfLines = [_dataSource wordExtractroNumberOfLines];
    if (location.y >= numberOfLines) {
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1),
                                          _logicalWindow.location, _logicalWindow.length);
    }
    // Search forward for the end of the word.
    iTermWordExtractorForwardsSearchResult forwardResults = [self searchForwardsInRange:VT100GridCoordRangeMake(location.x,
                                                                                                                location.y,
                                                                                                                width,
                                                                                                                numberOfLines - 1)
                                                                           initialClass:theClass
                                                                windowTouchesLeftMargin:windowTouchesLeftMargin
                                                               windowTouchesRightMargin:windowTouchesRightMargin];

    // Search backward for the start of the word.
    iTermWordExtractorReverseSearchResult reverseResults = [self searchReverseInRange:VT100GridCoordRangeMake(0, 0, location.x, location.y)
                                                                         initialClass:theClass
                                                              windowTouchesLeftMargin:windowTouchesLeftMargin
                                                             windowTouchesRightMargin:windowTouchesRightMargin];

    NSString *stringBeforeLocation = [reverseResults.substrings componentsJoinedByString:@""];
    NSArray<NSValue *> *coords = [reverseResults.coords arrayByAddingObjectsFromArray:forwardResults.coords];

    if (!coords.count) {
        DLog(@"Found no coords");
        return [_dataSource windowedRangeWithRange:VT100GridCoordRangeMake(location.x,
                                                                           location.y,
                                                                           location.x,
                                                                           location.y)];
    }

    if (theClass != kTextExtractorClassWord || _big) {
        DLog(@"Not word class");
        VT100GridCoord start = [[coords firstObject] gridCoordValue];
        VT100GridCoord end = [[coords lastObject] gridCoordValue];
        return [_dataSource windowedRangeWithRange:VT100GridCoordRangeMake(start.x,
                                                                           start.y,
                                                                           end.x + 1,
                                                                           end.y)];
    }

    __block VT100GridWindowedRange result;
    [_dataSource performBlockWithLineCache:^{
        result = [self languageSpecificWindowedRangeWithStringBefore:stringBeforeLocation
                                                             lengths:reverseResults.stringLengthsInPrefix
                                                               after:forwardResults.stringFromLocation
                                                             indexes:forwardResults.indexesInSuffix
                                                              coords:coords];
    }];
    return result;
}

typedef struct {
    NSArray<NSNumber *> *indexesInSuffix;
    NSString *stringFromLocation;
    NSArray<NSValue *> *coords;
} iTermWordExtractorForwardsSearchResult;

- (iTermWordExtractorForwardsSearchResult)searchForwardsInRange:(VT100GridCoordRange)theRange
                                                   initialClass:(iTermTextExtractorClass)theClass
                                        windowTouchesLeftMargin:(BOOL)windowTouchesLeftMargin
                                       windowTouchesRightMargin:(BOOL)windowTouchesRightMargin
{
    __block NSInteger iterations = 0;
    // Has one entry for each cell in the word after `location`. Stores the
    // index into `stringFromLocation` where that cell's string begins.
    NSMutableArray<NSNumber *> *indexesInSuffix = [NSMutableArray array];
    // String composed of the characters found to be in the word, excluding private range characters.
    NSMutableString *stringFromLocation = [NSMutableString string];
    NSMutableArray<NSValue *> *coords = [NSMutableArray array];

    DLog(@"** Begin searching forward for the end of the word");
    [_dataSource enumerateCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                  _logicalWindow.location,
                                                                  _logicalWindow.length)
                           supportBidi:NO
                             charBlock:^BOOL(const screen_char_t *currentLine,
                                             screen_char_t theChar,
                                             iTermExternalAttribute *ea,
                                             VT100GridCoord logicalCoord,
                                             VT100GridCoord coord) {
        DLog(@"Character at %@ is '%@'", VT100GridCoordDescription(coord), [_dataSource stringForCharacter:theChar]);
        ++iterations;
        if (iterations > _maximumLength) {
            DLog(@"Max length hit when searching forwards");
            return YES;
        }
        iTermTextExtractorClass newClass = [self classForCharacter:theChar
                                                          bigWords:_big];
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
        return [_dataSource shouldStopEnumeratingWithCode:code
                                                 numNulls:numPrecedingNulls
                                  windowTouchesLeftMargin:windowTouchesLeftMargin
                                 windowTouchesRightMargin:windowTouchesRightMargin
                                         ignoringNewlines:NO];
    }];
    return (iTermWordExtractorForwardsSearchResult){
        .indexesInSuffix = indexesInSuffix,
        .stringFromLocation = stringFromLocation,
        .coords = coords,
    };
}

typedef struct {
    NSArray<NSString *> *substrings;
    NSArray<NSValue *> *coords;
    NSArray<NSNumber *> *stringLengthsInPrefix;
} iTermWordExtractorReverseSearchResult;

- (iTermWordExtractorReverseSearchResult)searchReverseInRange:(VT100GridCoordRange)theRange
                                                 initialClass:(iTermTextExtractorClass)theClass
                                      windowTouchesLeftMargin:(BOOL)windowTouchesLeftMargin
                                     windowTouchesRightMargin:(BOOL)windowTouchesRightMargin {
    DLog(@"** Begin searching backward for the end of the word");

    // We want to iterate backward over the string and concatenate characters in reverse order.
    // Appending to the start of a NSMutableString is very slow, but appending to the start of
    // a NSMutableArray is fast. So we build an array of tiny strings in the reverse order of how
    // they appear and then concatenate them after the enumeration.
    NSMutableArray *substrings = [NSMutableArray array];

    // Has one entry for each cell in the word before `location`. Stores the
    // length of the string at that cell. Typically 1, but can be long for
    // surrogate pair and composed characters.
    NSMutableArray<NSNumber *> *stringLengthsInPrefix = [NSMutableArray array];
    NSMutableArray<NSValue *> *coords = [NSMutableArray array];
    __block NSInteger iterations = 0;

    [_dataSource enumerateInReverseCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                           _logicalWindow.location,
                                                                           _logicalWindow.length)
                                      charBlock:^BOOL(screen_char_t theChar,
                                                      VT100GridCoord logicalCoord,
                                                      VT100GridCoord coord) {
        DLog(@"Character at %@ is '%@'", VT100GridCoordDescription(coord), [_dataSource stringForCharacter:theChar]);
        ++iterations;
        if (iterations > _maximumLength) {
            DLog(@"Max length hit when searching backwards");
            return YES;
        }
        iTermTextExtractorClass newClass = [self classForCharacter:theChar
                                                          bigWords:_big];
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
        return [_dataSource shouldStopEnumeratingWithCode:code
                                                 numNulls:numPrecedingNulls
                                  windowTouchesLeftMargin:windowTouchesLeftMargin
                                 windowTouchesRightMargin:windowTouchesRightMargin
                                         ignoringNewlines:NO];

    }];

    return (iTermWordExtractorReverseSearchResult) {
        .substrings = substrings,
        .coords = coords,
        .stringLengthsInPrefix = stringLengthsInPrefix,
    };
}

- (VT100GridWindowedRange)languageSpecificWindowedRangeWithStringBefore:(NSString *)stringBeforeLocation
                                                                lengths:(NSArray<NSNumber *> *)stringLengthsInPrefix
                                                                  after:(NSString *)stringFromLocation
                                                                indexes:(NSArray<NSNumber *> *)indexesInSuffix
                                                                 coords:(NSArray<NSValue *> *)coords {
    DLog(@"An alphanumeric character was selected. Begin language-specific logic");

    // An alphanumeric character was selected. This is where it gets interesting.

    // We have now retrieved the longest possible string that could have a word. This is because we
    // are more permissive than the OS about what can be in a word (the user can add punctuation,
    // for example, making foo/bar a word if / belongs to the “characters considered part of a
    // word.”) Now we want to shrink the range. For non-English languages, there is an added
    // wrinkle: in issue 4325 we see that 翻真的 consists of two words: 翻 and 真的. The OS
    // (presumably by using ICU's text boundary analysis code) knows how to do the segmentation.

    NSString *string = [stringBeforeLocation stringByAppendingString:stringFromLocation];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:@{}];

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

            end = [_dataSource indexInSortedArray:indexes
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
        start = [_dataSource indexInSortedArray:indexes
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
            start = [_dataSource indexInSortedArray:indexes
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
    if (endCoord.x < [_dataSource xLimit] && [_dataSource haveDoubleWidthExtensionAt:endCoord]) {
        endCoord.x += 1;
    }
    return [_dataSource windowedRangeWithRange:VT100GridCoordRangeMake(startCoord.x,
                                                                       startCoord.y,
                                                                       endCoord.x,
                                                                       endCoord.y)];
}

- (NSString *)fastStringAt:(VT100GridCoord)location {
    iTermTextExtractorClass theClass = [self classForCharacter:[_dataSource characterAt:location]];
    const int xLimit = [_dataSource xLimit];
    const int width = [_dataSource wordExtractorWidth];
    int numberOfLines = [_dataSource wordExtractroNumberOfLines];
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
        [_dataSource enumerateCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                      _logicalWindow.location,
                                                                      _logicalWindow.length)
                               supportBidi:NO
                                 charBlock:^BOOL(const screen_char_t *currentLine, screen_char_t theChar, iTermExternalAttribute *ea, VT100GridCoord logicalCoord, VT100GridCoord coord) {
            if (++iterations == maxLength) {
                return YES;
            }
            iTermTextExtractorClass newClass = [self classForCharacter:theChar definitionOfAlphanumeric:iTermAlphaNumericDefinitionUnixCommands];
            if (newClass == kTextExtractorClassWord) {
                foundWord = YES;
                if (theChar.complexChar ||
                    theChar.code < ITERM2_PRIVATE_BEGIN ||
                    theChar.code > ITERM2_PRIVATE_END) {
                    NSString *s = [_dataSource stringForCharacter:theChar];
                    [word appendString:s];
                }
                return NO;
            } else {
                return foundWord;
            }
        }
                                  eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
            return [_dataSource shouldStopEnumeratingWithCode:code
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
    [_dataSource enumerateInReverseCharsInRange:VT100GridWindowedRangeMake(theRange,
                                                                           _logicalWindow.location,
                                                                           _logicalWindow.length)
                                      charBlock:^BOOL(screen_char_t theChar,
                                                      VT100GridCoord logicalCoord,
                                                      VT100GridCoord coord) {
        if (++iterations == maxLength) {
            return YES;
        }
        iTermTextExtractorClass newClass = [self classForCharacter:theChar definitionOfAlphanumeric:iTermAlphaNumericDefinitionUnixCommands];
        if (newClass == kTextExtractorClassWord) {
            foundWord = YES;
            if (theChar.complexChar ||
                theChar.code < ITERM2_PRIVATE_BEGIN ||
                theChar.code > ITERM2_PRIVATE_END) {
                NSString *s = [_dataSource stringForCharacter:theChar];
                [word insertString:s atIndex:0];
            }
            return NO;
        } else {
            return foundWord;
        }

    }
                                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
        return [_dataSource shouldStopEnumeratingWithCode:code
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

- (BOOL)isWhitelistedAlphanumericAtCoord:(VT100GridCoord)coord {
    screen_char_t theChar = [_dataSource characterAt:coord];
    return [self characterShouldBeTreatedAsAlphanumeric:ScreenCharToStr(&theChar) definitionOfAlphanumeric:iTermAlphaNumericDefinitionUserDefined];
}

- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter {
    return [self classForCharacter:theCharacter bigWords:NO];
}

// Returns the class for a character.
- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter
                                    bigWords:(BOOL)bigWords {
    return [self classForCharacter:theCharacter definitionOfAlphanumeric:bigWords ? iTermAlphaNumericDefinitionBigWords : iTermAlphaNumericDefinitionUserDefined];
}

- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter
                    definitionOfAlphanumeric:(iTermAlphaNumericDefinition)definition {
    if (theCharacter.image) {
        return kTextExtractorClassOther;
    }
    if (!theCharacter.complexChar && !theCharacter.image) {
        if (theCharacter.code == TAB_FILLER) {
            return kTextExtractorClassWhitespace;
        } else if (theCharacter.code == DWC_RIGHT || theCharacter.complexChar == DWC_SKIP) {
            return kTextExtractorClassDoubleWidthPlaceholder;
        }
    }

    if (!theCharacter.code) {
        return kTextExtractorClassNull;
    }

    NSString *asString = [_dataSource stringForCharacter:theCharacter];
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
        case iTermAlphaNumericDefinitionBigWords:
            return [characterAsString rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound;
    }
}

- (NSString *)fastString {
    VT100GridCoord location = [self coordLockedToWindow:_location];
    iTermTextExtractorClass theClass =
    [self classForCharacter:[_dataSource characterAt:_location]];
    if (theClass == kTextExtractorClassDoubleWidthPlaceholder) {
        VT100GridCoord predecessor = [_dataSource predecessorOfCoord:_location];
        if (predecessor.x != _location.x || predecessor.y != _location.y) {
            return [self fastStringAt:predecessor];
        }
    } else if (theClass == kTextExtractorClassOther) {
        return nil;
    }
    return [self fastStringAt:location];
}

@end
