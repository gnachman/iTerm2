//
//  iTermNaggingController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import "iTermNaggingController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSArray+iTerm.h"
#import "ProfileModel.h"

@implementation iTermNaggingController

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
                                     identifier:@"ThisProfileNoLongerExists"
                                        options:actions
                                     completion:^(int selection) {
        [self handleCompletionForMissingProfileInArrangementWithName:savedArrangementName
                                                 missingProfileNamed:missingProfileName
                                                                guid:guid
                                                           selection:selection];
    }];
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

@end
