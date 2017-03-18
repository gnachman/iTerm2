//
//  iTermDynamicProfileManager.m
//  iTerm2
//
//  Created by George Nachman on 12/30/15.
//
//

#import "iTermDynamicProfileManager.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableDictionary+Profile.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "SCEvents.h"

@interface iTermDynamicProfileManager () <SCEventListenerProtocol>
@end


@implementation iTermDynamicProfileManager {
  SCEvents *_events;
}

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static id instance;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _events = [[SCEvents alloc] init];
    _events.delegate = self;
    [_events startWatchingPaths:@[ [self dynamicProfilesPath] ]];
  }
  return self;
}

- (void)dealloc {
  [_events release];
  [super dealloc];
}

- (NSString *)dynamicProfilesPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appSupport = [fileManager applicationSupportDirectory];
    NSString *thePath = [appSupport stringByAppendingPathComponent:@"DynamicProfiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:thePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return thePath;
}

- (void)reloadDynamicProfiles {
    [[ProfileModel sharedInstance] performBlockWithCoalescedNotifications:^{
        [ITAddressBookMgr performBlockWithCoalescedNotifications:^{
            [self reallyReloadDynamicProfiles];
        }];
    }];
}

- (void)reallyReloadDynamicProfiles {
    NSString *path = [self dynamicProfilesPath];
    DLog(@"Reloading dynamic profiles from %@", path);
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Load the current dynamic profiles into |newProfiles|. The |guids| set
    // is used to ensure that guids are unique across all files.
    NSMutableArray *newProfiles = [NSMutableArray array];
    NSMutableSet *guids = [NSMutableSet set];
    NSMutableArray *fileNames = [NSMutableArray array];
    for (NSString *file in [fileManager enumeratorAtPath:path]) {
        [fileNames addObject:file];
    }
    [fileNames sortUsingSelector:@selector(compare:)];
    for (NSString *file in fileNames) {
        DLog(@"Examine file %@", file);
        if ([file hasPrefix:@"."]) {
            DLog(@"Skipping it because of leading dot");
            continue;
        }
        NSString *fullName = [path stringByAppendingPathComponent:file];
        if (![self loadDynamicProfilesFromFile:fullName intoArray:newProfiles guids:guids]) {
            XLog(@"Igoring dynamic profiles in malformed file %@ and continuing.", fullName);
        }
    }

    DLog(@"Begin add/update phase");
    // Update changes to existing dynamic profiles and add ones whose guids are
    // not known.
    NSArray *oldProfiles = [self dynamicProfiles];
    BOOL shouldReload = newProfiles.count > 0;
    for (Profile *profile in newProfiles) {
        Profile *existingProfile = [self profileWithGuid:profile[KEY_GUID] inArray:oldProfiles];
        if (existingProfile) {
            [self updateDynamicProfile:profile];
        } else {
            [self addDynamicProfile:profile];
        }
    }

    DLog(@"Begin remove phase");
    // Remove dynamic profiles whose guids no longer exist.
    for (Profile *profile in oldProfiles) {
        DLog(@"Check profile name=%@ guid=%@", profile[KEY_NAME], profile[KEY_GUID]);
        if (![self profileWithGuid:profile[KEY_GUID] inArray:newProfiles]) {
            if ([self removeDynamicProfile:profile]) {
                shouldReload = YES;
            }
        }
    }
    DLog(@"Remove phase is done");

    if (shouldReload) {
        DLog(@"Post reload notification");
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                            object:nil
                                                          userInfo:nil];
    }
}

- (NSArray<Profile *> *)profilesInFile:(NSString *)filename fileType:(iTermDynamicProfileFileType *)fileType {
    DLog(@"Loading dynamic profiles from file %@", filename);
    // First, try xml and binary.
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (dict) {
        if (fileType) {
            *fileType = kDynamicProfileFileTypePropertyList;
        }
    } else {
        // Try JSON
        NSData *data = [NSData dataWithContentsOfFile:filename];
        if (!data) {
            XLog(@"Dynamic Profiles file %@ is unreadable", filename);
            return nil;
        }
        NSError *error = nil;
        dict = [NSJSONSerialization JSONObjectWithData:data
                                               options:0
                                                 error:&error];
        if (!dict) {
            XLog(@"Dynamic Profiles file %@ doesn't contain a valid property list", filename);
            return nil;
        }
        if (fileType) {
            *fileType = kDynamicProfileFileTypeJSON;
        }
    }
    NSArray *entries = dict[@"Profiles"];
    if (!entries) {
        XLog(@"Property list in %@ has no entries", entries);
        return nil;
    }
    
    NSMutableArray *profiles = [NSMutableArray array];
    for (Profile *profile in entries) {
        if (![profile[KEY_GUID] isKindOfClass:[NSString class]]) {
            XLog(@"Dynamic profile is missing the Guid field in file %@", filename);
            continue;
        }
        if (![profile[KEY_NAME] isKindOfClass:[NSString class]]) {
            XLog(@"Dynamic profile with guid %@ is missing the name field", profile[KEY_GUID]);
            continue;
        }
        if ([self nonDynamicProfileHasGuid:profile[KEY_GUID]]) {
            XLog(@"Dynamic profile with guid %@ conflicts with non-dynamic profile with same guid",
                 profile[KEY_GUID]);
            continue;
        }
        [profiles addObject:profile];
    }
    return profiles;
}

