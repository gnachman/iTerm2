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
static NSString *const kResetKeyReportingModeAnnouncementIdentifier = @"ResetKeyReportingMode";
NSString *const kRestoreIconAndWindowNameOnHostChangeAnnouncementIdentifier = @"RestoreIconAndWindowName";
static NSString *const iTermNaggingControllerAskAboutClearingScrollbackHistoryIdentifier = @"ClearScrollbackHistory";
static NSString *const iTermNaggingControllerWarnAboutSecureKeyboardInputWithOpenCommand = @"WarnAboutSecureKeyboardInputWithOpenCommand";
NSString *const kTurnOffBracketedPasteOnHostChangeUserDefaultsKey = @"NoSyncTurnOffBracketedPasteOnHostChange";
static NSString *const kResetKeyReportingModeUserDefaultsKey = @"NoSyncResetKeyReportingModeOnPrompt";
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
static NSString *const iTermNaggingControllerClaudeCodeStatusToolIdentifier = @"ClaudeCodeStatusTool";
static NSString *const iTermNaggingControllerClaudeCodeStatusToolDismissedNotification = @"iTermNaggingControllerClaudeCodeStatusToolDismissed";
static NSString *const iTermNaggingControllerRestoreIconAndWindowNameChoiceNotification = @"iTermNaggingControllerRestoreIconAndWindowNameChoice";
static NSString *const iTermNaggingControllerRestoreIconAndWindowNameChoiceAlwaysKey = @"always";

static NSString *NaggingYes(void) { return NSLocalizedStringWithDefaultValue(@"NaggingController.YesShortcut", nil, [NSBundle mainBundle], @"_Yes", @"Yes button label; underscore marks the keyboard shortcut key"); }
static NSString *NaggingAlways(void) { return NSLocalizedStringWithDefaultValue(@"NaggingController.Always", nil, [NSBundle mainBundle], @"Always", @"Always button label"); }
static NSString *NaggingNever(void) { return NSLocalizedStringWithDefaultValue(@"NaggingController.Never", nil, [NSBundle mainBundle], @"Never", @"Never button label"); }

