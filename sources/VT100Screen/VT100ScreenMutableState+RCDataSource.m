//
//  VT100ScreenMutableState+RCDataSource.m
//  iTerm2SharedARC
//

#import "VT100ScreenMutableState+RCDataSource.h"

@implementation iTermSavedTreeRCDataSource (RCDataSource)

- (NSString *)rcGuid {
    return self.guid;
}

- (int32_t)rcWidth {
    return self.backing.rcWidth;
}

- (int32_t)rcNumberOfLines {
    return self.backing.rcNumberOfLines;
}

- (int64_t)rcScrollbackOverflow {
    return self.backing.rcScrollbackOverflow;
}

@end
