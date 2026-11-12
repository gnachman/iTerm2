#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "iTermFlagsChangedNotification.h"
#import "iTermNotificationCenter.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermWeakBox.h"
#import "NSArray+iTerm.h"

NSString *const iTermEventTapEventTappedNotification = @"iTermEventTapEventTappedNotification";

iTermEventTapMode iTermEventTapModeFor(BOOL allowed,
                                       BOOL delegateModifiesEvents,
                                       BOOL hasObservers,
                                       BOOL appActive) {
    if (!allowed) {
        return iTermEventTapModeOff;
    }
    if (delegateModifiesEvents) {
        return iTermEventTapModeFilter;
    }
    if (!hasObservers) {
        return iTermEventTapModeOff;
    }
    // While active, observers must hear about an event before the app receives it.
    // iTermFlagsChangedEventTap relies on that ordering to decide whether to inject events it
    // didn't see, and a listen-only tap doesn't guarantee it. The keystrokes are going to iTerm2
    // anyway, so filtering then delays no other app.
    return appActive ? iTermEventTapModeFilter : iTermEventTapModeListenOnly;
}

BOOL iTermEventTapInstallsListenOnly(iTermEventTapMode mode, BOOL hasListenEventAccess) {
    return mode == iTermEventTapModeListenOnly && hasListenEventAccess;
}

// Filtering taps run on this thread rather than the main thread. The system holds every matching
// event until the callback returns, so a busy main thread would otherwise stall typing in every
// app. See issue 12645.
static CFRunLoopRef iTermEventTapFilterRunLoop(void) {
    static CFRunLoopRef runLoop;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
            // A run loop with no sources returns immediately, so give it a port that never fires.
            [[NSRunLoop currentRunLoop] addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
            dispatch_semaphore_signal(sema);
            while (YES) {
                @autoreleasepool {
                    CFRunLoopRun();
                }
            }
        }];
        thread.name = @"com.googlecode.iterm2.event-tap";
        thread.qualityOfService = NSQualityOfServiceUserInteractive;
        [thread start];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    });
    return runLoop;
}

// Runs the block on the main thread without waiting. It uses the same run loop modes the tap's
// source used when it lived on the main thread, so the block runs whenever a main-thread tap
// callback would have. Everything the filter thread hands to the main thread must go through
// here: the main run loop runs its perform blocks in FIFO order, but makes no ordering promise
// between them and the main dispatch queue, and observers must see events in the order typed.
static void iTermEventTapPerformOnMainThread(void (^block)(void)) {
    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(mainRunLoop, kCFRunLoopCommonModes, block);
    CFRunLoopWakeUp(mainRunLoop);
}

