//
//  iTermHotkeyWindowController.h
//  iTerm2
//
//  Created by George Nachman on 6/21/16.
//
//

#import <Cocoa/Cocoa.h>

@class iTermHotKeyModel;
@class iTermHotkeyWindowController;

@protocol iTermHotKeyWindowControllerDelegate<NSObject>
- (void)hotKeyWindowController:(iTermHotkeyWindowController *)sender didFinishWithOK:(BOOL)ok;
@end

@interface iTermHotkeyWindowController : NSWindowController

@property(nonatomic, assign) IBOutlet id<iTermHotKeyWindowControllerDelegate> delegate;
@property(nonatomic, retain) iTermHotKeyModel *model;

@end
