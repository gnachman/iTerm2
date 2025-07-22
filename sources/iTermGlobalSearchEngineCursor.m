//
//  iTermGlobalSearchEngineCursor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchEngineCursor.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"
#import "VT100Screen.h"
#import "VT100Screen+Search.h"
#import "iTerm2SharedARC-Swift.h"

@interface iTermGlobalSearchEngineCursor()<iTermSearchEngineDelegate>
@end

@implementation iTermGlobalSearchEngineCursor

- (instancetype)initWithQuery:(NSString *)query
                         mode:(iTermFindMode)mode
                      session:(PTYSession *)session {
    iTermGlobalSearchEngineCursorPass pass;
    if (session.screen.showingAlternateScreen) {
        pass = iTermGlobalSearchEngineCursorPassMainScreen;
    } else {
        pass = iTermGlobalSearchEngineCursorPassCurrentScreen;
    }
    return [self initWithQuery:query mode:mode session:session pass:pass];
}

- (instancetype)initWithQuery:(NSString *)query
                         mode:(iTermFindMode)mode
                      session:(PTYSession *)session
                         pass:(iTermGlobalSearchEngineCursorPass)pass {
    self = [super init];
    if (self) {
        VT100Screen *screen = session.screen;
        iTermSearchEngine *searchEngine = [[iTermSearchEngine alloc] initWithDataSource:nil syncDistributor:nil];
        // Don't synchronize. Global search just searches a snapshot of state at the time it began.
        searchEngine.automaticallySynchronize = NO;
        searchEngine.dataSource = screen;
        searchEngine.delegate = self;
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

        self.session = session;
        self.searchEngine = searchEngine;
        self.pass = pass;
        self.query = query;
        self.mode = mode;
        self.currentScreenIsAlternate = screen.showingAlternateScreen;
    }
    return self;
}

- (instancetype)instanceForNextPass {
    switch (self.pass) {
        case iTermGlobalSearchEngineCursorPassMainScreen:
            return [[iTermGlobalSearchEngineCursor alloc] initWithQuery:self.query
                                                                   mode:self.mode
                                                                session:self.session
                                                                   pass:iTermGlobalSearchEngineCursorPassCurrentScreen];
        case iTermGlobalSearchEngineCursorPassCurrentScreen:
            return nil;
    }
}

- (long long)expectedLines {
    if (self.session.screen.showingAlternateScreen) {
        const long long lastLineY = [self.session.screen absLineNumberOfLastLineInLineBuffer] - self.session.screen.totalScrollbackOverflow;
        return self.session.screen.height + self.session.screen.numberOfLines - lastLineY;
    } else {
        return self.session.screen.numberOfLines;
    }
}

#pragma mark - iTermGlobalSearchEngineCursorProtocol

typedef struct iTermGlobalSearchEngineCursorSearchOutput {
    NSArray<iTermGlobalSearchResult *> *results;
    BOOL more;
    NSUInteger retiredLines;
} iTermGlobalSearchEngineCursorSearchOutput;

- (void)drainFully:(void (^ NS_NOESCAPE)(NSArray<iTermGlobalSearchResult *> *, NSUInteger))handler {
    while (self.searchEngine.havePendingResults) {
        iTermGlobalSearchEngineCursorSearchOutput output = [self search];
        handler(output.results, output.retiredLines);
    }
}

- (BOOL)consumeAvailable:(void (^ NS_NOESCAPE)(NSArray<iTermGlobalSearchResult *> *, NSUInteger))handler {
    iTermGlobalSearchEngineCursorSearchOutput output = [self search];
    handler(output.results, output.retiredLines);
    return output.more;
}

- (iTermGlobalSearchEngineCursorSearchOutput)search {
    NSMutableArray<SearchResult *> *results = [NSMutableArray array];
    NSString *query = [self.searchEngine.query copy];
    const iTermFindMode mode = self.searchEngine.mode;
    NSRange range;
    const BOOL more = [self.searchEngine continueFindAllResults:results
                                                       rangeOut:&range
                                                   absLineRange:NSMakeRange(0, 0)
                                                  rangeSearched:NULL];
    iTermTextExtractor *extractor;
    switch (self.pass) {
        case iTermGlobalSearchEngineCursorPassCurrentScreen:
            extractor = [[iTermTextExtractor alloc] initWithDataSource:self.session.screen];
            break;
        case iTermGlobalSearchEngineCursorPassMainScreen: {
            iTermTerminalContentSnapshot *snapshot = [self.session.screen snapshotWithPrimaryGrid];
            extractor = [[iTermTextExtractor alloc] initWithDataSource:snapshot];
            break;
        }
    }
    id<ExternalSearchResultsController> esrc = self.session.externalSearchResultsController;
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
    const long long gridStartAbsY = self.session.screen.numberOfScrollbackLines + self.session.screen.totalScrollbackOverflow;
    NSArray<iTermGlobalSearchResult *> *mapped = [results mapWithBlock:^id(SearchResult *anObject) {
        if (self.currentScreenIsAlternate &&
            self.pass == iTermGlobalSearchEngineCursorPassMainScreen &&
            anObject.safeAbsEndY < gridStartAbsY) {
            // Drop main screen results that are entirely in the linebuffer.
            // Switching to the main screen is confusing.
            return nil;
        }
        iTermGlobalSearchResult *result = [[iTermGlobalSearchResult alloc] init];
        result.session = self.session;
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
        if (self.pass == iTermGlobalSearchEngineCursorPassMainScreen) {
            result.onMainScreen = YES;
        } else {
            result.onMainScreen = !self.currentScreenIsAlternate;
        }
        return result;
    }];
    return (iTermGlobalSearchEngineCursorSearchOutput){
        .results = mapped,
        .more = more,
        .retiredLines = more ? 0 : self.session.screen.numberOfLines
    };
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

- (long long)approximateLinesSearched {
    return self.searchEngine.progress * self.session.screen.numberOfLines;
}

#pragma mark - iTermSearchEngineDelegate

// If this is a performance problem it can be removed.
- (void)searchEngineWillPause:(iTermSearchEngine *)searchEngine {
    if (self.willPause && searchEngine == self.searchEngine) {
        self.willPause(self);
    }
}
@end
