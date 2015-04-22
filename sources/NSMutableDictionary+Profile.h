//
//  NSMutableDictionary+Profile.h
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableDictionary (Profile)

// If the profile is not currently tagged as dynamic (per the rules for
// profileIsDynamic), add a "Dynamic" tag.
- (void)profileAddDynamicTagIfNeeded;

@end
