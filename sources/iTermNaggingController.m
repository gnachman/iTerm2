//
//  iTermNaggingController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import "iTermNaggingController.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "ProfileModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "iTermUserDefaults.h"

static NSString *const iTermNaggingControllerOrphanIdentifier = @"DidRestoreOrphan";
static NSString *const iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier = @"ReopenSessionAfterBrokenPipe";
static NSString *const iTermNaggingControllerAbortDownloadIdentifier = @"AbortDownloadOnKeyPressAnnouncement";
static NSString *const iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier = @"AbortUploadOnKeyPressAnnouncement";
static NSString *const iTermNaggingControllerArrangementProfileMissingIdentifier = @"ThisProfileNoLongerExists";
static NSString *const iTermNaggingControllerTmuxSupplementaryPlaneErrorIdentifier = @"Tmux2.2SupplementaryPlaneAnnouncement";
static NSString *const iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier = @"AskAboutAlternateMouseScroll";
static NSString *const iTermNaggingControllerAskAboutMouseReportingFrustrationIdentifier = @"AskAboutMouseReportingFrustration";
NSString *const kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier = @"TurnOffBracketedPasteOnHostChange";
NSString *const kRestoreIconAndWindowNameOnHostChangeAnnouncementIdentifier = @"RestoreIconAndWindowName";
static NSString *const iTermNaggingControllerAskAboutClearingScrollbackHistoryIdentifier = @"ClearScrollbackHistory";
static NSString *const iTermNaggingControllerWarnAboutSecureKeyboardInputWithOpenCommand = @"WarnAboutSecureKeyboardInputWithOpenCommand";
NSString *const kTurnOffBracketedPasteOnHostChangeUserDefaultsKey = @"NoSyncTurnOffBracketedPasteOnHostChange";
NSString *const kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey = @"NoSyncRestoreIconAndWindowNameOnHostChange";
static NSString *const iTermNaggingControllerAskAboutChangingProfileIdentifier = @"AskAboutChangingProfile";
static NSString *const iTermNaggingControllerTmuxWindowsShouldCloseAfterDetach = @"TmuxWindowsShouldCloseAfterDetach";
static NSString *const kTurnOffSlowTriggersOfferUserDefaultsKey = @"kTurnOffSlowTriggersOfferUserDefaultsKey";
static NSString *const iTermNaggingControllerOfferToSyncTmuxClipboard = @"NoSyncOfferToSyncTmuxClipboard";

static NSString *const iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll = @"NoSyncNeverAskAboutSettingAlternateMouseScroll";

static NSString *iTermNaggingControllerSetBackgroundImageFileIdentifier = @"SetBackgroundImageFile";
static NSString *iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage = @"AlwaysAllowBackgroundImage";
static NSString *iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage = @"AlwaysDenyBackgroundImage";
static NSString *const iTermNaggingControllerDidChangeTmuxWindowsShouldCloseAfterDetach = @"iTermNaggingControllerDidChangeTmuxWindowsShouldCloseAfterDetach";
static NSString *const iTermNaggingControllerArrangementTextReplacements = @"TextReplacements";
static NSString *const iTermNaggingControllerArrangementSetProfileProperty = @"SetProfileProperty";

@implementation iTermNaggingController {
    BOOL _haveOutstandingTextReplacementOffer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didChangeTmuxWindowsShouldCloseAfterDetach:)
                                                     name:iTermNaggingControllerDidChangeTmuxWindowsShouldCloseAfterDetach
                                                   object:nil];
    }
    return self;
}

