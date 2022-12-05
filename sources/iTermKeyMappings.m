//
//  iTermKeyMappings.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermKeyMappings.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermKeyBindingAction.h"
#import "iTermKeystroke.h"
#import "iTermPresetKeyMappings.h"
#import "iTermUserDefaultsObserver.h"
#import "NSArray+iTerm.h"
#import "ProfileModel.h"

NSString *const kKeyBindingsChangedNotification = @"kKeyBindingsChangedNotification";
static NSInteger iTermKeyMappingsNotificationSupressionCount = 0;
NSString *const iTermKeyMappingsLeaderDidChange = @"iTermKeyMappingsLeaderDidChange";

@implementation iTermKeyMappings

+ (void)suppressNotifications:(void (^ NS_NOESCAPE)(void))block {
    assert(iTermKeyMappingsNotificationSupressionCount >= 0);
    iTermKeyMappingsNotificationSupressionCount += 1;
    block();
    iTermKeyMappingsNotificationSupressionCount -= 1;
    assert(iTermKeyMappingsNotificationSupressionCount >= 0);
}

#pragma mark - Lookup

#pragma mark Action-Returning

+ (iTermKeyBindingAction *)actionForKeystroke:(iTermKeystroke *)keystroke
                                  keyMappings:(NSDictionary *)keyMappings {
    if (keyMappings) {
        iTermKeyBindingAction *action = [self localActionForKeystroke:keystroke
                                                          keyMappings:keyMappings];
        if (action) {
            return action;
        }
    }

    if (keyMappings == [self globalKeyMap]) {
        return nil;
    }

    return [self localActionForKeystroke:keystroke
                             keyMappings:[self globalKeyMap]];
}

+ (iTermKeyBindingAction *)globalActionAtIndex:(NSInteger)rowIndex {
    NSDictionary *km = [self globalKeyMap];
    NSArray *allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [iTermKeyBindingAction withDictionary:km[allKeys[rowIndex]]];
    }
    return nil;
}

+ (iTermKeyBindingAction *)localActionForKeystroke:(iTermKeystroke *)keystroke
                                       keyMappings:(NSDictionary *)keyMappings {
    NSDictionary *theKeyMapping = [keystroke valueInBindingDictionary:keyMappings];

    if (theKeyMapping == nil) {
        return nil;
    }

    return [iTermKeyBindingAction withDictionary:theKeyMapping];
}

#pragma mark Keystroke-Returning

+ (NSSet<iTermKeystroke *> *)keystrokesInKeyMappingsInProfile:(Profile *)sourceProfile {
    NSDictionary *keyMapping = sourceProfile[KEY_KEYBOARD_MAP];
    NSArray *keys = keyMapping.allKeys;
    NSArray *keystrokes = [keys mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }];
    return [NSSet setWithArray:keystrokes];
}

+ (NSSet<iTermKeystroke *> *)keystrokesInGlobalMapping {
    return [NSSet setWithArray:[[[self globalKeyMap] allKeys] mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }]];
}

+ (iTermKeystroke *)leader {
    NSString *string = [[NSUserDefaults standardUserDefaults] objectForKey:@"Leader"];
    if (!string) {
        return nil;
    }
    return [[iTermKeystroke alloc] initWithSerialized:string];
}

+ (void)setLeader:(iTermKeystroke *)keystroke {
    if (!keystroke) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"Leader"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:[keystroke serialized] forKey:@"Leader"];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermKeyMappingsLeaderDidChange object:nil];
}

#pragma mark Mapping-Related

+ (NSDictionary *)keyMappingsForProfile:(Profile *)profile {
    return profile[KEY_KEYBOARD_MAP];
}

+ (BOOL)haveKeyMappingForKeystroke:(iTermKeystroke *)keystroke inProfile:(Profile *)profile {
    NSDictionary *dict = profile[KEY_KEYBOARD_MAP];
    return [keystroke valueInBindingDictionary:dict] != nil;
}

+ (int)numberOfMappingsInProfile:(Profile *)profile {
    NSDictionary *keyMapDict = profile[KEY_KEYBOARD_MAP];
    return [keyMapDict count];
}

+ (NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)tuplesOfActionsInProfile:(Profile *)profile {
    NSMutableArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *result = [NSMutableArray array];
    NSDictionary<id, iTermKeyBindingAction *> *keyboardMap = profile[KEY_KEYBOARD_MAP];
    [keyboardMap enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull serialized, iTermKeyBindingAction * _Nonnull action, BOOL * _Nonnull stop) {
        iTermKeystroke *key = [[iTermKeystroke alloc] initWithSerialized:serialized];
        if (!key) {
            return;
        }
        [result addObject:[iTermTuple tupleWithObject:key
                                            andObject:action]];
    }];

    return result;
}

