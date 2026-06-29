//
//  NSDictionary+Profile.m
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import "NSDictionary+Profile.h"
#import "ITAddressBookMgr.h"
#import "NSObject+iTerm.h"

NSString *const kProfileDynamicTag = @"Dynamic";

@implementation NSDictionary (Profile)

- (BOOL)profileIsDynamic {
    NSNumber *isDynamic = [NSNumber castFrom:self[KEY_DYNAMIC_PROFILE]];
    return [isDynamic boolValue];
}

- (BOOL)isEqualToProfile:(NSDictionary *)other {
    return [self[KEY_GUID] isEqualToString:other[KEY_GUID]];
}

@end
