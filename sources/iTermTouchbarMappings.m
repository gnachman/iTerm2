//
//  iTermTouchbarMappings.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermTouchbarMappings.h"

#import "ITAddressBookMgr.h"
#import "iTermKeyBindingAction.h"
#import "iTermKeystroke.h"
#import "NSArray+iTerm.h"

static NSDictionary<NSString *, NSDictionary *> *gTouchBarMappings;

@implementation iTermTouchbarMappings

+ (NSArray<iTermTouchbarItem *> *)sortedTouchbarItemsInDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict {
    NSArray<NSString *> *keys = dict.allKeys;
    keys = [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *_Nonnull key1, NSString *_Nonnull key2) {
        NSString *desc1 = [[iTermKeyBindingAction withDictionary:dict[key1]] label];
        NSString *desc2 = [[iTermKeyBindingAction withDictionary:dict[key2]] label];
        return [desc1 compare:desc2];
    }];
    return [keys mapWithBlock:^id(NSString *anObject) {
        return [[iTermTouchbarItem alloc] initWithIdentifier:anObject];
    }];
}

+ (void)removeTouchbarItem:(iTermTouchbarItem *)item {
    NSDictionary *dict = [self globalTouchBarMap];
    dict = [self dictionaryByRemovingTouchbarItem:item fromDictionary:dict];
    [self setGlobalTouchBarMap:dict];
}

+ (void)updateDictionary:(NSMutableDictionary *)dict
         forTouchbarItem:(iTermTouchbarItem *)touchbarItem
                  action:(iTermKeyBindingAction *)keyBindingAction {
    dict[touchbarItem.identifier] = keyBindingAction.dictionaryValue;
}

+ (void)loadGlobalTouchBarMap {
    gTouchBarMappings = [[NSUserDefaults standardUserDefaults] objectForKey:@"GlobalTouchBarMap"];
    if (!gTouchBarMappings) {
        NSString *plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"DefaultGlobalTouchBarMap" ofType:@"plist"];
        gTouchBarMappings = [NSDictionary dictionaryWithContentsOfFile:plistFile] ?: @{};
    }
}

+ (NSDictionary *)globalTouchBarMap {
    if (!gTouchBarMappings) {
        [self loadGlobalTouchBarMap];
    }
    return gTouchBarMappings;
}

+ (void)setGlobalTouchBarMap:(NSDictionary *)src {
    gTouchBarMappings = [src copy];
    [[NSUserDefaults standardUserDefaults] setObject:gTouchBarMappings forKey:@"GlobalTouchBarMap"];
}

+ (NSDictionary *)dictionaryByRemovingTouchbarItem:(iTermTouchbarItem *)item
                                    fromDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *temp = [dictionary mutableCopy];
    id key = [item keyInDictionary:dictionary];
    if (!key) {
        return dictionary;
    }
    [temp removeObjectForKey:key];
    return temp;
}

@end
