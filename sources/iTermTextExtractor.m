//
//  iTermTextExtractor.m
//  iTerm
//
//  Created by George Nachman on 2/17/14.
//
//

#import "iTermTextExtractor.h"
#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImageInfo.h"
#import "iTermLocatedString.h"
#import "iTermPreferences.h"
#import "iTermSystemVersion.h"
#import "iTermURLStore.h"
#import "iTermWordExtractor.h"
#import "NSStringITerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "RegexKitLite.h"
#import "PreferencePanel.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"

// Must find at least this many divider chars in a row for it to count as a divider.
static const int kNumCharsToSearchForDivider = 8;

const NSInteger kReasonableMaximumWordLength = 1000;
const NSInteger kLongMaximumWordLength = 100000;

@interface iTermTextExtractor()<iTermWordExtractorDataSource>
@end

@implementation iTermTextExtractor {
    VT100GridRange _logicalWindow;

    BOOL _shouldCacheLines;
    int _cachedLineNumber;
    const screen_char_t *_cachedLine;
    int _cachedExternalAttributeLineNumber;
    id<iTermExternalAttributeIndexReading> _cachedExternalAttributeIndex;
}

+ (instancetype)textExtractorWithDataSource:(id<iTermTextDataSource>)dataSource {
    return [[self alloc] initWithDataSource:dataSource];
}

+ (NSCharacterSet *)wordSeparatorCharacterSet
{
    NSMutableCharacterSet *charset = [[NSMutableCharacterSet alloc] init];
    [charset formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];

    NSMutableCharacterSet *complement = [[NSMutableCharacterSet alloc] init];
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
    iTermWordExtractor *wordExtractor = [[iTermWordExtractor alloc] initWithLocation:location maximumLength:-1 big:NO];
    wordExtractor.dataSource = self;
    return [wordExtractor fastString];
}

- (NSURL *)urlOfHypertextLinkAt:(VT100GridCoord)coord urlId:(out NSString **)urlId {
    iTermExternalAttribute *ea = [self externalAttributesAt:coord];
    if (urlId) {
        *urlId = ea.url.identifier;
    }
    return ea.url.url;
}

- (VT100GridWindowedRange)rangeOfCoordinatesAround:(VT100GridCoord)origin
                                   maximumDistance:(int)maximumDistance
                                       passingTest:(BOOL(^)(screen_char_t *c,
                                                            iTermExternalAttribute *ea,
                                                            VT100GridCoord coord))block {
    VT100GridCoord coord = origin;
    VT100GridCoord previousCoord = origin;
    coord = [self predecessorOfCoord:coord];
    screen_char_t c = [self characterAt:coord];
    iTermExternalAttribute *ea = [self externalAttributesAt:coord];
    int distanceLeft = maximumDistance;
    while (distanceLeft > 0 && !VT100GridCoordEquals(coord, previousCoord) && block(&c, ea, coord)) {
        previousCoord = coord;
        coord = [self predecessorOfCoord:coord];
        c = [self characterAt:coord];
        ea = [self externalAttributesAt:coord];
        distanceLeft--;
    }

    VT100GridWindowedRange range;
    range.columnWindow = _logicalWindow;
    range.coordRange.start = previousCoord;

    coord = origin;
    previousCoord = origin;
    coord = [self successorOfCoord:coord];
    c = [self characterAt:coord];
    ea = [self externalAttributesAt:coord];
    distanceLeft = maximumDistance;
    while (distanceLeft > 0 && !VT100GridCoordEquals(coord, previousCoord) && block(&c, ea, coord)) {
        previousCoord = coord;
        coord = [self successorOfCoord:coord];
        c = [self characterAt:coord];
        ea = [self externalAttributesAt:coord];
        distanceLeft--;
    }

    range.coordRange.end = coord;

    return range;
}

- (int)startOfIndentationOnAbsLine:(long long)absLine {
    const long long overflow = [_dataSource totalScrollbackOverflow];
    if (absLine < overflow) {
        return 0;
    }
    if (absLine - overflow > INT_MAX) {
        return 0;
    }
    return [self startOfIndentationOnLine:absLine - overflow];
}

