//
//  iTermSettingsModel.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

@interface iTermSettingsModel : NSObject

+ (BOOL)useUnevenTabs;
+ (int)minTabWidth;
+ (int)minCompactTabWidth;
+ (int)optimumTabWidth;
+ (BOOL)alternateMouseScroll;
+ (BOOL)traditionalVisualBell;
+ (double)hotkeyTermAnimationDuration;
+ (NSString *)searchCommand;
+ (double)antiIdleTimerPeriod;
+ (BOOL)dockIconTogglesWindow;
+ (double)timeBetweenBlinks;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)trimWhitespaceOnCopy;
+ (int)autocompleteMaxOptions;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForUrl;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForFile;

@end
