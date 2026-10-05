#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermModalAlertDescriptor;

extern BOOL gShowRememberedAlerts;

@protocol iTermWarningHandler <NSObject>

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString * _Nullable)identifier;

@end
// The type of warning.
typedef NS_ENUM(NSInteger, iTermWarningType) {
    kiTermWarningTypePersistent,
    kiTermWarningTypePermanentlySilenceable,
    kiTermWarningTypeTemporarilySilenceable,  // 10 minutes
    kiTermWarningTypeSilenceableForOneMonth  // 30 days
};

typedef NS_ENUM(NSInteger, iTermWarningSelection) {
    kiTermWarningSelection0,  // First passed-in action
    kiTermWarningSelection1,  // Second passed-in action
    kiTermWarningSelection2,  // Third passed-in action
    kiTermWarningSelection3,  // Fourth passed-in action
    kiTermWarningSelection4,  // Fifth passed-in action
    kiTermWarningSelection5,  // Sixth passed-in action
    kiTermWarningSelection6,  // Seventh passed-in action
    kItermWarningSelectionError,  // Something went wrong.
};

typedef void(^iTermWarningActionBlock)(iTermWarningSelection);

// Encapsulates a label and an optional block that's called when the action is
// selected.
@interface iTermWarningAction : NSObject

@property (nonatomic, strong) NSString * _Nullable keyEquivalent;
@property (nonatomic) BOOL destructive;

+ (instancetype)warningActionWithLabel:(NSString *)label
                                 block:(iTermWarningActionBlock _Nullable)block;

@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) iTermWarningActionBlock _Nullable block;

// Structural identity, independent of the (localized) label. isCancel marks the Cancel/dismiss
// action: it is excluded from the "remember my choice" affordance and its choice is never
// persisted. neverRemember marks any other action whose choice should not be remembered. Object-
// API callers may set these directly; the label-array API resolves them from cancelLabel /
// doNotRememberLabels at show time, so the runtime never compares against a hardcoded @"Cancel".
@property(nonatomic) BOOL isCancel;
@property(nonatomic) BOOL neverRemember;

// Set for an action that only makes sense at this Mac, such as one that opens another window here.
// The companion app does not show its button and cannot press it.
@property(nonatomic) BOOL notOfferedRemotely;

@end

// Describes one control in a warning's accessory view whose value the paired companion app may set
// before it presses a button, so a warning that asks for input can be answered completely from
// the phone. The phone shows a field with `label` and the control's current value, and sends back
// what the user entered.
@interface iTermWarningRemoteInput : NSObject

// Stable name for this input within its warning. Not shown to the user.
@property(nonatomic, readonly) NSString *identifier;
// The control's label, already localized, or nil if the warning's text says what is being asked.
@property(nonatomic, readonly, nullable) NSString *label;
// YES for a whole number in [minimum, maximum]; NO for free text.
@property(nonatomic, readonly) BOOL isInteger;
@property(nonatomic, readonly) NSInteger minimum;
@property(nonatomic, readonly) NSInteger maximum;
// YES for a password or other secret. The phone shows an obscured field, and what the control
// holds is never sent to it: currentValue is always empty.
@property(nonatomic, readonly) BOOL isSecret;

// What the control holds now.
- (NSString *)currentValue;
// Whether `value` could be put in the control. Text always can; an integer must parse and be in
// range.
- (BOOL)acceptsValue:(NSString *)value;
// Put `value` in the control, as if the user had typed it. Only call with an accepted value.
- (void)applyValue:(NSString *)value;

// A free-text input backed by `textField`.
+ (instancetype)textInputWithIdentifier:(NSString *)identifier
                                  label:(NSString * _Nullable)label
                              textField:(NSTextField *)textField;

// A secret, such as a password, backed by `textField` (normally an NSSecureTextField). What the
// phone sends is put in the field; what the field holds is never sent to the phone.
+ (instancetype)secretInputWithIdentifier:(NSString *)identifier
                                    label:(NSString * _Nullable)label
                                textField:(NSTextField *)textField;

