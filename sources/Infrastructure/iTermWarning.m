#import "iTermWarning.h"

#import "DebugLogging.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDisclosableView.h"
#import "iTermUserDefaults.h"
#import "iTerm2SharedARC-Swift.h"

static const NSTimeInterval kTemporarySilenceTime = 600;
static const NSTimeInterval kOneMonthTime = 30 * 24 * 60 * 60;
// The default Cancel label. Localized so that the label-array API's implicit cancel action matches
// callers that pass the same localized "Cancel" (General.Cancel), rather than an English literal.
static NSString *iTermWarningDefaultCancelLabel(void) {
    return iTermLocalizedCancel();
}
static id<iTermWarningHandler> gWarningHandler;
static BOOL gShowingWarning;
BOOL gShowRememberedAlerts = NO;

@interface iTermWarningAction()
@property (nonatomic) NSRange shortcutRange;
@end

@implementation iTermWarningAction

+ (instancetype)warningActionWithLabel:(NSString *)label
                                 block:(iTermWarningActionBlock)block {
    iTermWarningAction *warningAction = [[self alloc] init];
    warningAction.label = label;
    warningAction.block = block;
    return warningAction;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p label=%@>",
            NSStringFromClass([self class]), self, _label];
}

@end

// Stands in for an alert's modal session when warnings run headless (see
// +[iTermWarning setRunsHeadlessModals:]). The alert is never shown. Its buttons are pointed here,
// so clicking one programmatically ends the wait with that button's return code, as it would end a
// real modal session.
@interface iTermHeadlessModalSession : NSObject
@property (nonatomic, readonly) BOOL finished;
@property (nonatomic, readonly) NSModalResponse response;
@end

static BOOL gRunsHeadlessModals;
static NSMutableArray<iTermHeadlessModalSession *> *gHeadlessModalSessions;

@implementation iTermHeadlessModalSession {
    // Set for a sheet, which reports its result later instead of blocking.
    void (^_completion)(NSModalResponse);
}

- (instancetype)initWithAlert:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    self = [super init];
    if (self) {
        _completion = [completion copy];
        [alert.buttons enumerateObjectsUsingBlock:^(NSButton *button, NSUInteger idx, BOOL *stop) {
            button.tag = NSAlertFirstButtonReturn + idx;
            button.target = self;
            button.action = @selector(buttonPressed:);
        }];
        if (!gHeadlessModalSessions) {
            gHeadlessModalSessions = [NSMutableArray array];
        }
        [gHeadlessModalSessions addObject:self];
    }
    return self;
}

- (void)buttonPressed:(NSButton *)sender {
    [self finishWithResponse:sender.tag];
}

- (void)finishWithResponse:(NSModalResponse)response {
    if (_finished) {
        return;
    }
    _finished = YES;
    _response = response;
    [gHeadlessModalSessions removeObject:self];
    if (_completion) {
        void (^completion)(NSModalResponse) = _completion;
        _completion = nil;
        completion(response);
    } else {
        // Wake the nested run loop in -runUntilFinished.
        CFRunLoopStop(CFRunLoopGetMain());
    }
}

// The sheet's parent window closed. Like a real sheet in that case, the completion never runs.
- (void)abandon {
    if (_finished) {
        return;
    }
    _finished = YES;
    _completion = nil;
    [gHeadlessModalSessions removeObject:self];
}

// Blocks like -[NSAlert runModal]: a nested run loop in the modal panel mode. Started from a
// main-queue callout it freezes the main dispatch queue, exactly as a real alert would.
- (NSModalResponse)runUntilFinished {
    while (!_finished) {
        CFRunLoopRunInMode((__bridge CFStringRef)NSModalPanelRunLoopMode, 60, false);
    }
    return _response;
}

@end

@implementation iTermWarningRemoteInput {
    NSString *(^_get)(void);
    void (^_set)(NSString *);
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             label:(NSString *)label
                         isInteger:(BOOL)isInteger
                           minimum:(NSInteger)minimum
                           maximum:(NSInteger)maximum
                               get:(NSString *(^)(void))get
                               set:(void (^)(NSString *))set {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _label = [label copy];
        _isInteger = isInteger;
        _minimum = minimum;
        _maximum = maximum;
        _get = [get copy];
        _set = [set copy];
    }
    return self;
}

