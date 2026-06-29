//
//  VT100ScreenState+RCDataSource.m
//  iTerm2SharedARC
//

#import "VT100ScreenState+RCDataSource.h"

@implementation VT100ScreenState (RCDataSource)

// Forwards to mainThreadPoolGuid so we don't need direct ivar access from
// the category. On VT100ScreenState the two return the same value; on
// VT100ScreenMutableState the main @implementation overrides -rcGuid to
// return its mutation-thread uniqueIdentifier instead.
- (NSString *)rcGuid {
    return self.mainThreadPoolGuid;
}

- (int32_t)rcWidth {
    return (int32_t)self.width;
}

- (int32_t)rcNumberOfLines {
    return (int32_t)self.numberOfLines;
}

- (int64_t)rcScrollbackOverflow {
    return (int64_t)self.cumulativeScrollbackOverflow;
}

@end
