//
//  NSBundle+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 6/29/17.
//
//

#import <Foundation/Foundation.h>

@interface NSBundle (iTerm)

+ (BOOL)it_isNightlyBuild;
+ (BOOL)it_isEarlyAdopter;
+ (NSDate *)it_buildDate;

@end
