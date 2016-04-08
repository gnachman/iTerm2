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

@interface iTermWarning : NSObject

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

@property(nonatomic, copy) NSString *title;
@property(nonatomic, retain) NSArray<NSString *> *actions;
@property(nonatomic, retain) NSArray<NSNumber *> *actionToSelectionMap;
@property(nonatomic, retain) NSView *accessory;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, assign) iTermWarningType warningType;
@property(nonatomic, copy) NSString *heading;
@property(nonatomic, copy) NSString *cancelLabel;
@property(nonatomic, copy) void (^showHelpBlock)();

- (iTermWarningSelection)runModal;

@end