+ (instancetype)textInputWithIdentifier:(NSString *)identifier
                                  label:(NSString *)label
                              textField:(NSTextField *)textField {
    // Weak: the warning's caller owns the control and may outlive or predecease this object.
    __weak NSTextField *weakTextField = textField;
    return [[self alloc] initWithIdentifier:identifier
                                      label:label
                                  isInteger:NO
                                    minimum:0
                                    maximum:0
                                        get:^NSString *{
        return weakTextField.stringValue ?: @"";
    }
                                        set:^(NSString *value) {
        weakTextField.stringValue = value;
    }];
}

+ (instancetype)integerInputWithIdentifier:(NSString *)identifier
                                     label:(NSString *)label
                                   minimum:(NSInteger)minimum
                                   maximum:(NSInteger)maximum
                                    getter:(NSInteger (^)(void))getter
                                    setter:(void (^)(NSInteger))setter {
    return [[self alloc] initWithIdentifier:identifier
                                      label:label
                                  isInteger:YES
                                    minimum:minimum
                                    maximum:maximum
                                        get:^NSString *{
        return [@(getter()) stringValue];
    }
                                        set:^(NSString *value) {
        setter(value.integerValue);
    }];
}

- (NSString *)currentValue {
    return _get();
}

- (BOOL)acceptsValue:(NSString *)value {
    if (!_isInteger) {
        return YES;
    }
    // The whole string must be a number: "12abc" and "" are not.
    NSScanner *scanner = [NSScanner scannerWithString:value];
    scanner.charactersToBeSkipped = nil;
    NSInteger number = 0;
    if (![scanner scanInteger:&number] || !scanner.isAtEnd) {
        return NO;
    }
    return number >= _minimum && number <= _maximum;
}

- (void)applyValue:(NSString *)value {
    _set(value);
}

@end

@interface iTermWarning()<NSAlertDelegate>
@end

@implementation iTermWarning

+ (void)setWarningHandler:(id<iTermWarningHandler>)handler {
    gWarningHandler = handler;
}

+ (id<iTermWarningHandler>)warningHandler {
    return gWarningHandler;
}

+ (void)setRunsHeadlessModals:(BOOL)headless {
    gRunsHeadlessModals = headless;
}

+ (BOOL)runsHeadlessModals {
    return gRunsHeadlessModals;
}

