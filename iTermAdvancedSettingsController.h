//
//  iTermAdvancedSettingsController.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const kAdvancedSettingIdentiferUseUnevenTabs;
extern NSString *const kAdvancedSettingIdentiferMinTabWidth;
extern NSString *const kAdvancedSettingIdentiferMinCompactTabWidth;
extern NSString *const kAdvancedSettingIdentiferOptimumTabWidth;
extern NSString *const kAdvancedSettingIdentiferAlternateMouseScroll;
extern NSString *const kAdvancedSettingIdentiferTraditionalVisualBell;

@interface iTermAdvancedSettingsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

+ (BOOL)boolForIdentifier:(NSString *)identifier;
+ (int)intForIdentifier:(NSString *)identifier;
+ (double)floatForIdentifier:(NSString *)identifier;

@end