#pragma mark - Ordering

+ (NSArray<iTermKeystroke *> *)sortedGlobalKeystrokes {
    NSDictionary* km = [self globalKeyMap];
    NSArray *serialized = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    return [serialized mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }];
}

+ (NSArray<iTermKeystroke *> *)sortedKeystrokesForProfile:(Profile *)profile {
    NSDictionary *km = profile[KEY_KEYBOARD_MAP];
    NSArray *serialized = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    return [serialized mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }];
}

+ (iTermKeystroke *)keystrokeAtIndex:(int)rowIndex inprofile:(Profile *)profile {
    NSDictionary *km = profile[KEY_KEYBOARD_MAP];
    NSArray *allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [[iTermKeystroke alloc] initWithSerialized:allKeys[rowIndex]];
    } else {
        return nil;
    }
}

+ (iTermKeystroke *)globalKeystrokeAtIndex:(int)rowIndex {
    NSDictionary *km = [self globalKeyMap];
    NSArray *allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [[iTermKeystroke alloc] initWithSerialized:allKeys[rowIndex]];
    } else {
        return nil;
    }
}

+ (NSArray<iTermKeystroke *> *)sortedKeystrokesForKeyMappingsInProfile:(Profile *)profile {
    NSDictionary *km = profile[KEY_KEYBOARD_MAP];
    NSArray *serialized = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    return [serialized mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }];
}

#pragma mark - Mutation

+ (void)removeAllGlobalKeyMappings {
    [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:@"GlobalKeyMap"];
}

+ (void)setMappingAtIndex:(int)rowIndex
             forKeystroke:(iTermKeystroke*)keyStroke
                   action:(iTermKeyBindingAction *)action
                createNew:(BOOL)newMapping
             inDictionary:(NSMutableDictionary *)mutableKeyMapping {
    assert(keyStroke);
    iTermKeystroke *originalKeystroke = nil;

    NSArray *allKeys =
        [[mutableKeyMapping allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    if (!newMapping) {
        if (rowIndex >= 0 && rowIndex < [allKeys count]) {
            originalKeystroke = [[iTermKeystroke alloc] initWithSerialized:allKeys[rowIndex]];
        } else {
            DLog(@"Invalid index %@", @(rowIndex));
            return;
        }
    } else if ([keyStroke keyInBindingDictionary:mutableKeyMapping]) {
        // new mapping but same key combo as an existing one - overwrite it
        originalKeystroke = keyStroke;
    } else {
        // creating a new mapping and it doesn't collide with an existing one
        originalKeystroke = nil;
    }

    if (originalKeystroke) {
        id keyToRemove = [originalKeystroke keyInBindingDictionary:mutableKeyMapping];
        if (keyToRemove) {
            [mutableKeyMapping removeObjectForKey:keyToRemove];
        }
    }
    mutableKeyMapping[keyStroke.serialized] = action.dictionaryValue;
}

+ (void)setMappingAtIndex:(int)rowIndex
             forKeystroke:(iTermKeystroke *)keystroke
                   action:(iTermKeyBindingAction *)action
                createNew:(BOOL)newMapping
                inProfile:(MutableProfile *)profile {
    NSMutableDictionary *keyMapping = [profile[KEY_KEYBOARD_MAP] mutableCopy];
    [self setMappingAtIndex:rowIndex
               forKeystroke:keystroke
                     action:action
                  createNew:newMapping
               inDictionary:keyMapping];
    profile[KEY_KEYBOARD_MAP] = keyMapping;
}

+ (void)removeKeystroke:(iTermKeystroke *)keystroke
            fromProfile:(MutableProfile *)profile {
    NSMutableDictionary *km = [profile[KEY_KEYBOARD_MAP] mutableCopy];
    id key = [keystroke keyInBindingDictionary:km];
    if (key) {
        [km removeObjectForKey:key];
    }
    profile[KEY_KEYBOARD_MAP] = km;
}

+ (NSMutableDictionary *)removeMappingAtIndex:(int)rowIndex inDictionary:(NSDictionary *)dict {
    NSMutableDictionary *km = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSArray *allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(compareSerializedKeystroke:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        [km removeObjectForKey:[allKeys objectAtIndex:rowIndex]];
    }
    return km;
}

+ (void)removeMappingAtIndex:(int)rowIndex fromProfile:(MutableProfile *)profile {
    profile[KEY_KEYBOARD_MAP] = [self removeMappingAtIndex:rowIndex
                                              inDictionary:profile[KEY_KEYBOARD_MAP]];
}

+ (void)removeAllMappingsInProfile:(MutableProfile *)profile {
    profile[KEY_KEYBOARD_MAP] = @{};
}

#pragma mark - Global State

+ (NSDictionary *)globalKeyMap {
    static NSDictionary *gGlobalKeyMapping;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *const key = @"GlobalKeyMap";
        gGlobalKeyMapping = [[NSUserDefaults standardUserDefaults] objectForKey:key];
        if (!gGlobalKeyMapping) {
            gGlobalKeyMapping = [iTermPresetKeyMappings defaultGlobalKeyMap];
        }
        static iTermUserDefaultsObserver *observer;
        observer = [[iTermUserDefaultsObserver alloc] init];
        [observer observeKey:key block:^{
            gGlobalKeyMapping = [[NSUserDefaults standardUserDefaults] objectForKey:key] ?: [iTermPresetKeyMappings defaultGlobalKeyMap];
            if (iTermKeyMappingsNotificationSupressionCount == 0) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                                    object:nil
                                                                  userInfo:nil];
            }
        }];
    });
    return gGlobalKeyMapping;
}