- (BOOL)permissionToReportVariableNamed:(NSString *)name {
    static NSString *const allow = @"allow:";
    static NSString *const deny = @"deny:";

    NSNumber *originalValue = nil;
    {
        NSArray<NSString *> *parts = [self variablesToReportEntries];
        if ([parts containsObject:[allow stringByAppendingString:name]]) {
            originalValue = @YES;
        }
        if ([parts containsObject:[deny stringByAppendingString:name]]) {
            originalValue = @NO;
        }
    }

    return [self requestPermissionWithOriginalValue:originalValue
                                                key:[NSString stringWithFormat:@"ShouldReportVariable%@", name]
                                   prompt:[NSString stringWithFormat:@"A request to report variable “%@” was denied. Allow it in the future?", name]
                                   setter:^(BOOL shouldAllow) {
        NSArray<NSString *> *parts = [self variablesToReportEntries];
        NSString *prefix = shouldAllow ? allow : deny;
        NSString *newEntry = [prefix stringByAppendingString:name];
        parts = [parts arrayByAddingObject:newEntry];
        [iTermAdvancedSettingsModel setNoSyncVariablesToReport:[parts componentsJoinedByString:@","]];
    }];
}

- (void)offerToFixSessionWithBrokenArrangementProfileIn:(NSString *)arrangementName
                                                   guid:(NSString *)guid {
    NSString *notice = @"This arrangement’s profile is missing. This could be due to a bug in iTerm2 version 3.5.7, which caused profiles to be corrupted in saved arrangements.";
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:YES
                                     identifier:@"ArrangementMissingProfile"
                                        options:@[ @"Assign Profile" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAssignProfileToSession:arrangementName
                                                              guid:guid];
        }
    }];
}

- (NSString *)userDefaultsKeyForProfileProperty:(NSString *)key {
    return [@"NoSyncSetProfileProperty_" stringByAppendingString:key];
}

- (void)offerToSetProfileProperties:(NSDictionary<NSString *, id> *)dict {
    DLog(@"%@", dict);
    NSDictionary *permissions = [dict mapValuesWithBlock:^id(NSString *key, id object) {
        return [[iTermUserDefaults userDefaults] objectForKey:[self userDefaultsKeyForProfileProperty:key]];
    }];
    DLog(@"permissions: %@", permissions);
    // true = deny, false = always allow
    if ([permissions.allValues containsObject:@(iTermTriStateTrue)]) {
        DLog(@"Disallowed by setting");
        return;
    }
    if (permissions.count == dict.count && [permissions.allValues allWithBlock:^BOOL(id anObject) {
        return [anObject isEqual:@(iTermTriStateFalse)];
    }]) {
        [self.delegate naggingControllerSetProfileProperties:dict];
        return;
    }
    NSString *notice;
    if (dict.count == 1) {
        NSString *key = dict.allKeys.firstObject;
        notice = [NSString stringWithFormat:@"An app tried to change the profile property **%@**", [iTermProfilePreferences descriptionForKey:key]];
    } else {
        NSMutableArray<NSString *> *descriptions = [NSMutableArray array];
        for (NSString *key in dict.allKeys) {
            NSString *desc = [iTermProfilePreferences descriptionForKey:key] ?: key;
            [descriptions addObject:[NSString stringWithFormat:@"* %@", desc]];
        }
        NSString *bulletList = [descriptions componentsJoinedByString:@"\n"];
        NSString *popoverMessage = [NSString stringWithFormat:@"**Properties to be changed:**\n\n%@", bulletList];
        NSString *encodedMessage = [popoverMessage stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *popoverURL = [NSString stringWithFormat:@"x-iterm2-popover:?message=%@", encodedMessage];
        notice = [NSString stringWithFormat:@"An app tried to change [multiple profile properties](%@).", popoverURL];
    }
    __weak __typeof(self) weakSelf = self;
    [self.delegate naggingControllerShowMarkdownMessage:notice
                                             isQuestion:YES
                                              important:NO
                                             identifier:iTermNaggingControllerArrangementSetProfileProperty
                                                options:@[ @"_Allow Once", @"Allow Always", @"Deny Always" ]
                                             completion:^(int selection) {
        if (selection == 0 || selection == 1) {
            [weakSelf.delegate naggingControllerSetProfileProperties:dict];
        }
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (selection == 1) {
            for (NSString *key in dict) {
                [[iTermUserDefaults userDefaults] setObject:@(iTermTriStateFalse)
                                                          forKey:[strongSelf userDefaultsKeyForProfileProperty:key]];
            }
        } else if (selection == 2) {
            for (NSString *key in dict) {
                [[iTermUserDefaults userDefaults] setObject:@(iTermTriStateTrue)
                                                          forKey:[strongSelf userDefaultsKeyForProfileProperty:key]];
            }
        }
    }];
}

- (void)offerTextReplacement:(void (^NS_NOESCAPE)(void))perform {
    NSString *userDefaultsKey = @"NoSyncTextReplacements";
    NSNumber *n = [NSNumber castFrom:[[iTermUserDefaults userDefaults] objectForKey:userDefaultsKey]];
    if (n) {
        if (n.boolValue) {
            perform();
        }
        return;
    }
    if (_haveOutstandingTextReplacementOffer) {
        return;
    }
    NSString *notice = @"Would you like macOS Text Replacements to be applied automatically?";
    _haveOutstandingTextReplacementOffer = YES;
    __weak __typeof(self) weakSelf = self;
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementTextReplacements
                                        options:@[ @"_Yes", @"_No" ]
                                     completion:^(int selection) {
        if (selection == 0 || selection == 1) {
            [[iTermUserDefaults userDefaults] setBool:selection == 0 forKey:userDefaultsKey];
        }
        [weakSelf resetHaveTextReplacementOffer];
    }];
}

