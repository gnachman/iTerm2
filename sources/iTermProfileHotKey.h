#import "iTermBaseHotKey.h"
#import "iTermWeakReference.h"
#import "NSDictionary+iTerm.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"

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

@property(nonatomic, readonly) BOOL autoHides;

// Is there a visible hotkey window right now?
@property(nonatomic, readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

// When the pressing of a hotkey causes a new window to be created, the window controller is stored
// here temporarily before the window is fully created. This is used for finding siblings of such a
// partially formed window so that when it becomes key its sibilings don't get hidden.
@property(nonatomic, readonly) NSWindowController *windowControllerBeingBorn;

@property(nonatomic, readonly) PseudoTerminal<iTermWeakReference> *windowController;
@property(nonatomic) BOOL wasAutoHidden;

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
          hasModifierActivation:(BOOL)hasModifierActivation
             modifierActivation:(iTermHotKeyModifierActivation)modifierActivation
                        profile:(Profile *)profile NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
          hasModifierActivation:(BOOL)hasModifierActivation
             modifierActivation:(iTermHotKeyModifierActivation)modifierActivation NS_UNAVAILABLE;

// Hide the hotkey window. If `suppressHideApp` is set then do not hide and then unhide
// iTerm after the hotkey window is dismissed (which would normally happen if iTerm2 was not the
// active app when the hotkey window was shown). The hide-unhide cycles moves all the iTerm2 windows
// behind the next app.
- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp;

// Erase the restorable state since it won't be needed after the last session is gone. We wouldn't
// want to restore a defunct session.
- (void)windowWillClose;

@end

@interface iTermProfileHotKey(Internal)

- (void)createWindow;
- (void)showHotKeyWindow;
- (void)saveHotKeyWindowState;
- (void)loadRestorableStateFromArray:(NSArray *)states;
- (void)setLegacyState:(NSDictionary *)state;

@end