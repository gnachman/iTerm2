//
//  iTermMigrationHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/1/18.
//

#import "iTermMigrationHelper.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermDisclosableView.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSWorkspace+iTerm.h"

@implementation iTermMigrationHelper

+ (BOOL)removeLegacyAppSupportFolderIfPossible {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *legacy = [fileManager legacyApplicationSupportDirectory];

    if (![fileManager itemIsDirectory:legacy]) {
        return NO;
    }

    BOOL foundVersionTxt = NO;
    for (NSString *file in [fileManager enumeratorAtPath:legacy]) {
        if ([file isEqualToString:@"version.txt"]) {
            foundVersionTxt = YES;
        } else {
            return NO;
        }
    }
    if (foundVersionTxt) {
        NSError *error = nil;
        [fileManager removeItemAtPath:[legacy stringByAppendingPathComponent:@"version.txt"] error:&error];
        if (error) {
            return NO;
        }
    }

    NSError *error = nil;
    [fileManager removeItemAtPath:legacy error:&error];
    return error == nil;
}

+ (void)migrateOpenAIKeyIfNeeded {
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kPreferenceKeyOpenAIAPIKey];
    if (!key) {
        return;
    }
    NSString *trimmedKey = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedKey length] == 0) {
        return;
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"Move OpenAI API key into the keychain? It is currently stored in User Defaults, which is not as secure."
                               actions:@[ @"OK", @"Erase from Settings" ]
                             accessory:nil
                            identifier:@"NoSyncMoveOpenAIAPIKeyIntoKeychain"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Move Key" 
                                window:nil];
    if (selection == kiTermWarningSelection0) {
        [self addOpenAIKeyToKeychain:key];
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPreferenceKeyOpenAIAPIKey];
}

+ (void)addOpenAIKeyToKeychain:(NSString *)key {
    [AITermControllerObjC setApiKey:key];
}

+ (void)migrateApplicationSupportDirectoryIfNeeded {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *modern = [fileManager applicationSupportDirectory];
    NSString *legacy = [fileManager legacyApplicationSupportDirectory];

    if ([fileManager itemIsSymlink:legacy]) {
        // Looks migrated, or crazy and impossible to reason about.
        return;
    }

    if ([self removeLegacyAppSupportFolderIfPossible]) {
        return;
    }

    if ([fileManager itemIsDirectory:modern] && [fileManager itemIsDirectory:legacy]) {
        // This is the normal code path for migrating users.
        const BOOL legacyEmpty = [fileManager directoryEmpty:legacy];

        if (legacyEmpty) {
            [fileManager removeItemAtPath:legacy error:nil];
            [fileManager createSymbolicLinkAtPath:legacy withDestinationPath:modern error:nil];
            return;
        }

        const BOOL modernEmpty = [fileManager directoryEmpty:modern];
        if (modernEmpty) {
            [fileManager removeItemAtPath:modern error:nil];
            [fileManager moveItemAtPath:legacy toPath:modern error:nil];
            [fileManager createSymbolicLinkAtPath:legacy withDestinationPath:modern error:nil];
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Manual Update Needed";
        alert.informativeText = @"iTerm2's Application Support directory has changed.\n\n"
        @"Previously, both these directories were supported:\n~/Library/Application Support/iTerm\n~/Library/Application Support/iTerm2.\n\n"
            @"Now, only the iTerm2 version is supported. But you have files in both so please move everything from iTerm to iTerm2.";

        NSMutableArray<NSString *> *files = [NSMutableArray array];
        int over = 0;
        for (NSString *file in [fileManager enumeratorAtPath:legacy]) {
            if (files.count > 5) {
                over++;
            } else {
                [files addObject:file];
            }
        }
        [files sortUsingSelector:@selector(compare:)];
        NSString *message;
        if (over == 0) {
            message = [files componentsJoinedByString:@"\n"];
        } else {
            message = [NSString stringWithFormat:@"%@\n…and %@ more", [files componentsJoinedByString:@"\n"], @(over)];
        }

        iTermDisclosableView *accessory = [[iTermDisclosableView alloc] initWithFrame:NSZeroRect
                                                                               prompt:@"Directory Listing"
                                                                              message:message];
        iTermAccessoryViewUnfucker *unfucker = [[iTermAccessoryViewUnfucker alloc] initWithView:accessory];
        accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
        accessory.textView.selectable = YES;
        accessory.requestLayout = ^{
            [unfucker layout];
            [alert layout];
            [alert layout];
        };
        [unfucker layout];
        alert.accessoryView = unfucker;

        [alert addButtonWithTitle:@"Open in Finder"];
        [alert addButtonWithTitle:@"I Fixed It"];
        [alert addButtonWithTitle:@"Not Now"];
        switch ([alert runModal]) {
            case NSAlertFirstButtonReturn:
                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:legacy],
                                                                              [NSURL fileURLWithPath:modern] ]];
                [self migrateApplicationSupportDirectoryIfNeeded];
                break;

            case NSAlertThirdButtonReturn:
                return;

            default:
                [self migrateApplicationSupportDirectoryIfNeeded];
                break;
        }
    }
}

