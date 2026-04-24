//
//  TemporaryNumberAllocator.m
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import "TemporaryNumberAllocator.h"

@implementation TemporaryNumberAllocator {
    NSMutableSet *_numbers;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _numbers = [[NSMutableSet alloc] init];
    }
    return self;
}

- (int)allocateNumber {
    int n = 0;
    while ([_numbers containsObject:@(n)]) {
        n++;
    }
    [_numbers addObject:@(n)];
    return n;
}

- (void)deallocateNumber:(int)n {
    [_numbers removeObject:@(n)];
}

@end
