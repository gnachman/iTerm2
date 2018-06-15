//
//  NSMutableDictionary+Profile.m
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import "NSMutableDictionary+Profile.h"
#import "ITAddressBookMgr.h"
#import "NSDictionary+Profile.h"
#import "NSObject+iTerm.h"

@implementation NSMutableDictionary (Profile)

- (void)profileAddDynamicTagIfNeeded {
    if (self.profileIsDynamic) {
        return;
    }
    NSArray *tags = [NSArray castFrom:self[KEY_TAGS]];
    if (!tags) {
        self[KEY_TAGS] = @[ kProfileDynamicTag ];
    } else if (!self.profileIsDynamic) {
        self[KEY_TAGS] = [tags arrayByAddingObject:kProfileDynamicTag];
    }
}

@end