@implementation iTermNaggingController {
    BOOL _haveOutstandingTextReplacementOffer;
    NSString *_pendingRestoreIconName;
    NSString *_pendingRestoreWindowName;
    BOOL _hasPendingRestoreOffer;
    // Tracks whether the user has already dismissed or acted on the Touch ID for
    // sudo offer for the current sudo invocation. Cleared when sudo is no longer
    // the foreground job.
    BOOL _touchIDForSudoDismissed;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didChangeTmuxWindowsShouldCloseAfterDetach:)
                                                     name:iTermNaggingControllerDidChangeTmuxWindowsShouldCloseAfterDetach
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(claudeCodeStatusToolDismissed:)
                                                     name:iTermNaggingControllerClaudeCodeStatusToolDismissedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(restoreIconAndWindowNameChoiceMade:)
                                                     name:iTermNaggingControllerRestoreIconAndWindowNameChoiceNotification
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
                                   prompt:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.ReportVariableDenied", nil, [NSBundle mainBundle], @"A request to report variable “%@” was denied. Allow it in the future?", @"Prompt asking whether to allow reporting a variable in the future; placeholder is the variable name"), name]
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
    NSString *notice = NSLocalizedStringWithDefaultValue(@"NaggingController.ArrangementProfileCorrupted", nil, [NSBundle mainBundle], @"This arrangement’s profile is missing. This could be due to a bug in iTerm2 version 3.5.7, which caused profiles to be corrupted in saved arrangements.", @"Announcement that a saved arrangement’s profile is missing due to a known bug");
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:YES
                                     identifier:@"ArrangementMissingProfile"
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AssignProfile", nil, [NSBundle mainBundle], @"Assign Profile", @"Button that assigns a profile to a session") ]
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
        notice = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.AppChangedProfileProperty", nil, [NSBundle mainBundle], @"An app tried to change the profile property **%@**", @"Announcement that an app tried to change a single profile property; placeholder is the property description"), [iTermProfilePreferences descriptionForKey:key]];
    } else {
        NSMutableArray<NSString *> *descriptions = [NSMutableArray array];
        for (NSString *key in dict.allKeys) {
            NSString *desc = [iTermProfilePreferences descriptionForKey:key] ?: key;
            [descriptions addObject:[NSString stringWithFormat:@"* %@", desc]];
        }
        NSString *bulletList = [descriptions componentsJoinedByString:@"\n"];
        NSString *popoverMessage = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.PropertiesToBeChanged", nil, [NSBundle mainBundle], @"**Properties to be changed:**\n\n%@", @"Popover heading listing the profile properties that will be changed; placeholder is a bullet list"), bulletList];
        NSString *encodedMessage = [popoverMessage stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *popoverURL = [NSString stringWithFormat:@"x-iterm2-popover:?message=%@", encodedMessage];
        notice = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.AppChangedMultipleProperties", nil, [NSBundle mainBundle], @"An app tried to change [multiple profile properties](%@).", @"Announcement that an app tried to change several profile properties; placeholder is a link URL"), popoverURL];
    }
    __weak __typeof(self) weakSelf = self;
    [self.delegate naggingControllerShowMarkdownMessage:notice
                                             isQuestion:YES
                                              important:NO
                                             identifier:iTermNaggingControllerArrangementSetProfileProperty
                                                options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AllowOnce", nil, [NSBundle mainBundle], @"_Allow Once", @"Button that allows an action one time; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.AllowAlways", nil, [NSBundle mainBundle], @"Allow Always", @"Button that always allows an action"), NSLocalizedStringWithDefaultValue(@"NaggingController.DenyAlways", nil, [NSBundle mainBundle], @"Deny Always", @"Button that always denies an action") ]
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
    NSString *notice = NSLocalizedStringWithDefaultValue(@"NaggingController.TextReplacements", nil, [NSBundle mainBundle], @"Would you like macOS Text Replacements to be applied automatically?", @"Prompt asking whether to apply macOS Text Replacements automatically");
    _haveOutstandingTextReplacementOffer = YES;
    __weak __typeof(self) weakSelf = self;
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementTextReplacements
                                        options:@[ NaggingYes(), NSLocalizedStringWithDefaultValue(@"NaggingController.NoShortcut", nil, [NSBundle mainBundle], @"_No", @"No button label; underscore marks the keyboard shortcut key") ]
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
    RLog(@"Can’t find profile %@ guid %@", missingProfileName, guid);
    if ([iTermAdvancedSettingsModel noSyncSuppressMissingProfileInArrangementWarning]) {
        return;
    }
    NSString *notice;
    NSArray<NSString *> *actions = @[ NSLocalizedStringWithDefaultValue(@"NaggingController.DontWarnAgain", nil, [NSBundle mainBundle], @"Don’t Warn Again", @"Button that suppresses future warnings") ];
    if ([[ProfileModel sharedInstance] bookmarkWithName:missingProfileName]) {
        notice = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.ProfileMissingButNameExists", nil, [NSBundle mainBundle], @"This session’s profile, “%@”, no longer exists. A profile with that name happens to exist.", @"Announcement that a session’s profile no longer exists but a same-named one exists; placeholder is the profile name"), missingProfileName];
        if (savedArrangementName) {
            actions = [actions arrayByAddingObject:NSLocalizedStringWithDefaultValue(@"NaggingController.RepairSavedArrangement", nil, [NSBundle mainBundle], @"Repair Saved Arrangement", @"Button that repairs a saved arrangement")];
        }
    } else {
        notice = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.ProfileMissing", nil, [NSBundle mainBundle], @"This session’s profile, “%@”, no longer exists.", @"Announcement that a session’s profile no longer exists; placeholder is the profile name"), missingProfileName];
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
    RLog(@"Arrangement %@ has bad pwd of %@ for session guid %@", arrangementName, badPWD, sessionGUID);
    if ([iTermAdvancedSettingsModel noSyncSuppressBadPWDInArrangementWarning]) {
        return;
    }
    NSString *notice = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.ArrangementBadPWD", nil, [NSBundle mainBundle], @"The saved arrangement “%1$@” has a bad initial directory of “%2$@” for this session.", @"Announcement that a saved arrangement has an invalid initial directory; first placeholder is the arrangement name, second is the directory"), arrangementName, badPWD];

    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementProfileMissingIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.DontWarnAgain", nil, [NSBundle mainBundle], @"Don’t Warn Again", @"Button that suppresses future warnings"), NSLocalizedStringWithDefaultValue(@"NaggingController.Repair", nil, [NSBundle mainBundle], @"Repair", @"Button that repairs a problem") ]
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
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.OrphanRestored", nil, [NSBundle mainBundle], @"This already-running session was restored but its contents were not saved.", @"Announcement that an already-running session was restored without saved contents")
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerOrphanIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Why", nil, [NSBundle mainBundle], @"Why?", @"Button that explains why something happened") ]
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
    [self.delegate naggingControllerShowMessage:execDidFail ? NSLocalizedStringWithDefaultValue(@"NaggingController.SessionFailedToStart", nil, [NSBundle mainBundle], @"Session failed to start.", @"Announcement that a session failed to start") : NSLocalizedStringWithDefaultValue(@"NaggingController.SessionEndedRestart", nil, [NSBundle mainBundle], @"Session ended (command exited). Restart it?", @"Prompt asking whether to restart a session whose command exited")
                                     isQuestion:!execDidFail
                                      important:YES
                                     identifier:iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Restart", nil, [NSBundle mainBundle], @"_Restart", @"Restart button label; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.DontAskAgain", nil, [NSBundle mainBundle], @"Don’t Ask Again", @"Button that suppresses future prompts") ]
                                     completion:^(int selection) {
        [self handleCompletionForBrokenPipe:selection];
    }];
}

- (void)askAboutAbortingDownload {
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.AbortDownload", nil, [NSBundle mainBundle], @"A file is being downloaded. Abort the download?", @"Prompt asking whether to abort an in-progress download")
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortDownloadIdentifier
                                        options:@[ iTermLocalizedOK(), iTermLocalizedCancel() ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAbortDownload];
        }
    }];
}

