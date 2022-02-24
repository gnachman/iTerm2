//
//  iTermCancelable.m
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import "iTermCancelable.h"

@implementation iTermBlockCanceller

- (instancetype)initWithBlock:(void (^)(void))block {
    self = [super init];
    if (self) {
        _block = [block copy];
    }
    return self;
}

- (void)cancelOperation {
    void (^block)(void) = _block;
    _block = nil;
    if (block) {
        block();
    }
}

@end


