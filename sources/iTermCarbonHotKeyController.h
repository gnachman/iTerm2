#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "iTermShortcut.h"

// An opaque representation of a binding of (keyCode, modifiers) -> (target, selector, userData).
@class iTermHotKey;

@interface iTermHotKey : NSObject
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) NSDictionary *userData;
@property(nonatomic, readonly) EventHotKeyRef eventHotKey;
@property(nonatomic, readonly) EventHotKeyID hotKeyID;
@property(nonatomic, readonly) iTermShortcut *shortcut;
@end

@interface iTermCarbonHotKeyController : NSObject

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Start calling [target selector:userData:siblings:] when the hotkey is pressed. More than one hotkey may
// use the same keycode and modifiers. The siblings argument gives an array of other iTermHotKey*s that
// take the same keypress. The selector returns an array of iTermHotKey*s that were handled, and they
// won't have their actions invoked.
- (iTermHotKey *)registerShortcut:(iTermShortcut *)shortcut
                           target:(id)target
                         selector:(SEL)selector
                         userData:(NSDictionary *)userData;

// Stop calling [target selector:userData] when the hotkey is pressed.
- (void)unregisterHotKey:(iTermHotKey *)hotKey;

@end