+ (void)cancelHeadlessModals {
    for (iTermHeadlessModalSession *session in [gHeadlessModalSessions copy]) {
        [session finishWithResponse:NSModalResponseAbort];
    }
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
                          cancelLabel:iTermWarningDefaultCancelLabel()
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
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:actionToSelectionMap
                            accessory:accessory
                         remoteInputs:nil
                           identifier:identifier
                          silenceable:warningType
                              heading:heading
                          cancelLabel:cancelLabel
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                 remoteInputs:(NSArray<iTermWarningRemoteInput *> *)remoteInputs
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                       window:(NSWindow *)window {
    return [self showWarningWithTitle:title
                              actions:actions
                        actionMapping:nil
                            accessory:accessory
                         remoteInputs:remoteInputs
                           identifier:identifier
                          silenceable:warningType
                              heading:nil
                          cancelLabel:iTermWarningDefaultCancelLabel()
                               window:window];
}

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                 remoteInputs:(NSArray<iTermWarningRemoteInput *> *)remoteInputs
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                  cancelLabel:(NSString *)cancelLabel
                                       window:(NSWindow *)window {
    iTermWarning *warning = [[iTermWarning alloc] init];
    warning.title = title;
    warning.actionLabels = actions;
    warning.actionToSelectionMap = actionToSelectionMap;
    warning.accessory = accessory;
    warning.remoteInputs = remoteInputs;
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

+ (void)asyncShowWarningWithTitle:(NSString *)title
                          actions:(NSArray *)actions
                    actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                        accessory:(NSView *)accessory
                       identifier:(NSString *)identifier
                      silenceable:(iTermWarningType)warningType
                          heading:(NSString *)heading
                      cancelLabel:(NSString *)cancelLabel
                           window:(NSWindow *)window
                       completion:(void (^)(iTermWarningSelection, iTermWarning *))completion {
    iTermWarning *warning = [[iTermWarning alloc] init];
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
    return [warning runModalAsync:completion];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=%@ heading=%@ actions=%@ identifier=%@>",
            NSStringFromClass([self class]), self, _title, _heading, _warningActions, _identifier];
}

- (void)setActionLabels:(NSArray<NSString *> *)actionLabels {
    self.warningActions = [[actionLabels mapWithBlock:^id(NSString *label) {
        return [iTermWarningAction warningActionWithLabel:label block:nil];
    }] mutableCopy];
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

- (void)runModalAsync:(void (^)(iTermWarningSelection result, iTermWarning *warning))completion {
    [self resolveActionRoles];
    iTermWarningSelection preemptedSelection;
    if ([self preempt:&preemptedSelection]) {
        completion(preemptedSelection, self);
        return;
    }

    NSAlert *alert = [self makeAlert];

    NSInteger result;
    if (gWarningHandler) {
        result = [gWarningHandler warningWouldShowAlert:alert identifier:_identifier];
    } else {
        DLog(@"Show warning %@\n%@", self, [NSThread callStackSymbols]);
        gShowingWarning = YES;
        if (self.window) {
            // A sheet shown this way does not block, so it is not app-modal.
            iTermModalAlertRegistration *sheetRegistration = [self registerAlert:alert appModal:NO];
            // AppKit does not call a sheet's completion handler if the parent window closes before
            // the sheet is answered, so the completion alone cannot be relied on to unregister.
            // Without this the alert would stay published (and unanswerable) until relaunch.
            NSWindow *parent = self.window;
            __block id parentCloseObserver = nil;
            __block iTermHeadlessModalSession *headlessSession = nil;
            void (^stopObservingParent)(void) = ^{
                if (parentCloseObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:parentCloseObserver];
                    parentCloseObserver = nil;
                }
            };
            parentCloseObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                                  object:parent
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *notification) {
                DLog(@"Parent window of sheet warning %@ closed before it was answered", self);
                stopObservingParent();
                [sheetRegistration unregister];
                [headlessSession abandon];
                headlessSession = nil;
                gShowingWarning = NO;
            }];
            void (^sheetCompletion)(NSModalResponse) = ^(NSModalResponse result) {
                stopObservingParent();
                headlessSession = nil;
                [sheetRegistration unregister];
                DLog(@"Result for %@ is %@", self, @(result));
                gShowingWarning = NO;
                completion([self handleResult:result alert:alert], self);
            };
            if (gRunsHeadlessModals) {
                // Kept alive by gHeadlessModalSessions until a button is clicked.
                headlessSession = [[iTermHeadlessModalSession alloc] initWithAlert:alert completion:sheetCompletion];
            } else {
                [alert beginSheetModalForWindow:parent completionHandler:sheetCompletion];
            }
            return;
        }
        iTermModalAlertRegistration *registration = [self registerAlert:alert appModal:YES];
        if (gRunsHeadlessModals) {
            result = [[[iTermHeadlessModalSession alloc] initWithAlert:alert completion:nil] runUntilFinished];
        } else {
            result = [alert runModal];
        }
        [registration unregister];
        DLog(@"Result for %@ is %@", self, @(result));
        gShowingWarning = NO;
    }

    completion([self handleResult:result alert:alert], self);
}

+ (void)unsilenceIdentifier:(NSString *)identifier ifSelectionEquals:(iTermWarningSelection)problemSelection {
    if ([self identifierIsSilenced:identifier] &&
        [self savedSelectionForIdentifier:identifier] == problemSelection) {
        NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
        NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
        [userDefaults removeObjectForKey:theKey];
    }
}

+ (void)unsilenceIdentifier:(NSString *)identifier {
    if (![self identifierIsSilenced:identifier]) {
        return;
    }
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
    [userDefaults removeObjectForKey:theKey];
}

+ (void)setIdentifier:(NSString *)identifier isSilenced:(BOOL)silenced {
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
    [userDefaults removeObjectForKey:theKey];
}

+ (BOOL)showRememberedAlerts {
    return gShowRememberedAlerts;
}

