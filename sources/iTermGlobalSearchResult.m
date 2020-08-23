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

- (VT100GridCoordRange)coordRange {
    const long long offset = self.session.screen.totalScrollbackOverflow;
    const int startY = MAX(0, self.result.absStartY - offset);
    const int endY = MAX(0, self.result.absEndY - offset);
    return VT100GridCoordRangeMake(self.result.startX,
                                   startY,
                                   self.result.endX + 1,
                                   endY);
}

- (void)highlightLines {
    const VT100GridCoordRange coordRange = [self coordRange];
    for (int i = coordRange.start.y; i <= coordRange.end.y; i++) {
        [self.session.textview highlightMarkOnLine:i hasErrorCode:NO];
    }
}

@end
