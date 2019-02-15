//
//  iTermStatusBarLargeComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarLargeComposerViewController.h"
#import "SolidColorView.h"

@interface iTermComposerView : NSView
@end

@implementation iTermComposerTextView

- (void)keyDown:(NSEvent *)event {
    if ([event.characters isEqualToString:@"\r"] && event.modifierFlags & NSEventModifierFlagOption) {
        [self.composerDelegate composerTextViewDidFinish];
        return;
    }
    [super keyDown:event];
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
}

- (void)updateBackgroundView {
    NSView *privateView = [[self.window contentView] superview];
    [_backgroundView removeFromSuperview];
    _backgroundView = [self newBackgroundViewWithFrame:privateView.bounds];
    _backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [privateView addSubview:_backgroundView positioned:NSWindowBelow relativeTo:privateView];
    [super viewDidMoveToWindow];
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
}

@end