+ (void)setShowRememberedAlerts:(BOOL)value {
    gShowRememberedAlerts = value;
}

+ (void)clearSavedSelectionForIdentifier:(NSString *)identifier {
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    // Remove the silence key (permanent)
    NSString *permanentKey = [self permanentlySilenceKeyForIdentifier:identifier];
    [userDefaults removeObjectForKey:permanentKey];
    // Remove the temporary silence key
    NSString *temporaryKey = [self temporarySilenceKeyForIdentifier:identifier];
    [userDefaults removeObjectForKey:temporaryKey];
    // Remove the selection key
    NSString *selectionKey = [self selectionKeyForIdentifier:identifier];
    [userDefaults removeObjectForKey:selectionKey];
}

+ (void)setIdentifier:(NSString *)identifier permanentSelection:(iTermWarningSelection)selection {
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    {
        NSString *theKey = [self permanentlySilenceKeyForIdentifier:identifier];
        [userDefaults setBool:YES forKey:theKey];
    }
    {
        NSString *theKey = [self selectionKeyForIdentifier:identifier];
        return [userDefaults setInteger:selection forKey:theKey];
    }
}

- (void)assignKeyEquivalents {
    NSSet<NSString *> *assignedValues = [NSSet set];
    for (iTermWarningAction *action in _warningActions) {
        if (action.keyEquivalent) {
            [assignedValues setByAddingObject:action.keyEquivalent];
        }
    }
    for (iTermWarningAction *action in _warningActions) {
        [action.label enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
            if (complexString.length > 1) {
                return;
            }
            const unichar c = complexString.length ? [complexString characterAtIndex:0] : simple;
            if (c <= ' ' || c >= 127) {
                return;
            }
            const char lower = tolower(c);
            if (lower < 'a' || lower > 'z') {
                return;
            }
            NSString *string = [NSString stringWithLongCharacter:lower];
            if ([assignedValues containsObject:string]) {
                return;
            }
            action.keyEquivalent = string;
            [assignedValues setByAddingObject:string];
            action.shortcutRange = range;
            *stop = YES;
        }];
    }
}

