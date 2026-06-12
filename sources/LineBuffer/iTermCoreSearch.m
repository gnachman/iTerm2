//
//  iTermCoreSearch.m
//  iTerm2
//
//  Created by George Nachman on 10/27/25.
//

#import "iTermCoreSearch.h"
#import "DebugLogging.h"
#import "iTermCache.h"
#import "NSArray+iTerm.h"
#import "RegexKitLite.h"
#import "ScreenChar.h"

#ifdef DEBUG_SEARCH
#define SearchLog(args...) NSLog(args)
#else
#define SearchLog(args...)
#endif

const unichar kPrefixChar = REGEX_START;
const unichar kSuffixChar = REGEX_END;

@interface NSString(LineBlockDebugging)
@end

@implementation NSString(LineBlockDebugging)
- (NSString *)asciified {
    NSMutableString *c = [self mutableCopy];
    NSRange range = [c rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 32)]];
    while (range.location != NSNotFound) {
        [c replaceCharactersInRange:range withString:@"."];
        range = [c rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 32)]];
    }
    return c;
}
@end

@interface NSString(CoreSearchAdditions)
- (NSArray<NSValue *> *)it_rangesOfString:(NSString *)needle
                                  options:(NSStringCompareOptions)options;
@end

static int CoreSearchStringIndexToScreenCharIndex(NSInteger stringIndex,
                                                  NSUInteger stringLength,
                                                  const int *deltas) {
    if (stringIndex >= stringLength) {
        if (stringLength == 0) {
            return 0;
        }
        return deltas[stringLength - 1] + 1;
    }
    return stringIndex + deltas[stringIndex];
}

static NSArray<ResultRange *> *CoreSearchResultsFromRanges(NSArray<NSValue *> *ranges,
                                                           const int *deltas,
                                                           NSUInteger stringLength) {
    if (ranges.count == 0) {
        return @[];
    }
    NSMutableArray<ResultRange *> *resultRanges = [ranges mapToMutableArrayWithBlock:^id _Nullable(NSValue *value) {
        const NSRange range = value.rangeValue;
        if (range.length == 0) {
            return nil;
        }
        const int lowerBound = CoreSearchStringIndexToScreenCharIndex(range.location,
                                                                      stringLength,
                                                                      deltas);
        const int upperBound = CoreSearchStringIndexToScreenCharIndex(NSMaxRange(range) - 1,
                                                                      stringLength,
                                                                      deltas);
        return [[ResultRange alloc] initWithPosition:lowerBound
                                              length:upperBound - lowerBound + 1];
    }];
    if (resultRanges.count < 2) {
        return resultRanges;
    }
    ResultRange *prev = resultRanges.lastObject;
    for (NSInteger i = resultRanges.count - 2; i >= 0; i--) {
        ResultRange *current = resultRanges[i];
        // If two of them share a bound, keep the longer one.
        if (current.position == prev.position || current.upperBound == prev.upperBound) {
            if (current.length > prev.length) {
                [resultRanges replaceObjectsInRange:NSMakeRange(i, 2) withObjectsFromArray:@[ current ]];
                prev = current;
            } else {
                [resultRanges replaceObjectsInRange:NSMakeRange(i, 2) withObjectsFromArray:@[ prev ]];
            }
        } else {
            prev = current;
        }
    }
    return resultRanges;
}

static NSRegularExpression* CoreSearchGetCompiledRegex(BOOL caseInsensitive,
                                                       NSString *pattern,
                                                       NSError **regexError) {
    static iTermCache<NSString *, NSRegularExpression *> *regexCacheCaseSensitive;
    static iTermCache<NSString *, NSRegularExpression *> *regexCacheCaseInsensitive;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regexCacheCaseSensitive = [[iTermCache alloc] initWithCapacity:32];
        regexCacheCaseInsensitive = [[iTermCache alloc] initWithCapacity:32];
    });
    iTermCache<NSString *, NSRegularExpression *> *regexCache = caseInsensitive ? regexCacheCaseInsensitive : regexCacheCaseSensitive;
    NSRegularExpression *compiled = regexCache[pattern];
    *regexError = nil;
    if (!compiled) {
        NSRegularExpressionOptions stringCompareOptions = 0;
        if (caseInsensitive) {
            stringCompareOptions |= NSRegularExpressionCaseInsensitive;
        }
        compiled = [[NSRegularExpression alloc] initWithPattern:pattern
                                                        options:stringCompareOptions
                                                          error:regexError];
        if (compiled) {
            regexCache[pattern] = compiled;
        }
    }
    return compiled;
}

