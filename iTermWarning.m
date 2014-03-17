#import "iTermWarning.h"

static const NSTimeInterval kTemporarySilenceTime = 600;

@implementation iTermWarning

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
{
    if ([self identifierIsSilenced:identifier]) {
        return kItermWarningSelectionNotShown;
    }
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"Warning"
                                     defaultButton:actions.count > 0 ? actions[0] : nil
                                   alternateButton:actions.count > 1 ? actions[1] : nil
                                       otherButton:actions.count > 2 ? actions[2] : nil
                         informativeTextWithFormat:@"%@", title];
    if (warningType == kiTermWarningTypeTemporarilySilenceable) {
        alert.suppressionButton.title = @"Suppress this warning temporarily";
        alert.showsSuppressionButton = YES;
    } else if (warningType == kiTermWarningTypePermanentlySilenceable) {
        alert.suppressionButton.title = @"Do not warn again";
        alert.showsSuppressionButton = YES;
    }
    
    NSInteger result = [alert runModal];
    if (alert.suppressionButton.state == NSOnState) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        if (warningType == kiTermWarningTypeTemporarilySilenceable) {
            NSString *theKey = [self temporarySilenceKeyForIdentifier:identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kTemporarySilenceTime
                             forKey:theKey];
        } else {
            NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
            [userDefaults setBool:YES forKey:theKey];
        }
    }
    
    switch (result) {
        case NSAlertDefaultReturn:
            return kiTermWarningSelection0;
        case NSAlertAlternateReturn:
            return kiTermWarningSelection1;
        case NSAlertOtherReturn:
            return kiTermWarningSelection2;
        default:
            return kItermWarningSelectionError;
    }
}

#pragma mark - Private

+ (NSInteger)alertValueForParameterIndex:(int)index {
    switch (index) {
        case 0:
            return NSAlertDefaultReturn;
            
        case 1:
            return NSAlertAlternateReturn;
            
        case 2:
            return NSAlertOtherReturn;
    }
    return NSAlertErrorReturn;
}

+ (NSString *)temporarySilenceKeyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"%@_SilenceUntil", identifier];
}

+ (NSString *)permanentlySilenceKeyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"%@", identifier];
}

+ (BOOL)identifierIsSilenced:(NSString *)identifier {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
    if ([userDefaults boolForKey:theKey]) {
        return YES;
    }
    
    theKey = [self temporarySilenceKeyForIdentifier:identifier];
    NSTimeInterval date = [userDefaults doubleForKey:theKey];
    if (date > [NSDate timeIntervalSinceReferenceDate]) {
        return YES;
    }
    
    return NO;
}

@end
