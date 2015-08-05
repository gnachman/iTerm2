#import "iTermWarning.h"

static const NSTimeInterval kTemporarySilenceTime = 600;
static NSString *const kCancel = @"Cancel";
static id<iTermWarningHandler> gWarningHandler;
static BOOL gShowingWarning;

@implementation iTermWarning

+ (void)setWarningHandler:(id<iTermWarningHandler>)handler {
    [gWarningHandler autorelease];
    gWarningHandler = [handler retain];
}

+ (id<iTermWarningHandler>)warningHandler {
    return gWarningHandler;
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType {
    return [self showWarningWithTitle:title
                              actions:actions
                            accessory:nil
                           identifier:identifier
                          silenceable:warningType
                              heading:nil];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                  actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                               identifier:(NSString *)identifier
                              silenceable:(iTermWarningType)warningType {
    return [self showWarningWithTitle:title
                              actions:actions
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:nil];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading {
    if (!gWarningHandler &&
        warningType != kiTermWarningTypePersistent &&
        [self identifierIsSilenced:identifier]) {
        return [self savedSelectionForIdentifier:identifier];
    }

    NSAlert *alert = [NSAlert alertWithMessageText:heading ?: @"Warning"
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
        assert(identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this message for ten minutes";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Remember my choice for ten minutes";
        }
        alert.showsSuppressionButton = YES;
    } else if (warningType == kiTermWarningTypePermanentlySilenceable) {
        assert(identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this message permanently";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Remember my choice";
        }
        alert.showsSuppressionButton = YES;
    }

    if (accessory) {
        [alert setAccessoryView:accessory];
    }

    NSInteger result;
    if (gWarningHandler) {
        result = [gWarningHandler warningWouldShowAlert:alert identifier:identifier];
    } else {
        gShowingWarning = YES;
        result = [alert runModal];
        gShowingWarning = NO;
    }

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
    if (!identifier) {
        return NO;
    }
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

+ (BOOL)showingWarning {
    return gShowingWarning;
}

@end
