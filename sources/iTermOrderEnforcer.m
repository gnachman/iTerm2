//
//  iTermOrderEnforcer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/14/20.
//

#import "iTermOrderEnforcer.h"

#import "DebugLogging.h"

@interface iTermOrderEnforcer()
- (BOOL)commit:(NSInteger)generation;
- (BOOL)peek:(NSInteger)generation;
@end

@interface iTermOrderedToken: NSObject<iTermOrderedToken>
@property(nonatomic, weak) iTermOrderEnforcer *enforcer;
@end

@implementation iTermOrderedToken {
    NSInteger _generation;
    BOOL _committed;
}

- (instancetype)initWithGeneration:(NSInteger)generation
                          enforcer:(iTermOrderEnforcer *)enforcer {
    self = [super init];
    if (self) {
        _generation = generation;
        _enforcer = enforcer;
    }
    return self;
}

- (NSString *)description {
    return [@(_generation) stringValue];
}

#pragma mark - iTermOrderedToken

- (BOOL)commit {
    assert(!_committed);
    _committed = YES;
    return [_enforcer commit:_generation];
}

- (BOOL)peek {
    return [_enforcer peek:_generation];
}

@end

@implementation iTermOrderEnforcer {
    NSInteger _generation;
    NSInteger _lastCommitted;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastCommitted = -1;
    }
    return self;
}

- (id<iTermOrderedToken>)newToken {
    NSInteger generation;
    @synchronized(self) {
        generation = _generation++;
    }
    return [[iTermOrderedToken alloc] initWithGeneration:generation
                                                enforcer:self];
}

- (BOOL)commit:(NSInteger)generation {
    const BOOL accepted = [self peek:generation];
    if (accepted) {
        _lastCommitted = generation;
    } else {
        DLog(@"Reject out of order token with generation %@", @(generation));
    }
    return accepted;
}

- (BOOL)peek:(NSInteger)generation {
    return (generation > _lastCommitted);
}
@end
