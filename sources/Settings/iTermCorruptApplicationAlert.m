//
//  iTermCorruptApplicationAlert.m
//  iTerm2
//

#import "iTermCorruptApplicationAlert.h"

#import <AppKit/AppKit.h>
#import "iTerm2SharedARC-Swift.h"

void iTermShowCorruptApplicationAlert(NSString * _Nullable settingKey) {
    NSString *team = [iTermAppSignatureValidator currentAppTeamID];
    NSString *message;
    if (!team) {
        message = NSLocalizedStringWithDefaultValue(@"CorruptApplication.SignatureUnverifiable", nil, [NSBundle mainBundle], @"A required file appears to be missing or corrupted and iTerm2’s code signature could not be verified. You should download a fresh copy of the app and reinstall it.", @"Alert shown when a required resource is missing and the code signature could not be verified");
    } else if (![team isEqualToString:@"H7V7XYVQ7D"]) {
        message = NSLocalizedStringWithDefaultValue(@"CorruptApplication.SignatureMismatch", nil, [NSBundle mainBundle], @"A required file appears to be missing or corrupted and iTerm2’s code signature did not match that of the official distribution. You should download a fresh copy of the app and reinstall it.", @"Alert shown when a required resource is missing and the code signature does not match the official distribution");
    } else {
        message = NSLocalizedStringWithDefaultValue(@"CorruptApplication.SignatureValidUnexpected", nil, [NSBundle mainBundle], @"A required file appears to be missing or corrupted, yet against all odds the code signature for iTerm2 is valid. Please file a bug at https://iterm2.com/bugs", @"Alert shown when a required resource is missing but the code signature is unexpectedly valid");
    }
    NSString *informativeText;
    if (settingKey) {
        informativeText = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"CorruptApplication.LoadSettingError", nil, [NSBundle mainBundle], @"While trying to load the setting for “%1$@”: %2$@", @"Error shown while loading a setting (first %@ is the setting key, second is the error message)"), settingKey, message];
    } else {
        informativeText = message;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedStringWithDefaultValue(@"CorruptApplication.Title", nil, [NSBundle mainBundle], @"Application Corrupt", @"Title of alert shown when the application appears corrupt")];
    [alert setInformativeText:informativeText];
    [alert addButtonWithTitle:iTermLocalizedOK()];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert runModal];
    exit(1);
}