- (NSAlert *)makeAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _heading ?: NSLocalizedStringWithDefaultValue(@"Warning.DefaultHeading", nil, [NSBundle mainBundle], @"Warning", @"Default title for a warning alert");

    // If this warning is being shown due to the "always show alerts with remembered
    // selections" mode, prepend explanatory text.
    if (_shownDueToRememberedAlertsMode && _savedSelectionLabel) {
        alert.informativeText = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Warning.RememberedSelectionExplanation", nil, [NSBundle mainBundle], @"%1$@\n\nThis alert had a saved selection of “%2$@”. It is being shown because “Always show alerts with remembered selections” is turned on in iTerm2 > Suppressed Alerts.", @"Explanation shown when a suppressed alert is displayed anyway; first %@ is the original message, second %@ is the saved selection label"), _title, _savedSelectionLabel];
    } else {
        alert.informativeText = _title;
    }

    for (iTermWarningAction *action in _warningActions) {
        [alert addButtonWithTitle:action.label];
        NSButton *button = alert.buttons.lastObject;
        button.hasDestructiveAction = action.destructive;
        if (action.keyEquivalent) {
            button.keyEquivalent = action.keyEquivalent;
        } else {
            action.keyEquivalent = button.keyEquivalent;
        }
    }
    [self assignKeyEquivalents];
    [_warningActions enumerateObjectsUsingBlock:^(iTermWarningAction * _Nonnull action, NSUInteger idx, BOOL * _Nonnull stop) {
        NSButton *button = alert.buttons[idx];
        if (!button.keyEquivalent.length) {
            button.keyEquivalent = action.keyEquivalent;
            button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
            if ([iTermAdvancedSettingsModel alertsIndicateShortcuts] && action.shortcutRange.length == 1) {
                dispatch_async(dispatch_get_main_queue(),
                               ^{
                    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:button.title
                                                                                                         attributes:nil];
                    [attributedString setAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) } range:action.shortcutRange];
                    button.attributedTitle = attributedString;
                });
            }
        }
    }];

    // Add "Permanently Forget Saved Selection" button when in remembered alerts mode.
    if (_shownDueToRememberedAlertsMode && _identifier) {
        [alert addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"Warning.PermanentlyForgetSavedSelection", nil, [NSBundle mainBundle], @"Permanently Forget Saved Selection", @"Button to forget a warning's remembered selection")];
    }

    int numNonCancelActions = [_warningActions count];
    for (iTermWarningAction *warningAction in _warningActions) {
        if (warningAction.isCancel) {
            --numNonCancelActions;
        }
    }
    // If this is silenceable and at least one button is not "Cancel" then offer to remember the
    // selection. But a "Cancel" action is not remembered.
    if (_warningType == kiTermWarningTypeTemporarilySilenceable) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            // Not a count plural: the wording depends on whether the warning has one action (suppress)
            // or several (remember which one), and “ten minutes” is a fixed duration.
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.SuppressTenMinutes", nil, [NSBundle mainBundle], @"Suppress this message for ten minutes", @"Suppression checkbox for a single-action warning, temporary (ten minutes)");
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.RememberTenMinutes", nil, [NSBundle mainBundle], @"Remember my choice for ten minutes", @"Suppression checkbox for a multi-action warning, temporary (ten minutes)");
        }
        alert.showsSuppressionButton = YES;
    } else if (_warningType == kiTermWarningTypeSilenceableForOneMonth) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.SuppressThirtyDays", nil, [NSBundle mainBundle], @"Suppress this message for 30 days", @"Suppression checkbox for a single-action warning, for 30 days");
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.RememberThirtyDays", nil, [NSBundle mainBundle], @"Remember my choice for 30 days", @"Suppression checkbox for a multi-action warning, for 30 days");
        }
        alert.showsSuppressionButton = YES;
    } else if (_warningType == kiTermWarningTypePermanentlySilenceable) {
        assert(_identifier);
        if (numNonCancelActions == 1) {
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.SuppressPermanently", nil, [NSBundle mainBundle], @"Suppress this message permanently", @"Suppression checkbox for a single-action warning, permanent");
        } else if (numNonCancelActions > 1) {
            alert.suppressionButton.title = NSLocalizedStringWithDefaultValue(@"Warning.RememberChoice", nil, [NSBundle mainBundle], @"Remember my choice", @"Suppression checkbox for a multi-action warning, permanent");
        }
        alert.showsSuppressionButton = YES;
    }

    if (_accessory) {
        iTermAccessoryViewUnfucker *unfucker = [[iTermAccessoryViewUnfucker alloc] initWithView:_accessory];
        iTermDisclosableView *disclosableView = [iTermDisclosableView castFrom:_accessory];
        if (disclosableView) {
            disclosableView.requestLayout = ^{
                [unfucker layout];
                [alert layout];
                [alert layout];
            };
            [unfucker layout];
        }

        [alert setAccessoryView:unfucker];
        if (_initialFirstResponder) {
            alert.window.initialFirstResponder = _initialFirstResponder;
        }
    }
    if (_showHelpBlock) {
        alert.showsHelp = YES;
        alert.delegate = self;
    }
    return alert;
}

- (BOOL)preempt:(out iTermWarningSelection *)selectionPtr {
    if (!gWarningHandler &&
        _warningType != kiTermWarningTypePersistent &&
        [self.class identifierIsSilenced:_identifier]) {
        const iTermWarningSelection selection = [self.class savedSelectionForIdentifier:_identifier];
        iTermWarningAction *action = [self actionForSelection:selection];
        NSString *label = action.label;
        if (!action || ![self shouldRememberAction:action]) {
            RLog(@"%@ has saved selection %@ but label %@ should not be remembered", self, @(selection), label);
            return NO;
        }
        // When "always show alerts with remembered selections" is on (a checkbox in the Suppressed Alerts panel), show the dialog instead of preempting.
        if (gShowRememberedAlerts) {
            RLog(@"%@ would be silenced but gShowRememberedAlerts is YES", self);
            self.shownDueToRememberedAlertsMode = YES;
            self.savedSelectionLabel = label;
            return NO;  // Don't preempt - show the dialog
        }
        RLog(@"%@ is silenced with saved selection %@", self, @(selection));
        [[iTermSuppressedAlerts sharedInstance] recordSuppressionWithIdentifier:_identifier
                                                                          title:_title
                                                                        heading:_heading
                                                                 selectionLabel:label];
        *selectionPtr = selection;
        return YES;
    }
    return NO;
}