- (void)askAboutAbortingUpload {
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.AbortUpload", nil, [NSBundle mainBundle], @"A file is being uploaded. Abort the upload?", @"Prompt asking whether to abort an in-progress upload")
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier
                                        options:@[ iTermLocalizedOK(), iTermLocalizedCancel() ]
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
    NSString *message = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.TmuxSupplementaryPlaneError", nil, [NSBundle mainBundle], @"Because of a bug in tmux 2.2, the character “%@” cannot be sent.", @"Announcement that a character cannot be sent due to a tmux 2.2 bug; placeholder is the character"), string];
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerTmuxSupplementaryPlaneErrorIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Why", nil, [NSBundle mainBundle], @"Why?", @"Button that explains why something happened") ]
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
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.ScrollWheelMovesCursor", nil, [NSBundle mainBundle], @"Do you want the scroll wheel to move the cursor in interactive programs like this?", @"Prompt asking whether the scroll wheel should move the cursor in interactive programs")
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Yes", nil, [NSBundle mainBundle], @"Yes", @"Yes button label"), NSLocalizedStringWithDefaultValue(@"NaggingController.DontAskAgain", nil, [NSBundle mainBundle], @"Don’t Ask Again", @"Button that suppresses future prompts") ]
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
        title = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"NaggingController.SetBackgroundImage", nil, [NSBundle mainBundle], @"Set background image to “%@”?", @"Prompt asking whether to set the background image; placeholder is the filename"), filename];
    } else {
        title = NSLocalizedStringWithDefaultValue(@"NaggingController.RemoveBackgroundImage", nil, [NSBundle mainBundle], @"Remove background image?", @"Prompt asking whether to remove the background image");
    }
    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerSetBackgroundImageFileIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Yes", nil, [NSBundle mainBundle], @"Yes", @"Yes button label"), NaggingAlways(), NaggingNever() ]
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
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.MouseReportingFrustration", nil, [NSBundle mainBundle], @"Looks like you’re trying to copy to the pasteboard, but mouse reporting has prevented making a selection. Disable mouse reporting?", @"Prompt asking whether to disable mouse reporting when it blocks selection")
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutMouseReportingFrustrationIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Temporarily", nil, [NSBundle mainBundle], @"_Temporarily", @"Button that performs an action temporarily; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.Permanently", nil, [NSBundle mainBundle], @"Permanently", @"Button that performs an action permanently"), NSLocalizedStringWithDefaultValue(@"NaggingController.StopAsking", nil, [NSBundle mainBundle], @"Stop Asking", @"Button that suppresses future prompts") ]
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
    title = NSLocalizedStringWithDefaultValue(@"NaggingController.PasteBracketingLeftOn", nil, [NSBundle mainBundle], @"Looks like paste bracketing was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?", @"Prompt asking whether to turn off paste bracketing");

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier
                                        options:@[ NaggingYes(), NaggingAlways(), NaggingNever(), NSLocalizedStringWithDefaultValue(@"NaggingController.Help", nil, [NSBundle mainBundle], @"Help", @"Help button") ]
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

