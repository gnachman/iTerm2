//
//  ProfilesAdvancedPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesAdvancedPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"
#import "SmartSelectionController.h"
#import "TriggerController.h"
#import "TrouterPrefsController.h"

@interface ProfilesAdvancedPreferencesViewController () <
    TriggerDelegate, SmartSelectionDelegate, TrouterPrefsControllerDelegate>

@end
@implementation ProfilesAdvancedPreferencesViewController {
    IBOutlet TriggerController *_triggerWindowController;
    IBOutlet SmartSelectionController *_smartSelectionWindowController;
    IBOutlet TrouterPrefsController *_trouterPrefController;
}

- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict {
    [super copyOwnedValuesToDict:dict];

    NSArray *keys = @[ KEY_TRIGGERS,
                       KEY_SMART_SELECTION_RULES,
                       KEY_TROUTER ];
    for (NSString *key in keys) {
        NSArray *value = (NSArray *)[self objectForKey:key];
        if (value) {
            dict[key] = value;
        } else {
            [dict removeObjectForKey:key];
        }
    }
}

- (void)reloadProfile {
    [super reloadProfile];
    NSString *selectedGuid = [self.delegate profilePreferencesCurrentProfile][KEY_GUID];
    _triggerWindowController.guid = selectedGuid;
    _smartSelectionWindowController.guid = selectedGuid;
    _trouterPrefController.guid = selectedGuid;
}

#pragma mark - Triggers

- (IBAction)editTriggers:(id)sender {
    [NSApp beginSheet:[_triggerWindowController window]
       modalForWindow:[self.view window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeTriggersSheet:(id)sender {
    [NSApp endSheet:[_triggerWindowController window]];
}

#pragma mark - TriggerDelegate

- (void)triggerChanged:(TriggerController *)triggerController {
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

#pragma mark - SmartSelectionDelegate

- (void)smartSelectionChanged:(SmartSelectionController *)controller {
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

#pragma mark - Modal sheets

- (void)advancedTabCloseSheet:(NSWindow *)sheet
                   returnCode:(int)returnCode
                  contextInfo:(void *)contextInfo {
    [sheet close];
}

#pragma mark - Smart selection

- (IBAction)editSmartSelection:(id)sender {
    [_smartSelectionWindowController window];
    [_smartSelectionWindowController windowWillOpen];
    [NSApp beginSheet:[_smartSelectionWindowController window]
       modalForWindow:[self.view window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeSmartSelectionSheet:(id)sender {
    [NSApp endSheet:[_smartSelectionWindowController window]];
}

#pragma mark - Trouter

- (void)trouterPrefsControllerSettingChanged:(TrouterPrefsController *)controller {
    [self setObject:[controller prefs] forKey:KEY_TROUTER];
}

@end
