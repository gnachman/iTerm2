//
//  iTermProfileSearchToken.m
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import "iTermProfileSearchToken.h"

static NSString *const kTagRestrictionOperator = @"tag:";
static NSString *const kTitleRestrictionOperator = @"name:";

@interface iTermProfileSearchToken()
@property(nonatomic, copy) NSArray *strings;
@property(nonatomic, copy) NSString *operator;
@property(nonatomic, assign) BOOL anchorStart;
@property(nonatomic, assign) BOOL anchorEnd;
@end

@implementation iTermProfileSearchToken {
  NSRange _range;
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
- (instancetype)initWithPhrase:(NSString *)phrase {
  self = [super init];
  if (self) {
    NSString *string = phrase;
    // First, parse an operator like tag: or name:, which must be at the beginning.
    NSArray *operators = @[ kTagRestrictionOperator, kTitleRestrictionOperator ];
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

- (BOOL)matchesAnyWordInNameWords:(NSArray *)titleWords {
  if ([_operator isEqualToString:kTagRestrictionOperator]) {
    return NO;
  }
  return [self matchesAnyWordInWords:titleWords];
}

- (BOOL)matchesAnyWordInTagWords:(NSArray *)tagWords {
  if ([_operator isEqualToString:kTitleRestrictionOperator]) {
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

- (void)dealloc {
  [_strings release];
  [_operator release];
  [super dealloc];
}

@end

