//
//  iTermProcessMonitor+Testing.m
//  iTerm2SharedARC
//
//  Testing-only implementation for iTermProcessMonitor.
//

#import "iTermProcessMonitor+Testing.h"

// Forward declare private ivars we need to access
@interface iTermProcessMonitor () {
    @public
    BOOL _isPaused;
    NSMutableArray<iTermProcessMonitor *> *_children;
}
@end

@implementation iTermProcessMonitor (Testing)

- (BOOL)isPaused {
    return _isPaused;
}

- (NSArray<iTermProcessMonitor *> *)childMonitors {
    return [_children copy];
}

@end
