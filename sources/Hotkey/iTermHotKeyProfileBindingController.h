#import <Foundation/Foundation.h>

// Ensures that profiles' hotkey settings are properly bound to carbon hot keys.
@interface iTermHotKeyProfileBindingController : NSObject
+ (instancetype)sharedInstance;
- (void)refresh;
@end

