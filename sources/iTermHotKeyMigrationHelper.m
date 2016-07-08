//
//  iTermHotKeyMigrationHelper.m
//  iTerm2
//
//  Created by George Nachman on 6/24/16.
//
//

#import "iTermHotKeyMigrationHelper.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDynamicProfileManager.h"
#import "iTermPreferences.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"
#import "NSStringITerm.h"
#import "ProfileModel.h"

@implementation iTermHotKeyMigrationHelper

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)migrateSingleHotkeyToMulti {
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyMigratedFromSingleToMulti]) {
        DLog(@"Have already migrated hotkey prefs");
        return;
    }
    
    DLog(@"Migrating hotkey prefs…");
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled] &&
        [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow_Deprecated]) {
        DLog(@"Legacy preferences have a dedicated window");
        
        NSString *guid = [iTermPreferences stringForKey:kPreferenceKeyHotkeyProfileGuid_Deprecated];
        // There is something to migrate
        Profile *profile = guid ? [[ProfileModel sharedInstance] bookmarkWithGuid:guid] : nil;
        if (profile) {
            DLog(@"Found the hotkey profile");
            if ([profile profileIsDynamic]) {
                [self migrateDynamicProfileHotKeySettings:profile];
            } else {
                DLog(@"Simple case");
                [[ProfileModel sharedInstance] setObjectsFromDictionary:[self hotkeyDictionary] inProfile:profile];
                [[ProfileModel sharedInstance] flush];
            }
            if ([self warnAboutChildrenOfHotkeyProfileIfNeeded:profile]) {
                DLog(@"Reloading dynamic profiles");
                // We changed the parent of a profile so reload them and the children will pick up
                // the (terrible) behavior we warned you about.
                [[iTermDynamicProfileManager sharedInstance] reloadDynamicProfiles];
            }
        }
        
        // Erase the legacy prefs so the keystroke doesn't show up as the global app toggle.
        [iTermPreferences setBool:NO forKey:kPreferenceKeyHotkeyEnabled];
        [iTermPreferences setInt:0 forKey:kPreferenceKeyHotKeyCode];
        [iTermPreferences setInt:0 forKey:kPreferenceKeyHotkeyCharacter];
    }

    _didMigration = YES;
    [iTermPreferences setBool:YES forKey:kPreferenceKeyHotkeyMigratedFromSingleToMulti];
}

- (BOOL)warnAboutChildrenOfHotkeyProfileIfNeeded:(Profile *)profile {
    NSString *name = profile[KEY_NAME];
    NSMutableArray *childrensNames = [NSMutableArray array];
    for (Profile *possibleChild in [[ProfileModel sharedInstance] bookmarks]) {
        if ([possibleChild[KEY_DYNAMIC_PROFILE_PARENT_NAME] isEqualToString:name]) {
            NSString *name = possibleChild[KEY_NAME];
            if (name) {
                name = [NSString stringWithFormat:@"“%@”", name];
            } else {
                name = @"Unnamed Profile";
            }
            [childrensNames addObject:name];
        }
    }
    if (childrensNames.count) {
        DLog(@"Warning about children of hotkey profile");
        NSString *concatenatedNames = [childrensNames componentsJoinedWithOxfordComma];
        NSString *title = [NSString stringWithFormat:@"You have dynamic profiles whose “Dynamic Profile Parent Name” is set to your hotkey window's profile, “%@.” Because multiple hotkey windows are now supported, the hotkey will now toggle a separate window for each of these profiles. Please update your dynamic profiles appropriately. The affected profiles are:\n%@",
                           profile[KEY_NAME], concatenatedNames];
        [iTermWarning showWarningWithTitle:title
                                   actions:@[ @"OK" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent];
    }
    return childrensNames.count > 0;
}

- (void)migrateDynamicProfileHotKeySettings:(Profile *)profile {
    DLog(@"Have a dynamic profile to migrate");
    NSString *title = [NSString stringWithFormat:@"Your hotkey window‘s profile is a dynamic profile named “%@.” It needs to be updated for this version of iTerm2 because hotkey settings are now stored in the profile.", profile[KEY_NAME]];
    
    NSArray *actions;
    NSData *replacementFile = [self modifiedDynamicProfileFileWithNewHotKeySettingsFromProfile:profile];
    
    iTermWarningSelection update = kItermWarningSelectionError;
    iTermWarningSelection show = kItermWarningSelectionError;
    iTermWarningSelection remove = kItermWarningSelectionError;
    
    if (replacementFile) {
        update = kiTermWarningSelection0;
        show = kiTermWarningSelection1;
        remove = kiTermWarningSelection2;
        actions = @[ @"Update File", @"Show Me What to Add", @"Remove Hotkey" ];
    } else {
        show = kiTermWarningSelection0;
        remove = kiTermWarningSelection1;
        actions = @[ @"Show Me What to Add", @"Remove Hotkey" ];
    }
    
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:title
                                                                 actions:actions
                                                               accessory:nil
                                                              identifier:nil
                                                             silenceable:kiTermWarningTypePersistent
                                                                 heading:@"Problem Updating Hotkey Window"];
    if (selection == update) {
        NSString *filename = profile[KEY_DYNAMIC_PROFILE_FILENAME];
        [replacementFile writeToFile:filename atomically:NO];
    } else if (selection == show) {
        [self showNeededChangesForHotKeyMigrationOfDynamicProfile:profile];
    }
    // There's nothing to do for the "remove" case. Setting the Migrated flag will silently
    // ignore the existing hotkey settings forever.
}

