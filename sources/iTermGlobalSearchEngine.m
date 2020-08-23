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
#import "iTermGlobalSearchEngineCursor.h"
#import "iTermGlobalSearchResult.h"
#import "iTermTextExtractor.h"

@implementation iTermGlobalSearchEngine {
    NSTimer *_timer;
    NSMutableArray<iTermGlobalSearchEngineCursor *> *_cursors;
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
        _cursors = [[sessions mapWithBlock:^id(PTYSession *session) {
            FindContext *findContext = [[FindContext alloc] init];
            [session.screen setFindString:query
                         forwardDirection:NO
                                     mode:mode
                              startingAtX:0
                              startingAtY:session.screen.numberOfLines + 1 + session.screen.totalScrollbackOverflow
                               withOffset:0
                                inContext:findContext
                          multipleResults:YES];
            iTermGlobalSearchEngineCursor *cursor = [[iTermGlobalSearchEngineCursor alloc] init];
            cursor.session = session;
            cursor.findContext = findContext;
            _expectedLines += session.screen.numberOfLines;
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

- (void)stop {
    self.handler(nil, nil, 1);
    [_timer invalidate];
    _timer = nil;
}

- (void)searchMore:(NSTimer *)timer {
    iTermGlobalSearchEngineCursor *cursor = _cursors.firstObject;
    if (!cursor) {
        [self stop];
        return;
    }
    [_cursors removeObjectAtIndex:0];
    const BOOL more = [self searchWithCursor:cursor];
    if (more) {
        [_cursors addObject:cursor];
        return;
    }
    if (_cursors.count == 0) {
        [self stop];
    }
}

- (NSAttributedString *)snippetFromExtractor:(iTermTextExtractor *)extractor result:(SearchResult *)result {
    const VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(result.startX,
                                                                    result.absStartY,
                                                                    result.endX + 1,
                                                                    result.absEndY);
    NSDictionary *matchAttributes = @{
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSBackgroundColorAttributeName: [NSColor colorWithRed:1 green:1 blue:0 alpha:0.35],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
    NSDictionary *regularAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
    return [extractor attributedStringForSnippetForRange:range
                                       regularAttributes:regularAttributes
                                         matchAttributes:matchAttributes
                                     maximumPrefixLength:20
                                     maximumSuffixLength:256];
}

- (BOOL)searchWithCursor:(iTermGlobalSearchEngineCursor *)cursor {
    NSMutableArray<SearchResult *> *results = [NSMutableArray array];
    const BOOL more = [cursor.session.screen continueFindAllResults:results inContext:cursor.findContext];
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:cursor.session.screen];
    NSArray<iTermGlobalSearchResult *> *mapped = [results mapWithBlock:^id(SearchResult *anObject) {
        iTermGlobalSearchResult *result = [[iTermGlobalSearchResult alloc] init];
        result.session = cursor.session;
        result.result = anObject;
        result.snippet = [self snippetFromExtractor:extractor result:anObject];
        return result;
    }];
    self.handler(cursor.session, mapped, [self progressIncludingCursor:cursor]);
    if (!more) {
        _retiredLines += cursor.session.screen.numberOfLines;
    }
    return more;
}

- (double)progressIncludingCursor:(iTermGlobalSearchEngineCursor *)additionalCursor {
    double done = _retiredLines;

    for (iTermGlobalSearchEngineCursor *cursor in [_cursors arrayByAddingObject:additionalCursor]) {
        done += cursor.findContext.progress * cursor.session.screen.numberOfLines;
    }
    return MIN(1, MAX(0, done / _expectedLines));
}

@end
