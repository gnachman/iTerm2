//
//  iTermShortcutInputView.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermShortcutInputView.h"

@implementation iTermShortcutInputView {
    IBOutlet id<iTermShortcutInputViewDelegate> _shortcutDelegate;
}

- (void)handleShortcutEvent:(NSEvent *)event {
    [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
}

@end
