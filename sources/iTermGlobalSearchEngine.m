//
//  iTermGlobalSearchEngine.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchEngine.h"

#import "NSArray+iTerm.h"

#import "NSTimer+iTerm.h"
#import "PTYSession.h"
#import "SearchResult.h"
#import "VT100Screen.h"
#import "VT100Screen+Search.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermGlobalSearchEngineCursor.h"
#import "iTermGlobalSearchResult.h"
#import "iTermTextExtractor.h"

@implementation iTermGlobalSearchEngine {
    NSTimer *_timer;
    NSMutableArray<id<iTermGlobalSearchEngineCursorProtocol>> *_cursors;
    NSUInteger _retiredLines;
    NSUInteger _expectedLines;
}

- (instancetype)initWithQuery:(NSString *)query
                     sessions:(NSArray<PTYSession *> *)sessions
                         mode:(iTermFindMode)mode
                      handler:(void (^)(PTYSession *,
                                        NSArray<iTermGlobalSearchResult *> *,
                                        double))handler {
    self = [super init];
    if (self) {
        _query = [query copy];
        _handler = [handler copy];
        _mode = mode;
        __weak __typeof(self) weakSelf = self;
        _cursors = [[sessions mapWithBlock:^id(PTYSession *session) {
            iTermGlobalSearchEngineCursor *cursor = [[iTermGlobalSearchEngineCursor alloc] initWithQuery:query mode:mode session:session];
            cursor.willPause = ^(iTermGlobalSearchEngineCursor *cursor) {
                [weakSelf drain:cursor];
            };
            _expectedLines += cursor.expectedLines;
            return cursor;
        }] mutableCopy];
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:0
                                                      target:self
                                                    selector:@selector(searchMore:)
                                                    userInfo:nil
                                                     repeats:YES];
    }
    return self;
}

- (void)drain:(id<iTermGlobalSearchEngineCursorProtocol>)cursor {
    [cursor drainFully:^(NSArray<iTermGlobalSearchResult *> *results, NSUInteger retired) {
        _retiredLines += retired;
        self.handler(cursor.session, results, [self progressIncludingCursor:cursor]);
    }];
}

- (void)stop {
    self.handler(nil, nil, 1);
    [_timer invalidate];
    _timer = nil;
}

- (void)searchMore:(NSTimer *)timer {
    id<iTermGlobalSearchEngineCursorProtocol> cursor = _cursors.firstObject;
    if (!cursor) {
        [self stop];
        return;
    }
    [_cursors removeObjectAtIndex:0];
    const BOOL more = [cursor consumeAvailable:^(NSArray<iTermGlobalSearchResult *> *results, NSUInteger retired) {
        _retiredLines += retired;
        self.handler(cursor.session, results, [self progressIncludingCursor:cursor]);
    }];
    if (more) {
        [_cursors addObject:cursor];
        return;
    }
    cursor = [cursor instanceForNextPass];
    if (cursor) {
        [_cursors addObject:cursor];
        return;
    }
    if (_cursors.count == 0) {
        [self stop];
    }
}

- (double)progressIncludingCursor:(id<iTermGlobalSearchEngineCursorProtocol>)additionalCursor {
    double done = _retiredLines;

    for (id<iTermGlobalSearchEngineCursorProtocol> cursor in [_cursors arrayByAddingObject:additionalCursor]) {
        done += cursor.approximateLinesSearched;
    }
    return MIN(1, MAX(0, done / _expectedLines));
}

@end
