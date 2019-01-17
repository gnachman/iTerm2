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

@implementation iTermComposerView

- (NSView *)newBackgroundViewWithFrame:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        NSVisualEffectView *myView = [[NSVisualEffectView alloc] initWithFrame:frame];
        myView.material = NSVisualEffectMaterialContentBackground;
        return myView;
    }

    SolidColorView *solidColorView = [[SolidColorView alloc] initWithFrame:frame
                                                                     color:[NSColor controlBackgroundColor]];
    return solidColorView;
}

- (void )viewDidMoveToWindow {
    NSView *privateView = [[self.window contentView] superview];
    NSView *myView = [self newBackgroundViewWithFrame:privateView.bounds];
    myView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [privateView addSubview:myView positioned:NSWindowBelow relativeTo:privateView];
    [super viewDidMoveToWindow];
}

@end

@interface iTermStatusBarLargeComposerViewController ()

@end

@implementation iTermStatusBarLargeComposerViewController

@end