- (void)cancelTextReplacementOffer {
    if (_haveOutstandingTextReplacementOffer) {
        [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerArrangementTextReplacements];
        _haveOutstandingTextReplacementOffer = NO;
    }
}

- (void)resetHaveTextReplacementOffer {
    _haveOutstandingTextReplacementOffer = NO;
}

- (void)arrangementWithName:(NSString *)savedArrangementName
        missingProfileNamed:(NSString *)missingProfileName
                       guid:(NSString *)guid {
    DLog(@"Can’t find profile %@ guid %@", missingProfileName, guid);
    if ([iTermAdvancedSettingsModel noSyncSuppressMissingProfileInArrangementWarning]) {
        return;
    }
    NSString *notice;
    NSArray<NSString *> *actions = @[ @"Don’t Warn Again" ];
    if ([[ProfileModel sharedInstance] bookmarkWithName:missingProfileName]) {
        notice = [NSString stringWithFormat:@"This session’s profile, “%@”, no longer exists. A profile with that name happens to exist.", missingProfileName];
        if (savedArrangementName) {
            actions = [actions arrayByAddingObject:@"Repair Saved Arrangement"];
        }
    } else {
        notice = [NSString stringWithFormat:@"This session’s profile, “%@”, no longer exists.", missingProfileName];
    }
    _missingSavedArrangementProfileGUID = [guid copy];
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementProfileMissingIdentifier
                                        options:actions
                                     completion:^(int selection) {
        [self handleCompletionForMissingProfileInArrangementWithName:savedArrangementName
                                                 missingProfileNamed:missingProfileName
                                                                guid:guid
                                                           selection:selection];
    }];
}

- (void)arrangementWithName:(NSString *)arrangementName
              hasInvalidPWD:(NSString *)badPWD
         forSessionWithGuid:(NSString *)sessionGUID {
    DLog(@"Arrangement %@ has bad pwd of %@ for session guid %@", arrangementName, badPWD, sessionGUID);
    if ([iTermAdvancedSettingsModel noSyncSuppressBadPWDInArrangementWarning]) {
        return;
    }
    NSString *notice = [NSString stringWithFormat:@"The saved arrangement “%@” has a bad initial directory of “%@” for this session.", arrangementName, badPWD];

    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementProfileMissingIdentifier
                                        options:@[ @"Don’t Warn Again", @"Repair" ]
                                     completion:^(int selection) {
        [self handleCompletionForInvalidPWDInArrangementWithName:arrangementName
                                                            guid:sessionGUID
                                                       selection:selection];
    }];
}

- (void)handleCompletionForInvalidPWDInArrangementWithName:(NSString *)arrangementName
                                                      guid:(NSString *)guid
                                                 selection:(int)selection {
    if (selection == 0) {
        [iTermAdvancedSettingsModel setNoSyncSuppressBadPWDInArrangementWarning:YES];
        return;
    }
    if (selection == 1) {
        [self.delegate naggingControllerRepairInitialWorkingDirectoryOfSessionWithGUID:guid
                                                                 inArrangementWithName:arrangementName];
    }
}

