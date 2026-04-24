//
//  PopupWindow.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Cocoa/Cocoa.h>

@interface PopupWindow : NSPanel

// I should really make this weak. I think there's enough hacks in place to
// prevent a leak. Some day when I have lots of free time I can arcify
// PseudoTerminal :)
@property (nonatomic, retain) NSWindow *owningWindow;

- (void)shutdown;
- (void)closeWithoutAdjustingWindowOrder;

@end
