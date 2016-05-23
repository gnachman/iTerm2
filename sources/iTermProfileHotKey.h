#import "iTermBaseHotKey.h"
#import "ProfileModel.h"

@class PseudoTerminal;

@interface iTermProfileHotKey : iTermBaseHotKey

// Hotkey windows' restorable state is saved in the application delegate because these windows are
// often ordered out, and ordered-out windows are not saved. This is assigned to when the app state
// is decoded and updated from saveHotkeyWindowState.
@property(nonatomic, readonly) NSDictionary *restorableState;

@property(nonatomic, readonly) Profile *profile;

// Is the hotkey window in the process of opening right now?
@property(nonatomic, readonly) BOOL rollingIn;
@property(nonatomic, readonly) BOOL rollingOut;

// Is there a visible hotkey window right now?
@property(nonatomic, readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

@property(nonatomic, readonly) PseudoTerminal *windowController;

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                        profile:(Profile *)profile NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers NS_UNAVAILABLE;

- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp;

- (void)windowWillClose;


@end

@interface iTermProfileHotKey(Internal)

- (void)createWindow;
- (void)showHotKeyWindow;
- (void)saveHotKeyWindowState;
- (void)loadRestorableStateFromArray:(NSArray *)states;

@end