- (int)startOfIndentationOnLine:(int)line {
    if (line >= [_dataSource numberOfLines]) {
        return 0;
    }
    __block int result = 0;
    [self enumerateCharsInRange:VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0,
                                                                                   line,
                                                                                   [_dataSource width], line),
                                                           _logicalWindow.location, _logicalWindow.length)
                    supportBidi:NO
                      charBlock:^BOOL(const screen_char_t *currentLine,
                                      screen_char_t theChar,
                                      iTermExternalAttribute *ea,
                                      VT100GridCoord logicalCoord,
                                      VT100GridCoord coord) {
        if (!theChar.complexChar &&
            !theChar.image &&
            (theChar.code == ' ' || theChar.code == '\t' || theChar.code == 0 || theChar.code == TAB_FILLER)) {
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

- (int)cellCountInWrappedLineWithAbsY:(long long)absY {
    int y = absY - self.dataSource.totalScrollbackOverflow;
    if (y < 0) {
        return self.dataSource.width;
    }
    if ([self.dataSource screenCharArrayForLine:y].eol == EOL_DWC) {
        return self.dataSource.width - 1;
    } else {
        return self.dataSource.width;
    }
}

- (int)rowCountForRawLineEncompassingWithAbsY:(long long)absY {
    const long long offset = self.dataSource.totalScrollbackOverflow;
    const VT100GridCoordRange lineRange =
    [self rangeForWrappedLineEncompassing:VT100GridCoordMake(0, absY - offset)
                          respectContinuations:NO
                                      maxChars:-1].coordRange;
    return lineRange.end.y - absY + 1;
}

- (VT100GridAbsWindowedRange)rangeForWordAtAbsCoord:(VT100GridAbsCoord)absLocation
                                      maximumLength:(NSInteger)maximumLength {
    return VT100GridAbsWindowedRangeFromWindowedRange([self rangeForWordAt:[self coordFromAbsolute:absLocation]
                                                             maximumLength:maximumLength],
                                                      [_dataSource totalScrollbackOverflow]);
}

- (VT100GridWindowedRange)rangeForWordAt:(VT100GridCoord)location
                           maximumLength:(NSInteger)maximumLength {
    return [self rangeForWordAt:location maximumLength:maximumLength big:NO];
}

- (VT100GridAbsWindowedRange)rangeForBigWordAtAbsCoord:(VT100GridAbsCoord)location
                                         maximumLength:(NSInteger)maximumLength {
    return VT100GridAbsWindowedRangeFromWindowedRange([self rangeForBigWordAt:[self coordFromAbsolute:location]
                                                                maximumLength:maximumLength],
                                                      [_dataSource totalScrollbackOverflow]);
}

- (VT100GridWindowedRange)rangeForBigWordAt:(VT100GridCoord)unsafeLocation
                              maximumLength:(NSInteger)maximumLength {
    iTermWordExtractor *wordExtractor = [[iTermWordExtractor alloc] initWithLocation:unsafeLocation
                                                                       maximumLength:maximumLength
                                                                                 big:YES];
    wordExtractor.dataSource = self;
    return [wordExtractor windowedRangeForBigWord];
}

// The maximum length is a rough guideline. You might get a word up to twice as long.
- (VT100GridWindowedRange)rangeForWordAt:(VT100GridCoord)visualLocation
                           maximumLength:(NSInteger)maximumLength
                                     big:(BOOL)big {
    VT100GridCoord location = visualLocation;
    iTermBidiDisplayInfo *bidi = nil;
    if (_supportBidi) {
        ScreenCharArray *sca = [_dataSource screenCharArrayForLine:visualLocation.y];
        bidi = sca.bidiInfo;
        if (bidi) {
            location.x = [bidi logicalForVisual:visualLocation.x];
        }
    }
    iTermWordExtractor *wordExtractor = [[iTermWordExtractor alloc] initWithLocation:location
                                                                       maximumLength:maximumLength
                                                                                 big:big];
    wordExtractor.dataSource = self;
    VT100GridWindowedRange range = [wordExtractor windowedRange];
    if (bidi) {
#warning TODO: This is wrong. When a word wraps, we need to select characters from the left side of the start line and the right side of the end line. Selections don't know how to do this currently.
        return [self visualWindowedRangeForLogical:range];
    }
    return range;
}

- (VT100GridCoordRange)visualRangeForLogical:(VT100GridCoordRange)logical {
    VT100GridCoordRange visual;

    VT100GridCoord a = [self visualCoordForLogical:logical.start];
    VT100GridCoord b = [self visualCoordForLogical:[self predecessorOfCoord:logical.end]];

    // Convert back to half-open range with start <= end.
    if (VT100GridCoordCompare(a, b) == NSOrderedDescending) {
        visual.start = b;
        a.x += 1;
        visual.end = a;
    } else {
        visual.start = a;
        b.x += 1;
        visual.end = b;
    }
    return visual;
}

- (VT100GridWindowedRange)visualWindowedRangeForLogical:(VT100GridWindowedRange)logical {
    VT100GridWindowedRange visual = logical;
    visual.coordRange = [self visualRangeForLogical:logical.coordRange];
    return visual;
}

- (VT100GridCoord)visualCoordForLogical:(VT100GridCoord)logical {
    if (!_supportBidi) {
        return logical;
    }
    ScreenCharArray *sca = [_dataSource screenCharArrayForLine:logical.y];
    iTermBidiDisplayInfo *bidi = sca.bidiInfo;
    if (!bidi) {
        return logical;
    }
    return VT100GridCoordMake([bidi visualForLogical:logical.x], logical.y);
}

// Make characterAt: much faster when called with the same line number over and over again. Assumes
// the line buffer won't be mutated while it's running.
- (void)performBlockWithLineCache:(void (^NS_NOESCAPE)(void))block {
    assert(!_shouldCacheLines);
    _shouldCacheLines = YES;
    block();
    _shouldCacheLines = NO;
    _cachedLine = nil;
    _cachedExternalAttributeIndex = nil;
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

- (NSString *)stringForCharacter:(screen_char_t)theChar {
    unichar temp[kMaxParts];
    int length = ExpandScreenChar(&theChar, temp);
    return [NSString stringWithCharacters:temp length:length];
}

- (NSString *)stringForCharacterAt:(VT100GridCoord)location {
    const screen_char_t *theLine = [_dataSource screenCharArrayForLine:location.y].line;
    unichar temp[kMaxParts];
    int length = ExpandScreenChar(theLine + location.x, temp);
    return [NSString stringWithCharacters:temp length:length];
}

- (NSIndexSet *)indexesOnLine:(int)line containingCharacter:(unichar)c inRange:(NSRange)range {
    const screen_char_t *theLine = [_dataSource screenCharArrayForLine:line].line;
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (int i = range.location; i < range.location + range.length; i++) {
        if (theLine[i].code == c && !theLine[i].complexChar && !theLine[i].image) {
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
    const int numLines = [iTermAdvancedSettingsModel smartSelectionRadius];
    NSMutableArray* coords = [NSMutableArray arrayWithCapacity:numLines * _logicalWindow.length];
    NSString *textWindow = [self textAround:location
                                     radius:numLines
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
                        SmartMatch* match = [[SmartMatch alloc] init];
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

- (VT100GridCoord)coordFromAbsolute:(VT100GridAbsCoord)absCoord {
    const long long overflow = [_dataSource totalScrollbackOverflow];
    if (absCoord.y < overflow) {
        return VT100GridCoordMake(0, 0);
    }
    if (absCoord.y - overflow > INT_MAX) {
        return VT100GridCoordMake(absCoord.x, [_dataSource numberOfLines]);
    }
    return VT100GridCoordMake(absCoord.x, absCoord.y - overflow);
}

- (VT100GridAbsCoord)coordToAbsolute:(VT100GridCoord)coord {
    return VT100GridAbsCoordMake(coord.x, [_dataSource totalScrollbackOverflow] + coord.y);
}

- (VT100GridAbsCoord)successorOfAbsCoordSkippingContiguousNulls:(VT100GridAbsCoord)absCoord {
    const VT100GridCoord coord = [self coordFromAbsolute:absCoord];
    VT100GridCoord result = [self successorOfCoordSkippingContiguousNulls:coord];
    return [self coordToAbsolute:result];
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

- (VT100GridAbsCoord)predecessorOfAbsCoordSkippingContiguousNulls:(VT100GridAbsCoord)coord {
    return [self coordToAbsolute:[self predecessorOfCoordSkippingContiguousNulls:[self coordFromAbsolute:coord]]];
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
                       andCoord:(VT100GridCoord)coord2 {
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
                                              andCoord:prevCoord];
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
                                           andCoord:prevCoord];
                prevCoord = coord;
            }
        } else {
            // If n was positive, move it left and down until it's legal.
            while (coord.x >= right) {
                coord.x -= span;
                coord.y++;
                n += [self numberOfCoordsInIndexSet:coordsToSkip
                                            between:coord
                                           andCoord:prevCoord];
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
    int y = coord.y;
    const screen_char_t *theLine = [_dataSource screenCharArrayForLine:coord.y].line;
    while (1) {
        if (y != coord.y) {
            theLine = [_dataSource screenCharArrayForLine:coord.y].line;
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
                               charBlock:^BOOL(screen_char_t theChar,
                                               VT100GridCoord logicalCoord,
                                               VT100GridCoord charCoord) {
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
                                   } else if (theChar.image) {
                                       // Treat images as nulls.
                                       return YES;
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
                                                       windowTouchesLeftMargin:(self->_logicalWindow.location == 0)
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
                    supportBidi:NO
                      charBlock:^BOOL(const screen_char_t *currentLine,
                                      screen_char_t theChar,
                                      iTermExternalAttribute *ea,
                                      VT100GridCoord logicalCoord,
                                      VT100GridCoord charCoord) {
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
                          } else if (theChar.image) {
                              // Treat images as nulls.
                              return YES;
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

- (void)enumerateWrappedLinesIntersectingRange:(VT100GridRange)range
                                         block:(void (^)(iTermStringLine *, VT100GridWindowedRange, BOOL *))block {
    if (range.length <= 0) {
        return;
    }
    if (range.location < 0) {
        [self enumerateWrappedLinesIntersectingRange:VT100GridRangeMake(0, range.length + range.location) block:block];
        return;
    }
    int line = range.location;
    while (line <= range.location + range.length - 1 && line < [_dataSource numberOfLines]) {
        VT100GridWindowedRange lineRange = [self rangeForWrappedLineEncompassing:VT100GridCoordMake(0, line)
                                                            respectContinuations:YES
                                                                        maxChars:-1];

        iTermStringLine *stringLine = [self stringLineInRange:lineRange];
        BOOL stop = NO;
        block(stringLine, lineRange, &stop);
        if (stop) {
            return;
        }
        line = MAX(line + 1, lineRange.coordRange.end.y + 1);
    }
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
                    supportBidi:NO
                      charBlock:^BOOL(const screen_char_t *currentLine,
                                      screen_char_t theChar,
                                      iTermExternalAttribute *ea,
                                      VT100GridCoord logicalCoord,
                                      VT100GridCoord coord) {
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

- (NSAttributedString *)attributedStringForSnippetForRange:(VT100GridAbsCoordRange)range
                                         regularAttributes:(NSDictionary *)regularAttributes
                                           matchAttributes:(NSDictionary *)matchAttributes
                                       maximumPrefixLength:(NSUInteger)maximumPrefixLength
                                       maximumSuffixLength:(NSUInteger)maximumSuffixLength {
    const VT100GridCoordRange relativeRange =
        VT100GridCoordRangeFromAbsCoordRange(range, self.dataSource.totalScrollbackOverflow);
    const NSInteger maxMatchLength = 1024;
    NSString *match = [self contentInRange:VT100GridWindowedRangeMake(relativeRange, _logicalWindow.location, _logicalWindow.length)
                         attributeProvider:nil
                                nullPolicy:kiTermTextExtractorNullPolicyFromLastToEnd
                                       pad:NO
                        includeLastNewline:NO
                    trimTrailingWhitespace:NO
                              cappedAtSize:maxMatchLength
                              truncateTail:YES
                         continuationChars:nil
                                    coords:nil];
    NSAttributedString *matchString = [[NSAttributedString alloc] initWithString:match
                                                                      attributes:matchAttributes];
    if (match.length == maxMatchLength) {
        return matchString;
    }
    NSString *prefix = [[self wrappedLocatedStringAt:relativeRange.start
                                             forward:NO
                                 respectHardNewlines:YES
                                            maxChars:maximumPrefixLength
                                   continuationChars:nil
                                 convertNullsToSpace:NO].string stringByTrimmingLeadingWhitespace];
    NSString *suffix = [[self wrappedLocatedStringAt:relativeRange.end
                                             forward:YES
                                 respectHardNewlines:YES
                                            maxChars:maximumSuffixLength + 1
                                   continuationChars:nil
                                 convertNullsToSpace:NO].string stringByTrimmingTrailingWhitespace];
    if (suffix.length > maximumSuffixLength) {
        suffix = [[[suffix stringByDroppingLastCharacters:1] stringByTrimmingOrphanedSurrogates] stringByAppendingString:@"…"];
    }
    NSAttributedString *attributedPrefix = [[NSAttributedString alloc] initWithString:prefix
                                                                           attributes:regularAttributes];
    NSAttributedString *attributedSuffix = [[NSAttributedString alloc] initWithString:suffix
                                                                           attributes:regularAttributes];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:attributedPrefix];
    [result appendAttributedString:matchString];
    [result appendAttributedString:attributedSuffix];
    return result;
}

- (id)contentInRange:(VT100GridWindowedRange)windowedRange
   attributeProvider:(NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProvider
          nullPolicy:(iTermTextExtractorNullPolicy)nullPolicy
                 pad:(BOOL)pad
  includeLastNewline:(BOOL)includeLastNewline
trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces
        cappedAtSize:(int)maxBytes
        truncateTail:(BOOL)truncateTail
   continuationChars:(NSMutableIndexSet *)continuationChars
              coords:(iTermGridCoordArray *)coordsOut {
    __kindof iTermLocatedString *locatedString =
    [self locatedStringInRange:windowedRange
             attributeProvider:attributeProvider
                    nullPolicy:nullPolicy
                           pad:pad
            includeLastNewline:includeLastNewline
        trimTrailingWhitespace:trimSelectionTrailingSpaces
                  cappedAtSize:maxBytes
                  truncateTail:truncateTail
             continuationChars:continuationChars];
    [coordsOut appendContentsOfArray:locatedString.gridCoords];
    return attributeProvider ? ((iTermLocatedAttributedString *)locatedString).attributedString : locatedString.string;
}

- (id)locatedStringInRange:(VT100GridWindowedRange)windowedRange
         attributeProvider:(NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProvider
                nullPolicy:(iTermTextExtractorNullPolicy)nullPolicy
                       pad:(BOOL)pad
        includeLastNewline:(BOOL)includeLastNewline
    trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces
              cappedAtSize:(int)maxBytes
              truncateTail:(BOOL)truncateTail
         continuationChars:(NSMutableIndexSet *)continuationChars {
    DLog(@"Find selected text in range %@ pad=%d, includeLastNewline=%d, trim=%d",
         VT100GridWindowedRangeDescription(windowedRange), (int)pad, (int)includeLastNewline,
         (int)trimSelectionTrailingSpaces);
    __block iTermLocatedString *locatedString;
    __block iTermLocatedAttributedString *locatedAttributedString;
    // Appends a string to |result|, either attributed or not, as appropriate.
    void (^appendString)(NSString *, screen_char_t, iTermExternalAttribute *, VT100GridCoord) =
    ^void(NSString *string, screen_char_t theChar, iTermExternalAttribute *ea, VT100GridCoord coord) {
        if (attributeProvider) {
            [locatedAttributedString appendString:string
                                   withAttributes:attributeProvider(theChar, ea)
                                               at:coord];
        } else {
            [locatedString appendString:string at:coord];
        }
    };

    if (attributeProvider) {
        locatedAttributedString = [[iTermLocatedAttributedString alloc] init];
        locatedString = locatedAttributedString;
    } else {
        locatedString = [[iTermLocatedString alloc] init];
    }

    if (maxBytes < 0) {
        maxBytes = INT_MAX;
    }
    const NSUInteger kMaximumOversizeAmountWhenTruncatingHead = 1024 * 100;
    int width = [_dataSource width];
    __block BOOL lineContainsNonImage = NO;
    __block BOOL lineContainsImage = NO;
    __block BOOL copiedImage = NO;
    __block BOOL needsTimestamps = self.addTimestamps;
    [self enumerateCharsInRange:windowedRange
                    supportBidi:YES
                      charBlock:^BOOL(const screen_char_t *currentLine,
                                      screen_char_t theChar,
                                      iTermExternalAttribute *ea,
                                      VT100GridCoord logicalCoord,
                                      VT100GridCoord visualCoord) {
        if (needsTimestamps) {
            appendString([self formattedTimestampForLine:logicalCoord.y],
                         (screen_char_t) { .code = 0, .complexChar = 0, .image = 0}, nil, logicalCoord);
            needsTimestamps = NO;
        }
        if (theChar.image) {
            lineContainsImage = YES;
        } else {
            lineContainsNonImage = YES;
        }
        if (theChar.image) {
            // TODO: Support virtual placeholders
            if (attributeProvider && theChar.foregroundColor == 0 && theChar.backgroundColor == 0 && theChar.virtualPlaceholder == 0) {
                id<iTermImageInfoReading> imageInfo = GetImageInfo(theChar.code);
                NSImage *image = imageInfo.image.images.firstObject;
                if (image) {
                    copiedImage = YES;
                    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
                    textAttachment.image = imageInfo.image.images.firstObject;
                    NSAttributedString *attributedStringWithAttachment = [NSAttributedString attributedStringWithAttachment:textAttachment];
                    [locatedAttributedString appendAttributedString:attributedStringWithAttachment
                                                                 at:logicalCoord];
                }
            }
        } else if (ea.controlCode.valid) {
            if (theChar.code != '^') {
                appendString([NSString stringWithLongCharacter:ea.controlCode.code], theChar, ea, logicalCoord);
            }
        } else if (theChar.code == TAB_FILLER && !theChar.complexChar) {
            // Convert orphan tab fillers (those without a subsequent
            // tab character) into spaces.
            if ([self tabFillerAtIndex:logicalCoord.x isOrphanInLine:currentLine]) {
                appendString(@" ", theChar, ea, logicalCoord);
            }
        } else if (theChar.code == 0 && !theChar.complexChar) {
            // This is only reached for midline nulls; nulls at the end of the
            // line end up in eolBlock.
            switch (nullPolicy) {
                case kiTermTextExtractorNullPolicyFromLastToEnd:
                    [locatedString erase];
                    break;
                case kiTermTextExtractorNullPolicyFromStartToFirst:
                    return YES;
                case kiTermTextExtractorNullPolicyTreatAsSpace:
                case kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal:
                    appendString(@" ", theChar, ea, logicalCoord);
                    break;
            }
        } else if (theChar.complexChar || (theChar.code != DWC_RIGHT &&
                                           theChar.code != DWC_SKIP)) {
            // Normal character. Add it unless it's a backslash at the right edge
            // of a window.
            if (continuationChars &&
                windowedRange.columnWindow.length > 0 &&
                visualCoord.x == windowedRange.columnWindow.location + windowedRange.columnWindow.length - 1 &&
                theChar.code == '\\' &&
                !theChar.complexChar) {
                // Is a backslash at the right edge of a window.
                [continuationChars addIndex:[self indexForCoord:logicalCoord width:width]];
            } else {
                // Normal character.
                appendString(ScreenCharToStr(&theChar) ?: @"", theChar, ea, logicalCoord);
            }
        }
        if (truncateTail) {
            return [locatedString length] >= maxBytes;
        } else if ([locatedString length] > maxBytes + kMaximumOversizeAmountWhenTruncatingHead) {
            // Truncate from head when significantly oversize.
            //
            // Removing byte from the beginning of the string is slow. The only reason to do it is to save
            // memory. Remove a big chunk periodically. After enumeration is done we'll cut it to the
            // exact size it needs to be.
            [locatedString dropFirst:locatedString.length - maxBytes];
        }
        return NO;
    }
                       eolBlock:^BOOL(unichar code, int numPrecedingNulls, int line) {
        if (needsTimestamps) {
            VT100GridCoord coord = VT100GridCoordMake(0, line);
            appendString([self formattedTimestampForLine:coord.y],
                         [self defaultChar],
                         nil,
                         coord);
        }
        needsTimestamps = self.addTimestamps;
        self.progress.fraction = (double)(line - windowedRange.coordRange.start.y) / (double)(windowedRange.coordRange.end.y - windowedRange.coordRange.start.y + 1);
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
                appendString(@" ", [self defaultChar], nil, coord);
            }
        } else if (numPrecedingNulls > 0) {
            switch (nullPolicy) {
                case kiTermTextExtractorNullPolicyFromLastToEnd:
                    [locatedString erase];
                    shouldAppendNewline = NO;
                    break;
                case kiTermTextExtractorNullPolicyFromStartToFirst:
                    return YES;
                case kiTermTextExtractorNullPolicyTreatAsSpace:
                    appendString(@" ",
                                 [self defaultChar],
                                 nil,
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
                [locatedString trimTrailingWhitespace];
            }
            appendString(@"\n",
                         [self defaultChar],
                         nil,
                         VT100GridCoordMake(right, line));
        }
        if (truncateTail) {
            return locatedString.length >= maxBytes;
        } else if (locatedString.length > maxBytes + kMaximumOversizeAmountWhenTruncatingHead) {
            // Truncate from head when significantly oversize.
            //
            // Removing byte from the beginning of the string is slow. The only reason to do it is to save
            // memory. Remove a big chunk periodically. After enumeration is done we'll cut it to the
            // exact size it needs to be.
            [locatedString dropFirst:locatedString.length - maxBytes];
        }
        return NO;
    }];
    self.progress.fraction = 1.0;

    if (!truncateTail && locatedString.length > maxBytes) {
        // Truncate the head to the exact size.
        [locatedString dropFirst:locatedString.length - maxBytes];
    }

    if (trimSelectionTrailingSpaces) {
        [locatedString trimTrailingWhitespace];
    }
    return locatedString;
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
                        supportBidi:NO
                          charBlock:^BOOL(const screen_char_t *currentLine,
                                          screen_char_t theChar,
                                          iTermExternalAttribute *ea,
                                          VT100GridCoord logicalCoord,
                                          VT100GridCoord coord) {
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
                                   charBlock:^BOOL(screen_char_t theChar,
                                                   VT100GridCoord logicalCoord,
                                                   VT100GridCoord coord) {
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

- (NSString *)formattedTimestampForLine:(int)line {
    NSDate *date = [self.dataSource dateForLine:line];
    static NSString *format;
    static dispatch_once_t onceToken;
    static NSDateFormatter *formatter;
    dispatch_once(&onceToken, ^{
        format = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd HH:mm:ss"
                                                    options:0
                                                     locale:[NSLocale currentLocale]];
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = format;
    });
    NSString *content;
    if (date) {
        content = [formatter stringFromDate:date];
    } else {
        content = [[formatter stringFromDate:[NSDate date]] stringByReplacingOccurrencesOfRegex:@"." withString:@" "];
    }
    return [NSString stringWithFormat:@"[%@] ", content];
}

- (BOOL)haveDoubleWidthExtensionAt:(VT100GridCoord)coord {
    screen_char_t sct = [self characterAt:coord];
    return !sct.complexChar && !sct.image && (sct.code == DWC_RIGHT || sct.code == DWC_SKIP);
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

- (BOOL)lineHasSoftEol:(int)y respectContinuations:(BOOL)respectContinuations {
    ScreenCharArray *sca = [_dataSource screenCharArrayForLine:y];
    const screen_char_t *theLine = sca.line;
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
        return (sca.eol != EOL_HARD ||
                (theLine[width - 1].code == '\\' && !theLine[width - 1].complexChar));
    } else {
        return sca.eol != EOL_HARD;
    }
}

- (BOOL)tabFillerAtIndex:(int)index isOrphanInLine:(const screen_char_t *)line {
    // A tab filler orphan is a tab filler that is followed by a tab filler orphan or a
    // non-tab character.
    int xLimit = [self xLimit];
    for (int i = index + 1; i < xLimit; i++) {
        if (line[i].complexChar || line[i].image) {
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

- (ScreenCharArray *)screenCharArrayAtLine:(int)line {
    return [_dataSource screenCharArrayForLine:line];
}

- (ScreenCharArray *)screenCharArrayAtLine:(int)line window:(VT100GridRange)window {
    return [[_dataSource screenCharArrayForLine:line] inWindow:window];
}

- (iTermStringLine *)stringLineInRange:(VT100GridWindowedRange)range {
    ScreenCharArray *array = [self combinedLinesInWindowedRange:range];
    return [[iTermStringLine alloc] initWithScreenChars:array.line length:array.length];
}

- (ScreenCharArray *)combinedLinesInWindowedRange:(VT100GridWindowedRange)range {
    ScreenCharArray *result = [[ScreenCharArray alloc] init];
    for (NSInteger i = range.coordRange.start.y; i <= range.coordRange.end.y; i++) {
        result = [result screenCharArrayByAppendingScreenCharArray:[self screenCharArrayAtLine:i window:range.columnWindow]];
    }
    return result;
}

- (ScreenCharArray *)combinedLinesInRange:(NSRange)range {
    ScreenCharArray *result = [[ScreenCharArray alloc] init];
    for (NSInteger i = range.location;
         i < NSMaxRange(range);
         i++) {
        result = [result screenCharArrayByAppendingScreenCharArray:[self screenCharArrayAtLine:i]];
    }
    return result;
}

- (iTermLocatedString *)wrappedLocatedStringAt:(VT100GridCoord)coord
                                       forward:(BOOL)forward
                           respectHardNewlines:(BOOL)respectHardNewlines
                                      maxChars:(int)maxChars
                             continuationChars:(NSMutableIndexSet *)continuationChars
                           convertNullsToSpace:(BOOL)convertNullsToSpace {
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
            return [[iTermLocatedString alloc] init];
        }
    } else {
        nullPolicy = kiTermTextExtractorNullPolicyFromLastToEnd;
        // This doesn't include the boundary character when returning a prefix because we don't
        // want it twice when getting the prefix and suffix at the same coord.
        range.coordRange.end = coord;
        if (VT100GridCoordOrder(range.coordRange.start,
                                range.coordRange.end) != NSOrderedAscending) {
            return [[iTermLocatedString alloc] init];
        }
    }
    if (convertNullsToSpace) {
        nullPolicy = kiTermTextExtractorNullPolicyTreatAsSpace;
    }
    if (range.coordRange.start.x >= _dataSource.width) {
        range.coordRange.start.x = 0;
        range.coordRange.start.y += 1;
    }
    iTermLocatedString *locatedString =
        [self locatedStringInRange:range
                 attributeProvider:nil
                        nullPolicy:nullPolicy
                               pad:NO
                includeLastNewline:NO
            trimTrailingWhitespace:NO
                      cappedAtSize:maxChars
                      truncateTail:forward
                 continuationChars:continuationChars];
    if (!respectHardNewlines) {
        [locatedString removeOcurrencesOfString:@"\n"];
    }
    return locatedString;
}

- (void)enumerateCharsInRange:(VT100GridWindowedRange)range
                  supportBidi:(BOOL)supportBidi
                    charBlock:(BOOL (^NS_NOESCAPE)(const screen_char_t *currentLine,
                                                   screen_char_t theChar,
                                                   iTermExternalAttribute *,
                                                   VT100GridCoord logicalCoord,
                                                   VT100GridCoord visualCoord))charBlock
                     eolBlock:(BOOL (^NS_NOESCAPE)(unichar code, int numPrecedingNulls, int line))eolBlock {
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
        if (self.stopAsSoonAsPossible) {
            DLog(@"Aborted");
            break;
        }
        if (y == range.coordRange.end.y) {
            // Reduce endx for last line.
            const int reducedEndX = range.columnWindow.length ? VT100GridWindowedRangeEnd(range).x : range.coordRange.end.x;
            endx = MAX(0, MIN(endx, reducedEndX));
        }
        ScreenCharArray *sca = [_dataSource screenCharArrayForLine:y];
        const screen_char_t *theLine = sca.line;
        id<iTermExternalAttributeIndexReading> eaIndex = [_dataSource externalAttributeIndexForLine:y];

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

        iTermBidiDisplayInfo *bidi = _supportBidi ? sca.bidiInfo : nil;
        if (charBlock) {
            if (supportBidi && bidi) {
                const NSRange visualRange = NSMakeRangeFromHalfOpenInterval(MIN(width - 1, MAX(range.columnWindow.location, startx)),
                                                                            endx);
                [bidi enumerateLogicalRangesIn:visualRange closure:^(NSRange logicalRange, int visualStart, BOOL *stop) {
                    for (int i = 0; i < logicalRange.length; i++) {
                        int x = logicalRange.location + i;
                        if (charBlock(theLine, theLine[x], eaIndex[x], VT100GridCoordMake(x, y), VT100GridCoordMake(visualStart + i, y))) {
                            *stop = YES;
                            return;
                        }
                    }
                }];
            } else {
                // Iterate over characters up to terminal nulls.
                for (int x = MIN(width - 1, MAX(range.columnWindow.location, startx)); x < endx - numNulls; x++) {
                    ITAssertWithMessage(x >= 0 && x < width, @"Iterating terminal nulls. x=%@ range=%@ width=%@ numNulls=%@", @(x), VT100GridWindowedRangeDescription(range), @(width), @(numNulls));
                    if (charBlock(theLine, theLine[x], eaIndex[x], VT100GridCoordMake(x, y), VT100GridCoordMake(x, y))) {
                        return;
                    }
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
                stop = eolBlock(sca.eol, numNulls, y);
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

static NSRange NSMakeRangeFromHalfOpenInterval(NSUInteger lowerBound, NSUInteger openUpperBound) {
    assert(lowerBound <= openUpperBound);
    return NSMakeRange(lowerBound, openUpperBound - lowerBound);
}

// NOTE: This enumerates in logical order. RTL characters will not actually be reversed.
- (void)enumerateInReverseCharsInRange:(VT100GridWindowedRange)range
                             charBlock:(BOOL (^NS_NOESCAPE)(screen_char_t theChar, VT100GridCoord logicalCoord, VT100GridCoord visualCoord))charBlock
                              eolBlock:(BOOL (^NS_NOESCAPE)(unichar code, int numPrecedingNulls, int line))eolBlock {
    int xLimit = range.columnWindow.length == 0 ? [_dataSource width] :
        (range.columnWindow.location + range.columnWindow.length);
    int initialX = MIN(xLimit - 1, range.coordRange.end.x - 1);
    int trueWidth = [_dataSource width];
    const int yLimit = MAX(0, range.coordRange.start.y);
    for (int y = MIN([_dataSource numberOfLines] - 1, range.coordRange.end.y);
         y >= yLimit;
         y--) {
        if (self.stopAsSoonAsPossible) {
            DLog(@"Aborted");
            break;
        }
        ScreenCharArray *sca = [_dataSource screenCharArrayForLine:y];
        const screen_char_t *theLine = sca.line;
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
                    if (eolBlock(sca.eol, numNulls, y)) {
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
                VT100GridCoord coord = VT100GridCoordMake(x, y);
                if (charBlock(theLine[x], coord, coord)) {
                    return;
                }
            }
        }
        initialX = xLimit - 1;
    }
}

- (int)lengthOfAbsLine:(long long)absLine {
    const long long overflow = [_dataSource totalScrollbackOverflow];
    if (absLine < overflow) {
        return 0;
    }
    if (absLine - overflow > INT_MAX) {
        return 0;
    }
    return [self lengthOfLine:absLine - overflow];
}

- (int)lengthOfLine:(int)line {
    const screen_char_t *theLine = [_dataSource screenCharArrayForLine:line].line;
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
                    supportBidi:NO
                      charBlock:^BOOL(const screen_char_t *currentLine,
                                      screen_char_t theChar,
                                      iTermExternalAttribute *ea,
                                      VT100GridCoord logicalCoord,
                                      VT100GridCoord theCoord) {
                          if (!theChar.complexChar &&
                              [columnDividers characterIsMember:theChar.code]) {
                              [indexes addIndex:theCoord.x];
                          }
                          return NO;
                      }
                       eolBlock:nil];
    return indexes;
}

- (NSCharacterSet *)columnDividers {
    static NSMutableCharacterSet *charSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        charSet = [[NSMutableCharacterSet alloc] init];
        [charSet addCharactersInString:@"|\u2502\u251c\u2524"];
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

- (screen_char_t)characterAtAbsCoord:(VT100GridAbsCoord)coord {
    const long long overflow = [_dataSource totalScrollbackOverflow];
    if (coord.y < overflow || coord.y - overflow > INT_MAX) {
        screen_char_t zero = { 0 };
        return zero;
    }
    return [self characterAt:[self coordFromAbsolute:coord]];
}

- (VT100GridCoord)logicalCoordForVisualCoord:(VT100GridCoord)visualCoord {
    if (!_supportBidi) {
        return visualCoord;
    }
    iTermBidiDisplayInfo *bidi = nil;
    ScreenCharArray *sca = [_dataSource screenCharArrayForLine:visualCoord.y];
    bidi = sca.bidiInfo;
    if (!bidi) {
        return visualCoord;
    }
    VT100GridCoord logicalCoord = visualCoord;
    logicalCoord.x = [bidi logicalForVisual:visualCoord.x];
    return logicalCoord;
}

- (screen_char_t)characterAtVisualCoord:(VT100GridCoord)visualCoord {
    return [self characterAt:[self logicalCoordForVisualCoord:visualCoord]];
}

- (screen_char_t)characterAt:(VT100GridCoord)coord {
    if (_shouldCacheLines && coord.y == _cachedLineNumber && _cachedLine != nil) {
        return _cachedLine[coord.x];
    }
    ScreenCharArray *sca = [_dataSource screenCharArrayForLine:coord.y];
    const screen_char_t *theLine = sca.line;
    if (_shouldCacheLines) {
        _cachedLineNumber = coord.y;
        _cachedLine = theLine;
    }
    if (coord.x >= sca.length) {
        return sca.continuation;
    }
    return theLine[coord.x];
}

- (id<iTermExternalAttributeIndexReading>)externalAttributeIndexForLine:(int)line {
    if (_shouldCacheLines && line == _cachedExternalAttributeLineNumber && _cachedExternalAttributeIndex != nil) {
        return _cachedExternalAttributeIndex;
    }
    id<iTermExternalAttributeIndexReading> index = [_dataSource externalAttributeIndexForLine:line];
    if (_shouldCacheLines) {
        _cachedExternalAttributeLineNumber = line;
        _cachedExternalAttributeIndex = index;
    }
    return index;
}

- (iTermExternalAttribute *)externalAttributesAt:(VT100GridCoord)coord {
    return [self externalAttributeIndexForLine:coord.y][coord.x];
}

#pragma mark - iTermWordExtractorDataSource

- (VT100GridRange)wordExtractorLogicalWindow {
    return _logicalWindow;
}

- (int)wordExtractorWidth {
    return _dataSource.width;
}

- (int)wordExtractroNumberOfLines {
    return _dataSource.numberOfLines;
}

@end
