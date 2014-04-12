//
//  iTermProfilePreferences.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

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

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;

@end