- (BOOL)shouldResetKeyReportingMode {
    NSNumber *number = [[iTermUserDefaults userDefaults] objectForKey:kResetKeyReportingModeUserDefaultsKey];
    if (number.boolValue) {
        // User chose "Always" - caller should reset
        return YES;
    }
    if (number != nil) {
        // User chose "Never" - do nothing
        return NO;
    }
    // User hasn't chosen yet - show nag
    NSString *title = NSLocalizedStringWithDefaultValue(@"NaggingController.ResetKeyReportingMode", nil, [NSBundle mainBundle], @"The key reporting mode may have been left in an unusual setting when an ssh session died or an app crashed. Restore?", @"Prompt asking whether to reset the key reporting mode");

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kResetKeyReportingModeAnnouncementIdentifier
                                        options:@[ NaggingYes(), NaggingAlways(), NaggingNever() ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [self.delegate naggingControllerResetKeyReportingMode];
                break;

            case 1: // Always
                [[iTermUserDefaults userDefaults] setBool:YES
                                                        forKey:kResetKeyReportingModeUserDefaultsKey];
                [self.delegate naggingControllerResetKeyReportingMode];
                break;

            case 2: // Never
                [[iTermUserDefaults userDefaults] setBool:NO
                                                        forKey:kResetKeyReportingModeUserDefaultsKey];
                break;
        }
    }];
    return NO;
}

- (void)dismissKeyReportingModeOffer {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:kResetKeyReportingModeAnnouncementIdentifier];
}

