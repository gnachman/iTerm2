//
//  iTermGlobalSearchResult.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchResult.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "SearchResult.h"
#import "VT100Screen.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermController.h"

static NSString *const stateKey = @"session guids with changed screens";

@implementation iTermGlobalSearchResult

+ (void)restoreAlternateScreensWithAnnouncement:(BOOL)announce state:(NSMutableDictionary *)state {
    NSMutableDictionary<NSString *, NSNumber *> *sessionGuidsWithChangedScreens = state[stateKey];

    [sessionGuidsWithChangedScreens enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *obj, BOOL *stop) {
        PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:key];
        if (session) {
            [session setShowAlternateScreen:obj.boolValue announce:announce];
        }
    }];
    [state removeAllObjects];
}

- (BOOL)isExternal {
    return self.result.isExternal;
}

- (VT100GridCoordRange)coordRangeFromResilientCoords {
    const long long overflow = self.session.screen.totalScrollbackOverflow;
    VT100GridAbsCoord start = self.resilientStart.coord;
    VT100GridAbsCoord end = self.resilientEnd.coord;
    return VT100GridCoordRangeMake(start.x,
                                   MAX(0, (int)(start.y - overflow)),
                                   end.x + 1,
                                   MAX(0, (int)(end.y - overflow)));
}

- (void)highlightLines {
    if (self.isExternal || !self.resilientStart || self.resilientStart.status != StatusValid) {
        return;
    }
    const VT100GridCoordRange coordRange = [self coordRangeFromResilientCoords];
    for (int i = coordRange.start.y; i <= coordRange.end.y; i++) {
        [self.session.textview highlightMarkOnLine:i hasErrorCode:NO];
    }
}

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion {
    [self switchSessionToAlternateScreenIfNeeded:state];
    if (self.isExternal) {
        [self.session.externalSearchResultsController selectExternalSearchResult:self.result.externalResult
                                                                        multiple:NO
                                                                          scroll:YES];

        completion(NSZeroRect);
    } else if (self.resilientStart && self.resilientStart.status == StatusValid) {
        const VT100GridCoordRange coordRange = [self coordRangeFromResilientCoords];
        [self.session.textview selectCoordRange:coordRange];
        const int margin = 3;
        VT100GridRange scrollRange = VT100GridRangeMake(MAX(0, coordRange.start.y - margin),
                                                         coordRange.end.y - coordRange.start.y + 1 + margin * 2);
        [self.session.textview scrollLineNumberRangeIntoView:scrollRange];
        [self highlightLines];
        const NSRect hull = [iTermGlobalSearchResult rectForCoordRange:coordRange session:self.session];
        completion(hull);
    } else {
        completion(NSZeroRect);
    }
}