// A whole-number input. `getter` reads the current value and `setter` stores a new one; the
// setter is only called with a value in [minimum, maximum].
+ (instancetype)integerInputWithIdentifier:(NSString *)identifier
                                     label:(NSString * _Nullable)label
                                   minimum:(NSInteger)minimum
                                   maximum:(NSInteger)maximum
                                    getter:(NSInteger (^)(void))getter
                                    setter:(void (^)(NSInteger value))setter;

- (instancetype)init NS_UNAVAILABLE;

@end

// Recommended usage:
/*
    iTermWarningAction *cancel = [iTermWarningAction warningActionWithLabel:@"Cancel" block:nil];
    iTermWarningAction *doStuff =
        [iTermWarningAction warningActionWithLabel:@"Do Stuff"
                                             block:^(iTermWarningSelection selection) {
            DoStuff();
        }];
    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = @"This is the main text for the warning.";      // TODO: CUSTOMIZE THIS
    warning.warningActions = @[ doStuff, cancel ];                  // TODO: CUSTOMIZE THIS
    warning.identifier = @"NoSyncSuppressDoStuffWarning";           // TODO: CUSTOMIZE THIS
    warning.warningType = kiTermWarningTypePermanentlySilenceable;  // TODO: CUSTOMIZE THIS
    [warning runModal];
*/

@interface iTermWarning : NSObject

// Used to unsilence a particular selection (e.g., when you have a bug and silence the Cancel selection).
+ (void)unsilenceIdentifier:(NSString * _Nullable)identifier ifSelectionEquals:(iTermWarningSelection)problemSelection;
+ (void)unsilenceIdentifier:(NSString * _Nullable)identifier;
+ (void)setIdentifier:(NSString * _Nullable)identifier permanentSelection:(iTermWarningSelection)selection;
+ (BOOL)identifierIsSilenced:(NSString * _Nullable)identifier;
// A token identifying the current silence episode, or nil if not silenced. It
// changes when a fresh silence episode begins (e.g. re-silencing after a
// temporary silence lapsed), so callers can tell one episode from the next.
+ (NSString * _Nullable)silenceEpisodeTokenForIdentifier:(NSString * _Nullable)identifier;
+ (void)setIdentifier:(NSString *)identifier isSilenced:(BOOL)silenced;

// Whether to show alerts even when they have a remembered selection. Toggled via
// the Suppressed Alerts panel. Backed by the gShowRememberedAlerts global, which
// is read directly in hot drawing paths.
@property (class, nonatomic) BOOL showRememberedAlerts;

// Remove the saved selection for a specific identifier.
+ (void)clearSavedSelectionForIdentifier:(NSString *)identifier;

// Tests can use this to prevent warning popups.
+ (void)setWarningHandler:(id<iTermWarningHandler>)handler;
+ (id<iTermWarningHandler>)warningHandler;

// Tells warnings which terminal sessions a window holds, so a warning attached to a window can be
// tied to them for the companion app (see sessionGuid). A block, set by the code that knows about
// terminal windows, so this class need not. Called on the main thread.
+ (void)setSessionGuidResolver:(NSArray<NSString *> * _Nonnull (^ _Nullable)(NSWindow *window))resolver;

// For tests. While YES, a warning that would be shown is not put on screen. It still builds its
// alert and blocks the way a real one does (runModal spins a nested run loop in the modal panel
// mode; a sheet started with runModalAsync: does not block), until one of the alert's buttons is
// clicked programmatically or +cancelHeadlessModals is called. Unlike a warning handler, the
// warning goes through everything else it normally does around showing an alert.
+ (void)setRunsHeadlessModals:(BOOL)headless;
+ (BOOL)runsHeadlessModals;