+ (void)copyProfileToBookmark:(NSMutableDictionary *)dict
{
    NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"MigrationMap"
                                                                           ofType:@"plist"];
    NSDictionary* fileDict = [NSDictionary dictionaryWithContentsOfFile: plistFile];
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    NSDictionary* keybindingProfiles = [prefs objectForKey: @"KeyBindings"];
    NSDictionary* displayProfiles =  [prefs objectForKey: @"Displays"];
    NSDictionary* terminalProfiles = [prefs objectForKey: @"Terminals"];
    NSArray* xforms = [fileDict objectForKey:@"Migration Map"];
    for (int i = 0; i < [xforms count]; ++i) {
        NSDictionary* xform = [xforms objectAtIndex:i];
        NSString* destination = [xform objectForKey:@"Destination"];
        if ([dict objectForKey:destination]) {
            continue;
        }
        NSString* prefix = [xform objectForKey:@"Prefix"];
        NSString* suffix = [xform objectForKey:@"Suffix"];
        id defaultValue = [xform objectForKey:@"Default"];

        NSDictionary* parent = nil;
        if ([prefix isEqualToString:@"Terminal"]) {
            parent = [terminalProfiles objectForKey:[dict objectForKey:KEY_TERMINAL_PROFILE]];
        } else if ([prefix isEqualToString:@"Displays"]) {
            parent = [displayProfiles objectForKey:[dict objectForKey:KEY_DISPLAY_PROFILE]];
        } else if ([prefix isEqualToString:@"KeyBindings"]) {
            parent = [keybindingProfiles objectForKey:[dict objectForKey:KEY_KEYBOARD_PROFILE]];
        } else {
            ITAssertWithMessage(0, @"Bad prefix");
        }
        id value = nil;
        if (parent) {
            value = [parent objectForKey:suffix];
        }
        if (!value) {
            value = defaultValue;
        }
        [dict setObject:value forKey:destination];
    }
}

