//
//  iTermStatusBarSetupConfigureComponentWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/5/18.
//

#import "iTermStatusBarSetupConfigureComponentWindowController.h"

@interface iTermStatusBarSetupConfigureComponentWindowController ()

@end

@interface iTermStatusBarSetupConfigureComponentContainerView : NSView
@end

@implementation iTermStatusBarSetupConfigureComponentContainerView

- (NSSize)intrinsicContentSize {
    return self.subviews.firstObject.frame.size;
}

@end

@implementation iTermStatusBarSetupConfigureComponentWindowController {
    IBOutlet NSView *_knobsView;
    NSViewController *_knobsViewController;
}

- (void)setKnobsViewController:(NSViewController *)viewController {
    _knobsViewController = viewController;
    [self.window.contentViewController addChildViewController:viewController];
    NSView *view = _knobsViewController.view;
    [_knobsView setFrameSize:view.frame.size];
    [_knobsView addSubview:view];
    [_knobsView invalidateIntrinsicContentSize];
}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

@end
