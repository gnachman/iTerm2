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
#import "iTermAdvancedSettingsModel.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSMutableDictionary+Profile.h"
#import "ProfileModel.h"
#import "SCEvents.h"

@interface iTermDynamicProfileManager () <SCEventListenerProtocol>
@end

@interface iTermFilesAndFolders: NSObject
@property (nonatomic, readonly) NSSet<NSString *> *files;
@property (nonatomic, readonly) NSSet<NSString *> *folders;
@end

@implementation iTermFilesAndFolders

- (instancetype)initWithFiles:(NSSet<NSString *> *)files
                      folders:(NSSet<NSString *> *)folders {
    self = [super init];
    if (self) {
        _files = files.copy;
        _folders = folders.copy;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p files=%@ folders=%@>",
            NSStringFromClass(self.class),
            self,
            [_files.allObjects componentsJoinedByString:@", "],
            [_folders.allObjects componentsJoinedByString:@", "]];
}

- (BOOL)isEqual:(id)other {
    iTermFilesAndFolders *obj = [iTermFilesAndFolders castFrom:other];
    return [obj.files isEqual:self.files] && [obj.folders isEqual:self.folders];
}

@end

@implementation iTermDynamicProfileManager {
    SCEvents *_events;
    NSMutableDictionary<NSString *, NSString *> *_guidToPathMap;
    NSInteger _pendingErrors;
    iTermFilesAndFolders *_paths;
    NSArray *_tokens;
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
      _guidToPathMap = [[NSMutableDictionary alloc] init];
      NSString *path = [self dynamicProfilesPath];
      if (path == nil) {
          ELog(@"Dynamic profiles path is nil");
          return nil;
      }
      _events = [[SCEvents alloc] init];
      _events.notificationLatency = [iTermAdvancedSettingsModel dynamicProfilesNotificationLatency];
      _events.delegate = self;
      _paths = self.pathsToWatch;
      DLog(@"Watching files: %@, folders: %@", _paths.files, _paths.folders);
      [self startWatching];
  }
  return self;
}

- (void)startWatching {
    [_events startWatchingPaths:_paths.folders.allObjects];
    __weak __typeof(self) weakSelf = self;
    _tokens = [_paths.files.allObjects mapWithBlock:^id(NSString *file) {
        return [[NSFileManager defaultManager] monitorFile:file block:^(long flags) {
            [weakSelf somethingChanged];
        }];
    }];
}

- (void)stopWatching {
    [_events stopWatchingPaths];
    for (id token in _tokens) {
        [[NSFileManager defaultManager] stopMonitoringFileWithToken:token];
    }
    _tokens = nil;
}

- (iTermFilesAndFolders *)pathsToWatch {
    NSMutableSet<NSString *> *files = [NSMutableSet set];
    NSMutableSet<NSString *> *folders = [NSMutableSet set];

    NSString *path = [self dynamicProfilesPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager itemIsSymlink:path]) {
        NSString *resolved = [fileManager destinationOfSymbolicLinkAtPath:path error:nil];
        if (resolved && [fileManager itemIsDirectory:resolved]) {
            [folders addObject:resolved];
        } else {
            return [[iTermFilesAndFolders alloc] init];
        }
    } else {
        [folders addObject:path];
    }

    for (NSString *relativeFile in [fileManager enumeratorAtPath:path]) {
        NSString *file = [path stringByAppendingPathComponent:relativeFile];
        if (![fileManager itemIsSymlink:file]) {
            // Just a regular file
            continue;
        }
        file = [fileManager destinationOfSymbolicLinkAtPath:file error:nil];
        if (!file) {
            // Bogus symlink
            continue;
        }
        [files addObject:file];
    }

    return [[iTermFilesAndFolders alloc] initWithFiles:files folders:folders];
}

- (void)reportError:(NSString *)error file:(NSString *)file {
    [[iTermScriptHistory sharedInstance] addDynamicProfilesLoggingEntryIfNeeded];
    [[iTermScriptHistoryEntry dynamicProfilesEntry] addOutput:[error stringByAppendingString:@"\n"]
                                                   completion:^{}];

    _pendingErrors += 1;
    if (_pendingErrors > 1) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reallyReportError:error file:file];
    });
}

