//
//  iTermDefer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/15/20.
//

#import "iTermDefer.h"

@implementation iTermDefer {
    void (^_block)(void);
}

+ (instancetype)block:(void (^)(void))block {
    iTermDefer *defer = [[self alloc] init];
    if (defer) {
        defer->_block = block;
    }
    return defer;
}

- (void)dealloc {
    _block();
}

@end
