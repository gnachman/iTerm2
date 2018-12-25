//
//  ToastWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "ToastWindowController.h"
#import "PseudoTerminal.h"
#import "RoundedRectView.h"
#import "iTermController.h"

static NSMutableArray *visibleToast;

@interface ToastWindowController ()

- (void)hideAfterDelay:(NSTimeInterval)delay;
- (void)hideToast;

@end

@implementation ToastWindowController

+ (void)initialize
{
    visibleToast = [[NSMutableArray alloc] init];
}

+ (void)showToastWithMessage:(NSString *)message {
    [self showToastWithMessage:message duration:5];
}

+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration
{
    ToastWindowController *toast = [[[ToastWindowController alloc] init] autorelease];

    NSTextField *textField = [[[NSTextField alloc] init] autorelease];
    [textField setTextColor:[NSColor whiteColor]];
    [textField setBackgroundColor:[NSColor clearColor]];
    [textField setFont:[NSFont boldSystemFontOfSize:24]];
    [textField setBordered:NO];
    [textField setStringValue:message];
    [textField setEditable:NO];
    [textField sizeToFit];

    RoundedRectView *roundedRect = [[[RoundedRectView alloc] init] autorelease];
    const int hPadding = 20;
    const int vPadding = 10;
    [roundedRect setFrame:NSMakeRect(0,
                                     0,
                                     textField.frame.size.width + hPadding * 2,
                                     textField.frame.size.height + vPadding * 2)];
    [textField setFrame:NSMakeRect(textField.frame.origin.x + hPadding,
                                   textField.frame.origin.y + vPadding,
                                   textField.frame.size.width,
                                   textField.frame.size.height)];
    [roundedRect addSubview:textField];

    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    NSScreen *screen = [NSScreen mainScreen];
    if (term) {
        screen = [[term window] screen];
    }
    NSPanel *panel = [[[NSPanel alloc] initWithContentRect:NSZeroRect
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO
                                                    screen:screen] autorelease];
    [panel setOpaque:NO];
    [panel setFrame:NSMakeRect((screen.visibleFrame.size.width - roundedRect.frame.size.width) / 2,
                               (screen.visibleFrame.size.height - roundedRect.frame.size.height) * 0.7,
                               roundedRect.frame.size.width,
                               roundedRect.frame.size.height)
            display:YES];
    [panel setContentView:roundedRect];
    [panel orderFrontRegardless];
    [toast setWindow:panel];
    [toast hideAfterDelay:duration];
    for (ToastWindowController *other in visibleToast) {
        [other hideToast];
    }
    [visibleToast addObject:toast];
}

- (void)hideAfterDelay:(NSTimeInterval)delay
{
    if (hiding_) {
        return;
    }
    if (hideTimer_) {
        [hideTimer_ invalidate];
    }
    hideTimer_ = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(hideToast) userInfo:nil repeats:NO];
}

- (void)hideToast
{
    if (hiding_) {
        return;
    }
    hiding_ = YES;
    [[self.window animator] setAlphaValue:0];
    [visibleToast performSelector:@selector(removeObject:)
                       withObject:self
                       afterDelay:[[NSAnimationContext currentContext] duration]];
}


@end