- (void)didRestoreOrphan {
    [self.delegate naggingControllerShowMessage:@"This already-running session was restored but its contents were not saved."
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerOrphanIdentifier
                                        options:@[ @"Why?" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            // Why?
            NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com/why_no_content.html"];
            [[NSWorkspace sharedWorkspace] it_openURL:whyUrl
                                               target:nil
                                                style:iTermOpenStyleTab
                                               window:self.delegate.naggingControllerWindow];
        }
    }];
}

- (void)sessionEndedWithExecFailure:(BOOL)execDidFail {
    [self.delegate naggingControllerShowMessage:execDidFail ? @"Session failed to start." : @"Session ended (command exited). Restart it?"
                                     isQuestion:!execDidFail
                                      important:YES
                                     identifier:iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier
                                        options:@[ @"_Restart", @"Don’t Ask Again" ]
                                     completion:^(int selection) {
        [self handleCompletionForBrokenPipe:selection];
    }];
}

- (void)askAboutAbortingDownload {
    [self.delegate naggingControllerShowMessage:@"A file is being downloaded. Abort the download?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortDownloadIdentifier
                                        options:@[ @"OK", @"Cancel" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAbortDownload];
        }
    }];
}

- (void)askAboutAbortingUpload {
    [self.delegate naggingControllerShowMessage:@"A file is being uploaded. Abort the upload?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier
                                        options:@[ @"OK", @"Cancel" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAbortUpload];
        }
    }];
}

- (void)didFinishDownload {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerAbortDownloadIdentifier];
}

- (void)didRepairSavedArrangement {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerArrangementProfileMissingIdentifier];
}

- (void)willRecycleSession {
    NSArray<NSString *> *identifiers = @[
        iTermNaggingControllerOrphanIdentifier,
        iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier,
        iTermNaggingControllerAbortDownloadIdentifier,
        iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier ];
    for (NSString *identifier in identifiers) {
        [self.delegate naggingControllerRemoveMessageWithIdentifier:identifier];
    }
}

- (void)tmuxSupplementaryPlaneErrorForCharacter:(NSString *)string {
    NSString *message = [NSString stringWithFormat:@"Because of a bug in tmux 2.2, the character “%@” cannot be sent.", string];
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerTmuxSupplementaryPlaneErrorIdentifier
                                        options:@[ @"Why?" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self showTmuxSupplementaryPlaneBugHelpPage];
        }
    }];
}

- (void)showTmuxSupplementaryPlaneBugHelpPage {
    NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com//tmux22bug.html"];
    [[NSWorkspace sharedWorkspace] it_openURL:whyUrl
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.delegate.naggingControllerWindow];
}

- (void)tryingToSendArrowKeysWithScrollWheel:(BOOL)isTrying {
    if (!isTrying) {
        [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier];
        return;
    }
    if ([[iTermUserDefaults userDefaults] boolForKey:iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll]) {
        return;
    }
    [self.delegate naggingControllerShowMessage:@"Do you want the scroll wheel to move the cursor in interactive programs like this?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier
                                        options:@[ @"Yes", @"Don‘t Ask Again" ]
                                     completion:^(int selection) {
        [self handleTryingToSendArrowKeysWithScrollWheel:selection];
    }];
}

- (void)handleTryingToSendArrowKeysWithScrollWheel:(int)selection {
    switch (selection) {
        case 0: // Yes
            [iTermAdvancedSettingsModel setAlternateMouseScroll:YES];
            break;

        case 1: { // Never
            [[iTermUserDefaults userDefaults] setBool:YES forKey:iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll];
            break;
        }
    }
}

