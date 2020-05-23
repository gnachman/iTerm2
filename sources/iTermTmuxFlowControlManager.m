//
//  iTermTmuxFlowControlManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/23/20.
//

#import "iTermTmuxFlowControlManager.h"

#import "DebugLogging.h"

@implementation iTermTmuxFlowControlManager {
    NSInteger _aggregating;
    NSMutableDictionary<NSNumber *, NSNumber *> *_counts;  // window pane ID -> byte count
    void (^_acker)(NSDictionary<NSNumber *, NSNumber *> *);
}

- (instancetype)initWithAcker:(void (^)(NSDictionary<NSNumber *, NSNumber *> *))acker {
    self = [super init];
    if (self) {
        _acker = [acker copy];
        _counts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)push {
    _aggregating++;
}

- (void)pop {
    _aggregating--;
    if (!_aggregating) {
        [self sendAcks];
    }
}

- (void)addBytes:(NSInteger)count pane:(NSInteger)pane {
    DLog(@"addBytes:%@ pane:%@", @(count), @(pane));
    NSNumber *number = _counts[@(pane)] ?: @0;
    _counts[@(pane)] = @(number.integerValue + count);
    if (_aggregating) {
        return;
    }
    [self sendAcks];
}

#pragma mark - Private

- (void)sendAcks {
    if (_counts.count == 0) {
        return;
    }
    NSDictionary<NSNumber *, NSNumber *> *counts = [_counts copy];
    DLog(@"Send acks: %@", counts);
    [_counts removeAllObjects];
    _acker(counts);
}

@end
