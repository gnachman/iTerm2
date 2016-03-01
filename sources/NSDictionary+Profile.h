//
//  NSDictionary+Profile.h
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import <Foundation/Foundation.h>

extern NSString *const kProfileDynamicTag;
extern NSString *const kProfileLegacyDynamicTag;

@interface NSDictionary (Profile)

// Profile has the tag "Dynamic" or "dynamic" (deprecated) or a tag that begins
// with "Dynamic/".
@property(nonatomic, readonly) BOOL profileIsDynamic;

// Just compares GUIDs.
- (BOOL)isEqualToProfile:(NSDictionary *)other;

@end
