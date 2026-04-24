//
//  iTermSessionHotkeyController.h
//  iTerm2
//
//  Created by George Nachman on 6/27/16.
//
//

#import <Foundation/Foundation.h>
#import "iTermShortcut.h"
#import "iTermWeakReference.h"

@protocol iTermHotKeyNavigableSession<NSObject, iTermWeaklyReferenceable>
- (void)sessionHotkeyDidNavigateToSession:(iTermShortcut *)shortcut;
- (BOOL)sessionHotkeyIsAlreadyFirstResponder;
- (BOOL)sessionHotkeyIsAlreadyActiveInNonkeyWindow;
@end

// Registers carbon hotkeys for sessions that want a hotkey to navigate
// straight to them. This exists because more than one session could use the
// same hotkey. If each session were to register its own carbon hotkey then
// they'd all get callbacks and there'd be no clear arbitrator to decide who
// gets navigated to. This stores only weak refs to the sessions, but they
// still need to unregister themselves properly to avoid leaking the hotkey
// (and leaving it registered forever).
@interface iTermSessionHotkeyController : NSObject

+ (instancetype)sharedInstance;

- (void)removeSession:(id<iTermHotKeyNavigableSession>)session;
- (void)setShortcut:(iTermShortcut *)shortcut forSession:(id<iTermHotKeyNavigableSession>)session;
- (iTermShortcut *)shortcutForSession:(id<iTermHotKeyNavigableSession>)session;

@end
