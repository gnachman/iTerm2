//
//  iTermSearchHistory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/19.
//

#import "iTermSearchHistory.h"
#import "iTermUserDefaults.h"

@implementation iTermSearchHistory {
    NSMutableArray<NSString *> *_queries;
    BOOL _canCoalesce;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queries = [iTermUserDefaults.searchHistory mutableCopy];
        _maximumCount = 10;
    }
    return self;
}

- (void)addQuery:(NSString *)query {
    if (query.length < 3) {
        [self coalescingFence];
        return;
    }
    if (_canCoalesce && _queries.count) {
        NSString *last = _queries.firstObject;
        if ([query hasPrefix:last]) {
            // abc -> abcd. Replace abc with abcd.
            [_queries removeObjectAtIndex:0];
        } else if ([last hasPrefix:query]) {
            // abcd -> abc. Don't add abc to history.
            return;
        }
    }
    [_queries removeObject:query];
    [_queries insertObject:query atIndex:0];
    while (_queries.count > _maximumCount) {
        [_queries removeLastObject];
    }
    iTermUserDefaults.searchHistory = _queries;
    _canCoalesce = YES;
}

- (void)eraseHistory {
    iTermUserDefaults.searchHistory = @[];
    [_queries removeAllObjects];
}

- (void)coalescingFence {
    _canCoalesce = NO;
}

@end