// Does not invoke the warning action's block
// Resolve each action's structural role once, from the caller's own (already-localized) cancelLabel
// and doNotRememberLabels, so the runtime never string-matches against a hardcoded @"Cancel". Only
// sets flags; object-API callers that set isCancel/neverRemember directly are preserved.
- (void)resolveActionRoles {
    for (iTermWarningAction *action in _warningActions) {
        if (_cancelLabel.length && [action.label isEqualToString:_cancelLabel]) {
            action.isCancel = YES;
        }
        if (_doNotRememberLabels.count && [_doNotRememberLabels containsObject:action.label]) {
            action.neverRemember = YES;
        }
    }
}

- (iTermWarningAction *)actionForSelection:(iTermWarningSelection)selection {
    if (_actionToSelectionMap) {
        for (NSUInteger i = 0; i < _actionToSelectionMap.count && i < _warningActions.count; i++) {
            if (_actionToSelectionMap[i].integerValue == selection) {
                return _warningActions[i];
            }
        }
    } else if (selection >= 0 && selection < _warningActions.count) {
        return _warningActions[selection];
    }
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _remotelyAnswerable = YES;
    }
    return self;
}

#pragma mark - Remote answering

- (iTermModalAlertDescriptor *)modalAlertDescriptorWhenAppModal:(BOOL)appModal {
    if (!_remotelyAnswerable) {
        return nil;
    }
    return [self modalAlertDescriptorForAlert:[self makeAlertForRemoteAnswer] appModal:appModal];
}

// Describes `alert` for iTermModalAlertRegistry. The buttons are exactly this warning's actions:
// the "Permanently Forget Saved Selection" button that remembered-alerts mode appends after them is
// left out, so a button's index is always an index into _warningActions. Accessory views and the
// help button are not described.
- (iTermModalAlertDescriptor *)modalAlertDescriptorForAlert:(NSAlert *)alert appModal:(BOOL)appModal {
    NSArray<iTermModalAlertButton *> *buttons = [_warningActions mapWithBlock:^id(iTermWarningAction *action) {
        return [[iTermModalAlertButton alloc] initWithTitle:action.label
                                                   isCancel:action.isCancel
                                              isDestructive:action.destructive
                                               rememberable:[self shouldRememberAction:action]];
    }];
    NSArray<iTermModalAlertInput *> *inputs = [_remoteInputs mapWithBlock:^id(iTermWarningRemoteInput *input) {
        return [[iTermModalAlertInput alloc] initWithIdentifier:input.identifier
                                                          label:input.label
                                                      isInteger:input.isInteger
                                                        minimum:input.minimum
                                                        maximum:input.maximum
                                                          value:[input currentValue]];
    }];
    // Remote inputs stand for everything in the accessory that matters to the answer, so with them
    // there is nothing more to see on the Mac.
    const BOOL hasUndescribedAccessory = _accessory != nil && inputs.count == 0;
    return [[iTermModalAlertDescriptor alloc] initWithHeading:alert.messageText
                                                         body:alert.informativeText
                                                      buttons:buttons ?: @[]
                                             suppressionLabel:alert.showsSuppressionButton ? alert.suppressionButton.title : nil
                                                       inputs:inputs ?: @[]
                                                 hasAccessory:hasUndescribedAccessory
                                                   isAppModal:appModal];
}

// Publishes `alert`, which is about to be shown, so the companion app can show it and press a
// button. Returns nil if this warning opted out. The caller unregisters when the alert is gone.
- (iTermModalAlertRegistration *)registerAlert:(NSAlert *)alert appModal:(BOOL)appModal {
    if (!_remotelyAnswerable) {
        return nil;
    }
    // A headless alert (tests) runs no real modal session, so there is no window for the registry
    // to compare against the one in front.
    NSWindow *window = gRunsHeadlessModals ? nil : alert.window;
    return [[iTermModalAlertRegistry shared] registerAlert:[self modalAlertDescriptorForAlert:alert appModal:appModal]
                                                    window:window
                                                     press:[self modalAlertPressBlockForAlert:alert]];
}

