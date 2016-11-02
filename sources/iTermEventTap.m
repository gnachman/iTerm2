#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "NSArray+iTerm.h"

NSString *const iTermEventTapEventTappedNotification = @"iTermEventTapEventTappedNotification";

@interface iTermEventTap()
@property(nonatomic, retain) NSMutableArray<iTermWeakReference<id<iTermEventTapObserver>> *> *observers;
@end

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

- (instancetype)init {
    self = [super init];
    if (self) {
        _observers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_observers release];
    [super dealloc];
}

#pragma mark - APIs

- (void)setRemappingDelegate:(id<iTermEventTapRemappingDelegate>)remappingDelegate {
    _remappingDelegate = remappingDelegate;
    [self setEnabled:[self shouldBeEnabled]];
}

- (NSEvent *)runEventTapHandler:(NSEvent *)event {
    CGEventRef newEvent = OnTappedEvent(nil, kCGEventKeyDown, [event CGEvent], self);
    if (newEvent) {
        return [NSEvent eventWithCGEvent:newEvent];
    } else {
        return nil;
    }
}

- (void)addObserver:(id<iTermEventTapObserver>)observer {
    [_observers addObject:observer.weakSelf];
    [self setEnabled:[self shouldBeEnabled]];
}

- (void)removeObserver:(id<iTermEventTapObserver>)observer {
    [_observers removeObject:observer];
    [self setEnabled:[self shouldBeEnabled]];
}

#pragma mark - Accessors

- (void)setEnabled:(BOOL)enabled {
    NSLog(@"iTermEventTap setEnabled:%@", @(enabled));
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

- (BOOL)shouldBeEnabled {
    [self pruneReleasedObservers];
    return (self.remappingDelegate != nil) || (self.observers.count > 0);
}

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
    NSLog(@"Event tap running");
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        ELog(@"Event tap disabled (type is %@)", @(type));
        if ([[iTermEventTap sharedInstance] isEnabled]) {
            ELog(@"Re-enabling event tap");
            [[iTermEventTap sharedInstance] reEnable];
        }
        return NULL;
    }
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        NSLog(@"Workspace session not active");
        return event;
    }
    
    if (![[iTermEventTap sharedInstance] userIsActive]) {
        NSLog(@"User not active");
        // Fast user switching has switched to another user, don't do any remapping.
        DLog(@"** not doing any remapping for event %@", [NSEvent eventWithCGEvent:event]);
        return event;
    }
    
    id<iTermEventTapRemappingDelegate> delegate = [[iTermEventTap sharedInstance] remappingDelegate];
    if (delegate) {
        NSLog(@"Calling delegate");
        event = [delegate remappedEventFromEventTappedWithType:type event:event];
    }

    NSLog(@"Notifying observers");
    [[iTermEventTap sharedInstance] postEventToObservers:event type:type];

    return event;
}

- (void)postEventToObservers:(CGEventRef)event type:(CGEventType)type {
    for (id<iTermEventTapObserver> observer in self.observers) {
        [observer eventTappedWithType:type event:event];
    }
    [self pruneReleasedObservers];
}

- (void)pruneReleasedObservers {
    [_observers removeObjectsPassingTest:^BOOL(iTermWeakReference<id<iTermEventTapObserver>> *anObject) {
        return anObject.weaklyReferencedObject == nil;
    }];
}

- (void)reEnable {
    CGEventTapEnable(_eventTapMachPort, true);
}

// Indicates if the user at the keyboard is the same user that owns this process. Used to avoid
// remapping keys when the user has switched users with fast user switching.
- (BOOL)userIsActive {
    CFDictionaryRef sessionInfoDict;
    
    sessionInfoDict = CGSessionCopyCurrentDictionary();
    if (sessionInfoDict) {
        NSNumber *userIsActiveNumber = CFDictionaryGetValue(sessionInfoDict,
                                                            kCGSessionOnConsoleKey);
        if (!userIsActiveNumber) {
            CFRelease(sessionInfoDict);
            return YES;
        } else {
            BOOL value = [userIsActiveNumber boolValue];
            CFRelease(sessionInfoDict);
            return value;
        }
    }
    return YES;
}

- (void)stopEventTap {
    NSLog(@"Stop event tap %@", [NSThread callStackSymbols]);
    assert(self.isEnabled);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                          _runLoopEventSource,
                          kCFRunLoopCommonModes);
    CFMachPortInvalidate(_eventTapMachPort);  // Switches off the event tap.
    CFRelease(_eventTapMachPort);
    _eventTapMachPort = NULL;
}

- (BOOL)startEventTap {
    NSLog(@"Start event tap");
    assert(!self.isEnabled);

    DLog(@"Register event tap.");
    _eventTapMachPort = CGEventTapCreate(kCGHIDEventTap,
                                         kCGTailAppendEventTap,
                                         kCGEventTapOptionDefault,
                                         (CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventFlagsChanged)),
                                         (CGEventTapCallBack)OnTappedEvent,
                                         self);
    if (!_eventTapMachPort) {
        NSLog(@"CGEventTapCreate failed");
        return NO;
    }

    NSLog(@"Create runloop source");
    _runLoopEventSource = CFMachPortCreateRunLoopSource(NULL, _eventTapMachPort, 0);
    if (_runLoopEventSource == NULL) {
        NSLog(@"CFMachPortCreateRunLoopSource failed.");
        CFRelease(_eventTapMachPort);
        _eventTapMachPort = NULL;
        return NO;
    }

    NSLog(@"Adding run loop source.");
    // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       _runLoopEventSource,
                       kCFRunLoopCommonModes);
    CFRelease(_runLoopEventSource);

    return YES;
}

@end
