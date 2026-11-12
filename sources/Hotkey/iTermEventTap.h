#import <Foundation/Foundation.h>
#import "iTermWeakBox.h"

@class iTermEventTap;

typedef NS_ENUM(NSInteger, iTermEventTapMode) {
    iTermEventTapModeOff,
    // Sees events but cannot change or delay them.
    iTermEventTapModeListenOnly,
    // Every matching event in every app waits for the callback to return, so use it only when
    // events must be rewritten.
    iTermEventTapModeFilter
};

// Exposed for testing.
iTermEventTapMode iTermEventTapModeFor(BOOL allowed,
                                       BOOL delegateModifiesEvents,
                                       BOOL hasObservers,
                                       BOOL appActive);

// Whether a tap started for `mode` is installed listen-only. A listen-only keyboard tap needs
// Input Monitoring permission; without it a filtering tap is installed instead. Exposed for testing.
BOOL iTermEventTapInstallsListenOnly(iTermEventTapMode mode, BOOL hasListenEventAccess);

@protocol iTermEventTapRemappingDelegate<NSObject>

// Called on every keypress when the event tap is enabled and iTerm2 is active. While iTerm2 is
// inactive, events pass through unmodified without waiting for the main thread.
//
// `event` is the keypress event. Returns the event the system should use or
// NULL to cancel the event.
//
// The type may indicate the event tap was cancelled and the delegate  may call
// -reEnable to start it up again.
- (CGEventRef)remappedEventFromEventTap:(iTermEventTap *)eventTap
                               withType:(CGEventType)type
                                  event:(CGEventRef)event;

@end

@protocol iTermEventTapObserver<NSObject>
- (void)eventTappedWithType:(CGEventType)type event:(CGEventRef)event;
@end

/**
 * Manages an event tap. The delegate's method will be invoked when any key is pressed.
 */
@interface iTermEventTap : NSObject

// Indicates if the event tap has started. Whether it should be, and what kind of tap it is, follows
// desiredMode.
@property(nonatomic, getter=isEnabled, readonly) BOOL enabled;

// The kind of tap that should be installed (see iTermEventTapModeFor):
// - Off when secure input disallows it, or with neither a delegate that modifies events nor
//   observers.
// - Filter with a delegate that modifies events, or with observers while iTerm2 is active.
// - ListenOnly with only observers while iTerm2 is inactive, so other apps never wait for iTerm2.
// Filtering taps run on a dedicated thread; see iTermEventTap.m.
@property(nonatomic, readonly) iTermEventTapMode desiredMode;

// While the event tap is enabled and iTerm2 is active the delegate's method is invoked on each
// event. The returned value replaces the original event. If you want read-only access add yourself
// as an observer.
@property(nonatomic, assign) id<iTermEventTapRemappingDelegate> remappingDelegate;

@property(nonatomic, readonly) NSArray<iTermWeakBox<id<iTermEventTapObserver>> *> *weakObservers;

// `types` is from CGEventMaskBit(kCGEventKeyDown), for example
- (instancetype)initWithEventTypes:(CGEventMask)types NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addObserver:(id<iTermEventTapObserver>)observer;
- (void)removeObserver:(id<iTermEventTapObserver>)observer;

// For testing. Returns the transformed event.
- (NSEvent *)runEventTapHandler:(NSEvent *)event;

@end

// Use this event tap to catch flags-changed events. It's provided as a
// convenience since there are multiple consumers. Setting the remapping delegate to nil installs
// itself as a pass-through delegate, which doesn't count as modifying events: with no other
// delegate and no observers the tap is off. When iTerm2 receives a flags-changed event the tap
// didn't report, it injects it into the observers.
@interface iTermFlagsChangedEventTap : iTermEventTap
// Number of times the event tap reported an event since -resetCount, initialization, or iTerm2
// last received a flags-changed event.
@property (nonatomic, readonly) NSInteger count;

// WARNING: This creates the object, though not necessarily a live tap (see desiredMode). Use
// sharedInstanceCreatingIfNeeded: if you don't want it created at all.
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded;
- (void)resetCount;

@end

// A shared key-down tap for observers. Like iTermFlagsChangedEventTap, its default pass-through
// delegate doesn't count as modifying events, so it's off without observers.
@interface iTermKeyDownEventTap : iTermEventTap

// WARNING: This creates the object, though not necessarily a live tap (see desiredMode). Use
// sharedInstanceCreatingIfNeeded: if you don't want it created at all.
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded;

@end