- (void)reallyReportError:(NSString *)error file:(NSString *)file {
    NSString *message =
    [NSString stringWithFormat:@"There was a problem with one of your Dynamic Profiles:\n\n%@", error];
    if (_pendingErrors > 1) {
        const NSInteger count = _pendingErrors - 1;
        message = [message stringByAppendingFormat:@"\n\n%@ additional error%@ may be seen in the log.",
                   @(count), count == 1 ? @"" : @"s"];
    }
    _pendingErrors = 0;
    NSButton *button = nil;
    if (file && [[NSFileManager defaultManager] fileExistsAtPath:file]) {
        button = [[NSButton alloc] init];
        button.buttonType = NSButtonTypeMomentaryPushIn;
        button.bezelStyle = NSBezelStyleRounded;
        button.title = @"Reveal in Finder";
        [button setAction:@selector(reveal:)];
        [button setTarget:self];
        [button setIdentifier:file];
        [button sizeToFit];
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK", @"View Log" ]
                             accessory:button
                            identifier:@"NoSyncDynamicProfilesWarning"
                           silenceable:kiTermWarningTypeTemporarilySilenceable
                               heading:@"Dynamic Profiles Error"
                                window:nil];
    if (selection == 1) {
        [[iTermScriptConsole sharedInstance] revealTailOfHistoryEntry:[iTermScriptHistoryEntry dynamicProfilesEntry]];
    }
}

- (void)reveal:(id)sender {
    NSButton *button = [NSButton castFrom:sender];
    if (!button) {
        return;
    }
    NSString *file = button.identifier;
    if (!file) {
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:file] ]];
}

