//
//  NSTextField+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/27/14.
//
//

#import "NSTextField+iTerm.h"

@implementation NSTextField (iTerm)

- (BOOL)textFieldIsFirstResponder {
    BOOL inFocus = NO;
    
    // If the textfield's widow's first responder is a text view and
    // the default editor for the text field exists and
    // the textfield is the textfield's window's first responder's delegate
    inFocus = ([[[self window] firstResponder] isKindOfClass:[NSTextView class]] &&
               [[self window] fieldEditor:NO forObject:nil] !=nil &&
               [self isEqualTo:(id)[(NSTextView *)[[self window] firstResponder] delegate]]);
    
    return inFocus;
}

@end
