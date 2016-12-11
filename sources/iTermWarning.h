#import <Cocoa/Cocoa.h>

@protocol iTermWarningHandler <NSObject>

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier;

@end
// The type of warning.
typedef NS_ENUM(NSInteger, iTermWarningType) {
    kiTermWarningTypePersistent,
    kiTermWarningTypePermanentlySilenceable,
    kiTermWarningTypeTemporarilySilenceable  // 10 minutes
};

typedef NS_ENUM(NSInteger, iTermWarningSelection) {
    kiTermWarningSelection0,  // First passed-in action
    kiTermWarningSelection1,  // Second passed-in action
    kiTermWarningSelection2,  // Third passed-in action
    kItermWarningSelectionError,  // Something went wrong.
};

typedef void(^iTermWarningActionBlock)(iTermWarningSelection);

// Encpasulates a label and an optional block that's called when the action is
// selected.
@interface iTermWarningAction : NSObject

+ (instancetype)warningActionWithLabel:(NSString *)label
                                 block:(iTermWarningActionBlock)block;

@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) iTermWarningActionBlock block;

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
+ (void)unsilenceIdentifier:(NSString *)identifier ifSelectionEquals:(iTermWarningSelection)problemSelection;
+ (BOOL)identifierIsSilenced:(NSString *)identifier;

// Tests can use this to prevent warning popups.
+ (void)setWarningHandler:(id<iTermWarningHandler>)handler;
+ (id<iTermWarningHandler>)warningHandler;
+ (BOOL)showingWarning;

// Show a warning, optionally with a suppression checkbox. It may not be shown
// if it was previously suppressed.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading;

// actionToSelectionMap gives the iTermWarningSelection that should be returned for each entry in
// actions. It must be in 1:1 correspondence with actions. It is useful because it allows you to add
// a new action in the middle of the actions array without invalidating a saved selection. If nil
// then the first selection is Selection0, second is Selection1, etc. For example, if you originally
// had actions = [ "Hide", "Kill" ] and a user saved "Kill" as their default, then NSUserDefaults
// would store a value of kiTermWarningSelection1. If you then change actions to [ "Hide", "Cancel", "Kill" ],
// you want Kill to still be iTermWarningSelection1, even though Cancel is in the second position,
// so the saved preference will be respected. In that case, you'd use an actionToSelectionMap of
// [ kiTermWawrningSelection0, kiTermWarningSelection2, kItermWarningSelection1 ], which has the
// effect of making Cancel return Selection2 even though it's in the second position.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading;

// cancelLabel is the action name to treat like "Cancel". It won't be remembered.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                actionMapping:(NSArray<NSNumber *> *)actionToSelectionMap
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading
                                  cancelLabel:(NSString *)cancelLabel;


// If you prefer you can set the properties you care about and then invoke runModal.

// Main text to display.
@property(nonatomic, copy) NSString *title;

// Strings to display in buttons. This is computed from warningActions.
@property(nonatomic, retain) NSArray<NSString *> *actionLabels;

// 1:1 with buttons to show. First button is default.
@property(nonatomic, retain) NSArray<iTermWarningAction *> *warningActions;

// Optional. Should be 1:1 with actions. Provides a mapping from the index of the button actually
// pressed to the index runModal reports.
@property(nonatomic, retain) NSArray<NSNumber *> *actionToSelectionMap;

// Optional view to show below main text.
@property(nonatomic, retain) NSView *accessory;

// String used as a user defaults key to remember the user's preference.
@property(nonatomic, copy) NSString *identifier;

// What kind of suppression options are availble.
@property(nonatomic, assign) iTermWarningType warningType;

// Optional. Changes the bold heading on the warning.
@property(nonatomic, copy) NSString *heading;

// Optional. An action whose string is equal to `cancelLabel`
@property(nonatomic, copy) NSString *cancelLabel;

// If set then a "help" button is added to the alert box and this block is invoked when it is clicked.
@property(nonatomic, copy) void (^showHelpBlock)();

// Modally show the alert. Returns the selection.
- (iTermWarningSelection)runModal;

@end