- (NSString *)jsonEntriesInDictionary:(NSDictionary *)dictionary {
    NSMutableArray *linesArray = [NSMutableArray array];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSString *encodedKey = [key stringByEscapingForJSON];
        NSString *encodedValue = nil;
        if ([obj isKindOfClass:[NSString class]]) {
            encodedValue = [obj stringByEscapingForJSON];
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            encodedValue = [obj stringValue];
        }
        [linesArray addObject:[NSString stringWithFormat:@"%@: %@", encodedKey, encodedValue]];
    }];
    return [linesArray componentsJoinedByString:@",\n"];
}

// Note: this isn't totally general. It only supports string, real, and integer values. No containers, etc.
- (NSString *)xmlEntriesInDictionary:(NSDictionary *)dictionary {
    NSMutableArray *linesArray = [NSMutableArray array];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSString *encodedKey = [key stringByEscapingForXML];
        NSString *encodedValue = nil;
        NSString *type = @"";
        if ([obj isKindOfClass:[NSString class]]) {
            type = @"string";
            encodedValue = [obj stringByEscapingForXML];
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            switch (CFNumberGetType((CFNumberRef)obj)) {
                case kCFNumberFloatType:
                case kCFNumberFloat32Type:
                case kCFNumberCGFloatType:
                case kCFNumberDoubleType:
                case kCFNumberFloat64Type:
                    type = @"real";
                    break;
                    
                default:
                    type = @"integer";
                    break;
            }
            encodedValue = [obj stringValue];
        }
        assert(encodedValue);
        [linesArray addObject:[NSString stringWithFormat:@"<key>%@</key><%@>%@</%@>", encodedKey, type, encodedValue, type]];
    }];
    return [linesArray componentsJoinedByString:@"\n"];
}

- (void)showNeededChangesForHotKeyMigrationOfDynamicProfile:(Profile *)profile {
    NSString *filename = profile[KEY_DYNAMIC_PROFILE_FILENAME];
    iTermDynamicProfileFileType fileType = kDynamicProfileFileTypeJSON;
    [[iTermDynamicProfileManager sharedInstance] profilesInFile:filename fileType:&fileType];
    NSString *lines = nil;
    switch (fileType) {
        case kDynamicProfileFileTypeJSON: {
            lines = [self jsonEntriesInDictionary:[self hotkeyDictionary]];
            break;
        }
        case kDynamicProfileFileTypePropertyList: {
            lines = [self xmlEntriesInDictionary:[self hotkeyDictionary]];
            break;
        }

    }
    NSAlert *alert = [NSAlert alertWithMessageText:@"Changes to Make"
                                     defaultButton:@"OK"
                                   alternateButton:@"Copy to Pasteboad"
                                       otherButton:nil
                         informativeTextWithFormat:@"Add these settings to the profile named “%@” in “%@”:\n%@",
                      profile[KEY_NAME],
                      filename,
                      lines];
    switch ([alert runModal]) {
        case NSAlertDefaultReturn:
            break;
            
        case NSAlertAlternateReturn: {
            NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
            [pasteBoard declareTypes:@[ NSStringPboardType ] owner:self];
            [pasteBoard setString:lines forType:NSStringPboardType];
            break;
        }
    }
}

