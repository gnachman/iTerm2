#import <Cocoa/Cocoa.h>

// Window controller for the "open quickly" window, which lets you select a tab
// by doing a textual query for it.
@interface iTermOpenQuicklyWindowController : NSWindowController

+ (instancetype)sharedInstance;
- (void)presentWindow;

@end
