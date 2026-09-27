//
//  PSMTabDragSessionDriver.m
//  PSMTabBarControl
//
//  Manual retain/release, like the rest of this directory: it is compiled into
//  iTerm2Shared, which sets CLANG_ENABLE_OBJC_ARC = NO.
//

#import "PSMTabDragSessionDriver.h"

#import "DebugLogging.h"
#import "PSMTabBarControl.h"

#import <CoreVideo/CoreVideo.h>

@interface PSMAppKitTabDragSessionDriver ()
- (void)displayLinkDidFire;
@end

// Runs on a CVDisplayLink thread, so it hops to the main thread before calling
// out. CFRunLoopPerformBlock with the common modes rather than dispatch_async:
// during a live drag the main run loop sits in the event-tracking mode, where a
// dispatch_async is not serviced promptly.
static CVReturn PSMTabDragDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                              const CVTimeStamp *now,
                                              const CVTimeStamp *outputTime,
                                              CVOptionFlags flagsIn,
                                              CVOptionFlags *flagsOut,
                                              void *context) {
    @autoreleasepool {
        // Unretained: -stopMouseTracking tears the link down before the driver
        // goes away, so the callback cannot outlive it.
        PSMAppKitTabDragSessionDriver *driver = (PSMAppKitTabDragSessionDriver *)context;
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [driver displayLinkDidFire];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
    return kCVReturnSuccess;
}

@implementation PSMAppKitTabDragSessionDriver {
    CVDisplayLinkRef _displayLink;
    void (^_handler)(void);
}

- (void)dealloc {
    [self stopMouseTracking];
    [super dealloc];
}

- (void)startDragSessionWithItems:(NSArray<NSDraggingItem *> *)items
                            event:(NSEvent *)event
                         inTabBar:(PSMTabBarControl *)control {
    ILog(@"Begin dragging session for tab bar %p", control);
    NSDraggingSession *session = [control beginDraggingSessionWithItems:items
                                                                 event:event
                                                                source:control];
    session.animatesToStartingPositionsOnCancelOrFail = YES;
    session.draggingFormation = NSDraggingFormationNone;
}

- (void)startMouseTrackingWithHandler:(void (^)(void))handler {
    // A second start without an intervening stop would leak the old link.
    [self stopMouseTracking];

    _handler = [handler copy];
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &PSMTabDragDisplayLinkCallback, self);
    CVDisplayLinkStart(_displayLink);
}

- (void)stopMouseTracking {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
    [_handler release];
    _handler = nil;
}

- (NSPoint)currentMouseLocation {
    return [NSEvent mouseLocation];
}

- (void)displayLinkDidFire {
    if (_handler) {
        _handler();
    }
}

@end
