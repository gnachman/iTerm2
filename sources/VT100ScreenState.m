//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"

#import "IntervalTree.h"
#import "iTermOrderEnforcer.h"

@implementation VT100ScreenMutableState

- (instancetype)init {
    self = [super init];
    if (self) {
        _animatedLines = [NSMutableIndexSet indexSet];
        _setWorkingDirectoryOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _currentDirectoryDidChangeOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _intervalTree = [[IntervalTree alloc] init];
    }
    return self;
}

@end
