//
//  iTermSlownessDetector.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/3/21.
//

#import "iTermSlownessDetector.h"
#import "NSDate+iTerm.h"

@implementation iTermSlownessDetector {
    NSMutableDictionary<NSString *, NSNumber *> *_state;
    NSTimeInterval _resetTime;
    // When measurements are nested the stack records how much time was counted by inner events.
    NSMutableArray<NSNumber *> *_stack;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stack = [NSMutableArray array];
        _state = [NSMutableDictionary dictionary];
        _resetTime = [NSDate it_timeSinceBoot];
    }
    return self;
}

- (void)measureEvent:(NSString *)event block:(void (^ NS_NOESCAPE)(void))block {
    [_stack addObject:@0];
    const NSTimeInterval durationWithDoubleCounting = [NSDate durationOfBlock:block];
    const NSTimeInterval duration = durationWithDoubleCounting - _stack.lastObject.doubleValue;
    [_stack removeLastObject];
    for (NSInteger i = 0; i < _stack.count; i++) {
        _stack[i] = @(_stack[i].doubleValue + duration);
    }
    [self increaseTimeInEvent:event by:duration];
}

- (void)increaseTimeInEvent:(NSString *)event by:(NSTimeInterval)duration {
    NSNumber *n = _state[event] ?: @0;
    _state[event] = @(n.doubleValue + duration);
}

- (NSDictionary<NSString *, NSNumber *> *)timeDistribution {
    return [_state copy];
}

- (void)reset {
    [_state removeAllObjects];
     _resetTime = [NSDate it_timeSinceBoot];
}

- (NSTimeInterval)timeSinceReset {
    return [NSDate it_timeSinceBoot] - _resetTime;
}

@end
