//
//  iTermShortcutInputView.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermShortcutInputView.h"
#import "iTermKeyBindingMgr.h"

@implementation iTermShortcutInputView

+ (instancetype)firstResponder {
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    if (![firstResponder isKindOfClass:[NSTextView class]]) {
        return nil;
    }
    NSTextView *fieldEditor = (NSTextView *)firstResponder;
    id<NSTextViewDelegate> fieldEditorDelegate = fieldEditor.delegate;
    if ([fieldEditorDelegate isKindOfClass:[iTermShortcutInputView class]]) {
        return (iTermShortcutInputView *)fieldEditorDelegate;
    } else {
        return nil;
    }
}

- (void)handleShortcutEvent:(NSEvent *)event {
    [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
    [[self window] makeFirstResponder:[self window]];
}

- (void)setEnabled:(BOOL)flag {
    [super setEnabled:flag];
    [self setEditable:flag];
    [self setSelectable:flag];
}

- (void)setKeyCode:(NSUInteger)code
         modifiers:(NSEventModifierFlags)modifiers
         character:(NSUInteger)character {
    NSString *identifier = [self identifierForCode:code modifiers:modifiers character:character];
    if (identifier) {
        self.stringValue = [iTermKeyBindingMgr formatKeyCombination:identifier];
    } else {
        self.stringValue = @"";
    }
}

- (NSString *)identifierForCode:(NSUInteger)code
                      modifiers:(NSEventModifierFlags)modifiers
                      character:(NSUInteger)character {
    if (code || character) {
        return [NSString stringWithFormat:@"0x%x-0x%x", (int)character, (int)modifiers];
    } else {
        return nil;
    }
}

@end
