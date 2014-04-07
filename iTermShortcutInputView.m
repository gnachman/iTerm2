//
//  iTermShortcutInputView.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermShortcutInputView.h"

@implementation iTermShortcutInputView

- (void)handleShortcutEvent:(NSEvent *)event {
    [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
    [[self window] makeFirstResponder:[self window]];
}

- (void)setEnabled:(BOOL)flag {
    [super setEnabled:flag];
    [self setEditable:flag];
    [self setSelectable:flag];
}

@end