- (void)setBackgroundImageToFileWithName:(NSString *)maybeFilename {
    NSString *filename = maybeFilename ?: @"";
    DLog(@"screenSetbackgroundImageFile:%@", filename);

    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    NSArray *allowedFiles = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
    NSArray *deniedFiles = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
    if ([deniedFiles containsObject:filename]) {
        return;
    }
    if ([allowedFiles containsObject:filename]) {
        [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
        return;
    }

    NSString *title;
    if (filename.length) {
        title = [NSString stringWithFormat:@"Set background image to “%@”?", filename];
    } else {
        title = @"Remove background image?";
    }
    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerSetBackgroundImageFileIdentifier
                                        options:@[ @"Yes", @"Always", @"Never" ]
                                     completion:^(int selection) {
        [self handleSetBackgroundImageToFileWithName:filename selection:selection];
    }];
}

- (void)handleSetBackgroundImageToFileWithName:(NSString *)filename selection:(int)selection {
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    switch (selection) {
        case 0: // Yes
            if (!filename.length) {
                DLog(@"Filename is empty. Reset the background image.");
                [self.delegate naggingControllerSetBackgroundImageToFileWithName:nil];
                return;
            }
            [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
            break;

        case 1: { // Always
            NSArray *allowed = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
            if (!allowed) {
                allowed = @[];
            }
            allowed = [allowed arrayByAddingObject:filename];
            [userDefaults setObject:allowed forKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
            if (!filename.length) {
                DLog(@"Filename is empty. Reset the background image.");
                [self.delegate naggingControllerSetBackgroundImageToFileWithName:nil];
                return;
            }
            [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
            break;
        }
        case 2: {  // Never
            NSArray *denied = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
            if (!denied) {
                denied = @[];
            }
            denied = [denied arrayByAddingObject:filename];
            [userDefaults setObject:denied forKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
            break;
        }
    }
}

- (void)didDetectMouseReportingFrustration {
    if ([iTermAdvancedSettingsModel noSyncNeverAskAboutMouseReportingFrustration]) {
        return;
    }
    [self.delegate naggingControllerShowMessage:@"Looks like you’re trying to copy to the pasteboard, but mouse reporting has prevented making a selection. Disable mouse reporting?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutMouseReportingFrustrationIdentifier
                                        options:@[ @"_Temporarily", @"Permanently", @"Stop Asking" ]
                                     completion:^(int selection) {
        [self handleMouseReportingFrustration:selection];
    }];
}

- (void)handleMouseReportingFrustration:(int)selection {
    switch (selection) {
        case 0: // Temporarily
            [self.delegate naggingControllerDisableMouseReportingPermanently:NO];
            break;

        case 1: { // Never
            [self.delegate naggingControllerDisableMouseReportingPermanently:YES];
            break;
        }

        case 2: { // Stop asking
            [iTermAdvancedSettingsModel setNoSyncNeverAskAboutMouseReportingFrustration:YES];
        }
    }
}

- (void)offerToTurnOffBracketedPasteOnHostChange {
    NSString *title;
    title = @"Looks like paste bracketing was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier
                                        options:@[ @"_Yes", @"Always", @"Never", @"Help" ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [self.delegate naggingControllerDisableBracketedPasteMode];
                break;

            case 1: // Always
                [[iTermUserDefaults userDefaults] setBool:YES
                                                        forKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
                [self.delegate naggingControllerDisableBracketedPasteMode];
                break;

            case 2: // Never
                [[iTermUserDefaults userDefaults] setBool:NO
                                                        forKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
                break;

            case 3: // Help
                [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/paste_bracketing"]
                                                   target:nil
                                                    style:iTermOpenStyleTab
                                                   window:self.delegate.naggingControllerWindow];
                break;
        }
    }];
}

- (void)offerToRestoreIconName:(NSString *)iconName windowName:(NSString *)windowName {
    NSString *title;
    title = @"Automatically restore the tab and window title when an ssh session ends?";

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kRestoreIconAndWindowNameOnHostChangeAnnouncementIdentifier
                                        options:@[ @"_Yes", @"Always", @"Never" ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [self.delegate naggingControllerRestoreIconNameTo:iconName windowName:windowName];
                break;

            case 1: // Always
                [[iTermUserDefaults userDefaults] setBool:YES
                                                        forKey:kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey];
                [self.delegate naggingControllerRestoreIconNameTo:iconName windowName:windowName];
                break;

            case 2: // Never
                [[iTermUserDefaults userDefaults] setBool:NO
                                                        forKey:kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey];
                break;
        }
    }];
}

- (void)offerToDisableTriggersInInteractiveAppsWithStats:(NSString *)stats {
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:kTurnOffSlowTriggersOfferUserDefaultsKey]) {
        DLog(@"Don't show warning");
        return;
    }
    if ([[[iTermUserDefaults userDefaults] objectForKey:kTurnOffSlowTriggersOfferUserDefaultsKey] isEqual:@NO]) {
        return;
    }
    NSString *title;
    title = @"This session’s triggers are pretty slow. Disable them in interactive apps?";

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kTurnOffSlowTriggersOfferUserDefaultsKey
                                        options:@[ @"_Yes", @"Stop Asking", @"View Stats", @"Help" ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [self.delegate naggingControllerDisableTriggersInInteractiveApps];
                break;

            case 1: // Stop Asking
                [[iTermUserDefaults userDefaults] setBool:NO
                                                        forKey:kTurnOffSlowTriggersOfferUserDefaultsKey];
                break;

            case 2:  { // View stats
                [self showStats:stats];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self offerToDisableTriggersInInteractiveAppsWithStats:stats];
                });
                break;
            }

            case 4: // Help
                [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/slow_triggers"]
                                                   target:nil
                                                    style:iTermOpenStyleTab
                                                   window:self.delegate.naggingControllerWindow];
                break;
        }
    }];
}