// Ends every headless modal that is waiting, as if it had been aborted: each reports
// kItermWarningSelectionError. Safe to call from inside a headless modal's run loop.
+ (void)cancelHeadlessModals;
+ (BOOL)showingWarning;
// Nil if nothing saved, otherwise an iTermWarningSelection.
+ (NSNumber * _Nullable)conditionalSavedSelectionForIdentifier:(NSString *)identifier;

// Show a warning, optionally with a suppression checkbox. It may not be shown
// if it was previously suppressed.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                       window:(NSWindow * _Nullable)window;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView * _Nullable)accessory
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                       window:(NSWindow * _Nullable)window;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView * _Nullable)accessory
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString * _Nullable)heading
                                       window:(NSWindow * _Nullable)window;

// actionToSelectionMap gives the iTermWarningSelection that should be returned for each entry in
// actions. It must be in 1:1 correspondence with actions. It is useful because it allows you to add
// a new action in the middle of the actions array without invalidating a saved selection. If nil
// then the first selection is Selection0, second is Selection1, etc. For example, if you originally
// had actions = [ "Hide", "Kill" ] and a user saved "Kill" as their default, then NSUserDefaults
// would store a value of kiTermWarningSelection1. If you then change actions to [ "Hide", "Cancel", "Kill" ],
// you want Kill to still be iTermWarningSelection1, even though Cancel is in the second position,
// so the saved preference will be respected. In that case, you'd use an actionToSelectionMap of
// [ kiTermWarningSelection0, kiTermWarningSelection2, kItermWarningSelection1 ], which has the
// effect of making Cancel return Selection2 even though it's in the second position.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> * _Nullable)actionToSelectionMap
                                    accessory:(NSView * _Nullable)accessory
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString * _Nullable)heading
                                       window:(NSWindow * _Nullable)window;

// cancelLabel is the action name to treat like "Cancel". It won't be remembered.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> * _Nullable)actionToSelectionMap
                                    accessory:(NSView * _Nullable)accessory
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString * _Nullable)heading
                                  cancelLabel:(NSString * _Nullable)cancelLabel
                                       window:(NSWindow * _Nullable)window;

+ (void)asyncShowWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> * _Nullable)actionToSelectionMap
                                    accessory:(NSView * _Nullable)accessory
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString * _Nullable)heading
                                  cancelLabel:(NSString * _Nullable)cancelLabel
                                       window:(NSWindow * _Nullable)window
                       completion:(void (^)(iTermWarningSelection selection,
                                            iTermWarning *warning))completion;

// As above, with the accessory's controls described for the companion app (see remoteInputs).
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView * _Nullable)accessory
                                 remoteInputs:(NSArray<iTermWarningRemoteInput *> * _Nullable)remoteInputs
                                   identifier:(NSString * _Nullable)identifier
                                  silenceable:(iTermWarningType)warningType
                                       window:(NSWindow * _Nullable)window;

// If you prefer you can set the properties you care about and then invoke runModal.

// Main text to display.
@property(nonatomic, copy) NSString *title;

// Strings to display in buttons. This is computed from warningActions.
@property(nonatomic, retain) NSArray<NSString *> *actionLabels;

// 1:1 with buttons to show. First button is default.
@property(nullable, nonatomic, retain) NSArray<iTermWarningAction *> *warningActions;

// Optional. Should be 1:1 with actions. Provides a mapping from the index of the button actually
// pressed to the index runModal reports.
@property(nullable, nonatomic, retain) NSArray<NSNumber *> *actionToSelectionMap;

// Optional view to show below main text.
@property(nonatomic, retain) NSView * _Nullable accessory;

// String used as a user defaults key to remember the user's preference.
@property(nonatomic, copy) NSString * _Nullable identifier;

// What kind of suppression options are available.
@property(nonatomic, assign) iTermWarningType warningType;

// Optional. Changes the bold heading on the warning.
@property(nonatomic, copy) NSString * _Nullable heading;