static NSArray<ResultRange *> *CoreRegexSearch(const CoreSearchRequest *request) {
    const BOOL caseInsensitive = (request->mode == iTermFindModeCaseInsensitiveRegex);
    NSError *regexError = nil;
    NSRegularExpression *compiled = CoreSearchGetCompiledRegex(caseInsensitive,
                                                               request->needle,
                                                               &regexError);
    if (regexError || !compiled) {
        VLog(@"regex error: %@", regexError);
        return @[];
    }
    NSArray<NSTextCheckingResult *> *textCheckingResults = [compiled matchesInString:request->haystack
                                                                             options:NSMatchingWithTransparentBounds
                                                                               range:NSMakeRange(0, request->haystack.length)];
    NSArray<NSValue *> *ranges = [textCheckingResults mapWithBlock:^id (NSTextCheckingResult *result) {
        return [NSValue valueWithRange:result.range];
    }];
    if (request->options & FindOptBackwards) {
        ranges = [ranges reversed];
    }

    return CoreSearchResultsFromRanges(ranges, request->deltas, request->haystack.length);
}

static NSArray<ResultRange *> *CoreSubstringSearch(const CoreSearchRequest *request) {
    NSStringCompareOptions stringCompareOptions = 0;
    if (request->options & FindOptBackwards) {
        stringCompareOptions |= NSBackwardsSearch;
    }
    BOOL caseInsensitive = (request->mode == iTermFindModeCaseInsensitiveSubstring);
    if (request->mode == iTermFindModeSmartCaseSensitivity &&
        [request->needle rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location == NSNotFound) {
        caseInsensitive = YES;
    }
    if (caseInsensitive) {
        stringCompareOptions |= NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
    }
    SearchLog(@"Search %@ for %@ with options %@", request->haystack, request->needle, @(stringCompareOptions));
    NSArray<NSValue *> *ranges = [request->haystack it_rangesOfString:request->needle
                                                              options:stringCompareOptions];
    return CoreSearchResultsFromRanges(ranges, request->deltas, request->haystack.length);
}

NSArray<ResultRange *> *CoreSearch(const CoreSearchRequest *request) {
    if (request->haystack.length == 0) {
        return @[];
    }
    if (request->needle.length == 0) {
        if ((request->options & FindOptEmptyQueryMatches)) {
            NSRange range = NSMakeRange(0, request->haystack.length);
            return CoreSearchResultsFromRanges(@[ [NSValue valueWithRange:range] ],
                                               request->deltas,
                                               request->haystack.length);
        } else {
            return @[];
        }
    }

    const BOOL regex = (request->mode == iTermFindModeCaseInsensitiveRegex ||
                        request->mode == iTermFindModeCaseSensitiveRegex);
    if (regex) {
        return CoreRegexSearch(request);
    } else {
        return CoreSubstringSearch(request);

    }
}

@implementation NSString(CoreSearchAdditions)

- (NSArray<NSValue *> *)it_rangesOfString:(NSString *)needle
                                  options:(NSStringCompareOptions)options {
    NSMutableArray<NSValue *> *result = [NSMutableArray array];
    const NSInteger length = self.length;
    NSRange rangeToSearch = NSMakeRange(0, length);
    while (rangeToSearch.location < length) {
        const NSRange range = [self rangeOfString:needle options:options range:rangeToSearch];
        if (range.location == NSNotFound) {
            break;
        }
        [result addObject:[NSValue valueWithRange:range]];
        if (options & NSBackwardsSearch) {
            rangeToSearch.length = range.location;
        } else {
            rangeToSearch.location = NSMaxRange(range);
            rangeToSearch.length = length - rangeToSearch.location;
        }
    }
    return result;

}

@end