- (void)revealProfileWithGUID:(NSString *)guid {
    NSString *fullPath = _guidToPathMap[guid];
    if (!fullPath) {
        [[NSWorkspace sharedWorkspace] openFile:self.dynamicProfilesPath
                                withApplication:@"Finder"];
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
}

// Returns ~/Library/Application Support/iTerm2/DynamicProfiles
- (NSString *)unresolvedDynamicProfilesPath {
    if ([[iTermAdvancedSettingsModel dynamicProfilesPath] length]) {
        return [[iTermAdvancedSettingsModel dynamicProfilesPath] stringByExpandingTildeInPath];
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appSupport = [fileManager applicationSupportDirectory];
    NSString *thePath = [appSupport stringByAppendingPathComponent:@"DynamicProfiles"];
    [fileManager createDirectoryAtPath:thePath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
    return thePath;
}

// If DynamicProfiles is a symlink, returns its destination
- (NSString *)dynamicProfilesPath {
    NSString *thePath = [self unresolvedDynamicProfilesPath];
    return [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:thePath error:nil] ?: thePath;
}

// Call this when a file or folder changes.
- (void)somethingChanged {
    DLog(@"Path watcher noticed a change");
    [self reloadDynamicProfiles];

    iTermFilesAndFolders *updatedPaths = self.pathsToWatch;
    if (![updatedPaths isEqual:_paths]) {
        DLog(@"Paths to watch changed to %@", updatedPaths);
        [self stopWatching];
        _paths = updatedPaths;
        [self startWatching];
    }
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
        } else if ([file hasSuffix:@"~"]) {
            DLog(@"Skipping it because of trailing tilde (GNU-style backup file)");
            continue;
        }
        NSString *fullName = [path stringByAppendingPathComponent:file];
        if (![self loadDynamicProfilesFromFile:fullName intoArray:newProfiles guids:guids]) {
            [self reportError:[NSString stringWithFormat:@"Ignoring dynamic profiles in “%@” because of an error.", fullName]
                         file:fullName];
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
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:filename options:0 error:&error];
        if (!data) {
            [self reportError:[NSString stringWithFormat:@"Could not read Dynamic Profile from file %@: %@",
                               filename, error.localizedDescription]
                         file:filename];
            return nil;
        }
        dict = [NSJSONSerialization JSONObjectWithData:data
                                               options:0
                                                 error:&error];
        if (!dict) {
            [self reportError:[NSString stringWithFormat:@"Dynamic Profiles file %@ contains invalid JSON: %@", filename, error.localizedDescription]
                         file:filename];
            return nil;
        }
        dict = [NSDictionary castFrom:dict];
        if (!dict) {
            [self reportError:[NSString stringWithFormat:@"Dynamic Profiles file %@ does not have an Object (i.e., a dictionary) as its root element", filename]
                         file:filename];
            return nil;
        }
        if (fileType) {
            *fileType = kDynamicProfileFileTypeJSON;
        }
    }
    NSArray *entries = dict[@"Profiles"];
    if (!entries) {
        XLog(@"Property list in %@ has no entries", entries);
        [self reportError:[NSString stringWithFormat:@"Dynamic Profiles file %@ does not have a “Profiles” key at the root.",
                           filename]
                     file:filename];
        return nil;
    }

    NSMutableArray *profiles = [NSMutableArray array];
    for (Profile *profile in entries) {
        if (![profile[KEY_GUID] isKindOfClass:[NSString class]]) {
            [self reportError:[NSString stringWithFormat:@"Dynamic profile is missing the Guid field in file %@", filename]
                         file:filename];
            continue;
        }
        if (![profile[KEY_NAME] isKindOfClass:[NSString class]]) {
            [self reportError:[NSString stringWithFormat:@"Dynamic profile with Guid %@ is missing the “name” field", profile[KEY_GUID]]
                         file:filename];
            continue;
        }
        if ([self nonDynamicProfileHasGuid:profile[KEY_GUID]]) {
            [self reportError:[NSString stringWithFormat:@"Dynamic profile with Guid %@ conflicts with non-dynamic profile with same Guid",
                 profile[KEY_GUID]]
                         file:filename];
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
            [self reportError:[NSString stringWithFormat:@"Two dynamic profiles have the same Guid: %@", profile[KEY_GUID]]
                         file:filename];
            continue;
        }
        DLog(@"Read profile name=%@ guid=%@", profile[KEY_NAME], profile[KEY_GUID]);
        {
            Profile *amendedProfile = [profile dictionaryBySettingObject:filename forKey:KEY_DYNAMIC_PROFILE_FILENAME];
            [profiles addObject:amendedProfile];
            NSString *guid = amendedProfile[KEY_GUID];
            [guids addObject:guid];
            _guidToPathMap[guid] = filename;
        }
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
    NSMutableDictionary *merged = [profile mutableCopy];
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
    NSString *parentGUID = profile[KEY_DYNAMIC_PROFILE_PARENT_GUID];
    if (!parentName && !parentGUID) {
        return [[ProfileModel sharedInstance] defaultBookmark];
    }
    // Find prototype by guid or name.
    prototype = [[ProfileModel sharedInstance] bookmarkWithGuid:parentGUID];
    if (!prototype) {
        prototype = [[ProfileModel sharedInstance] bookmarkWithName:parentName];
    }
    if (prototype) {
        return prototype;
    }

    // Failed. Show an error.
    NSString *feature;
    NSString *value;
    if (parentGUID) {
        value = parentGUID;
        feature = @"GUID";
    } else {
        value = parentName;
        feature = @"name";
    }
    [self reportError:[NSString stringWithFormat:@"Dynamic profile %@ references unknown parent %@ %@. Using default profile as parent.",
                       profile[KEY_NAME], feature, value]
                 file:profile[KEY_DYNAMIC_PROFILE_FILENAME]];
    return nil;
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

- (NSArray *)profilesByRemovingDynamicProfiles:(NSArray *)source {
    return [source filteredArrayUsingBlock:^BOOL(Profile *profile) {
        return !profile.profileIsDynamic;
    }];
}

#pragma mark - SCEventListenerProtocol

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event {
    [self somethingChanged];
}

@end
