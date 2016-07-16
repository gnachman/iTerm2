#import <Cocoa/Cocoa.h>

@interface iTermPreviousState : NSObject

// For restoring previously active app when exiting hotkey window.
@property(nonatomic, copy) NSNumber *previouslyActiveAppPID;

// Set when iTerm was key at the time the hotkey window was opened.
@property(nonatomic) BOOL itermWasActiveWhenHotkeyOpened;

- (void)restore;
- (void)restorePreviouslyActiveApp;
- (void)suppressHideApp;

@end