- (NSData *)modifiedDynamicProfileFileWithNewHotKeySettingsFromProfile:(Profile *)profile {
    NSString *filename = profile[KEY_DYNAMIC_PROFILE_FILENAME];
    iTermDynamicProfileFileType fileType;
    NSArray<Profile *> *profiles = [[iTermDynamicProfileManager sharedInstance] profilesInFile:filename
                                                                                      fileType:&fileType];
    NSUInteger index = [profiles indexOfObjectPassingTest:^BOOL(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj[KEY_GUID] isEqualToString:profile[KEY_GUID]];
    }];
    if (index != NSNotFound) {
        Profile *modifiedProfile = [[profiles[index] mutableCopy] autorelease];
        [modifiedProfile setValuesForKeysWithDictionary:[self hotkeyDictionary]];
        NSMutableArray<Profile *> *modifiedProfilesArray = [[profiles mutableCopy] autorelease];
        modifiedProfilesArray[index] = modifiedProfile;
        
        NSDictionary *dict = [[iTermDynamicProfileManager sharedInstance] dictionaryForProfiles:modifiedProfilesArray];
        switch (fileType) {
            case kDynamicProfileFileTypeJSON: {
                NSError *error = nil;
                NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
                if (error) {
                    ELog(@"Failed to create JSON data from dictionary %@ with error %@", dict, error);
                }
                return data;
            }
                
            case kDynamicProfileFileTypePropertyList:
                return [dict propertyListData];
        }
    }
    return nil;
}

- (NSDictionary *)hotkeyDictionary {
    NSUInteger keyCode = [iTermPreferences unsignedIntegerForKey:kPreferenceKeyHotKeyCode];
    unichar character = [iTermPreferences unsignedIntegerForKey:kPreferenceKeyHotkeyCharacter];
    NSString *characters = character ? [NSString stringWithFormat:@"%C", character] : @"";
    NSEventModifierFlags modifiers = [iTermPreferences unsignedIntegerForKey:kPreferenceKeyHotkeyModifiers];
    BOOL autohides = [iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides_Deprecated];
    
    // We use deprecated methods to do the migration.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL animate = [iTermAdvancedSettingsModel hotkeyTermAnimationDuration] > 0;
    BOOL dockIconTogglesWindow = [iTermAdvancedSettingsModel dockIconTogglesWindow];
#pragma clang diagnostic pop
    iTermHotKeyDockPreference dockAction = dockIconTogglesWindow ? iTermHotKeyDockPreferenceShowIfNoOtherWindowsOpen : iTermHotKeyDockPreferenceDoNotShow;
    
    NSDictionary *newSettings = @{ KEY_HAS_HOTKEY: @YES,
                                   KEY_HOTKEY_KEY_CODE: @(keyCode),
                                   KEY_HOTKEY_CHARACTERS: characters,
                                   KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS: characters,
                                   KEY_HOTKEY_MODIFIER_FLAGS: @(modifiers),
                                   KEY_HOTKEY_AUTOHIDE: @(autohides),
                                   KEY_HOTKEY_REOPEN_ON_ACTIVATION: @NO,
                                   KEY_HOTKEY_ANIMATE: @(animate),
                                   KEY_HOTKEY_FLOAT: @NO,
                                   KEY_HOTKEY_DOCK_CLICK_ACTION: @(dockAction) };
    return newSettings;
}

@end
