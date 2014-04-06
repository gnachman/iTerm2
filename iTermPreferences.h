//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>

extern NSString *const kPreferenceKeyOpenBookmark;
extern NSString *const kPreferenceKeyOpenArrangementAtStartup;
extern NSString *const kPreferenceKeyQuitWhenAllWindowsClosed;

@interface iTermPreferences : NSObject

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;

@end
