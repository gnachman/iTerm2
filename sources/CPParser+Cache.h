//
//  CPParser+Cache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 17/04/19.
//

#import <CoreParse/CoreParse.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPShiftReduceParser (Cache)

+ (instancetype)parserWithBNF:(NSString *)bnf start:(NSString *)start;
- (void)it_releaseParser;

@end

NS_ASSUME_NONNULL_END
