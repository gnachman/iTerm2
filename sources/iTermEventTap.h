#import <Foundation/Foundation.h>
#import "iTermWeakBox.h"

@class iTermEventTap;

@protocol iTermEventTapRemappingDelegate<NSObject>

// Called on every keypress when the event tap is enabled.
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

// Indicates if the event tap has started. When a remapping delegate or observers are present it will
// be enabled.
@property(nonatomic, getter=isEnabled, readonly) BOOL enabled;

// While the event tap is enabled the delegate's method is invoked on each
// event. The returned value replaces the original event. This must be set for
// the event tap to be enabled. If you want read-only access add yourself as an
// observer.
@property(nonatomic, assign) id<iTermEventTapRemappingDelegate> remappingDelegate;

@property(nonatomic, readonly) NSArray<iTermWeakBox<id<iTermEventTapObserver>> *> *weakObservers;

// `types` is from CGEventMaskBit(kCGEventKeyDown), for example
- (instancetype)initWithEventTypes:(CGEventMask)types NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addObserver:(id<iTermEventTapObserver>)observer;
- (void)removeObserver:(id<iTermEventTapObserver>)observer;

// For testing. Returns the transformed event.
- (NSEvent *)runEventTapHandler:(NSEvent *)event;
- (void)reinsertAtHead;

@end

// Use this event tap to catch flags-changed events. It's provided as a
// convenience since there are multiple consumers. It is enabled even when the
// remapping delegate is set to nil.
@interface iTermFlagsChangedEventTap : iTermEventTap
// Number of times the event tap fired since -resetCount or initialization.
@property (nonatomic, readonly) NSInteger count;

// WARNING: This will create the event tap. Use sharedInstanceCreatingIfNeeded: if you don't want
// it created at all.
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded;
- (void)resetCount;

@end

@interface iTermKeyDownEventTap : iTermEventTap

// WARNING: This will create the event tap. Use sharedInstanceCreatingIfNeeded: if you don't want
// it created at all.
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceCreatingIfNeeded:(BOOL)createIfNeeded;

@end
