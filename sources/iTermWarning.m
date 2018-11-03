#import "iTermWarning.h"

#import "DebugLogging.h"
#import "iTermDisclosableView.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

static const NSTimeInterval kTemporarySilenceTime = 600;
static const NSTimeInterval kOneMonthTime = 30 * 24 * 60 * 60;
static NSString *const kCancel = @"Cancel";
static id<iTermWarningHandler> gWarningHandler;
static BOOL gShowingWarning;

@implementation iTermWarningAction

+ (instancetype)warningActionWithLabel:(NSString *)label
                                 block:(iTermWarningActionBlock)block {
    iTermWarningAction *warningAction = [[[self alloc] init] autorelease];
    warningAction.label = label;
    warningAction.block = block;
    return warningAction;
}

- (void)dealloc {
    [_label release];
    [_block release];
    [super dealloc];
}

@end

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
                                  silenceable:(iTermWarningType)warningType
                                       window:(NSWindow *)window {
    return [self showWarningWithTitle:title
                              actions:actions
                            accessory:nil
                           identifier:identifier
                          silenceable:warningType
                              heading:nil
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                  actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                               identifier:(NSString *)identifier
                              silenceable:(iTermWarningType)warningType
                                       window:(NSWindow *)window {
    return [self showWarningWithTitle:title
                              actions:actions
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:nil
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                       window:(NSWindow *)window {
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:nil
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:heading
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                       window:(NSWindow *)window {
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:actionToSelectionMap
                            accessory:accessory
                           identifier:identifier
                          silenceable:warningType
                              heading:heading
                          cancelLabel:kCancel
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                  cancelLabel:(NSString *)cancelLabel
                                       window:(NSWindow *)window {
    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = title;
    warning.actionLabels = actions;
    warning.actionToSelectionMap = actionToSelectionMap;
    warning.accessory = accessory;
    warning.identifier = identifier;
    warning.warningType = warningType;
    warning.heading = heading;
    warning.cancelLabel = cancelLabel;
    NSWindow *deepestWindow = window;
    while (deepestWindow.sheets.lastObject) {
        deepestWindow = deepestWindow.sheets.lastObject;
    }
    warning.window = deepestWindow;
    return [warning runModal];
}

- (void)dealloc {
    [_title release];
    [_warningActions release];
    [_actionToSelectionMap release];
    [_accessory release];
    [_identifier release];
    [_heading release];
    [_cancelLabel release];
    [_showHelpBlock release];
    [_window release];
    [super dealloc];
}

- (void)setActionLabels:(NSArray<NSString *> *)actionLabels {
    self.warningActions = [[[actionLabels mapWithBlock:^id(NSString *label) {
        return [iTermWarningAction warningActionWithLabel:label block:nil];
    }] mutableCopy] autorelease];
}

- (NSArray<NSString *> *)actionLabels {
    return [self.warningActions mapWithBlock:^id(iTermWarningAction *warningAction) {
        return warningAction.label;
    }];
}

- (iTermWarningSelection)runModal {
    iTermWarningSelection selection = [self runModalImpl];

    if (selection >= 0 && selection < _warningActions.count) {
        iTermWarningActionBlock block = _warningActions[selection].block;
        if (block) {
            block(selection);
        }
    }

    return selection;
}

+ (void)unsilenceIdentifier:(NSString *)identifier ifSelectionEquals:(iTermWarningSelection)problemSelection {
    if ([self identifierIsSilenced:identifier] &&
        [self savedSelectionForIdentifier:identifier] == problemSelection) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
        [userDefaults removeObjectForKey:theKey];
    }
}

// Does not invoke the warning action's block
- (iTermWarningSelection)runModalImpl {
    if (!gWarningHandler &&
        _warningType != kiTermWarningTypePersistent &&
        [self.class identifierIsSilenced:_identifier]) {
        return [self.class savedSelectionForIdentifier:_identifier];
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = _heading ?: @"Warning";
    alert.informativeText = _title;
    for (int i = 0; i < _warningActions.count; i++) {
        [alert addButtonWithTitle:_warningActions[i].label];
    }
    int numNonCancelActions = [_warningActions count];
    for (iTermWarningAction *warningAction in _warningActions) {
        if ([warningAction.label isEqualToString:_cancelLabel]) {
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
    } else if (_warningType == kiTermWarningTypeSilencableForOneMonth) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = @"Suppress this message for 30 days";
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = @"Remember my choice for 30 days";
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
        iTermDisclosableView *disclosableView = [iTermDisclosableView castFrom:_accessory];
        if (disclosableView) {
            disclosableView.requestLayout = ^{
                [alert layout];
            };
        }
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
        if (self.window) {
            result = [alert runSheetModalForWindow:self.window];
        } else {
            result = [alert runModal];
        }
        gShowingWarning = NO;
    }

    BOOL remember = NO;
    iTermWarningSelection selection;
    switch (result) {
        case NSAlertFirstButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection0 withMapping:_actionToSelectionMap];
            remember = ![_warningActions[0].label isEqualToString:_cancelLabel];
            break;
        case NSAlertSecondButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection1 withMapping:_actionToSelectionMap];
            remember = ![_warningActions[1].label isEqualToString:_cancelLabel];
            break;
        case NSAlertThirdButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection2 withMapping:_actionToSelectionMap];
            remember = ![_warningActions[2].label isEqualToString:_cancelLabel];
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
        } else if (_warningType == kiTermWarningTypeSilencableForOneMonth) {
            NSString *theKey = [self.class temporarySilenceKeyForIdentifier:_identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kOneMonthTime
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
        XLog(@"Selected value %@ is out of range for mapping %@", @(pre), mapping);
        return pre;
    }
    return [mapping[pre] integerValue];
}

#pragma mark - Private

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
