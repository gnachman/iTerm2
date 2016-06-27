#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermShortcut.h"
#import "NSDictionary+iTerm.h"


@interface iTermHotkeyPreferencesModel : NSObject

@property(nonatomic, retain) iTermShortcut *primaryShortcut;

@property(nonatomic, assign) BOOL hasModifierActivation;
@property(nonatomic, assign) iTermHotKeyModifierActivation modifierActivation;

@property(nonatomic, assign) BOOL autoHide;
@property(nonatomic, assign) BOOL showAutoHiddenWindowOnAppActivation;
@property(nonatomic, assign) BOOL animate;
@property(nonatomic, retain) NSArray<iTermShortcut *> *alternateShortcuts;
@property(nonatomic, retain) NSArray<NSDictionary *> *alternateShortcutDictionaries;

// Radio buttons
@property(nonatomic, assign) iTermHotKeyDockPreference dockPreference;


@property(nonatomic, readonly) BOOL hotKeyAssigned;
@property(nonatomic, readonly) NSDictionary<NSString *, id> *dictionaryValue;

@end

@interface iTermHotkeyPreferencesWindowController : NSWindowController

// Assign to this before using it. UI will be updated on assignemnt. Model will be updated when
// the user interacts with the UI.
@property(nonatomic, retain) iTermHotkeyPreferencesModel *model;
@property(nonatomic, copy) NSArray<iTermHotKeyDescriptor *> *descriptorsInUseByOtherProfiles;

- (void)setExplanation:(NSString *)explanation;

@end