- (void)offerToRestoreIconName:(NSString *)iconName windowName:(NSString *)windowName {
    NSString *title;
    title = NSLocalizedStringWithDefaultValue(@"NaggingController.RestoreTitlesAfterSSH", nil, [NSBundle mainBundle], @"Automatically restore the tab and window title when an ssh session ends?", @"Prompt asking whether to restore tab and window titles when an ssh session ends");

    _pendingRestoreIconName = [iconName copy];
    _pendingRestoreWindowName = [windowName copy];
    _hasPendingRestoreOffer = YES;

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kRestoreIconAndWindowNameOnHostChangeAnnouncementIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.OnlyThisTime", nil, [NSBundle mainBundle], @"_Only This Time", @"Button that performs an action only once; underscore marks the keyboard shortcut key"), NaggingAlways(), NaggingNever() ]
                                     completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                [self clearPendingRestoreOffer];
                break;

            case -1: // No
                [self clearPendingRestoreOffer];
                break;

            case 0: // Only This Time
                [self clearPendingRestoreOffer];
                [self.delegate naggingControllerRestoreIconNameTo:iconName windowName:windowName];
                break;

            case 1: // Always
                [self clearPendingRestoreOffer];
                [[iTermUserDefaults userDefaults] setBool:YES
                                                        forKey:kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey];
                [self.delegate naggingControllerRestoreIconNameTo:iconName windowName:windowName];
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermNaggingControllerRestoreIconAndWindowNameChoiceNotification
                                                                    object:nil
                                                                  userInfo:@{ iTermNaggingControllerRestoreIconAndWindowNameChoiceAlwaysKey: @YES }];
                break;

            case 2: // Never
                [self clearPendingRestoreOffer];
                [[iTermUserDefaults userDefaults] setBool:NO
                                                        forKey:kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey];
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermNaggingControllerRestoreIconAndWindowNameChoiceNotification
                                                                    object:nil
                                                                  userInfo:@{ iTermNaggingControllerRestoreIconAndWindowNameChoiceAlwaysKey: @NO }];
                break;
        }
    }];
}

- (void)clearPendingRestoreOffer {
    _hasPendingRestoreOffer = NO;
    _pendingRestoreIconName = nil;
    _pendingRestoreWindowName = nil;
}

