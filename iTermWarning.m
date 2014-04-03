#import "iTermWarning.h"

static const NSTimeInterval kTemporarySilenceTime = 600;
static NSString *const kCancel = @"Cancel";

@implementation iTermWarning

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
{
    if (warningType != kiTermWarningTypePersistent && [self identifierIsSilenced:identifier]) {
        return [self savedSelectionForIdentifier:identifier];
    }
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"Warning"
                                     defaultButton:actions.count > 0 ? actions[0] : nil
                                   alternateButton:actions.count > 1 ? actions[1] : nil
                                       otherButton:actions.count > 2 ? actions[2] : nil
                         informativeTextWithFormat:@"%@", title];
    int numNonCancelActions = [actions count];
    for (NSString *string in actions) {
        if ([string isEqualToString:kCancel]) {
            --numNonCancelActions;
        }
    }
    // If this is silenceable and at least one button is not "Cancel" then offer to remember the
    // selection. But a "Cancel" action is not remembered.
    if (warningType == kiTermWarningTypeTemporarilySilenceable) {
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this warning temporarily";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Suppress this warning temporarily and use my choice from now on";
        }
        alert.showsSuppressionButton = YES;
    } else if (warningType == kiTermWarningTypePermanentlySilenceable) {
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Do not warn again";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Do not warn again and use my choice from now on";
        }
        alert.showsSuppressionButton = YES;
    }
    
    NSInteger result = [alert runModal];

    BOOL remember = NO;
    iTermWarningSelection selection;
    switch (result) {
        case NSAlertDefaultReturn:
            selection = kiTermWarningSelection0;
            remember = ![actions[0] isEqualToString:kCancel];
            break;
        case NSAlertAlternateReturn:
            selection = kiTermWarningSelection1;
            remember = ![actions[1] isEqualToString:kCancel];
            break;
        case NSAlertOtherReturn:
            selection = kiTermWarningSelection2;
            remember = ![actions[2] isEqualToString:kCancel];
            break;
        default:
            selection = kItermWarningSelectionError;
    }

    // Save info if suppression was enabled.
    if (remember && alert.suppressionButton.state == NSOnState) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        if (warningType == kiTermWarningTypeTemporarilySilenceable) {
            NSString *theKey = [self temporarySilenceKeyForIdentifier:identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kTemporarySilenceTime
                             forKey:theKey];
        } else {
            NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
            [userDefaults setBool:YES forKey:theKey];
        }
        [[NSUserDefaults standardUserDefaults] setObject:@(selection)
                                                  forKey:[self selectionKeyForIdentifier:identifier]];
    }

    return selection;
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

+ (NSString *)selectionKeyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"%@_selection", identifier];
}

+ (iTermWarningSelection)savedSelectionForIdentifier:(NSString *)identifier {
    NSString *theKey = [self selectionKeyForIdentifier:identifier];
    return [[NSUserDefaults standardUserDefaults] integerForKey:theKey];
}

@end
