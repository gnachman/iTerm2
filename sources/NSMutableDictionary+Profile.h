//
//  NSMutableDictionary+Profile.h
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableDictionary (Profile)

// Mark this profile as a dynamic profile by setting KEY_DYNAMIC_PROFILE to YES.
- (void)profileMarkAsDynamic;

@end