- (void)showStats:(NSString *)stats {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"trigger-stats-%@.txt", [NSUUID UUID].UUIDString]];

    NSError *error = nil;
    BOOL ok = [stats writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!ok) {
        DLog(@"Error writing file: %@", error);
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments = @[ @"-a", @"TextEdit", path ];
    [task launch];
}

- (void)tmuxDidUpdatePasteBuffer {
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:iTermNaggingControllerOfferToSyncTmuxClipboard]) {
        DLog(@"Don't show warning");
        return;
    }
    if ([[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyTmuxSyncClipboard]) {
        DLog(@"Nag disabled");
        return;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyTmuxSyncClipboard]) {
        return;
    }
    [self.delegate naggingControllerShowMessage:@"The tmux paste buffer was updated. Would you like to mirror it to the local clipboard from now on?"
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerOfferToSyncTmuxClipboard
                                        options:@[ @"_Always", @"_Never" ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programatically
                break;
            case -1: // No
                break;

            case 0: // Always
                [iTermPreferences setBool:YES forKey:kPreferenceKeyTmuxSyncClipboard];
                break;

            case 1:  // Never
                [iTermPreferences setBool:NO forKey:kPreferenceKeyTmuxSyncClipboard];
                break;
        }
    }];
}

- (BOOL)shouldAskAboutClearingScrollbackHistory {
    return iTermAdvancedSettingsModel.preventEscapeSequenceFromClearingHistory == nil;
}

- (void)askAboutClearingScrollbackHistory {
    NSString *message = @"A control sequence attempted to clear scrollback history. Allow this in the future?";
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerAskAboutClearingScrollbackHistoryIdentifier
                                        options:@[ @"Always _Allow", @"Always _Deny" ]
                                     completion:^(int selection) {
        switch (selection) {
            case 0: {
                const BOOL value = NO;
                iTermAdvancedSettingsModel.preventEscapeSequenceFromClearingHistory = &value;
                break;
            }
            case 1: {
                const BOOL value = YES;
                iTermAdvancedSettingsModel.preventEscapeSequenceFromClearingHistory = &value;
                break;
            }
        }
    }];
}

- (void)openCommandDidFailWithSecureInputEnabled {
    if (!iTermAdvancedSettingsModel.warnAboutSecureKeyboardInputWithOpenCommand) {
        return;
    }
    NSString *message = @"The open command doesn't activate other apps when Secure Keyboard Input is enabled.";
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerWarnAboutSecureKeyboardInputWithOpenCommand
                                        options:@[ @"Don’t Remind Me Again" ]
                                     completion:^(int selection) {
        switch (selection) {
            case 0: {
                iTermAdvancedSettingsModel.warnAboutSecureKeyboardInputWithOpenCommand = NO;
                break;
            }
        }
    }];
}

