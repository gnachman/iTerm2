//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>

NSString *const kPreferenceKeyOpenBookmark;

@interface iTermPreferences : NSObject

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

@end
