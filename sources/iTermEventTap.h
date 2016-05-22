#import <Foundation/Foundation.h>

@protocol iTermEventTapDelegate<NSObject>

// Called on every keypress when the event tap is enabled.
//
// `event` is the keypress event. Returns the event the system should use or
// NULL to cancel the event.
//
// The type may indicate the event tap was cancelled and the delegate  may call
// -reEnable to start it up again.
- (CGEventRef)eventTappedWithType:(CGEventType)type event:(CGEventRef)event;

@end

/**
 * Manages an event tap. The delegate's method will be invoked when any key is pressed.
 */
@interface iTermEventTap : NSObject

// Assign to start or stop the event tap. The getter indicates if the event tap was started.
@property(nonatomic, getter=isEnabled) BOOL enabled;

// While the event tap is enabled the delegate's method is invoked on each key-down.
@property(nonatomic, assign) id<iTermEventTapDelegate> delegate;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

- (void)reEnable;

// For testing. Returns the transformed event.
- (NSEvent *)runEventTapHandler:(NSEvent *)event;

@end