- (BOOL)terminalCanChangeProfile {
    const BOOL *boolPtr = iTermAdvancedSettingsModel.preventEscapeSequenceFromChangingProfile;
    if (boolPtr) {
        return !*boolPtr;
    }
    NSString *message = @"A control sequence attempted to change the current profile. Allow this in the future?";
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerAskAboutChangingProfileIdentifier
                                        options:@[ @"Always _Allow", @"Always _Deny" ]
                                     completion:^(int selection) {
        switch (selection) {
            case 0: {
                const BOOL value = NO;
                iTermAdvancedSettingsModel.preventEscapeSequenceFromChangingProfile = &value;
                break;
            }
            case 1: {
                const BOOL value = YES;
                iTermAdvancedSettingsModel.preventEscapeSequenceFromChangingProfile = &value;
                break;
            }
        }
    }];
    return NO;
}

- (BOOL)tmuxWindowsShouldCloseAfterDetach {
    const BOOL *boolPtr = iTermAdvancedSettingsModel.tmuxWindowsShouldCloseAfterDetach;
    if (boolPtr) {
        return *boolPtr;
    }
    NSString *message = @"Close tmux windows after detaching?";
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerTmuxWindowsShouldCloseAfterDetach
                                        options:@[ @"_Always", @"_Never" ]
                                     completion:^(int selection) {
        if (selection == 0 || selection == 1) {
            BOOL value = (selection == 0);
            iTermAdvancedSettingsModel.tmuxWindowsShouldCloseAfterDetach = &value;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermNaggingControllerDidChangeTmuxWindowsShouldCloseAfterDetach
                                                                object:@(value)];
        }
    }];
    return NO;
}

- (void)didChangeTmuxWindowsShouldCloseAfterDetach:(NSNotification *)notification {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerTmuxWindowsShouldCloseAfterDetach];
    if ([notification.object boolValue]) {
        [self.delegate naggingControllerCloseSession];
    }
}

- (void)showJSONPromotion {
    [_delegate naggingControllerShowMessage:@"That's a gnarly JSON blob you've got there! iTerm2 can replace this hard-to-read selection with a pretty-printed value."
                                 isQuestion:NO
                                  important:NO
                                 identifier:@"JSONPromotion"
                                    options:@[ @"Try it Now", @"Dismiss" ]
                                 completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // Closed
                break;

            case 0: // try
                [self.delegate naggingControllerPrettyPrintJSON];
                break;

            case 1:  // Dismiss
                // The caller is responsible for not showing the promotion more than once.
                break;
        }
    }];
}

- (void)openURL:(NSURL *)url {
    NSString *allowHostKey = [NSString stringWithFormat:@"NoSyncAllowOpenURL_host:%@", url.host];

    if ([iTermAdvancedSettingsModel noSyncDisableOpenURL]) {
        DLog(@"OpenUrl disabled");
        return;
    }
    if ([iTermSecureUserDefaults openURLWithHost:url.host]) {
        DLog(@"Always allow %@", url.host);
        [[NSWorkspace sharedWorkspace] it_openURL:url
                                           target:nil
                                            style:iTermOpenStyleTab
                                           window:self.delegate.naggingControllerWindow];
        return;
    }

    [_delegate naggingControllerShowMessage:[NSString stringWithFormat: @"Open this URL? %@", url.sanitizedForPrinting.absoluteString]
                                 isQuestion:YES
                                  important:YES
                                 identifier:allowHostKey
                                    options:@[ @"Allow", @"Always allow for this host", @"Never allow" ]
                                 completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // Closed
                break;

            case 0: // Allow
                [[NSWorkspace sharedWorkspace] it_openURL:url
                                                   target:nil
                                                    style:iTermOpenStyleTab
                                                   window:self.delegate.naggingControllerWindow];
                break;

            case 1:  // Allow for this host
                [iTermSecureUserDefaults setOpenURLWithHost:url.host allowed:YES];
                [[NSWorkspace sharedWorkspace] it_openURL:url
                                                   target:nil
                                                    style:iTermOpenStyleTab
                                                   window:self.delegate.naggingControllerWindow];
                break;

            case 2:  // Never allow
                [iTermAdvancedSettingsModel setNoSyncDisableOpenURL:YES];
                break;
        }
    }];
}

