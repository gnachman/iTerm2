//
//  iTermKeyboardNavigatableTableView.m
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import "iTermKeyboardNavigatableTableView.h"

@implementation iTermKeyboardNavigatableTableView

- (void)keyDown:(NSEvent *)theEvent {
  [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

// Our superclass responds to selectAll but it can't actually be used because these tables only
// allow selection of one row. If we pretend not to respond to it then iTermPopupWindowController
// gets a whack at it, and it can forward it to its owning window.
- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(selectAll:)) {
        return NO;
    } else {
        return [super respondsToSelector:aSelector];
    }
}

@end
