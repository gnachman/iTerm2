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

@end
