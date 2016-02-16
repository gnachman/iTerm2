//
//  iTermFullScreenWindowManager.m
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermFullScreenWindowManager.h"

#import "DebugLogging.h"

// Only one window can enter full screen mode at a time. This ensures it is done safely when
// opening multiple windows.
@implementation iTermFullScreenWindowManager {
    NSMutableArray<NSWindow<iTermWeakReference> *> *_queue;
    Class _class;
    NSInteger _numberOfWindowsEnteringFullScreen;
    SEL _selector;
}

- (instancetype)initWithClass:(Class)class enterFullScreenSelector:(SEL)selector {
    self = [super init];
    if (self) {
        _class = [class retain];
        _queue = [[NSMutableArray alloc] init];
        _selector = selector;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillEnterFullScreen:)
                                                     name:NSWindowWillEnterFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidEnterFullScreen:)
                                                     name:NSWindowDidEnterFullScreenNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_queue release];
    [_class release];
    [super dealloc];
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    NSWindow *object = [notification object];
    if (![object isKindOfClass:_class]) {
        return;
    }
    ++_numberOfWindowsEnteringFullScreen;
    DLog(@"Window will enter full screen. Count is now %ld", _numberOfWindowsEnteringFullScreen);
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    NSWindow *object = [notification object];
    if (![object isKindOfClass:_class]) {
        return;
    }
    --_numberOfWindowsEnteringFullScreen;
    DLog(@"Window did enter full screen. Count is now %ld", _numberOfWindowsEnteringFullScreen);
    if (_numberOfWindowsEnteringFullScreen == 0 && _queue.count) {
        [self makeNextWindowInQueueFullScreen];
    }
}

- (void)makeNextWindowInQueueFullScreen {
    DLog(@"Trying to dequeue next window");
    if (_numberOfWindowsEnteringFullScreen > 0) {
        DLog(@"  Can't, something is going fullscreen (count is nonzero)");
        return;
    }
    while (_queue.count) {
        NSWindow *window = [[_queue firstObject] weaklyReferencedObject];
        [_queue removeObjectAtIndex:0];
        DLog(@"  Reference is %@", window);
        if (window) {
            DLog(@"    Do it now.");
            [window performSelector:_selector];
            return;
        }
    }
}

- (void)makeWindowEnterFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window {
    DLog(@"Make window enter full screen: %@", window);
    if (_numberOfWindowsEnteringFullScreen) {
        DLog(@"  Add it to the queue");
        [_queue addObject:[window weakSelf]];
    } else {
        DLog(@"  Do it now");
        [window performSelector:_selector];
    }
}

@end
