//
//  iTermLaunchExperienceController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/14/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Manages spamming the user on cold launch to avoid battering them too much.
@interface iTermLaunchExperienceController : NSObject

+ (void)applicationWillFinishLaunching;
+ (void)applicationDidFinishLaunching;
+ (void)performStartupActivities;
+ (void)forceShowWhatsNew;

@end

NS_ASSUME_NONNULL_END
