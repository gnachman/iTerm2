//
//  iTermGlobalSearchResult.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchResult.h"
#import "PTYSession.h"
#import "PTYSession.h"
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

- (VT100GridCoordRange)internalCoordRange {
    const long long offset = self.session.screen.totalScrollbackOverflow;
    const int startY = MAX(0, self.result.internalAbsStartY - offset);
    const int endY = MAX(0, self.result.internalAbsEndY - offset);
    return VT100GridCoordRangeMake(self.result.internalStartX,
                                   startY,
                                   self.result.internalEndX + 1,
                                   endY);
}

- (void)highlightLines {
    if (self.isExternal) {
        return;
    }
    const VT100GridCoordRange coordRange = [self internalCoordRange];
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
    } else {
        const VT100GridCoordRange coordRange = [self internalCoordRange];
        [self.session.textview selectCoordRange:coordRange];
        [self.session.textview scrollToSelection];
        [self highlightLines];
        const NSRect hull = [self rectForCoordRange:coordRange session:self.session];
        completion(hull);
    }
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange session:(PTYSession *)session {
    NSRect (^screenRect)(VT100GridCoord) = ^NSRect(VT100GridCoord coord) {
        const NSRect viewRect = [session.textview frameForCoord:coord];
        const NSRect windowRect = [session.textview convertRect:viewRect toView:nil];
        return [session.textview.window convertRectToScreen:windowRect];
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

@implementation iTermGlobalBrowserSearchResult

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion {
    return [self.session.view.browserViewController revealFindResult:self.findResult
                                                          completion:completion];
}

@end
