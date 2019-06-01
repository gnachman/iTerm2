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

+ (NSArray<NSString *> *)allKeys;
+ (BOOL)valueIsLegal:(id)value forKey:(NSString *)key;
+ (id)defaultObjectForKey:(NSString *)key;

// Sets a bunch of values at once (just one notification posted).
+ (void)setObjectsFromDictionary:(NSDictionary *)dictionary
                       inProfile:(Profile *)profile
                           model:(ProfileModel *)model;

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

+ (NSInteger)integerForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setInteger:(NSInteger)value
            forKey:(NSString *)key
         inProfile:(Profile *)profile
             model:(ProfileModel *)model;

+ (NSUInteger)unsignedIntegerForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setUnsignedInteger:(NSUInteger)value
        forKey:(NSString *)key
     inProfile:(Profile *)profile
         model:(ProfileModel *)model;

+ (double)floatForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setFloat:(double)value
          forKey:(NSString *)key
       inProfile:(Profile *)profile
           model:(ProfileModel *)model;

+ (double)doubleForKey:(NSString *)key inProfile:(Profile *)profile;
+ (void)setDouble:(double)value
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

+ (void)setObject:(id)object
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model
  withSideEffects:(BOOL)withSideEffects;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;
+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;

// Returns nil if the value is nil, the key is bogus, or it could not be json encoded for some reason.
+ (NSString *)jsonEncodedValueForKey:(NSString *)key inProfile:(Profile *)profile;
+ (NSArray<NSString *> *)nonDeprecatedKeys;

@end
