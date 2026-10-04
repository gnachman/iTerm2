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
// showing (see iTermModalAlertRegistry). Defaults to YES. Set to NO for a warning that has to be
// answered at this Mac, such as one about the companion pairing itself.
@property(nonatomic) BOOL remotelyAnswerable;

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
// that button's choice may be remembered; then it clicks the button. Returns NO, clicking nothing,
// if the index is not one of this warning's actions or the alert is gone. Holds the alert weakly.
- (BOOL (^)(NSInteger buttonIndex, BOOL suppress))modalAlertPressBlockForAlert:(NSAlert *)alert;

@end

NS_ASSUME_NONNULL_END
