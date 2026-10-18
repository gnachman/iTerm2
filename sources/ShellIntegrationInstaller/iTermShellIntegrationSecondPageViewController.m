//
//  iTermShellIntegrationSecondPageViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationSecondPageViewController.h"

#import "DebugLogging.h"

@interface iTermShellIntegrationSecondPageViewController ()

@end

@implementation iTermShellIntegrationSecondPageViewController

- (void)awakeFromNib {
    [super awakeFromNib];
    [self fitChoiceButtonsToTitles];
}

// A translation of the two choice buttons can be wider than the English. Widen both to the widest
// title, move the descriptions to their right over by the same amount, and widen the page to make
// room (the window is fitted to the page when it is shown). Then widen any right-aligned button,
// like Cancel, whose title doesn't fit, keeping its right edge.
- (void)fitChoiceButtonsToTitles {
    NSView *view = self.view;
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSView *subview in view.subviews) {
        if (![subview isKindOfClass:[NSButton class]]) {
            continue;
        }
        NSButton *button = (NSButton *)subview;
        if (button.action == @selector(downloadAndRun:) || button.action == @selector(sendShellCommands:)) {
            [buttons addObject:button];
        }
    }
    CGFloat currentWidth = 0;
    CGFloat neededWidth = 0;
    CGFloat buttonsMaxX = 0;
    for (NSButton *button in buttons) {
        currentWidth = MAX(currentWidth, NSWidth(button.frame));
        neededWidth = MAX(neededWidth, ceil(button.cell.cellSize.width));
        buttonsMaxX = MAX(buttonsMaxX, NSMaxX(button.frame));
    }
    const CGFloat delta = neededWidth - currentWidth;
    if (buttons.count > 0 && delta > 0) {
        DLog(@"Widen installer choice buttons by %@", @(delta));
        // Autoresizing moves the right-aligned buttons and widens the text at the top.
        NSRect viewFrame = view.frame;
        viewFrame.size.width += delta;
        view.frame = viewFrame;
        for (NSButton *button in buttons) {
            NSRect frame = button.frame;
            frame.size.width = neededWidth;
            button.frame = frame;
        }
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:[NSTextField class]] && NSMinX(subview.frame) >= buttonsMaxX) {
                NSRect frame = subview.frame;
                frame.origin.x += delta;
                subview.frame = frame;
            }
        }
    }
    for (NSView *subview in view.subviews) {
        if (![subview isKindOfClass:[NSButton class]] ||
            !(subview.autoresizingMask & NSViewMinXMargin)) {
            continue;
        }
        NSButton *button = (NSButton *)subview;
        NSRect frame = button.frame;
        const CGFloat width = ceil(button.cell.cellSize.width);
        if (width > NSWidth(frame)) {
            frame.origin.x = NSMaxX(frame) - width;
            frame.size.width = width;
            button.frame = frame;
        }
    }
}

- (void)setBusy:(BOOL)busy {
}

- (IBAction)downloadAndRun:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerConfirmDownloadAndRun];
}
- (IBAction)sendShellCommands:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSendShellCommands:-1];
}
@end
