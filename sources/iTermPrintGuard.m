//
//  iTermPrintGuard.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/19.
//

#import "iTermPrintGuard.h"

#import "NSDate+iTerm.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermWarning.h"

@implementation iTermPrintGuard {
    NSTimeInterval _lastPrintingAttempt;
    BOOL _printingDisabled;
}

- (BOOL)haveTriedToPrintRecently {
    const NSTimeInterval now = [NSDate it_timeSinceBoot];
    const NSTimeInterval last = _lastPrintingAttempt;
    _lastPrintingAttempt = now;
    return now - last < 30;
}

- (BOOL)shouldPrintWithProfile:(Profile *)profile
                      inWindow:(NSWindow *)window {
    if (_printingDisabled) {
        return NO;
    }
    const BOOL okByProfile = ![[profile objectForKey:KEY_DISABLE_PRINTING] boolValue];
    if (!okByProfile) {
        return NO;
    }
    if ([self haveTriedToPrintRecently]) {
        iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"There's a lot of printing going on. Want to keep allowing it?"
                                   actions:@[ @"Allow", @"Disable Temporarily", @"Disable Permanently" ]
                                 accessory:nil
                                identifier:@"NoSyncAllowPrinting"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Allow Printing?"
                                    window:window];
        switch (selection) {
            case kiTermWarningSelection0:
                break;
            case kiTermWarningSelection1: {
                _printingDisabled = YES;
                __weak __typeof(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * 60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf reenable];
                });
                return NO;
            }
            case kiTermWarningSelection2: {
                _printingDisabled = YES;
                NSString *guid = profile[KEY_ORIGINAL_GUID] ?: profile[KEY_GUID];
                Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
                [iTermProfilePreferences setBool:YES forKey:KEY_DISABLE_PRINTING inProfile:profile model:[ProfileModel sharedInstance]];
                return NO;
            }
            default:
                break;
        }
    }
    return YES;
}

- (void)reenable {
    _printingDisabled = NO;
}

@end
