//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"

@implementation VT100ScreenMutableState

- (instancetype)init {
    self = [super init];
    if (self) {
        _animatedLines = [NSMutableIndexSet indexSet];
    }
    return self;
}

@end
