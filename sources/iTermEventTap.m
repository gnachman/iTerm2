#import <Cocoa/Cocoa.h>

#import "iTermEventTap.h"

#import "DebugLogging.h"

NSString *const iTermEventTapEventTappedNotification = @"iTermEventTapEventTappedNotification";

@implementation iTermEventTap {
    // When using an event tap, these will be non-NULL.
    CFMachPortRef _eventTapMachPort;
    CFRunLoopSourceRef _runLoopEventSource;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - APIs

- (NSEvent *)runEventTapHandler:(NSEvent *)event {
    CGEventRef newEvent = OnTappedEvent(nil, kCGEventKeyDown, [event CGEvent], self);
    if (newEvent) {
        return [NSEvent eventWithCGEvent:newEvent];
    } else {
        return nil;
    }
}

- (void)reEnable {
    CGEventTapEnable(_eventTapMachPort, true);
}

#pragma mark - Accessors

- (void)setEnabled:(BOOL)enabled {
    if (enabled && !self.isEnabled) {
        [self startEventTap];
    } else if (!enabled && self.isEnabled) {
        [self stopEventTap];
    }
}

- (BOOL)isEnabled {
    return _eventTapMachPort != NULL;
}

#pragma mark - Private

/*
 * The function should return the (possibly modified) passed in event,
 * a newly constructed event, or NULL if the event is to be deleted.
 *
 * The CGEventRef passed into the callback is retained by the calling code, and is
 * released after the callback returns and the data is passed back to the event
 * system.  If a different event is returned by the callback function, then that
 * event will be released by the calling code along with the original event, after
 * the event data has been passed back to the event system.
 */
static CGEventRef OnTappedEvent(CGEventTapProxy proxy,
                                CGEventType type,
                                CGEventRef event,
                                void *refcon) {
    id<iTermEventTapDelegate> delegate = [[iTermEventTap sharedInstance] delegate];
    if (delegate) {
        return [delegate eventTappedWithType:type event:event];
    } else {
        return event;
    }
}

- (void)stopEventTap {
    assert(self.isEnabled);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                          _runLoopEventSource,
                          kCFRunLoopCommonModes);
    CFMachPortInvalidate(_eventTapMachPort);  // Switches off the event tap.
    CFRelease(_eventTapMachPort);
    _eventTapMachPort = NULL;
}

- (BOOL)startEventTap {
    assert(!self.isEnabled);

    DLog(@"Register event tap.");
    _eventTapMachPort = CGEventTapCreate(kCGHIDEventTap,
                                         kCGTailAppendEventTap,
                                         kCGEventTapOptionDefault,
                                         CGEventMaskBit(kCGEventKeyDown),
                                         (CGEventTapCallBack)OnTappedEvent,
                                         self);
    if (!_eventTapMachPort) {
        return NO;
    }

    DLog(@"Create runloop source");
    _runLoopEventSource = CFMachPortCreateRunLoopSource(NULL, _eventTapMachPort, 0);
    if (_runLoopEventSource == NULL) {
        ELog(@"CFMachPortCreateRunLoopSource failed.");
        CFRelease(_eventTapMachPort);
        _eventTapMachPort = NULL;
        return NO;
    }

    DLog(@"Adding run loop source.");
    // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       _runLoopEventSource,
                       kCFRunLoopCommonModes);
    CFRelease(_runLoopEventSource);

    return YES;
}

@end
