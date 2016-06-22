#import <Foundation/Foundation.h>

// Ensures that profiles' hotkey settingss are properly bound to carbon hot keys.
@interface iTermHotKeyProfileBindingController : NSObject
+ (instancetype)sharedInstance;
- (void)refresh;
@end

