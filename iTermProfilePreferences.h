//
//  iTermProfilePreferences.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import <Foundation/Foundation.h>
#import "PreferenceInfo.h"
#import "ProfileModel.h"

// Values for KEY_CUSTOM_COMMAND
extern NSString *const kProfilePreferenceCommandTypeCustomValue;
extern NSString *const kProfilePreferenceCommandTypeLoginShellValue;

// Values for KEY_CUSTOM_DIRECTORY
extern NSString *const kProfilePreferenceInitialDirectoryCustomValue;
extern NSString *const kProfilePreferenceInitialDirectoryHomeValue;
extern NSString *const kProfilePreferenceInitialDirectoryRecycleValue;
extern NSString *const kProfilePreferenceInitialDirectoryAdvancedValue;

@interface iTermProfilePreferences : NSObject

+ (BOOL)boolForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setBool:(BOOL)value
         forKey:(NSString *)key
      inProfile:(Profile *)profile
          model:(ProfileModel *)model;

+ (int)intForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setInt:(int)value
        forKey:(NSString *)key
     inProfile:(Profile *)profile
         model:(ProfileModel *)model;

+ (double)floatForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setFloat:(double)value
          forKey:(NSString *)key
       inProfile:(Profile *)profile
           model:(ProfileModel *)model;

+ (NSString *)stringForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setString:(NSString *)value
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model;

+ (id)objectForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setObject:(id)object
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;
+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;

@end