// Optional. An action whose string is equal to `cancelLabel` won't be remembered.
@property(nonatomic, copy) NSString * _Nullable cancelLabel;

// Optional. Actions whose strings are in `doNotRememberLabels` won't be remembered.
@property(nonatomic, copy) NSArray<NSString *> * _Nullable doNotRememberLabels;

// If set then a "help" button is added to the alert box and this block is invoked when it is clicked.
@property(nullable, nonatomic, copy) void (^showHelpBlock)(void);

// Whether the paired companion app may see this warning and press one of its buttons while it is
// showing (see iTermModalAlertRegistry). Defaults to YES, so every warning is answerable from the
// phone unless its call site sets this to NO. No call site does yet. Set it to NO for a warning
// that must be answered at this Mac.
//
// The accessory view itself is never sent. If it holds controls whose values matter to the answer,
// describe them in remoteInputs so the phone can show and set them. Otherwise the phone is told
// only that an accessory exists, and can still press any button, which for an accessory that takes
// input means confirming contents the user has not seen.
@property(nonatomic) BOOL remotelyAnswerable;

// The terminal session this warning is about, if its caller knows. The companion app interrupts
// with the warning only while the user is looking at a session it is about (or when the warning
// has the whole app blocked). When nil, the sessions are taken from `window`: see
// +setSessionGuidResolver:.
@property(nullable, nonatomic, copy) NSString *sessionGuid;

// The controls in `accessory` that the companion app may set before pressing a button. Setting
// this declares that they are everything in the accessory that matters to the answer, so the phone
// does not tell the user that more is shown on the Mac.
@property(nullable, nonatomic, copy) NSArray<iTermWarningRemoteInput *> *remoteInputs;

// A checkbox in `accessory` that the companion app shows and sets the way it does a warning's
// own "don't ask again" box: for example "Remember this password". Only for a warning that has no
// box of its own (kiTermWarningTypePersistent). The phone starts from the checkbox's state, and
// what the phone chose is put in it before a button is pressed, whichever button that is.
@property(nullable, nonatomic, strong) NSButton *remoteCheckbox;

@property(nonatomic, retain) NSWindow * _Nullable window;
@property(nonatomic, retain) NSView * _Nullable initialFirstResponder;

// Set to YES when this warning is being shown because "always show alerts with remembered selections" is on (a checkbox in the Suppressed Alerts panel).
@property(nonatomic) BOOL shownDueToRememberedAlertsMode;
// The label of the saved selection (set when shownDueToRememberedAlertsMode is YES).
@property(nonatomic, copy) NSString * _Nullable savedSelectionLabel;

// Modally show the alert. Returns the selection.
- (iTermWarningSelection)runModal;
- (void)runModalAsync:(void (^)(iTermWarningSelection result, iTermWarning *warning))completion;

// How this warning would be described to iTermModalAlertRegistry if it were shown now. Builds the
// alert without showing it. Nil when the warning is not remotelyAnswerable. For tests.
- (iTermModalAlertDescriptor * _Nullable)modalAlertDescriptorWhenAppModal:(BOOL)appModal;

// Builds this warning's alert without showing it. For tests.
- (NSAlert *)makeAlertForRemoteAnswer;

// The block iTermModalAlertRegistry calls to press a button on `alert` (which must be one this
// warning made). It checks the suppression box first if `suppress` is set, the alert has one, and
// that button's choice may be remembered; then it clicks the button. Before either, it puts each
// value in `inputs` (keyed by remote input identifier) into its control; an input whose identifier
// is absent keeps what it holds. Returns NO, changing and clicking nothing, if the index is not one
// of this warning's actions, the button is disabled or hidden, a value is not acceptable to its
// input, or the alert is gone. Holds the alert weakly.
- (BOOL (^)(NSInteger buttonIndex, BOOL suppress, NSDictionary<NSString *, NSString *> *inputs))modalAlertPressBlockForAlert:(NSAlert *)alert;

@end

NS_ASSUME_NONNULL_END
