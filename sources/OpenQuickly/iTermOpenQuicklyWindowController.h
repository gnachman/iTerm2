#import <Cocoa/Cocoa.h>

// Window controller for the "open quickly" window, which lets you select a tab
// by doing a textual query for it.
@interface iTermOpenQuicklyWindowController : NSWindowController

+ (instancetype)sharedInstance;
- (void)presentWindow;

// Presents the window in the mode of `commandClass` (an iTermOpenQuicklyCommand
// subclass): the query field starts with its prefix, such as “/g ”, and the
// cursor after it. If the window is already open, what was typed is kept.
- (void)presentWindowWithCommand:(Class)commandClass;

@end
