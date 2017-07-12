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
    CFMachPortRef _keyDownMachPort;
    CFRunLoopSourceRef _keyDownEventSource;
    CFMachPortRef _flagsChangedMachPort;  // weak
    CFRunLoopSourceRef _flagsChangedEventSource;  // weak
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
    DLog(@"iTermEventTap setEnabled:%@", @(enabled));
    if (enabled && !self.isEnabled) {
        [self startEventTap];
    } else if (!enabled && self.isEnabled) {
        [self stopEventTap];
    }
}

- (BOOL)isEnabled {
    return _keyDownMachPort != NULL && _flagsChangedMachPort != NULL;
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
    DLog(@"Event tap running");
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        DLog(@"Event tap disabled (type is %@)", @(type));
        if ([[iTermEventTap sharedInstance] isEnabled]) {
            DLog(@"Re-enabling event tap");
            [[iTermEventTap sharedInstance] reEnable];
        }
        return NULL;
    }
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        DLog(@"Workspace session not active");
        return event;
    }
    
    if (![[iTermEventTap sharedInstance] userIsActive]) {
        DLog(@"User not active");
        // Fast user switching has switched to another user, don't do any remapping.
        DLog(@"** not doing any remapping for event %@", [NSEvent eventWithCGEvent:event]);
        return event;
    }
    
    id<iTermEventTapRemappingDelegate> delegate = [[iTermEventTap sharedInstance] remappingDelegate];
    if (delegate) {
        DLog(@"Calling delegate");
        event = [delegate remappedEventFromEventTappedWithType:type event:event];
    }

    DLog(@"Notifying observers");
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
    CGEventTapEnable(_keyDownMachPort, true);
    CGEventTapEnable(_flagsChangedMachPort, true);
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
    DLog(@"Stop event tap %@", [NSThread callStackSymbols]);
    assert(self.isEnabled);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                          _keyDownEventSource,
                          kCFRunLoopCommonModes);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                          _flagsChangedEventSource,
                          kCFRunLoopCommonModes);

    // Switch off the event taps.
    CFMachPortInvalidate(_keyDownMachPort);
    CFRelease(_keyDownMachPort);
    _keyDownMachPort = NULL;

    CFMachPortInvalidate(_flagsChangedMachPort);
    CFRelease(_flagsChangedMachPort);
    _flagsChangedMachPort = NULL;

    _keyDownEventSource = NULL;
    _flagsChangedEventSource = NULL;
}

- (BOOL)startEventTap {
    DLog(@"Start event tap");
    assert(!self.isEnabled);

    DLog(@"Register event tap.");
    _keyDownMachPort = CGEventTapCreate(kCGHIDEventTap,
                                        kCGTailAppendEventTap,
                                        kCGEventTapOptionDefault,
                                        CGEventMaskBit(kCGEventKeyDown),
                                        (CGEventTapCallBack)OnTappedEvent,
                                        self);
    if (!_keyDownMachPort) {
        XLog(@"CGEventTapCreate failed for key down events");
        goto error;
    }
    _flagsChangedMachPort = CGEventTapCreate(kCGHIDEventTap,
                                             kCGTailAppendEventTap,
                                             kCGEventTapOptionDefault,
                                             CGEventMaskBit(kCGEventFlagsChanged),
                                             (CGEventTapCallBack)OnTappedEvent,
                                             self);
    if (!_flagsChangedMachPort) {
        XLog(@"CGEventTapCreate failed for flags changed events");
        goto error;
    }

    DLog(@"Create runloop source for keydown");
    _keyDownEventSource = CFMachPortCreateRunLoopSource(NULL, _keyDownMachPort, 0);
    if (_keyDownEventSource == NULL) {
        XLog(@"CFMachPortCreateRunLoopSource for key down failed.");
        goto error;
    }

    DLog(@"Create runloop source for flags changed");
    _flagsChangedEventSource = CFMachPortCreateRunLoopSource(NULL, _flagsChangedMachPort, 0);
    if (_flagsChangedEventSource == NULL) {
        XLog(@"CFMachPortCreateRunLoopSource for flags changed failed.");
        goto error;
    }

    DLog(@"Adding run loop source.");
    // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       _keyDownEventSource,
                       kCFRunLoopCommonModes);
    CFRelease(_keyDownEventSource);

    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       _flagsChangedEventSource,
                       kCFRunLoopCommonModes);
    CFRelease(_flagsChangedEventSource);

    return YES;

error:
    if (_keyDownEventSource) {
        CFRelease(_keyDownEventSource);
        _keyDownEventSource = NULL;
    }
    if (_flagsChangedEventSource) {
        CFRelease(_flagsChangedEventSource);
        _flagsChangedEventSource = NULL;
    }
    if (_keyDownMachPort) {
        CFMachPortInvalidate(_keyDownMachPort);
        CFRelease(_keyDownMachPort);
        _keyDownMachPort = NULL;
    }
    if (_flagsChangedMachPort) {
        CFRelease(_flagsChangedMachPort);
        _flagsChangedMachPort = NULL;
    }
    return NO;

}

@end
