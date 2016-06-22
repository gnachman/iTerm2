#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

// An opaque representation of a binding of (keyCode, modifiers) -> (target, selector, userData).
@class iTermHotKey;

@interface iTermCarbonHotKeyController : NSObject

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Start calling [target selector:userData] when the hotkey is pressed. More than one hotkey may
// use the same keycode and modifiers.
- (iTermHotKey *)registerKeyCode:(NSUInteger)keyCode
                       modifiers:(NSEventModifierFlags)modifiers
                      characters:(NSString *)characters
     charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                          target:(id)target
                        selector:(SEL)selector
                        userData:(NSDictionary *)userData;

// Stop calling [target selector:userData] when the hotkey is pressed.
- (void)unregisterHotKey:(iTermHotKey *)hotKey;

@end
