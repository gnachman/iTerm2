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

@interface iTermGlobalSearchEngine()<iTermSearchEngineDelegate>
@end

@implementation iTermGlobalSearchEngine {
    NSTimer *_timer;
    NSMutableArray<iTermGlobalSearchEngineCursor *> *_cursors;
    NSUInteger _retiredLines;
    NSUInteger _expectedLines;
}

static void iTermGlobalSearchEngineCursorInitialize(iTermGlobalSearchEngineCursor *cursor,
                                                    NSString *query,
                                                    iTermFindMode mode,
                                                    PTYSession *session,
                                                    iTermGlobalSearchEngineCursorPass pass) {
    VT100Screen *screen = session.screen;
    iTermSearchEngine *searchEngine = [[iTermSearchEngine alloc] initWithDataSource:nil syncDistributor:nil];
    // Don't synchronize. Global search just searches a snapshot of state at the time it began.
    searchEngine.automaticallySynchronize = NO;
    searchEngine.dataSource = screen;
    // Avoid blocking the main queue for too long
    searchEngine.maxConsumeCount = 128;

    NSRange range;
    switch (pass) {
        case iTermGlobalSearchEngineCursorPassMainScreen: {
            const long long lastLineStart = [session.screen absLineNumberOfLastLineInLineBuffer];
            const long long numberOfLines = session.screen.numberOfLines + session.screen.height;
            range = NSMakeRange(lastLineStart, numberOfLines - lastLineStart);
            break;
        }
        case iTermGlobalSearchEngineCursorPassCurrentScreen:
            range = NSMakeRange(0, 0);
            break;
    }

    iTermSearchRequest *request = [[iTermSearchRequest alloc] initWithQuery:query
                                                                       mode:mode
                                                                 startCoord:VT100GridCoordMake(0, screen.numberOfLines + 1)
                                                                     offset:0
                                                                    options:FindOptBackwards | FindMultipleResults
                                                            forceMainScreen:(pass == iTermGlobalSearchEngineCursorPassMainScreen)
                                                              startPosition:nil];
    [request setAbsLineRange:range];
    [searchEngine search:request];

    cursor.session = session;
    cursor.searchEngine = searchEngine;
    cursor.pass = pass;
    cursor.query = query;
    cursor.mode = mode;
    cursor.currentScreenIsAlternate = screen.showingAlternateScreen;
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
            iTermGlobalSearchEngineCursorPass pass;
            if (session.screen.showingAlternateScreen) {
                pass = iTermGlobalSearchEngineCursorPassMainScreen;
                const long long lastLineY = [session.screen absLineNumberOfLastLineInLineBuffer] - session.screen.totalScrollbackOverflow;
                _expectedLines += session.screen.height + session.screen.numberOfLines - lastLineY;
            } else {
                pass = iTermGlobalSearchEngineCursorPassCurrentScreen;
            }
            _expectedLines += session.screen.numberOfLines;
            iTermGlobalSearchEngineCursor *cursor = [[iTermGlobalSearchEngineCursor alloc] init];
            iTermGlobalSearchEngineCursorInitialize(cursor, query, mode, session, pass);
            cursor.searchEngine.delegate = self;
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

// If this is a performance problem it can be removed.
- (void)searchEngineWillPause:(iTermSearchEngine *)searchEngine {
    for (iTermGlobalSearchEngineCursor *cursor in _cursors) {
        if (cursor.searchEngine == searchEngine) {
            [self drain:cursor];
            return;
        }
    }
}

- (void)drain:(iTermGlobalSearchEngineCursor *)cursor {
    while (cursor.searchEngine.havePendingResults) {
        [self searchWithCursor:cursor];
    }
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
    switch (cursor.pass) {
        case iTermGlobalSearchEngineCursorPassMainScreen: {
            iTermGlobalSearchEngineCursorInitialize(cursor,
                                                        cursor.query,
                                                        cursor.mode,
                                                        cursor.session,
                                                        iTermGlobalSearchEngineCursorPassCurrentScreen);
            [_cursors addObject:cursor];
            return;
        }
        case iTermGlobalSearchEngineCursorPassCurrentScreen:
            break;
    }
    if (_cursors.count == 0) {
        [self stop];
    }
}

- (NSDictionary *)matchAttributes {
    return @{
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSBackgroundColorAttributeName: [NSColor colorWithRed:1 green:1 blue:0 alpha:0.35],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
}

- (NSDictionary *)regularAttributes {
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
}

- (NSAttributedString *)snippetFromExtractor:(iTermTextExtractor *)extractor result:(SearchResult *)result {
    assert(!result.isExternal);

    const VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(result.internalStartX,
                                                                    result.internalAbsStartY,
                                                                    result.internalEndX + 1,
                                                                    result.internalAbsEndY);
    return [extractor attributedStringForSnippetForRange:range
                                       regularAttributes:self.regularAttributes
                                         matchAttributes:self.matchAttributes
                                     maximumPrefixLength:20
                                     maximumSuffixLength:256];
}

- (BOOL)searchWithCursor:(iTermGlobalSearchEngineCursor *)cursor {
    NSMutableArray<SearchResult *> *results = [NSMutableArray array];
    NSString *query = [cursor.searchEngine.query copy];
    const iTermFindMode mode = cursor.searchEngine.mode;
    NSRange range;
    const BOOL more = [cursor.searchEngine continueFindAllResults:results
                                                         rangeOut:&range
                                                     absLineRange:NSMakeRange(0, 0)
                                                    rangeSearched:NULL];
    iTermTextExtractor *extractor;
    switch (cursor.pass) {
        case iTermGlobalSearchEngineCursorPassCurrentScreen:
            extractor = [[iTermTextExtractor alloc] initWithDataSource:cursor.session.screen];
            break;
        case iTermGlobalSearchEngineCursorPassMainScreen: {
            iTermTerminalContentSnapshot *snapshot = [cursor.session.screen snapshotWithPrimaryGrid];
            extractor = [[iTermTextExtractor alloc] initWithDataSource:snapshot];
            break;
        }
    }
    id<ExternalSearchResultsController> esrc = cursor.session.externalSearchResultsController;
    NSArray<iTermExternalSearchResult *> *externals =
        [esrc externalSearchResultsForQuery:query
                                       mode:mode];
    NSArray<SearchResult *> *wrapped =
    [externals mapEnumeratedWithBlock:^id(NSUInteger i,
                                          iTermExternalSearchResult *external,
                                          BOOL *stop) {
        return [SearchResult searchResultFromExternal:external index:i];
    }];
    if (wrapped.count) {
        [results addObjectsFromArray:wrapped];
        [results sortUsingComparator:^NSComparisonResult(SearchResult *lhs, SearchResult *rhs) {
            return [lhs compare:rhs];
        }];
    }
    NSDictionary *matchAttributes = [self matchAttributes];
    NSDictionary *regularAttributes = [self regularAttributes];
    const long long gridStartAbsY = cursor.session.screen.numberOfScrollbackLines + cursor.session.screen.totalScrollbackOverflow;
    NSArray<iTermGlobalSearchResult *> *mapped = [results mapWithBlock:^id(SearchResult *anObject) {
        if (cursor.currentScreenIsAlternate &&
            cursor.pass == iTermGlobalSearchEngineCursorPassMainScreen &&
            anObject.safeAbsEndY < gridStartAbsY) {
            // Drop main screen results that are entirely in the linebuffer.
            // Switching to the main screen is confusing.
            return nil;
        }
        iTermGlobalSearchResult *result = [[iTermGlobalSearchResult alloc] init];
        result.session = cursor.session;
        result.result = anObject;
        if (anObject.isExternal) {
            result.snippet =
            [esrc snippetFromExternalSearchResult:anObject.externalResult
                                  matchAttributes:matchAttributes
                                regularAttributes:regularAttributes];
        } else {
            result.snippet = [self snippetFromExtractor:extractor
                                                 result:anObject];
        }
        if (cursor.pass == iTermGlobalSearchEngineCursorPassMainScreen) {
            result.onMainScreen = YES;
        } else {
            result.onMainScreen = !cursor.currentScreenIsAlternate;
        }
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
        done += cursor.searchEngine.progress * cursor.session.screen.numberOfLines;
    }
    return MIN(1, MAX(0, done / _expectedLines));
}

@end
