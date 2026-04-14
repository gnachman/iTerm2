//
//  iTermGlobalSearchEngineCursor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchEngineCursor.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "VT100Screen.h"
#import "VT100Screen+Search.h"
#import "iTermGlobalSearchResult.h"
#import "iTerm2SharedARC-Swift.h"

static NSDictionary *iTermGlobalSearchSnippetMatchAttributes(void) {
    return @{
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSBackgroundColorAttributeName: [NSColor colorWithRed:1 green:1 blue:0 alpha:0.35],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
}

static NSDictionary *iTermGlobalSearchSnippetRegularAttributes(void) {
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
}

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
                // The main screen starts at the last line in the line buffer and extends
                // for numberOfLines. Calculate the range carefully to avoid negative lengths.
                const long long lastLineStart = [session.screen absLineNumberOfLastLineInLineBuffer];
                const long long numberOfLines = session.screen.numberOfLines;
                const long long length = MAX(0, numberOfLines - lastLineStart);
                range = NSMakeRange(lastLineStart, length);
                break;
            }
            case iTermGlobalSearchEngineCursorPassCurrentScreen: {
                const long long offset = session.screen.totalScrollbackOverflow;
                range = NSMakeRange(offset, session.screen.numberOfLines);
                break;
            }
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
    NSArray<id<iTermGlobalSearchResultProtocol>> *results;
    BOOL more;
    NSUInteger retiredLines;
} iTermGlobalSearchEngineCursorSearchOutput;

- (void)drainFully:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
    while (self.searchEngine.havePendingResults) {
        iTermGlobalSearchEngineCursorSearchOutput output = [self search];
        handler(output.results, output.retiredLines);
    }
}

- (BOOL)consumeAvailable:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
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
    NSArray<id<iTermGlobalSearchResultProtocol>> *mapped = [results mapWithBlock:^id(SearchResult *anObject) {
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
            result.resilientStart =
                [[iTermResilientCoordinate alloc] initWithDataSource:self.session
                                                        absCoord:VT100GridAbsCoordMake(anObject.internalStartX,
                                                                                        anObject.internalAbsStartY)];
            result.resilientEnd =
                [[iTermResilientCoordinate alloc] initWithDataSource:self.session
                                                        absCoord:VT100GridAbsCoordMake(anObject.internalEndX,
                                                                                        anObject.internalAbsEndY)];
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
    return iTermGlobalSearchSnippetMatchAttributes();
}

- (NSDictionary *)regularAttributes {
    return iTermGlobalSearchSnippetRegularAttributes();
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

@implementation iTermGlobalSearchEngineFoldCursor {
    iTermFoldSearchEngine *_engine;
    NSMutableArray<id<iTermGlobalSearchResultProtocol>> *_pendingResults;
    BOOL _searchComplete;
    long long _totalFoldLines;
}

- (instancetype)initWithQuery:(NSString *)query
                         mode:(iTermFindMode)mode
                      session:(PTYSession *)session {
    self = [super init];
    if (self) {
        self.query = query;
        self.mode = mode;
        self.session = session;
        _pendingResults = [NSMutableArray array];
        _engine = [[iTermFoldSearchEngine alloc] init];

        VT100Screen *screen = session.screen;
        const int width = screen.width;
        const int totalLines = screen.numberOfLines;
        VT100GridRange range = VT100GridRangeMake(0, totalLines);
        NSArray<id<iTermFoldMarkReading>> *foldMarks = [screen foldMarksInRange:range];
        if (foldMarks.count == 0) {
            _searchComplete = YES;
            return self;
        }

        NSMutableArray<id<iTermFoldMarkReading>> *marks = [NSMutableArray array];
        NSMutableArray<NSNumber *> *absLines = [NSMutableArray array];
        for (id<iTermFoldMarkReading> mark in foldMarks) {
            Interval *interval = mark.entry.interval;
            if (!interval) {
                continue;
            }
            VT100GridAbsCoordRange absRange = [screen absCoordRangeForInterval:interval];
            [marks addObject:mark];
            [absLines addObject:@(absRange.start.y)];
            _totalFoldLines += mark.savedLines.count;
        }

        if (marks.count == 0) {
            _searchComplete = YES;
            return self;
        }

        NSDictionary *matchAttributes = iTermGlobalSearchSnippetMatchAttributes();
        NSDictionary *regularAttributes = iTermGlobalSearchSnippetRegularAttributes();

        __weak __typeof(self) weakSelf = self;

        [_engine searchForQuery:query
                           mode:mode
                      foldMarks:marks
                       absLines:absLines
                          width:width
                        results:^(NSArray<iTermExternalSearchResult *> *results) {
            __typeof(self) strongSelf = weakSelf;
            if (!strongSelf || results.count == 0) {
                return;
            }
            NSAttributedString *groupSnippet =
                [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Folded region (%lu matches)", (unsigned long)results.count]
                                                attributes:regularAttributes];
            iTermGlobalSearchFoldGroup *group =
                [[iTermGlobalSearchFoldGroup alloc] initWithSession:strongSelf.session
                                                             snippet:groupSnippet];
            for (iTermExternalSearchResult *externalResult in results) {
                iTermFoldSearchResult *foldResult = (iTermFoldSearchResult *)externalResult;
                iTermGlobalFoldSearchResult *globalResult = [[iTermGlobalFoldSearchResult alloc] init];
                globalResult.session = strongSelf.session;
                globalResult.foldResult = foldResult;
                globalResult.snippet = [strongSelf snippetFromFoldResult:foldResult
                                                         matchAttributes:matchAttributes
                                                       regularAttributes:regularAttributes];

                // Create resilient coordinates anchored to the fold mark.
                iTermFoldMark *foldMark = (iTermFoldMark *)foldResult.foldMark;
                if (foldMark) {
                    globalResult.resilientStart =
                        [[iTermResilientCoordinate alloc] initWithDataSource:strongSelf.session
                                                           enclosingFold:foldMark
                                                                   coord:VT100GridCoordMake(foldResult.startX,
                                                                                            foldResult.startY)];
                    globalResult.resilientEnd =
                        [[iTermResilientCoordinate alloc] initWithDataSource:strongSelf.session
                                                           enclosingFold:foldMark
                                                                   coord:VT100GridCoordMake(foldResult.endX,
                                                                                            foldResult.endY)];
                }

                [group addResult:globalResult];
            }
            [strongSelf->_pendingResults addObject:group];
        }
                       finished:^{
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_searchComplete = YES;
            }
        }];
    }
    return self;
}

- (NSAttributedString *)snippetFromFoldResult:(iTermFoldSearchResult *)foldResult
                              matchAttributes:(NSDictionary *)matchAttributes
                            regularAttributes:(NSDictionary *)regularAttributes {
    NSString *text = foldResult.snippetText;
    if (text.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"" attributes:regularAttributes];
    }
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text
                                                                              attributes:regularAttributes];
    NSRange matchRange = foldResult.snippetMatchRange;
    if (matchRange.location <= result.length &&
        matchRange.length <= result.length - matchRange.location) {
        [result addAttributes:matchAttributes range:matchRange];
    }
    return result;
}

