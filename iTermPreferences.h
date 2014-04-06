//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>

// General
extern NSString *const kPreferenceKeyOpenBookmark;
extern NSString *const kPreferenceKeyOpenArrangementAtStartup;
extern NSString *const kPreferenceKeyQuitWhenAllWindowsClosed;
extern NSString *const kPreferenceKeyConfirmClosingMultipleTabs;
extern NSString *const kPreferenceKeyPromptOnQuit;
extern NSString *const kPreferenceKeyInstantReplayMemoryMegabytes;
extern NSString *const kPreferenceKeySavePasteAndCommandHistory;
extern NSString *const kPreferenceKeyAddBonjourHostsToProfiles;
extern NSString *const kPreferenceKeyCheckForUpdatesAutomatically;
extern NSString *const kPreferenceKeyCheckForTestReleases;


@interface iTermPreferences : NSObject

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

+ (int)intForKey:(NSString *)key;
+ (void)setInt:(int)value forKey:(NSString *)key;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;

// When the value held by |key| changes, the block is invoked with the old an
// new values. Either may be nil, but they are guaranteed to be different by
// value equality with isEqual:.
+ (void)addObserverForKey:(NSString *)key block:(void (^)(id before, id after))block;

@end
