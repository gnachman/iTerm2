#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "iTermNotificationCenter.h"
#import "NSArray+iTerm.h"

NSString *const iTermEventTapEventTappedNotification = @"iTermEventTapEventTappedNotification";

@interface iTermEventTap()
@property(nonatomic, strong) NSMutableArray<iTermWeakReference<id<iTermEventTapObserver>> *> *observers;
@end

@implementation iTermEventTap {
    // When using an event tap, these will be non-NULL.
    CFMachPortRef _machPort;
    CFRunLoopSourceRef _eventSource;  // weak
    CGEventMask _types;
}

- (instancetype)initWithEventTypes:(CGEventMask)types {
    self = [super init];
    if (self) {
        _types = types;
        _observers = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(secureInputDidChange:)
                                                     name:iTermDidToggleSecureInputNotification
                                                   object:nil];
    }
    return self;
}

- (void)secureInputDidChange:(NSNotification *)notification {
    [self setEnabled:[self shouldBeEnabled]];
}

#pragma mark - APIs

- (void)setRemappingDelegate:(id<iTermEventTapRemappingDelegate>)remappingDelegate {
    _remappingDelegate = remappingDelegate;
    [self setEnabled:[self shouldBeEnabled]];
}

- (NSEvent *)runEventTapHandler:(NSEvent *)event {
    CGEventRef newEvent = iTermEventTapCallback(nil, kCGEventKeyDown, [event CGEvent], (__bridge void *)self);
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
    return _machPort != NULL;
}

#pragma mark - Private

- (BOOL)shouldBeEnabled {
    [self pruneReleasedObservers];
    if (IsSecureEventInputEnabled()) {
        return NO;
    }
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
static CGEventRef iTermEventTapCallback(CGEventTapProxy proxy,
                                        CGEventType type,
                                        CGEventRef event,
                                        void *refcon) {
    iTermEventTap *eventTap = (__bridge id)refcon;
    DLog(@"event tap %@ for %@", eventTap, event);
    return [eventTap eventTapCallbackWithProxy:proxy type:type event:event];
}

- (CGEventRef)eventTapCallbackWithProxy:(CGEventTapProxy)proxy
                                   type:(CGEventType)type
                                  event:(CGEventRef)event {
    DLog(@"Event tap running");
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        DLog(@"Event tap disabled (type is %@)", @(type));
        if ([self isEnabled]) {
            DLog(@"Re-enabling event tap");
            [self reEnable];
        }
        return NULL;
    }
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        DLog(@"Workspace session not active");
        return event;
    }

    if (![self userIsActive]) {
        DLog(@"User not active");
        // Fast user switching has switched to another user, don't do any remapping.
        DLog(@"** not doing any remapping for event %@", [NSEvent eventWithCGEvent:event]);
        return event;
    }

    return [self handleEvent:event ofType:type];
}

- (CGEventRef)handleEvent:(CGEventRef)originalEvent ofType:(CGEventType)type {
    CGEventRef event = [self.remappingDelegate remappedEventFromEventTappedWithType:type event:originalEvent];

    DLog(@"Notifying observers");
    [self postEventToObservers:event type:type];

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
    CGEventTapEnable(_machPort, true);
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
                          _eventSource,
                          kCFRunLoopCommonModes);
    _eventSource = NULL;

    // Switch off the event taps.
    CFMachPortInvalidate(_machPort);
    CFRelease(_machPort);
    _machPort = NULL;
}

- (BOOL)startEventTap {
    DLog(@"Start event tap");
    assert(!self.isEnabled);

    AppendPinnedDebugLogMessage(@"EventTap", @"Register event tap.");
    _machPort = CGEventTapCreate(kCGHIDEventTap,
                                 kCGTailAppendEventTap,
                                 kCGEventTapOptionDefault,
                                 _types,
                                 (CGEventTapCallBack)iTermEventTapCallback,
                                 (__bridge void *)self);
    if (!_machPort) {
        XLog(@"CGEventTapCreate failed");
        AppendPinnedDebugLogMessage(@"EventTap", @"CGEventTapCreate failed");
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @YES});
        goto error;
    }

    DLog(@"Create runloop source");
    AppendPinnedDebugLogMessage(@"EventTap", @"Create runloop source");
    _eventSource = CFMachPortCreateRunLoopSource(NULL, _machPort, 0);
    if (_eventSource == NULL) {
        XLog(@"CFMachPortCreateRunLoopSource for key down failed.");
        AppendPinnedDebugLogMessage(@"EventTap", @"CFMachPortCreateRunLoopSource for key down failed");
        goto error;
    }

    DLog(@"Adding run loop source.");
    AppendPinnedDebugLogMessage(@"EventTap", @"Adding run loop source");
    // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event source
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       _eventSource,
                       kCFRunLoopCommonModes);
    CFRelease(_eventSource);

    return YES;

error:
    if (_eventSource) {
        CFRelease(_eventSource);
        _eventSource = NULL;
    }
    if (_machPort) {
        CFMachPortInvalidate(_machPort);
        CFRelease(_machPort);
        _machPort = NULL;
    }
    return NO;

}

@end

@interface iTermFlagsChangedEventTap()<iTermEventTapRemappingDelegate>
@end

@implementation iTermFlagsChangedEventTap

+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded {
    NSAssert([NSThread isMainThread], @"Don't call this off the main thread because it's not thread-safe");
    static dispatch_once_t onceToken;
    static id instance;
    if (!createIfNeeded) {
        return instance;
    }
    dispatch_once(&onceToken, ^{
        instance = [[iTermFlagsChangedEventTap alloc] initPrivate];
    });
    return instance;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[iTermFlagsChangedEventTap alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super initWithEventTypes:CGEventMaskBit(kCGEventFlagsChanged)];
    if (self) {
        self.remappingDelegate = self;
        __weak __typeof(self) weakSelf = self;
        [iTermFlagsChangedNotification subscribe:self block:^(iTermFlagsChangedNotification * _Nonnull notification) {
            [weakSelf flagsDidChange:notification];
        }];
    }
    return self;
}

- (void)setRemappingDelegate:(id<iTermEventTapRemappingDelegate>)remappingDelegate {
    if (remappingDelegate == nil) {
        remappingDelegate = self;
    }
    [super setRemappingDelegate:remappingDelegate];
}

- (void)flagsDidChange:(iTermFlagsChangedNotification *)notification {
    if (@available(macOS 10.13, *)) {
        if (IsSecureEventInputEnabled()) {
            DLog(@"Injecting flagsChanged event %@ because secure input is on", notification.event);
            [self handleEvent:notification.event.CGEvent ofType:kCGEventFlagsChanged];
        }
    }
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTappedWithType:(CGEventType)type event:(CGEventRef)event {
    return event;
}

@end
