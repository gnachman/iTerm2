#import "iTermWarning.h"

#import "DebugLogging.h"

static const NSTimeInterval kTemporarySilenceTime = 600;
static NSString *const kCancel = @"Cancel";
static id<iTermWarningHandler> gWarningHandler;
static BOOL gShowingWarning;

@interface iTermWarning()<NSAlertDelegate>
@end

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
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:nil
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:heading];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading {
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:actionToSelectionMap
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:heading
                          cancelLabel:kCancel];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                  cancelLabel:(NSString *)cancelLabel {
    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = title;
    warning.actions = actions;
    warning.actionToSelectionMap = actionToSelectionMap;
    warning.accessory = accessory;
    warning.identifier = identifier;
    warning.warningType = warningType;
    warning.heading = heading;
    warning.cancelLabel = cancelLabel;
    return [warning runModal];
}

- (iTermWarningSelection)runModal {
    if (!gWarningHandler &&
        _warningType != kiTermWarningTypePersistent &&
        [self.class identifierIsSilenced:_identifier]) {
        return [self.class savedSelectionForIdentifier:_identifier];
    }

    NSAlert *alert = [NSAlert alertWithMessageText:_heading ?: @"Warning"
                                     defaultButton:_actions.count > 0 ? _actions[0] : nil
                                   alternateButton:_actions.count > 1 ? _actions[1] : nil
                                       otherButton:_actions.count > 2 ? _actions[2] : nil
                         informativeTextWithFormat:@"%@", _title];
    int numNonCancelActions = [_actions count];
    for (NSString *string in _actions) {
        if ([string isEqualToString:_cancelLabel]) {
            --numNonCancelActions;
        }
    }
    // If this is silenceable and at least one button is not "Cancel" then offer to remember the
    // selection. But a "Cancel" action is not remembered.
    if (_warningType == kiTermWarningTypeTemporarilySilenceable) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this message for ten minutes";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Remember my choice for ten minutes";
        }
        alert.showsSuppressionButton = YES;
    } else if (_warningType == kiTermWarningTypePermanentlySilenceable) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this message permanently";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Remember my choice";
        }
        alert.showsSuppressionButton = YES;
    }

    if (_accessory) {
        [alert setAccessoryView:_accessory];
    }
    if (_showHelpBlock) {
        alert.showsHelp = YES;
        alert.delegate = self;
    }

    NSInteger result;
    if (gWarningHandler) {
        result = [gWarningHandler warningWouldShowAlert:alert identifier:_identifier];
    } else {
        gShowingWarning = YES;
        result = [alert runModal];
        gShowingWarning = NO;
    }

    BOOL remember = NO;
    iTermWarningSelection selection;
    switch (result) {
        case NSAlertDefaultReturn:
            selection = [self.class remapSelection:kiTermWarningSelection0 withMapping:_actionToSelectionMap];
            remember = ![_actions[0] isEqualToString:_cancelLabel];
            break;
        case NSAlertAlternateReturn:
            selection = [self.class remapSelection:kiTermWarningSelection1 withMapping:_actionToSelectionMap];
            remember = ![_actions[1] isEqualToString:_cancelLabel];
            break;
        case NSAlertOtherReturn:
            selection = [self.class remapSelection:kiTermWarningSelection2 withMapping:_actionToSelectionMap];
            remember = ![_actions[2] isEqualToString:_cancelLabel];
            break;
        default:
            selection = kItermWarningSelectionError;
    }

    // Save info if suppression was enabled.
    if (remember && alert.suppressionButton.state == NSOnState) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        if (_warningType == kiTermWarningTypeTemporarilySilenceable) {
            NSString *theKey = [self.class temporarySilenceKeyForIdentifier:_identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kTemporarySilenceTime
                             forKey:theKey];
        } else {
            NSString *theKey = [self.class permanentlySilenceKeyForIdentifier:_identifier];
            [userDefaults setBool:YES forKey:theKey];
        }
        [[NSUserDefaults standardUserDefaults] setObject:@(selection)
                                                  forKey:[self.class selectionKeyForIdentifier:_identifier]];
    }

    return selection;
}

+ (iTermWarningSelection)remapSelection:(iTermWarningSelection)pre
                            withMapping:(NSArray<NSNumber *> *)mapping {
    if (!mapping) {
        return pre;
    }
    if (pre < 0 || pre >= mapping.count) {
        ELog(@"Selected value %@ is out of range for mapping %@", @(pre), mapping);
        return pre;
    }
    return [mapping[pre] integerValue];
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

#pragma mark - NSAlertDelegate

- (BOOL)alertShowHelp:(NSAlert *)alert {
    self.showHelpBlock();
    return YES;
}

@end