- (void)restoreIconAndWindowNameChoiceMade:(NSNotification *)notification {
    if (!_hasPendingRestoreOffer) {
        return;
    }
    NSString *iconName = _pendingRestoreIconName;
    NSString *windowName = _pendingRestoreWindowName;
    const BOOL always = [notification.userInfo[iTermNaggingControllerRestoreIconAndWindowNameChoiceAlwaysKey] boolValue];
    [self clearPendingRestoreOffer];
    if (always) {
        [self.delegate naggingControllerRestoreIconNameTo:iconName windowName:windowName];
    }
    [self.delegate naggingControllerRemoveMessageWithIdentifier:kRestoreIconAndWindowNameOnHostChangeAnnouncementIdentifier];
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
    title = NSLocalizedStringWithDefaultValue(@"NaggingController.SlowTriggers", nil, [NSBundle mainBundle], @"This session’s triggers are pretty slow. Disable them in interactive apps?", @"Prompt asking whether to disable slow triggers in interactive apps");

    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:YES
                                     identifier:kTurnOffSlowTriggersOfferUserDefaultsKey
                                        options:@[ NaggingYes(), NSLocalizedStringWithDefaultValue(@"NaggingController.StopAsking", nil, [NSBundle mainBundle], @"Stop Asking", @"Button that suppresses future prompts"), NSLocalizedStringWithDefaultValue(@"NaggingController.ViewStats", nil, [NSBundle mainBundle], @"View Stats", @"Button that shows statistics"), NSLocalizedStringWithDefaultValue(@"NaggingController.Help", nil, [NSBundle mainBundle], @"Help", @"Help button") ]
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
    [self.delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.TmuxPasteBufferUpdated", nil, [NSBundle mainBundle], @"The tmux paste buffer was updated. Would you like to mirror it to the local clipboard from now on?", @"Prompt asking whether to mirror the tmux paste buffer to the local clipboard")
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerOfferToSyncTmuxClipboard
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysShortcut", nil, [NSBundle mainBundle], @"_Always", @"Always button label; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.NeverShortcut", nil, [NSBundle mainBundle], @"_Never", @"Never button label; underscore marks the keyboard shortcut key") ]
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
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.ControlSequenceClearScrollback", nil, [NSBundle mainBundle], @"A control sequence attempted to clear scrollback history. Allow this in the future?", @"Prompt asking whether to allow a control sequence to clear scrollback history");
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerAskAboutClearingScrollbackHistoryIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysAllowShortcut", nil, [NSBundle mainBundle], @"Always _Allow", @"Always Allow button label; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysDenyShortcut", nil, [NSBundle mainBundle], @"Always _Deny", @"Always Deny button label; underscore marks the keyboard shortcut key") ]
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
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.OpenCommandSecureInput", nil, [NSBundle mainBundle], @"The open command doesn't activate other apps when Secure Keyboard Input is enabled.", @"Announcement explaining that the open command does not activate apps while Secure Keyboard Input is on");
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerWarnAboutSecureKeyboardInputWithOpenCommand
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.DontRemindMeAgain", nil, [NSBundle mainBundle], @"Don’t Remind Me Again", @"Button that suppresses future reminders") ]
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
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.ControlSequenceChangeProfile", nil, [NSBundle mainBundle], @"A control sequence attempted to change the current profile. Allow this in the future?", @"Prompt asking whether to allow a control sequence to change the current profile");
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerAskAboutChangingProfileIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysAllowShortcut", nil, [NSBundle mainBundle], @"Always _Allow", @"Always Allow button label; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysDenyShortcut", nil, [NSBundle mainBundle], @"Always _Deny", @"Always Deny button label; underscore marks the keyboard shortcut key") ]
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
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.CloseTmuxWindowsAfterDetach", nil, [NSBundle mainBundle], @"Close tmux windows after detaching?", @"Prompt asking whether to close tmux windows after detaching");
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerTmuxWindowsShouldCloseAfterDetach
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysShortcut", nil, [NSBundle mainBundle], @"_Always", @"Always button label; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.NeverShortcut", nil, [NSBundle mainBundle], @"_Never", @"Never button label; underscore marks the keyboard shortcut key") ]
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
    [_delegate naggingControllerShowMessage:NSLocalizedStringWithDefaultValue(@"NaggingController.JSONPromotion", nil, [NSBundle mainBundle], @"That's a gnarly JSON blob you've got there! iTerm2 can replace this hard-to-read selection with a pretty-printed value.", @"Announcement offering to pretty-print a JSON selection")
                                 isQuestion:NO
                                  important:NO
                                 identifier:@"JSONPromotion"
                                    options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.TryItNow", nil, [NSBundle mainBundle], @"Try it Now", @"Button that tries a suggested feature immediately"), NSLocalizedStringWithDefaultValue(@"NaggingController.Dismiss", nil, [NSBundle mainBundle], @"Dismiss", @"Button that dismisses an announcement") ]
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
        RLog(@"OpenUrl disabled");
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

    [_delegate naggingControllerShowMessage:[NSString stringWithFormat: NSLocalizedStringWithDefaultValue(@"NaggingController.OpenThisURL", nil, [NSBundle mainBundle], @"Open this URL? %@", @"Prompt asking whether to open a URL; placeholder is the URL"), url.sanitizedForPrinting.absoluteString]
                                 isQuestion:YES
                                  important:YES
                                 identifier:allowHostKey
                                    options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.Allow", nil, [NSBundle mainBundle], @"Allow", @"Button that allows an action once"), NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysAllowForThisHost", nil, [NSBundle mainBundle], @"Always allow for this host", @"Button that always allows an action for a given host"), NSLocalizedStringWithDefaultValue(@"NaggingController.NeverAllow", nil, [NSBundle mainBundle], @"Never allow", @"Button that never allows an action") ]
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
    if (_touchIDForSudoDismissed) {
        DLog(@"Touch ID for sudo offer already dismissed for this sudo invocation");
        return;
    }
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:iTermNaggingControllerTouchIDForSudoIdentifier]) {
        DLog(@"Can't show Touch ID for sudo offer");
        return;
    }
    NSNumber *setting = [[iTermUserDefaults userDefaults] objectForKey:iTermNaggingControllerTouchIDForSudoUserDefaultsKey];
    if (setting != nil) {
        RLog(@"Touch ID for sudo offer disabled by user default: %@", setting);
        return;
    }
    if ([iTermTouchIDHelper isTouchIDEnabledForSudo]) {
        DLog(@"Touch ID for sudo already enabled");
        return;
    }
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.EnableTouchIDForSudo", nil, [NSBundle mainBundle], @"Would you like to enable Touch ID for sudo?", @"Announcement offering to enable Touch ID for sudo");
    if ([self.delegate naggingControllerAnnouncementWouldObscureCursorForText:message]) {
        DLog(@"Announcement would obscure cursor");
        return;
    }
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerTouchIDForSudoIdentifier
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.RunInNewWindow", nil, [NSBundle mainBundle], @"_Run In New Window", @"Button that runs a command in a new window; underscore marks the keyboard shortcut key"), NSLocalizedStringWithDefaultValue(@"NaggingController.CopyCommand", nil, [NSBundle mainBundle], @"Copy Command", @"Button that copies a command to the clipboard"), NSLocalizedStringWithDefaultValue(@"NaggingController.DontAskAgain", nil, [NSBundle mainBundle], @"Don’t Ask Again", @"Button that suppresses future prompts") ]
                                     completion:^(int selection) {
        // Any explicit user action — including closing with the X (selection -1)
        // — should suppress further offers for this sudo invocation.
        if (selection != -2) {
            self->_touchIDForSudoDismissed = YES;
        }
        switch (selection) {
            case 0:  // Run In New Window
                [iTermTouchIDHelper runInstallInNewWindow];
                break;
            case 1: {  // Copy Command
                NSString *command = [iTermTouchIDHelper installCommand];
                if (command) {
                    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                    [pasteboard clearContents];
                    [pasteboard setString:command forType:NSPasteboardTypeString];
                }
                break;
            }
            case 2:  // Don't ask again
                [[iTermUserDefaults userDefaults] setBool:NO
                                                   forKey:iTermNaggingControllerTouchIDForSudoUserDefaultsKey];
                break;
        }
    }];
}