- (NSDictionary *)dictionaryForProfiles:(NSArray<Profile *> *)profiles {
    return @{ @"Profiles": profiles };
}

- (BOOL)loadDynamicProfilesFromFile:(NSString *)filename
                          intoArray:(NSMutableArray *)profiles
                              guids:(NSMutableSet *)guids {
    NSArray<Profile *> *allProfiles = [self profilesInFile:filename fileType:nil];
    if (!allProfiles) {
        return NO;
    }
    
    for (Profile *profile in allProfiles) {
        if ([guids containsObject:profile[KEY_GUID]]) {
            XLog(@"Two dynamic profiles have the same guid: %@", profile[KEY_GUID]);
            continue;
        }
        DLog(@"Read profile name=%@ guid=%@", profile[KEY_NAME], profile[KEY_GUID]);
        profile = [profile dictionaryBySettingObject:filename forKey:KEY_DYNAMIC_PROFILE_FILENAME];
        [profiles addObject:profile];
        [guids addObject:profile[KEY_GUID]];
    }
    return YES;
}

// Does any "regular" profile have Guid |guid|?
- (BOOL)nonDynamicProfileHasGuid:(NSString *)guid {
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (!profile) {
        return NO;
    }
    return !profile.profileIsDynamic;
}

// Returns the current dynamic profiles.
- (NSArray *)dynamicProfiles {
    NSMutableArray *array = [NSMutableArray array];
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        if (profile.profileIsDynamic) {
            [array addObject:profile];
        }
    }
    return array;
}

// Returns the first profile in |profiles| whose guid is |guid|.
- (Profile *)profileWithGuid:(NSString *)guid inArray:(NSArray *)profiles {
    for (Profile *aProfile in profiles) {
        if ([guid isEqualToString:aProfile[KEY_GUID]]) {
            return aProfile;
        }
    }
    return nil;
}

// Reload a dynamic profile, re-merging it with its parent.
- (void)updateDynamicProfile:(Profile *)newProfile {
    DLog(@"Updating dynamic profile name=%@ guid=%@", newProfile[KEY_NAME], newProfile[KEY_GUID]);
    Profile *prototype = [self prototypeForDynamicProfile:newProfile];
    NSMutableDictionary *merged = [self profileByMergingProfile:newProfile
                                                    intoProfile:prototype];
    [merged profileAddDynamicTagIfNeeded];
    [[ProfileModel sharedInstance] setBookmark:merged
                                      withGuid:merged[KEY_GUID]];
}

// Copies fields from |profile| over those in |prototype| and returns a new
// mutable dictionary.
- (NSMutableDictionary *)profileByMergingProfile:(Profile *)profile
                                     intoProfile:(Profile *)prototype {
    NSMutableDictionary *merged = [[profile mutableCopy] autorelease];
    for (NSString *key in prototype) {
        if (profile[key]) {
            merged[key] = profile[key];
        } else {
            merged[key] = prototype[key];
        }
    }
    return merged;
}

- (Profile *)prototypeForDynamicProfile:(Profile *)profile {
    Profile *prototype = nil;
    NSString *parentName = profile[KEY_DYNAMIC_PROFILE_PARENT_NAME];
    if (parentName) {
        prototype = [[ProfileModel sharedInstance] bookmarkWithName:parentName];
        if (!prototype) {
            XLog(@"Dynamic profile %@ references unknown parent name %@. Using default profile as parent.",
                 profile[KEY_NAME], parentName);
        }
    }
    if (!prototype) {
        prototype = [[ProfileModel sharedInstance] defaultBookmark];
    }
    return prototype;
}

// Add a new dynamic profile to the model.
- (void)addDynamicProfile:(Profile *)profile {
    DLog(@"Add dynamic profile name=%@ guid=%@", profile[KEY_NAME], profile[KEY_GUID]);
    Profile *prototype = [self prototypeForDynamicProfile:profile];
    NSMutableDictionary *merged = [self profileByMergingProfile:profile
                                                    intoProfile:prototype];
    // Don't inherit the deprecated KEY_DEFAULT_BOOKMARK value, which in issue 4115 we learn can
    // cause a dynamic profile to become the default profile!
    [merged removeObjectForKey:KEY_DEFAULT_BOOKMARK];
    [merged profileAddDynamicTagIfNeeded];

    [[ProfileModel sharedInstance] addBookmark:merged];
}

// Remove a dynamic profile from the model. Updates displays of profiles,
// references to the profile, etc.
- (BOOL)removeDynamicProfile:(Profile *)profile {
    DLog(@"Remove dynamic profile name=%@ guid=%@", profile[KEY_NAME], profile[KEY_GUID]);
    ProfileModel *model = [ProfileModel sharedInstance];
    if ([ITAddressBookMgr canRemoveProfile:profile fromModel:model]) {
        return [ITAddressBookMgr removeProfile:profile fromModel:model];
    }
    return NO;
}

#pragma mark - SCEventListenerProtocol

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event {
    DLog(@"Path watcher noticed a change");
    [self reloadDynamicProfiles];
}

@end
