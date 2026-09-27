//
//  PSMTabDragSessionDriver.h
//  PSMTabBarControl
//
//  The live AppKit services a tab drag needs, behind a protocol so tests can
//  simulate a drag instead of asking AppKit to run one.
//

#import <Cocoa/Cocoa.h>

@class PSMTabBarControl;

NS_ASSUME_NONNULL_BEGIN

// A tab drag needs two things from the window server: an NSDraggingSession, and
// a high-frequency source of pointer positions (the session's own callbacks are
// throttled). PSMTabDragAssistant reaches both only through this protocol.
//
// The indirection exists because -beginDraggingSessionWithItems:event:source:
// does not start the drag inline. It arms an NSCoreDragManager run-loop
// observer, and the drag begins the next time anything pumps the run loop. In a
// headless test process that observer fires inside whatever test happens to pump
// next, AppKit enters its modal drag-tracking loop, and the loop blocks forever
// waiting for a mouse-up that will never be posted. The blocked test is not even
// the one that started the drag. Substituting a driver keeps the session out of
// the test process entirely.
@protocol PSMTabDragSessionDriver <NSObject>

// Begin the dragging session. Called once, at the start of a drag.
- (void)startDragSessionWithItems:(NSArray<NSDraggingItem *> *)items
                            event:(NSEvent *)event
                         inTabBar:(PSMTabBarControl *)control;

// Begin delivering pointer updates. `handler` is invoked on the main thread
// whenever the pointer may have moved; it reads `currentMouseLocation` to find
// out where it went.
- (void)startMouseTrackingWithHandler:(void (^)(void))handler;

// Stop delivering updates and tear the session down. Called from -finishDrag and
// -dealloc, so it must be safe when no drag is in progress and safe to call
// more than once.
- (void)stopMouseTracking;

// Where the pointer is now, in screen coordinates.
@property (nonatomic, readonly) NSPoint currentMouseLocation;

@end

// The production driver: a real NSDraggingSession, a CVDisplayLink for pointer
// polling, and +[NSEvent mouseLocation].
@interface PSMAppKitTabDragSessionDriver : NSObject <PSMTabDragSessionDriver>
@end

NS_ASSUME_NONNULL_END