- (long long)expectedLines {
    return _totalFoldLines;
}

- (void)drainFully:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
    if (_pendingResults.count > 0) {
        NSArray *results = [_pendingResults copy];
        [_pendingResults removeAllObjects];
        handler(results, _totalFoldLines);
    }
}

- (BOOL)consumeAvailable:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
    NSArray *results = [_pendingResults copy];
    [_pendingResults removeAllObjects];
    handler(results, _searchComplete ? _totalFoldLines : 0);
    return !_searchComplete;
}

- (id<iTermGlobalSearchEngineCursorProtocol>)instanceForNextPass {
    return nil;
}

- (long long)approximateLinesSearched {
    return _searchComplete ? _totalFoldLines : 0;
}

@end

@implementation iTermGlobalSearchEngineBrowserCursor {
    BOOL _done;
    iTermBrowserGlobalSearchResultStream *_stream;
}

- (instancetype)initWithQuery:(NSString *)query
                         mode:(iTermFindMode)mode
                      session:(PTYSession *)session {
    self = [super init];
    if (self) {
        self.query = query;
        self.mode = mode;
        self.session = session;
        _stream = [self.session.view.browserViewController executeGlobalSearch:self.query
                                                                          mode:self.mode];
    }
    return self;
}

- (void)drainFully:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
    if (_done) {
        return;
    }
    NSArray<id<iTermGlobalSearchResultProtocol>> *results = [_stream.consume mapWithBlock:^id _Nullable(iTermBrowserFindResult *findResult) {
        iTermGlobalBrowserSearchResult *gsr = [[iTermGlobalBrowserSearchResult alloc] init];
        gsr.session = self.session;
        gsr.snippet = [self snippetForResult:findResult];
        gsr.findResult = findResult;
        return gsr;
    }];
    _done = _stream.done;
    handler(results, 1000);
}

- (BOOL)consumeAvailable:(void (^ NS_NOESCAPE)(NSArray<id<iTermGlobalSearchResultProtocol>> *, NSUInteger))handler {
    [self drainFully:handler];
    return !_done;
}

- (id<iTermGlobalSearchEngineCursorProtocol> _Nullable)instanceForNextPass {
    return nil;
}

- (long long)approximateLinesSearched {
    return _done ? 0 : 1000;
}

- (NSAttributedString *)snippetForResult:(iTermBrowserFindResult *)result {
    NSAttributedString *matchString = [[NSAttributedString alloc] initWithString:result.matchedText
                                                                      attributes:[self matchAttributes]];
    NSString *prefix = [(result.contextBefore ?: @"") stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSString *suffix = [(result.contextAfter ?: @"") stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSAttributedString *attributedPrefix = [[NSAttributedString alloc] initWithString:prefix
                                                                           attributes:self.regularAttributes];
    NSAttributedString *attributedSuffix = [[NSAttributedString alloc] initWithString:suffix
                                                                           attributes:self.regularAttributes];
    return [@[attributedPrefix, matchString, attributedSuffix] it_componentsJoinedBySeparator:nil];
}

- (NSDictionary *)matchAttributes {
    return iTermGlobalSearchSnippetMatchAttributes();
}

- (NSDictionary *)regularAttributes {
    return iTermGlobalSearchSnippetRegularAttributes();
}


@end
