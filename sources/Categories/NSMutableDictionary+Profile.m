//
//  NSMutableDictionary+Profile.m
//  iTerm2
//
//  Created by George Nachman on 4/20/15.
//
//

#import "NSMutableDictionary+Profile.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSDictionary+Profile.h"
#import "NSObject+iTerm.h"

@implementation NSMutableDictionary (Profile)

- (void)profileMarkAsDynamic {
    self[KEY_DYNAMIC_PROFILE] = @YES;
    if ([iTermAdvancedSettingsModel addDynamicTagToDynamicProfiles]) {
        [self profileAddDynamicTagIfNeeded];
    }
}

- (void)profileAddDynamicTagIfNeeded {
    NSArray *tags = [NSArray castFrom:self[KEY_TAGS]];
    if ([tags containsObject:kProfileDynamicTag]) {
        return;
    }
    if (!tags) {
        self[KEY_TAGS] = @[ kProfileDynamicTag ];
    } else {
        self[KEY_TAGS] = [tags arrayByAddingObject:kProfileDynamicTag];
    }
}

@end
