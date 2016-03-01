//
//  NSDictionary+Profile.m
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import "NSDictionary+Profile.h"
#import "ITAddressBookMgr.h"

NSString *const kProfileDynamicTag = @"Dynamic";
NSString *const kProfileDynamicTagRoot = @"Dynamic/";
NSString *const kProfileLegacyDynamicTag = @"dynamic";

@implementation NSDictionary (Profile)

- (BOOL)profileIsDynamic {
    NSArray *tags = self[KEY_TAGS];
    if ([tags containsObject:kProfileDynamicTag]) {
        return YES;
    }
    if ([tags containsObject:kProfileLegacyDynamicTag]) {
        return YES;
    }
    for (NSString *tag in tags) {
        if ([tag hasPrefix:kProfileDynamicTagRoot]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isEqualToProfile:(NSDictionary *)other {
    return [self[KEY_GUID] isEqualToString:other[KEY_GUID]];
}

@end