- (void)removeTouchIDForSudoOffer {
    // Called by PTYSession when sudo is no longer the foreground job. Reset the
    // dismissal flag so future sudo invocations can offer again.
    _touchIDForSudoDismissed = NO;
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
                                        options:@[ NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysAllow", nil, [NSBundle mainBundle], @"Always Allow", @"Button that always allows an action"), NSLocalizedStringWithDefaultValue(@"NaggingController.AlwaysDeny", nil, [NSBundle mainBundle], @"Always Deny", @"Button that always denies an action") ]
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

#pragma mark - Claude Code Status Tool

- (void)offerClaudeCodeStatusTool:(void (^)(iTermClaudeCodeUpsellStatus))completion {
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:iTermNaggingControllerClaudeCodeStatusToolIdentifier]) {
        return;
    }
    NSString *message = NSLocalizedStringWithDefaultValue(@"NaggingController.ClaudeCodeUpsell", nil, [NSBundle mainBundle], @"Want to try iTerm2’s Claude Code integration?", @"Announcement offering to try the Claude Code integration");
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerClaudeCodeStatusToolIdentifier
                                        options:@[ NaggingYes(), NaggingNever(), NSLocalizedStringWithDefaultValue(@"NaggingController.AskLater", nil, [NSBundle mainBundle], @"Ask Later", @"Button that dismisses an offer but allows it to reappear later") ]
                                     completion:^(int selection) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermNaggingControllerClaudeCodeStatusToolDismissedNotification
                                                            object:nil];
        switch (selection) {
            case 0:
                completion(iTermClaudeCodeUpsellStatusAccept);
                break;
            case 1:
                completion(iTermClaudeCodeUpsellStatusNever);
                break;
            case 2:
                completion(iTermClaudeCodeUpsellStatusAskLater);
                break;
        }
    }];
}

- (void)claudeCodeStatusToolDismissed:(NSNotification *)notification {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerClaudeCodeStatusToolIdentifier];
}

@end