// Like iTermEventTapPerformOnMainThread, but waits for the block to finish.
static void iTermEventTapPerformOnMainThreadAndWait(void (^block)(void)) {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    iTermEventTapPerformOnMainThread(^{
        block();
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

@interface iTermEventTap ()
- (BOOL)startEventTapListenOnly:(BOOL)listenOnly;
- (void)filterThreadWillDeferDelivery;
- (void)notifyObserversOfEventFromInactiveApp:(CGEventRef)event type:(CGEventType)type;
@end

@implementation iTermEventTap {
    // When using an event tap, these will be non-NULL.
    CFMachPortRef _machPort;
    CFRunLoopSourceRef _eventSource;
    // The run loop _eventSource was added to.
    CFRunLoopRef _runLoop;
    // Whether the installed tap is listen-only (on the main thread) rather than filtering (on the
    // filter thread). Only meaningful while enabled.
    BOOL _installedListenOnly;
    CGEventMask _types;
    NSMutableArray<iTermWeakBox<id<iTermEventTapObserver>> *> *_weakObservers;
}

- (instancetype)initWithEventTypes:(CGEventMask)types {
    self = [super init];
    if (self) {
        _types = types;
        _weakObservers = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(secureInputDidChange:)
                                                     name:iTermDidToggleSecureInputNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationActiveDidChange:)
                                                     name:iTermApplicationActiveStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    if (self.isEnabled) {
        [self stopEventTap];
    }
}

- (void)secureInputDidChange:(NSNotification *)notification {
    // Avoid trying to enable it if the process is not trusted because this gets called when the
    // app is activated/deactivated
    const iTermEventTapMode mode = self.desiredMode;
    if (mode == iTermEventTapModeOff || [[iTermPermissionsHelper accessibility] status]) {
        [self setMode:mode];
    }
}

- (void)applicationActiveDidChange:(NSNotification *)notification {
    // Only switch between modes of an existing tap. Creating one is up to the delegate and
    // observers, and this avoids attempting it (and the permission request that follows a failure)
    // on every activation.
    if (self.isEnabled) {
        [self setMode:self.desiredMode];
    }
}

#pragma mark - APIs

- (void)setRemappingDelegate:(id<iTermEventTapRemappingDelegate>)remappingDelegate {
    _remappingDelegate = remappingDelegate;
    [self setMode:self.desiredMode];
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
    RLog(@"Add observer %@", observer);
    [_weakObservers addObject:[iTermWeakBox boxFor:observer]];
    [self setMode:self.desiredMode];
}

- (void)removeObserver:(id<iTermEventTapObserver>)observer {
    RLog(@"Remove observer %@", observer);
    [_weakObservers removeWeakBoxedObject:observer];
    [self setMode:self.desiredMode];
}

#pragma mark - Accessors

- (void)setMode:(iTermEventTapMode)mode {
    DLog(@"iTermEventTap setMode:%@ (currently enabled=%@ mode=%@)\n%@",
         @(mode), @(self.isEnabled), @(_installedListenOnly), [NSThread callStackSymbols]);
    const BOOL listenOnly = iTermEventTapInstallsListenOnly(mode, CGPreflightListenEventAccess());
    // Keep a tap that is already the right kind. Rebuilding it leaves a gap where events are
    // missed, and without Input Monitoring both modes get the same filtering tap.
    if (self.isEnabled && (mode == iTermEventTapModeOff || listenOnly != _installedListenOnly)) {
        [self stopEventTap];
    }
    if (mode != iTermEventTapModeOff && !self.isEnabled) {
        [self startEventTapListenOnly:listenOnly];
    }
}

- (BOOL)isEnabled {
    return _machPort != NULL;
}

#pragma mark - Private

- (iTermEventTapMode)desiredMode {
    DLog(@"Before pruning observers are %@", self.weakObservers);
    [self pruneReleasedObservers];
    DLog(@"%@ remappingDelegate=%@ observers=%@", self, self.remappingDelegate, self.weakObservers);
    const BOOL allowed = [self allowedByEventTap];
    if (!allowed) {
        RLog(@"Event tap %@ not allowed by secure input", self.class);
    }
    return iTermEventTapModeFor(allowed,
                                self.remappingDelegateModifiesEvents,
                                self.weakObservers.count > 0,
                                [(iTermApplication *)NSApp it_isActiveThreadSafe]);
}

// Subclasses that install themselves as a pass-through remapping delegate override this.
- (BOOL)remappingDelegateModifiesEvents {
    return self.remappingDelegate != nil;
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
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        RLog(@"event tap special type %@", @(type));
    } else {
        @try {
            DLog(@"event tap %@ for %@", eventTap, [NSEvent eventWithCGEvent:event]);
        } @catch (NSException *exception) {
            DLog(@"Exception while trying to log event");
        }
    }
    if ([NSThread isMainThread]) {
        return [eventTap eventTapCallbackWithProxy:proxy type:type event:event];
    }
    return [eventTap filterThreadEventTapCallbackWithProxy:proxy type:type event:event];
}

// Runs on the filter thread. Avoids touching the main thread at all while iTerm2 is inactive so
// other apps never wait for it.
- (CGEventRef)filterThreadEventTapCallbackWithProxy:(CGEventTapProxy)proxy
                                               type:(CGEventType)type
                                              event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        __weak __typeof(self) weakSelf = self;
        iTermEventTapPerformOnMainThread(^{
            [weakSelf eventTapCallbackWithProxy:proxy type:type event:NULL];
        });
        return event;
    }
    if (![(iTermApplication *)NSApp it_isActiveThreadSafe]) {
        // Remapping only happens while iTerm2 is active. Observers still need to hear about the
        // event but they can do so later.
        [self filterThreadWillDeferDelivery];
        CGEventRef copy = CGEventCreateCopy(event);
        __weak __typeof(self) weakSelf = self;
        iTermEventTapPerformOnMainThread(^{
            [weakSelf notifyObserversOfEventFromInactiveApp:copy type:type];
            CFRelease(copy);
        });
        return event;
    }
    __block CGEventRef result = NULL;
    iTermEventTapPerformOnMainThreadAndWait(^{
        result = [self eventTapCallbackWithProxy:proxy type:type event:event];
    });
    return result;
}

// Called on the filter thread before deferring delivery to observers to the main thread.
- (void)filterThreadWillDeferDelivery {
}

- (void)notifyObserversOfEventFromInactiveApp:(CGEventRef)event type:(CGEventType)type {
    if (![self shouldHandleEvents]) {
        return;
    }
    [self postEventToObservers:event type:type];
}

- (CGEventRef)eventTapCallbackWithProxy:(CGEventTapProxy)proxy
                                   type:(CGEventType)type
                                  event:(CGEventRef)event {
    DLog(@"Event tap running");
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        RLog(@"Event tap disabled (type is %@)", @(type));
        if ([self isEnabled]) {
            RLog(@"Re-enabling event tap");
            [self reEnable];
        }
        return NULL;
    }
    if (![self shouldHandleEvents]) {
        return event;
    }

    return [self handleEvent:event ofType:type];
}

