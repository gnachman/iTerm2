//
//  iTermStatusBarLargeComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarLargeComposerViewController.h"
#import "NSEvent+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"

@interface iTermComposerView : NSView
@end

@implementation iTermComposerTextView

- (BOOL)it_preferredFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    const BOOL pressedEsc = ([event.characters isEqualToString:@"\x1b"]);
    const BOOL pressedShiftEnter = ([event.characters isEqualToString:@"\r"] &&
                                    (event.it_modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift);
    if (pressedShiftEnter || pressedEsc) {
        [self.composerDelegate composerTextViewDidFinishWithCancel:pressedEsc];
        return;
    }
    [super keyDown:event];
}

- (BOOL)resignFirstResponder {
    if ([self.composerDelegate respondsToSelector:@selector(composerTextViewDidResignFirstResponder)]) {
        [self.composerDelegate composerTextViewDidResignFirstResponder];
    }
    return [super resignFirstResponder];
}

@end

@implementation iTermComposerView {
    NSView *_backgroundView;
}

- (NSView *)newBackgroundViewWithFrame:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        NSVisualEffectView *myView = [[NSVisualEffectView alloc] initWithFrame:frame];
        myView.appearance = self.appearance;
        return myView;
    }

    SolidColorView *solidColorView = [[SolidColorView alloc] initWithFrame:frame
                                                                     color:[NSColor controlBackgroundColor]];
    return solidColorView;
}

- (void )viewDidMoveToWindow {
    [self updateBackgroundView];
    [super viewDidMoveToWindow];
}

- (void)updateBackgroundView {
    if ([NSStringFromClass(self.window.class) containsString:@"Popover"]) {
        NSView *privateView = [[self.window contentView] superview];
        [_backgroundView removeFromSuperview];
        _backgroundView = [self newBackgroundViewWithFrame:privateView.bounds];
        _backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [privateView addSubview:_backgroundView positioned:NSWindowBelow relativeTo:privateView];
    }
}

- (void)setAppearance:(NSAppearance *)appearance {
    if (appearance != self.appearance) {
        [super setAppearance:appearance];
        [self updateBackgroundView];
    }
}
@end

@interface iTermStatusBarLargeComposerViewController ()

@end

@implementation iTermStatusBarLargeComposerViewController

- (void)awakeFromNib {
    [super awakeFromNib];
    self.textView.textColor = [NSColor textColor];
    self.textView.font = [NSFont fontWithName:@"Menlo" size:11];
}

@end