+ (void)recursiveMigrateBookmarks:(NSDictionary*)node path:(NSArray*)path {
    NSDictionary* data = [node objectForKey:@"Data"];

    if ([data objectForKey:KEY_COMMAND_LINE]) {
        // Not just a folder if it has a command.
        NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:data];
        [self copyProfileToBookmark:temp];
        [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        [temp setObject:path forKey:KEY_TAGS];
        [temp setObject:kProfilePreferenceCommandTypeCustomValue forKey:KEY_CUSTOM_COMMAND];
        NSString* dir = [data objectForKey:KEY_WORKING_DIRECTORY];
        if (dir && [dir length] > 0) {
            [temp setObject:kProfilePreferenceInitialDirectoryCustomValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        } else if (dir && [dir length] == 0) {
            [temp setObject:kProfilePreferenceInitialDirectoryRecycleValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        } else {
            [temp setObject:kProfilePreferenceInitialDirectoryHomeValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        }
        [[ProfileModel sharedInstance] addBookmark:temp];
    }

    NSArray* entries = [node objectForKey:@"Entries"];
    for (int i = 0; i < [entries count]; ++i) {
        NSMutableArray* childPath = [NSMutableArray arrayWithArray:path];
        NSDictionary* dataDict = [node objectForKey:@"Data"];
        if (dataDict) {
            NSString* name = [dataDict objectForKey:@"Name"];
            if (name) {
                [childPath addObject:name];
            }
        }
        [self recursiveMigrateBookmarks:[entries objectAtIndex:i] path:childPath];
    }
}

static NSString *const iTermMigrationHelperRemoveDeprecatedKeyMappingsUserDefaultKey = @"NoSyncRemoveDeprecatedKeyMappings";

+ (iTermMigrationHelperShouldRemoveDeprecatedKeyMappings)shouldRemoveDeprecatedKeyMappings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSNumber *n = [NSNumber castFrom:[ud objectForKey:iTermMigrationHelperRemoveDeprecatedKeyMappingsUserDefaultKey]];
    if (!n) {
        // User hasn't been prompted.
        return iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsDefault;
    }
    return (iTermMigrationHelperShouldRemoveDeprecatedKeyMappings)n.unsignedIntegerValue;
}

+ (void)setShouldRemoveDeprecatedKeyMappings:(iTermMigrationHelperShouldRemoveDeprecatedKeyMappings)value {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@(value)
           forKey:iTermMigrationHelperRemoveDeprecatedKeyMappingsUserDefaultKey];
}

+ (void)askToRemoveDeprecatedKeyMappingsIfNeeded NS_AVAILABLE_MAC(15) {
    switch ([self shouldRemoveDeprecatedKeyMappings]) {
        case iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNoneFound:
            // Didn't find any last time. To avoid slowing launch, assume it hasn't changed.
            return;
        case iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNo:
            // User declined previously.
            return;
        case iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsYes:
            // Already removed them. To avoid slowing launch, assume they are still gone.
            return;
        case iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsDefault:
            // First launch since this user defaultw as added.
            if (![self anyProfileOrArrangementHasDeprecatedKeyMappings]) {
                [self setShouldRemoveDeprecatedKeyMappings:iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNoneFound];
                return;
            }
            // Go on to prompt the user.
            break;

    }

    if ([self askToRemoveDeprecatedKeyMappings:nil]) {
        [self removeDeprecatedKeyMappingsTestOnly:NO];
    }
}

+ (BOOL)askToRemoveDeprecatedKeyMappings:(NSString *)specialReason NS_AVAILABLE_MAC(15) {
    NSString *message = specialReason ?: @"Some profiles have unnecessary key mappings which may interfere with window tiling shortcuts added in macOS Sequoia. These were in the default profile for many years but are no longer needed. Remove the key mappings? It shouldn’t break anything, and it won’t modify the on-disk copy of the dynamic profile.";


    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK", @"Learn More", @"Cancel" ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Remove Deprecated Key Mappings?"
                                window:nil];
    switch (selection) {
        case kiTermWarningSelection0:  // ok
            [self setShouldRemoveDeprecatedKeyMappings:iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsYes];
            return YES;
            break;
        case kiTermWarningSelection1:  // lean more
            [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://gitlab.com/gnachman/iterm2/-/wikis/Deprecated-Key-Mappings"]];
            return [self askToRemoveDeprecatedKeyMappings:specialReason];
            break;
        default:  // cancel
            [self setShouldRemoveDeprecatedKeyMappings:iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNo];
            return NO;
            break;
    }
}

// Returns true if any change would be made.
+ (BOOL)anyProfileOrArrangementHasDeprecatedKeyMappings {
    return [self removeDeprecatedKeyMappingsTestOnly:YES];
}

// Returns true if any change was/would be made.
+ (BOOL)removeDeprecatedKeyMappingsTestOnly:(BOOL)testOnly {
    const BOOL global = [self removeDeprecatedKeyMappingsInModel:[ProfileModel sharedInstance]
                                                        testOnly:testOnly];
    const BOOL divorced = [self removeDeprecatedKeyMappingsInModel:[ProfileModel sessionsInstance]
                                                          testOnly:testOnly];
    const BOOL arrangement = [self removeDeprecatedKeyMappingsFromArrangementsTestOnly:testOnly];
    return global || divorced || arrangement;
}

+ (BOOL)removeDeprecatedKeyMappingsFromArrangementsTestOnly:(BOOL)testOnly {
    __block BOOL changed = NO;
    for (NSString *name in [WindowArrangements allNames]) {
        NSArray *windowArrangements = [WindowArrangements arrangementWithName:name];
        NSArray *modifiedArrangements = [windowArrangements mapWithBlock:^id _Nullable(NSDictionary *arrangement) {
            return [PseudoTerminal repairedArrangement:arrangement profileMutator:^NSDictionary *(NSDictionary *profile) {
                NSDictionary *keyMappings = profile[KEY_KEYBOARD_MAP];
                if (!keyMappings) {
                    return profile;
                }
                NSDictionary *dict = [self keyMappingsByRemovingDeprecatedKeyMappingsFrom:keyMappings];
                if (dict) {
                    changed = YES;
                }
                NSMutableDictionary *fixed = [profile mutableCopy];
                fixed[KEY_KEYBOARD_MAP] = dict;
                return fixed;
            }];
        }];
        if (!testOnly) {
            [WindowArrangements setArrangement:modifiedArrangements withName:name];
        }
    }
    return changed;
}

+ (BOOL)removeDeprecatedKeyMappingsInModel:(ProfileModel *)model
                                  testOnly:(BOOL)testOnly {
    NSArray<Profile *> *profiles = [[model bookmarks] copy];
    __block BOOL changed = NO;
    [profiles enumerateObjectsUsingBlock:^(NSDictionary *profile, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([self removeDeprecatedKeyMappingsInProfile:profile model:model testOnly:testOnly]) {
            changed = YES;
        }
    }];
    return changed;
}

// Returns nil if nothing was changed.
+ (NSDictionary *)keyMappingsByRemovingDeprecatedKeyMappingsFrom:(NSDictionary *)input {
    if (!input) {
        return nil;
    }
    NSString *path = [[NSBundle bundleForClass:[self class]]
                      pathForResource:@"DeprecatedProfileKeyMappings"
                      ofType:@"plist"];
    NSDictionary *deprecations = [NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableDictionary *mappings = nil;

    for (NSString *key in deprecations) {
        id deprecatedValue = deprecations[key];
        id actualValue = input[key];
        if ([deprecatedValue isEqual:actualValue]) {
            if (!mappings) {
                mappings = [input mutableCopy];
            }
            [mappings removeObjectForKey:key];
        }
    }
    return mappings;
}

+ (BOOL)removeDeprecatedKeyMappingsInProfile:(Profile *)profile
                                       model:(ProfileModel *)model
                                    testOnly:(BOOL)testOnly {
    NSDictionary *mappings = [self keyMappingsByRemovingDeprecatedKeyMappingsFrom:profile[KEY_KEYBOARD_MAP]];
    if (mappings && !testOnly) {
        [iTermProfilePreferences setObject:mappings
                                    forKey:KEY_KEYBOARD_MAP
                                 inProfile:profile
                                     model:model];
    }
    return mappings != nil;
}

@end