- (BOOL)shouldHandleEvents {
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        DLog(@"Workspace session not active");
        return NO;
    }

    if (![self userIsActive]) {
        // Fast user switching has switched to another user, don't do any remapping.
        DLog(@"User not active");
        return NO;
    }
    return YES;
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
    for (iTermWeakBox<id<iTermEventTapObserver>> *box in [self.weakObservers copy]) {
        [box.object eventTappedWithType:type event:event];
    }
    [self pruneReleasedObservers];
}

- (void)pruneReleasedObservers {
    [_weakObservers pruneEmptyWeakBoxes];
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
    CFRunLoopRemoveSource(_runLoop,
                          _eventSource,
                          kCFRunLoopCommonModes);
    CFRelease(_eventSource);
    _eventSource = NULL;
    _runLoop = NULL;

    // Switch off the event taps.
    CFMachPortInvalidate(_machPort);
    CFRelease(_machPort);
    _machPort = NULL;
}

// A listen-only keyboard tap needs Input Monitoring permission, while a filtering tap needs
// Accessibility, which is what users have historically granted. Callers don't ask for listen-only
// without Input Monitoring, to avoid a new permission prompt; they get a filtering tap on the filter
// thread instead, which passes events straight through while iTerm2 is inactive.
- (BOOL)startEventTapListenOnly:(BOOL)listenOnly {
    RLog(@"Start event tap listenOnly=%@", @(listenOnly));
    assert(!self.isEnabled);
    AppendPinnedDebugLogMessage(@"EventTap",
                                listenOnly ? @"Register listen-only event tap." : @"Register filtering event tap.");
    _machPort = CGEventTapCreate(kCGHIDEventTap,
                                 kCGTailAppendEventTap,
                                 listenOnly ? kCGEventTapOptionListenOnly : kCGEventTapOptionDefault,
                                 _types,
                                 (CGEventTapCallBack)iTermEventTapCallback,
                                 (__bridge void *)self);
    if (!_machPort) {
        XLog(@"CGEventTapCreate failed");
        AppendPinnedDebugLogMessage(@"EventTap", @"CGEventTapCreate failed");
        [[iTermPermissionsHelper accessibility] request];
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
    // A listen-only tap can't delay anyone, so its observers run on the main thread as before.
    _runLoop = listenOnly ? CFRunLoopGetMain() : iTermEventTapFilterRunLoop();
    _installedListenOnly = listenOnly;
    CFRunLoopAddSource(_runLoop,
                       _eventSource,
                       kCFRunLoopCommonModes);

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

@implementation iTermFlagsChangedEventTap {
    iTermFlagsChangedLedger *_ledger;
}

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
    return [self sharedInstanceCreatingIfNeeded:YES];
}

- (instancetype)initPrivate {
    self = [super initWithEventTypes:CGEventMaskBit(kCGEventFlagsChanged)];
    if (self) {
        _ledger = [[iTermFlagsChangedLedger alloc] init];
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
    const NSInteger count = _ledger.deliveryCount;
    if ([_ledger appReceivedEventShouldInject]) {
        DLog(@"Injecting flagsChanged event %@ because the tap didn't report it", notification.event);
        [super handleEvent:notification.event.CGEvent ofType:kCGEventFlagsChanged];
    } else {
        DLog(@"NOT injecting flagsChanged event. count was %@", @(count));
    }
}

- (CGEventRef)handleEvent:(CGEventRef)originalEvent ofType:(CGEventType)type {
    [_ledger eventTapDidDeliverEvent];
    DLog(@"Incr count to %@", @(_ledger.deliveryCount));
    return [super handleEvent:originalEvent ofType:type];
}

- (void)filterThreadWillDeferDelivery {
    [_ledger eventTapWillDeliverEventLater];
}

- (void)notifyObserversOfEventFromInactiveApp:(CGEventRef)event type:(CGEventType)type {
    [_ledger eventTapDidDeliverDeferredEvent];
    [super notifyObserversOfEventFromInactiveApp:event type:type];
}

- (NSInteger)count {
    return _ledger.deliveryCount;
}

- (void)resetCount {
    DLog(@"Reset count");
    [_ledger reset];
}

- (BOOL)startEventTapListenOnly:(BOOL)listenOnly {
    // A count left over from the previous tap would keep -flagsDidChange: from injecting an event
    // the new tap missed while it was being built.
    [self resetCount];
    return [super startEventTapListenOnly:listenOnly];
}

- (BOOL)allowedByEventTap {
    return YES;
}

- (BOOL)remappingDelegateModifiesEvents {
    return self.remappingDelegate != nil && self.remappingDelegate != self;
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
    return [self sharedInstanceCreatingIfNeeded:YES];
}

- (instancetype)initPrivate {
    self = [super initWithEventTypes:CGEventMaskBit(kCGEventKeyDown)];
    if (self) {
        self.remappingDelegate = self;
    }
    return self;
}

- (BOOL)remappingDelegateModifiesEvents {
    return self.remappingDelegate != nil && self.remappingDelegate != self;
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTap:(iTermEventTap *)eventTap
                               withType:(CGEventType)type
                                  event:(CGEventRef)event {
    return event;
}

@end
