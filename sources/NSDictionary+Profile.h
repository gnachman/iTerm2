//
//  NSDictionary+Profile.h
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import <Foundation/Foundation.h>

extern NSString *const kProfileDynamicTag;

@interface NSDictionary (Profile)

// Profile is dynamic if KEY_DYNAMIC_PROFILE is YES.
@property(nonatomic, readonly) BOOL profileIsDynamic;

// Just compares GUIDs.
- (BOOL)isEqualToProfile:(NSDictionary *)other;

@end
