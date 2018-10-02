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

// This is designed to be set when a window is a tmux integration window. It prevents it from getting
// restored by state restoration.
@property(nonatomic, assign) BOOL allowsStateRestoration;

@property(nonatomic, readonly) Profile *profile;

// Is the window level floating? May not be a floating panel if it doesn't meet all the criteria
// to be a panel (must join all spaces).
@property(nonatomic, readonly) BOOL floats;

// Is the hotkey window in the process of opening right now?
@property(nonatomic, readonly) BOOL rollingIn;
@property(nonatomic, readonly) BOOL rollingOut;

// A rollout is cancelable after the window has animated out but before previously active app becomes active.
@property(nonatomic, readonly) BOOL rollOutCancelable;

@property(nonatomic, assign) BOOL autoHides;

// Is there a visible hotkey window right now?
@property(nonatomic, readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

// When the pressing of a hotkey causes a new window to be created, the window controller is stored
// here temporarily before the window is fully created. This is used for finding siblings of such a
// partially formed window so that when it becomes key its siblings don't get hidden.
@property(nonatomic, readonly) NSWindowController *windowControllerBeingBorn;

// You may only set the window controller if there is not a weakly referenced object.
@property(nonatomic, retain) PseudoTerminal<iTermWeakReference> *windowController;
@property(nonatomic) BOOL wasAutoHidden;
@property(nonatomic) BOOL closedByOtherHotkeyWindowOpening;

// This is computed based on the current settings of the profile we were created with.
@property(nonatomic, readonly) iTermHotkeyWindowType hotkeyWindowType;

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
            hasModifierActivation:(BOOL)hasModifierActivation
               modifierActivation:(iTermHotKeyModifierActivation)modifierActivation
                          profile:(Profile *)profile NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
            hasModifierActivation:(BOOL)hasModifierActivation
               modifierActivation:(iTermHotKeyModifierActivation)modifierActivation NS_UNAVAILABLE;

// Hide the hotkey window. If `suppressHideApp` is set then do not hide and then unhide
// iTerm after the hotkey window is dismissed (which would normally happen if iTerm2 was not the
// active app when the hotkey window was shown). The hide-unhide cycles moves all the iTerm2 windows
// behind the next app.
- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp
                otherIsRollingIn:(BOOL)otherIsRollingIn;

// Erase the restorable state since it won't be needed after the last session is gone. We wouldn't
// want to restore a defunct session.
- (void)windowWillClose;

- (void)revealForScripting;
- (void)hideForScripting;
- (void)toggleForScripting;
- (BOOL)isRevealed;
- (void)cancelRollOut;

@end

@interface iTermProfileHotKey(Internal)

- (void)createWindow;
- (void)showHotKeyWindow;
- (BOOL)showHotKeyWindowCreatingWithURLIfNeeded:(NSURL *)url;
- (void)saveHotKeyWindowState;
- (BOOL)loadRestorableStateFromArray:(NSArray *)states;
- (void)setLegacyState:(NSDictionary *)state;

@end
