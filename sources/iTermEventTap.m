#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "iTermFlagsChangedNotification.h"
#import "iTermNotificationCenter.h"
#import "iTermSecureKeyboardEntryController.h"
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

- (BOOL)isProcessTrustedWithPrompt:(BOOL)prompt {
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @(prompt)});
}

- (void)secureInputDidChange:(NSNotification *)notification {
    // Avoid trying to enable it if the process is not trusted because this gets called when the
    // app is activated/deactivated
    const BOOL shouldBeEnabled = self.shouldBeEnabled;
    if (!shouldBeEnabled || [self isProcessTrustedWithPrompt:NO]) {
        [self setEnabled:shouldBeEnabled];
    }
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
    DLog(@"Add observer %@", observer);
    [_observers addObject:observer.weakSelf];
    [self setEnabled:[self shouldBeEnabled]];
}

- (void)removeObserver:(id<iTermEventTapObserver>)observer {
    DLog(@"Remove observer %@", observer);
    [_observers removeObject:observer];
    [self setEnabled:[self shouldBeEnabled]];
}

#pragma mark - Accessors

- (void)setEnabled:(BOOL)enabled {
    DLog(@"iTermEventTap setEnabled:%@\n%@", @(enabled), [NSThread callStackSymbols]);
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
    DLog(@"Before pruning observers are %@", self.observers);
    [self pruneReleasedObservers];
    DLog(@"%@ remappingDelegate=%@ observers=%@", self, self.remappingDelegate, self.observers);
    if (![self allowedByEventTap]) {
        DLog(@"Event tap %@ not allowed by secure input", self.class);
        return NO;
    }
    return (self.remappingDelegate != nil) || (self.observers.count > 0);
}

- (BOOL)allowedByEventTap {
    return !IsSecureEventInputEnabled();
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
    CGEventRef event = [self.remappingDelegate remappedEventFromEventTap:self
                                                                withType:type
                                                                   event:originalEvent];

    DLog(@"Notifying observers");
    [self postEventToObservers:event type:type];

    return event;
}

- (void)postEventToObservers:(CGEventRef)event type:(CGEventType)type {
    for (id<iTermEventTapObserver> observer in [self.observers copy]) {
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
    ITAssertWithMessage([NSThread isMainThread], @"Don't call this off the main thread because it's not thread-safe");
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
    DLog(@"Set remapping delegate to %@\n%@", remappingDelegate, [NSThread callStackSymbols]);
    [super setRemappingDelegate:remappingDelegate];
}

- (void)flagsDidChange:(iTermFlagsChangedNotification *)notification {
    if (_count == 0) {
        DLog(@"Injecting flagsChanged event %@ because count is 0", notification.event);
        [self handleEvent:notification.event.CGEvent ofType:kCGEventFlagsChanged];
    } else {
        DLog(@"NOT injecting flagsChanged event because count is %@", @(_count));
    }
    [self resetCount];
}

- (CGEventRef)handleEvent:(CGEventRef)originalEvent ofType:(CGEventType)type {
    _count++;
    DLog(@"Incr count to %@", @(_count));
    return [super handleEvent:originalEvent ofType:type];
}

- (void)resetCount {
    DLog(@"Reset count");
    _count = 0;
}

- (BOOL)allowedByEventTap {
    return YES;
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTap:(iTermEventTap *)eventTap
                               withType:(CGEventType)type
                                  event:(CGEventRef)event {
    return event;
}

@end

@interface iTermKeyDownEventTap()<iTermEventTapRemappingDelegate>
@end

@implementation iTermKeyDownEventTap

+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded {
    ITAssertWithMessage([NSThread isMainThread], @"Don't call this off the main thread because it's not thread-safe");
    static dispatch_once_t onceToken;
    static id instance;
    if (!createIfNeeded) {
        return instance;
    }
    dispatch_once(&onceToken, ^{
        instance = [[iTermKeyDownEventTap alloc] initPrivate];
    });
    return instance;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[iTermKeyDownEventTap alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super initWithEventTypes:CGEventMaskBit(kCGEventKeyDown)];
    if (self) {
        self.remappingDelegate = self;
    }
    return self;
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTap:(iTermEventTap *)eventTap
                               withType:(CGEventType)type
                                  event:(CGEventRef)event {
    return event;
}

@end