+ (NSDictionary *)defaultGlobalKeyMap {
    NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"DefaultGlobalKeyMap" ofType:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (void)setGlobalKeyMap:(NSDictionary *)src {
    [[NSUserDefaults standardUserDefaults] setObject:src forKey:@"GlobalKeyMap"];
    assert([self.globalKeyMap isEqual:src]);
}

+ (BOOL)haveGlobalKeyMappingForKeystroke:(iTermKeystroke *)keystroke {
    return [keystroke valueInBindingDictionary:self.globalKeyMap] != nil;
}

#pragma mark - High-Level APIs

+ (iTermKeystroke *)keystrokeForMappingReferencingProfileWithGuid:(NSString *)guid
                                                        inProfile:(Profile *)profile {
    __block iTermKeystroke *result = nil;
    NSDictionary *keyboardMap = profile[KEY_KEYBOARD_MAP];

    // Search for a keymapping with an action that references a profile.
    [keyboardMap enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull keyMap, BOOL * _Nonnull stop) {
        iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:keyMap];
        if (action.keyAction == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
            action.keyAction == KEY_ACTION_NEW_WINDOW_WITH_PROFILE ||
            action.keyAction == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
            action.keyAction == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
            action.keyAction == KEY_ACTION_SET_PROFILE) {
            NSString *referencedGuid = action.parameter;
            if ([referencedGuid isEqualToString:guid]) {
                result = [[iTermKeystroke alloc] initWithSerialized:key];
                *stop = YES;
            }
        }
    }];
    return result;
}

+ (Profile *)removeKeyMappingsReferencingGuid:(NSString *)guid fromProfile:(Profile *)profile {
    if (profile) {
        MutableProfile *mutableProfile = nil;
        while (YES) {
            iTermKeystroke *keystrokeToRemove =
                [iTermKeyMappings keystrokeForMappingReferencingProfileWithGuid:guid
                                                                      inProfile:mutableProfile ?: profile];
            if (!keystrokeToRemove) {
                break;
            }
            NSArray *sortedKeystrokes = [iTermKeyMappings sortedKeystrokesForKeyMappingsInProfile:mutableProfile ?: profile];
            const NSInteger i = [sortedKeystrokes indexOfObject:keystrokeToRemove];
            if (i != NSNotFound) {
                if (!mutableProfile) {
                    mutableProfile = [profile mutableCopy];
                }
                [self removeMappingAtIndex:i fromProfile:mutableProfile];
            } else {
                XLog(@"Profile with guid %@ has key mapping referencing guid %@ with keystroke %@ but I can't find it in sorted keys",
                     profile[KEY_GUID],
                     guid,
                     keystrokeToRemove);
                break;
            }
        }
        return mutableProfile;
    }
    BOOL change;
    do {
        NSMutableDictionary *mutableGlobalKeyMap = [[self globalKeyMap] mutableCopy];
        change = NO;
        for (NSInteger i = 0; i < [mutableGlobalKeyMap count]; i++) {
            iTermKeyBindingAction *action = [self globalActionAtIndex:i];
            if (action.keyAction == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
                action.keyAction == KEY_ACTION_NEW_WINDOW_WITH_PROFILE ||
                action.keyAction == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
                action.keyAction == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
                action.keyAction == KEY_ACTION_SET_PROFILE) {
                NSString *referencedGuid = action.parameter;
                if (![referencedGuid isEqualToString:guid]) {
                    continue;
                }
                mutableGlobalKeyMap = [self removeMappingAtIndex:i
                                                    inDictionary:mutableGlobalKeyMap];
                [self setGlobalKeyMap:mutableGlobalKeyMap];
                change = YES;
                break;
            }
        }
    } while (change);
    return nil;
}

@end
