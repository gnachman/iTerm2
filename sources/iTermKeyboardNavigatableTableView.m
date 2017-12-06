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
  if (([theEvent modifierFlags] & (NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask)) == NSControlKeyMask
	&& [theEvent keyCode] == 8) {
    [super keyDown:theEvent];
  } else {
    [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
  }
}

@end
