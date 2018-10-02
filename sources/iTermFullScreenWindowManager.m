//
//  iTermFullScreenWindowManager.m
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermFullScreenWindowManager.h"

#import "DebugLogging.h"
#import "NSWindow+iTerm.h"

// A queued entry for transitioning a window in or out of full screen.
@interface iTermFullScreenTransition : NSObject
@property(nonatomic, retain) NSWindow<iTermWeakReference> *window;
@property(nonatomic, assign) BOOL enterFullScreen;
@end

@implementation iTermFullScreenTransition

- (void)dealloc {
    [_window release];
    [super dealloc];
}

@end

// Only one window can enter full screen mode at a time. This ensures it is done safely when
// opening multiple windows.
@implementation iTermFullScreenWindowManager {
    NSMutableArray<iTermFullScreenTransition *> *_queue;
    NSInteger _numberOfTransitions;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillTransition:)
                                                     name:NSWindowWillEnterFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillTransition:)
                                                     name:NSWindowWillExitFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidTransition:)
                                                     name:NSWindowDidEnterFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidTransition:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_queue release];
    [super dealloc];
}

- (void)windowWillTransition:(NSNotification *)notification {
    DLog(@"%@", notification);
    ++_numberOfTransitions;
    DLog(@"Window will enter/exit full screen. Count is now %ld", _numberOfTransitions);
}

- (void)windowDidTransition:(NSNotification *)notification {
    DLog(@"%@", notification);
    --_numberOfTransitions;
    DLog(@"Window did enter/exit full screen. Count is now %ld", _numberOfTransitions);
    if (_numberOfTransitions == 0) {
        [self transitionNextWindowInQueue];
    }
}

- (void)transitionNextWindowInQueue {
    DLog(@"Trying to dequeue next window");
    if (_numberOfTransitions > 0) {
        DLog(@"  Can't, something is transitioning now (count is nonzero)");
        return;
    }
    while (_queue.count) {
        iTermFullScreenTransition *transition = [[_queue.firstObject retain] autorelease];
        [_queue removeObjectAtIndex:0];
        NSWindow *window = transition.window.weaklyReferencedObject;

        DLog(@"  Reference is %@", window);
        if (window && !!window.isFullScreen != !!transition.enterFullScreen) {
            DLog(@"    Do it now.");
            [window performSelector:@selector(toggleFullScreen:)];
            return;
        }
    }
}

// Returns YES if the window is already in the queue. Removes it if its `enterFullScreen` equals `ifEntering`.
- (BOOL)haveTransitionWithWindow:(NSWindow *)window removeIfEntering:(BOOL)ifEntering {
    NSInteger index = [_queue indexOfObjectPassingTest:^BOOL(iTermFullScreenTransition * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.window.weaklyReferencedObject == window;
    }];
    if (index != NSNotFound) {
        iTermFullScreenTransition *transition = _queue[index];
        if (!!transition.enterFullScreen == !!ifEntering) {
            DLog(@"Removing window from queue");
            [_queue removeObjectAtIndex:index];
        } else {
            DLog(@"Already queued. Do nothing");
        }
        return YES;
    }
    return NO;
}

- (void)enqueueWindow:(NSWindow<iTermWeakReference> *)window enter:(BOOL)enter {
    iTermFullScreenTransition *transition = [[[iTermFullScreenTransition alloc] init] autorelease];
    transition.window = window;
    transition.enterFullScreen = enter;
    [_queue addObject:transition];
    [self transitionNextWindowInQueue];
}

- (void)makeWindowEnterFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window {
    DLog(@"Make window enter full screen: %@", window);

    if ([self haveTransitionWithWindow:window removeIfEntering:YES]) {
        return;
    }

    if (window.isFullScreen) {
        DLog(@"Window is already full screen");
        return;
    }

    [self enqueueWindow:window.weakSelf enter:YES];
}

- (void)makeWindowExitFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window {
    DLog(@"Make window exit full screen: %@", window);

    if ([self haveTransitionWithWindow:window removeIfEntering:NO]) {
        return;
    }

    if (!window.isFullScreen) {
        DLog(@"Window is not fullscreen");
        return;
    }

    [self enqueueWindow:window.weakSelf enter:NO];
}

- (NSUInteger)numberOfQueuedTransitions {
    return _queue.count;
}

@end
