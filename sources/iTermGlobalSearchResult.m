//
//  iTermGlobalSearchResult.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchResult.h"
#import "PTYSession.h"
#import "SearchResult.h"
#import "VT100Screen.h"

@implementation iTermGlobalSearchResult

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

@end