+ (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange session:(PTYSession *)session {
    PTYTextView *textView = session.textview;
    if (!textView) {
        return NSZeroRect;
    }
    NSRect (^screenRect)(VT100GridCoord) = ^NSRect(VT100GridCoord coord) {
        const NSRect viewRect = [textView frameForCoord:coord];
        const NSRect windowRect = [textView convertRect:viewRect toView:nil];
        return [textView.window convertRectToScreen:windowRect];
    };
    const NSRect firstRect = screenRect(coordRange.start);
    const NSRect lastRect = screenRect(coordRange.end);
    return NSUnionRect(firstRect, lastRect);
}

- (void)switchSessionToAlternateScreenIfNeeded:(NSMutableDictionary *)state {
    const BOOL shouldShowAlternateScreen = !self.onMainScreen;
    if (shouldShowAlternateScreen != self.session.screen.showingAlternateScreen) {
        NSMutableDictionary<NSString *, NSNumber *> *sessionGuidsWithChangedScreens = state[stateKey];
        if (!sessionGuidsWithChangedScreens) {
            sessionGuidsWithChangedScreens = [NSMutableDictionary dictionary];
            state[stateKey] = sessionGuidsWithChangedScreens;
        }
        sessionGuidsWithChangedScreens[self.session.guid] = @(self.session.screen.showingAlternateScreen);
        [self.session setShowAlternateScreen:shouldShowAlternateScreen
                                    announce:YES];
    }
}

@end

@implementation iTermGlobalFoldSearchResult

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion {
    if (!self.session) {
        completion(NSZeroRect);
        return;
    }

    PTYTextView *textView = self.session.textview;

    // Check if the result is still inside a fold.
    if (self.resilientStart.status == StatusInFold) {
        // Need to unfold first. The mutation is async, so we observe the
        // notification that fires after the buffer is updated.
        iTermResilientCoordinateFoldInfo *foldInfo = self.resilientStart.objcFoldInfo;
        if (foldInfo) {
            // After the mutation completes, the side effect fires on the main
            // thread. The ResilientCoordinate will transition to .valid, and
            // the buffer will contain the unfolded content.
            __weak __typeof(self) weakSelf = self;
            [textView unfoldMark:foldInfo.mark completion:^(BOOL ok) {
                [weakSelf revealAfterUnfoldWithCompletion:completion];
            }];
            return;
        }
    }

    // The fold was already expanded — the resilient coord should be valid.
    [self revealAfterUnfoldWithCompletion:completion];
}

- (void)revealAfterUnfoldWithCompletion:(void (^)(NSRect))completion {
    if (self.resilientStart.status == StatusValid) {
        PTYTextView *textView = self.session.textview;
        const long long overflow = self.session.screen.totalScrollbackOverflow;
        VT100GridAbsCoord start = self.resilientStart.coord;
        VT100GridAbsCoord end = self.resilientEnd.coord;
        const VT100GridCoordRange coordRange = VT100GridCoordRangeMake(
            start.x, MAX(0, (int)(start.y - overflow)),
            end.x + 1, MAX(0, (int)(end.y - overflow)));
        [self selectAndScroll:coordRange textView:textView completion:completion];
    } else {
        completion(NSZeroRect);
    }
}

- (void)selectAndScroll:(VT100GridCoordRange)coordRange
               textView:(PTYTextView *)textView
             completion:(void (^)(NSRect))completion {
    [textView selectCoordRange:coordRange];
    const int margin = 3;
    VT100GridRange scrollRange = VT100GridRangeMake(MAX(0, coordRange.start.y - margin),
                                                     coordRange.end.y - coordRange.start.y + 1 + margin * 2);
    [textView scrollLineNumberRangeIntoView:scrollRange];

    for (int i = coordRange.start.y; i <= coordRange.end.y; i++) {
        [textView highlightMarkOnLine:i hasErrorCode:NO];
    }

    const NSRect hull = [self rectForCoordRange:coordRange];
    completion(hull);
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange {
    return [iTermGlobalSearchResult rectForCoordRange:coordRange session:self.session];
}

@end

@implementation iTermGlobalSearchFoldGroup {
    NSMutableArray<iTermGlobalFoldSearchResult *> *_results;
}

- (instancetype)initWithSession:(PTYSession *)session
                        snippet:(NSAttributedString *)snippet {
    self = [super init];
    if (self) {
        _session = session;
        _snippet = [snippet copy];
        _results = [NSMutableArray array];
    }
    return self;
}

- (NSArray<iTermGlobalFoldSearchResult *> *)results {
    return _results;
}

- (void)addResult:(iTermGlobalFoldSearchResult *)result {
    [_results addObject:result];
}

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion {
    // Revealing the group reveals its first result.
    if (_results.count > 0) {
        [_results.firstObject revealWithState:state completion:completion];
    } else {
        completion(NSZeroRect);
    }
}

@end

@implementation iTermGlobalBrowserSearchResult

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion {
    return [self.session.view.browserViewController revealFindResult:self.findResult
                                                          completion:completion];
}

@end
