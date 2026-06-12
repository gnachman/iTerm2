//
//  NSIndexSet+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import "NSIndexSet+iTerm.h"

#import <AppKit/AppKit.h>


@implementation NSIndexSet (iTerm)

+ (instancetype)it_indexSetWithIndexesInRange:(NSRange)range {
    if (range.length == 0|| range.location >= NSNotFound) {
        return [self indexSet];
    }
    return [self indexSetWithIndexesInRange:range];
}

- (NSArray<NSNumber *> *)it_array {
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [result addObject:@(idx)];
    }];
    return result;
}

@end