- (NSAlert *)makeAlertForRemoteAnswer {
    [self resolveActionRoles];
    return [self makeAlert];
}

- (BOOL (^)(NSInteger, BOOL, NSDictionary<NSString *, NSString *> *))modalAlertPressBlockForAlert:(NSAlert *)alert {
    __weak NSAlert *weakAlert = alert;
    __weak __typeof(self) weakSelf = self;
    return ^BOOL(NSInteger buttonIndex, BOOL suppress, NSDictionary<NSString *, NSString *> *inputs) {
        NSAlert *strongAlert = weakAlert;
        iTermWarning *strongSelf = weakSelf;
        if (!strongAlert || !strongSelf) {
            return NO;
        }
        NSArray<iTermWarningAction *> *actions = strongSelf.warningActions;
        if (buttonIndex < 0 || buttonIndex >= actions.count || buttonIndex >= strongAlert.buttons.count) {
            return NO;
        }
        // A click on a disabled button does nothing. Reporting it as a press would leave the
        // other end waiting for an alert that is not going away. Nor may a hidden button be
        // pressed: the user at this Mac could not.
        NSButton *button = strongAlert.buttons[buttonIndex];
        if (!button.isEnabled || button.isHidden) {
            return NO;
        }
        // Check every value before changing any control, so a refused press changes nothing.
        NSArray<iTermWarningRemoteInput *> *remoteInputs = strongSelf.remoteInputs;
        for (iTermWarningRemoteInput *input in remoteInputs) {
            NSString *value = inputs[input.identifier];
            if (value && ![input acceptsValue:value]) {
                return NO;
            }
        }
        for (iTermWarningRemoteInput *input in remoteInputs) {
            NSString *value = inputs[input.identifier];
            if (value) {
                [input applyValue:value];
            }
        }
        // -handleResult:alert: reads the box's state when it handles the click, and would persist
        // the choice even for a warning that shows no box. So check it only when the warning has
        // one and this action may be remembered.
        if (suppress &&
            strongAlert.showsSuppressionButton &&
            [strongSelf shouldRememberAction:actions[buttonIndex]]) {
            strongAlert.suppressionButton.state = NSControlStateValueOn;
        }
        // The same as a mouse click: ends the modal session (or sheet) with this button's code.
        [button performClick:nil];
        return YES;
    };
}

- (iTermWarningSelection)runModalImpl {
    [self resolveActionRoles];
    iTermWarningSelection preemptedSelection;
    if ([self preempt:&preemptedSelection]) {
        return preemptedSelection;
    }

    NSAlert *alert = [self makeAlert];

    NSInteger result;
    if (gWarningHandler) {
        result = [gWarningHandler warningWouldShowAlert:alert identifier:_identifier];
    } else {
        DLog(@"Show warning %@\n%@", self, [NSThread callStackSymbols]);
        gShowingWarning = YES;
        // Registered just before the modal loop starts and unregistered as soon as it ends, before
        // -handleResult:alert: (which may show this warning again, registering anew).
        iTermModalAlertRegistration *registration = [self registerAlert:alert appModal:YES];
        if (gRunsHeadlessModals) {
            result = [[[iTermHeadlessModalSession alloc] initWithAlert:alert completion:nil] runUntilFinished];
        } else if (self.window) {
            result = [alert runSheetModalForWindow:self.window];
        } else {
            result = [alert runModal];
        }
        [registration unregister];
        DLog(@"Result for %@ is %@", self, @(result));
        gShowingWarning = NO;
    }

    return [self handleResult:result alert:alert];
}

- (BOOL)shouldRememberAction:(iTermWarningAction *)action {
    // Cancel choices and explicitly-not-remembered actions are never persisted. Uses structural
    // flags (resolved once in -resolveActionRoles) rather than comparing localized label strings.
    if (action.isCancel || action.neverRemember) {
        return NO;
    }
    return YES;
}