#pragma mark - Touch ID for Sudo

static NSString *const iTermNaggingControllerTouchIDForSudoIdentifier = @"TouchIDForSudo";
static NSString *const iTermNaggingControllerTouchIDForSudoUserDefaultsKey = @"NoSyncOfferTouchIDForSudo";

- (void)offerToEnableTouchIDForSudo {
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:iTermNaggingControllerTouchIDForSudoIdentifier]) {
        DLog(@"Can't show Touch ID for sudo offer");
        return;
    }
    NSNumber *setting = [[iTermUserDefaults userDefaults] objectForKey:iTermNaggingControllerTouchIDForSudoUserDefaultsKey];
    if (setting != nil) {
        DLog(@"Touch ID for sudo offer disabled by user default: %@", setting);
        return;
    }
    if ([iTermTouchIDHelper isTouchIDEnabledForSudo]) {
        DLog(@"Touch ID for sudo already enabled");
        return;
    }
    NSString *message = @"Would you like to enable Touch ID for sudo?";
    if ([self.delegate naggingControllerAnnouncementWouldObscureCursorForText:message]) {
        DLog(@"Announcement would obscure cursor");
        return;
    }
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerTouchIDForSudoIdentifier
                                        options:@[ @"_Enable", @"Don't Ask Again" ]
                                     completion:^(int selection) {
        switch (selection) {
            case 0:  // Enable
                (void)[iTermTouchIDHelper enableTouchIDForSudo];
                break;
            case 1:  // Don't ask again
                [[iTermUserDefaults userDefaults] setBool:NO
                                                   forKey:iTermNaggingControllerTouchIDForSudoUserDefaultsKey];
                break;
        }
    }];
}

- (void)removeTouchIDForSudoOffer {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerTouchIDForSudoIdentifier];
}

#pragma mark - Variable Reporting

- (NSArray<NSString *> *)variablesToReportEntries {
    return [[[iTermAdvancedSettingsModel noSyncVariablesToReport] componentsSeparatedByString:@","] filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return anObject.length > 0;
    }];
}

- (BOOL)requestPermissionWithOriginalValue:(NSNumber *)setting
                                       key:(NSString *)key
                                    prompt:(NSString *)prompt
                                    setter:(void (^)(BOOL))setter {
    if (setting) {
        return setting.boolValue;
    }
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:key]) {
        return NO;
    }
    [self.delegate naggingControllerShowMessage:prompt
                                     isQuestion:YES
                                      important:YES
                                     identifier:key
                                        options:@[ @"Always Allow", @"Always Deny" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            setter(YES);
        } else if (selection == 1) {
            setter(NO);
        }
    }];
    return NO;
}

#pragma mark - Arrangement with missing profile

- (void)handleCompletionForMissingProfileInArrangementWithName:(NSString *)savedArrangementName
                                           missingProfileNamed:(NSString *)missingProfileName
                                                          guid:(NSString *)guid
                                                     selection:(int)selection {
    if (selection == 0) {
        [iTermAdvancedSettingsModel setNoSyncSuppressMissingProfileInArrangementWarning:YES];
        return;
    }
    if (selection == 1) {
        [self.delegate naggingControllerRepairSavedArrangement:savedArrangementName
                                           missingProfileNamed:missingProfileName
                                                          guid:guid];
        return;
    }
}

- (void)handleCompletionForBrokenPipe:(int)selection {
    switch (selection) {
        case 0: // Yes
            [self.delegate naggingControllerRestart];
            break;

        case 1: // Don't ask again
            [iTermAdvancedSettingsModel setSuppressRestartAnnouncement:YES];
            break;
    }
}

@end
