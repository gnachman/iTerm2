//
//  iTermProfileSearchToken.m
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import "iTermProfileSearchToken.h"
#import "NSArray+iTerm.h"

NSString *const kTagRestrictionOperator = @"tag:";

@interface iTermProfileSearchToken()
@property(nonatomic, copy) NSArray *strings;
@property(nonatomic, readwrite, copy) NSString *operator;
@property(nonatomic, assign) BOOL anchorStart;
@property(nonatomic, assign) BOOL anchorEnd;
@end

@implementation iTermProfileSearchToken {
    NSRange _range;
    NSArray<NSString *> *_operators;
    NSArray<NSString *> *_nonTagOperators;
}

// Valid phrases look like
//   word
//   ^word
//   word$
//   ^word$
//   operator:word
//   "two words"
//   ^"two words"
//   "two words"$
//   ^"two words"$
//   operator:^"two words"
//   operator:"two words"$
//   operator:^"two words"$
//
// For backward compatibility, * may occur in place of ^, but it has no effect.
- (instancetype)initWithPhrase:(NSString *)originalPhrase {
    return [self initWithPhrase:originalPhrase operators:@[ kTagRestrictionOperator, @"name:", @"command:" ]];
}

- (instancetype)initWithPhrase:(NSString *)originalPhrase operators:(NSArray<NSString *> *)operators {
    self = [super init];
    if (self) {
        _operators = [operators copy];
        _nonTagOperators = [operators filteredArrayUsingBlock:^BOOL(NSString *op) {
            return ![op isEqualToString:kTagRestrictionOperator];
        }];

        // First, parse an operator like tag: or name:, which must be at the beginning.
        NSString *phrase = originalPhrase;
        if ([phrase hasPrefix:@"-"]) {
            _negated = YES;
            phrase = [originalPhrase substringFromIndex:1];
        }
        NSString *string = phrase;
        for (NSString *operator in operators) {
            if ([phrase hasPrefix:operator]) {
                string = [phrase substringFromIndex:operator.length];
                self.operator = operator;
                break;
            }
        }

        // If what follows is quoted, remove the quotation marks.
        if (phrase.length >= 2 && [phrase hasPrefix:@"\""] && [phrase hasSuffix:@"\""]) {
            string = [phrase substringWithRange:NSMakeRange(1, phrase.length - 2)];
        }

        // If the first letter of the string is ^, use an anchored search. If it is * do nothing
        // because that used to be the operator for non-anchored search.
        if ([string hasPrefix:@"^"]) {
            self.anchorStart = YES;
            string = [string substringFromIndex:1];
        } else if ([string hasPrefix:@"*"]) {
            // Legacy query syntax
            string = [string substringFromIndex:1];
        }
        if ([string hasSuffix:@"$"]) {
            self.anchorEnd = YES;
            string = [string substringToIndex:string.length - 1];
        }

        self.strings = [string componentsSeparatedByString:@" "];
    }
    return self;
}

- (instancetype)initWithTag:(NSString *)tag {
    return [self initWithTag:tag operators:@[ kTagRestrictionOperator, @"name:" ]];
}

- (instancetype)initWithTag:(NSString *)tag operators:(NSArray<NSString *> *)operators {
    self = [super init];
    if (self) {
        _operators = [operators copy];
        _nonTagOperators = [operators filteredArrayUsingBlock:^BOOL(NSString *op) {
            return ![op isEqualToString:kTagRestrictionOperator];
        }];
        _negated = NO;
        self.operator = kTagRestrictionOperator;
        self.anchorStart = NO;
        self.anchorEnd = NO;
        self.strings = [tag componentsSeparatedByString:@" "];
    }
    return self;
}

- (BOOL)matchesAnyWordIn:(NSArray<NSString *> *)words operator:(NSString *)operator {
    if (_operator != nil && ![operator isEqualToString:_operator]) {
        // This query token has an operator but the words (correspnding to a phrase in the document)
        // do not match it. For example, token is "title:foo" and words are "foo" with operator "text:".
        return NO;
    }
    return [self matchesAnyWordInWords:words];
}

- (BOOL)matchesAnyWordInNameWords:(NSArray<NSString *> *)titleWords {
    if (_operator != nil && ![_nonTagOperators containsObject:_operator]) {
        return NO;
    }
    return [self matchesAnyWordInWords:titleWords];
}

- (BOOL)matchesAnyWordInTagWords:(NSArray *)tagWords {
    if (_operator != nil && [_nonTagOperators containsObject:_operator]) {
        return NO;
    }
    return [self matchesAnyWordInWords:tagWords];
}

- (BOOL)matchesAnyWordInWords:(NSArray *)words {
    NSStringCompareOptions options = NSCaseInsensitiveSearch;
    if (_anchorStart) {
        options |= NSAnchoredSearch;
    }
    NSInteger offset = 0;
    NSString *combinedString = [_strings componentsJoinedByString:@" "];
    if (combinedString.length == 0) {
        return YES;
    }
    for (int i = 0; i + _strings.count <= words.count; i++) {
        NSString *combinedWords = [[words subarrayWithRange:NSMakeRange(i, _strings.count)] componentsJoinedByString:@" "];
        _range = [combinedWords rangeOfString:combinedString options:options];

        if (_range.location != NSNotFound) {
            if (_anchorEnd && NSMaxRange(_range) != combinedWords.length) {
                _range.location = NSNotFound;
            } else {
                _range.location += offset;
                return YES;
            }
        }
        offset += [words[i] length] + 1;
    }
    return NO;
}

- (BOOL)isTag {
    return ([_operator isEqualToString:kTagRestrictionOperator]);
}

@end

