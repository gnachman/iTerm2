#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

// An opaque representation of a binding of (keyCode, modifiers) -> (target, selector, userData).
@class iTermHotKey;

// Modifiers that aren't ignored.
extern NSEventModifierFlags kCarbonHotKeyModifiersMask;

@interface iTermHotKey : NSObject
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) NSDictionary *userData;
@property(nonatomic, readonly) EventHotKeyRef eventHotKey;
@property(nonatomic, readonly) EventHotKeyID hotKeyID;
@property(nonatomic, readonly) NSUInteger keyCode;
@property(nonatomic, readonly) UInt32 modifiers;
@property(nonatomic, readonly) NSString *characters;
@property(nonatomic, readonly) NSString *charactersIgnoringModifiers;
@end

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