- (iTermWarningSelection)handleResult:(NSInteger)result alert:(NSAlert *)alert {
    // Check if "Permanently Forget Saved Selection" button was clicked.
    // This button is added after all the regular action buttons.
    if (_shownDueToRememberedAlertsMode && _identifier) {
        NSInteger forgetButtonIndex = NSAlertFirstButtonReturn + _warningActions.count;
        if (result == forgetButtonIndex) {
            RLog(@"Permanently forget saved selection for %@", _identifier);
            [self.class clearSavedSelectionForIdentifier:_identifier];
            // Re-show the alert without the remembered alerts mode explanatory text.
            // Create a fresh warning with the same parameters but without the remembered mode flag.
            self.shownDueToRememberedAlertsMode = NO;
            self.savedSelectionLabel = nil;
            return [self runModalImpl];
        }
    }

    BOOL remember = NO;
    iTermWarningSelection selection;
    switch (result) {
        case NSAlertFirstButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection0 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[0]];
            break;
        case NSAlertSecondButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection1 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[1]];
            break;
        case NSAlertThirdButtonReturn:
            selection = [self.class remapSelection:kiTermWarningSelection2 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[2]];
            break;
        case NSAlertThirdButtonReturn + 1:
            selection = [self.class remapSelection:kiTermWarningSelection3 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[3]];
            break;
        case NSAlertThirdButtonReturn + 2:
            selection = [self.class remapSelection:kiTermWarningSelection4 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[4]];
            break;
        case NSAlertThirdButtonReturn + 3:
            selection = [self.class remapSelection:kiTermWarningSelection5 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[5]];
            break;
        case NSAlertThirdButtonReturn + 4:
            selection = [self.class remapSelection:kiTermWarningSelection6 withMapping:_actionToSelectionMap];
            remember = [self shouldRememberAction:_warningActions[6]];
            break;
        default:
            selection = kItermWarningSelectionError;
    }

    // Save info if suppression was enabled.
    if (remember && alert.suppressionButton.state == NSControlStateValueOn) {
        RLog(@"Remember selection for %@", self);
        NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
        if (_warningType == kiTermWarningTypeTemporarilySilenceable) {
            NSString *theKey = [self.class temporarySilenceKeyForIdentifier:_identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kTemporarySilenceTime
                             forKey:theKey];
        } else if (_warningType == kiTermWarningTypeSilenceableForOneMonth) {
            NSString *theKey = [self.class temporarySilenceKeyForIdentifier:_identifier];
            [userDefaults setDouble:[NSDate timeIntervalSinceReferenceDate] + kOneMonthTime
                             forKey:theKey];
        } else {
            NSString *theKey = [self.class permanentlySilenceKeyForIdentifier:_identifier];
            [userDefaults setBool:YES forKey:theKey];
        }
        [[iTermUserDefaults userDefaults] setObject:@(selection)
                                                  forKey:[self.class selectionKeyForIdentifier:_identifier]];
    }
    DLog(@"Return selection %@ for %@", @(selection), self);
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
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
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

+ (NSString *)silenceEpisodeTokenForIdentifier:(NSString *)identifier {
    if (!identifier) {
        return nil;
    }
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    if ([userDefaults boolForKey:[self permanentlySilenceKeyForIdentifier:identifier]]) {
        return @"permanent";
    }
    const NSTimeInterval until = [userDefaults doubleForKey:[self temporarySilenceKeyForIdentifier:identifier]];
    if (until > [NSDate timeIntervalSinceReferenceDate]) {
        // A new temporary/monthly silence gets a new expiry, so this changes when
        // a fresh silence episode begins after an earlier one lapsed.
        return [NSString stringWithFormat:@"until:%@", @(until)];
    }
    return nil;
}

+ (NSNumber *)conditionalSavedSelectionForIdentifier:(NSString *)identifier {
    if (![self identifierIsSilenced:identifier]) {
        return nil;
    }
    const iTermWarningSelection selection = [self savedSelectionForIdentifier:identifier];
    return @(selection);
}

+ (NSString *)selectionKeyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"%@_selection", identifier];
}

+ (iTermWarningSelection)savedSelectionForIdentifier:(NSString *)identifier {
    NSString *theKey = [self selectionKeyForIdentifier:identifier];
    return [[iTermUserDefaults userDefaults] integerForKey:theKey];
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
