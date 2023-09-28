//
//  ToastWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "ToastWindowController.h"
#import "NSScreen+iTerm.h"
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


+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    NSScreen *screen = [NSScreen mainScreen];
    if (term) {
        screen = [[term window] screen];
    }
    [self showToastWithMessage:message
                      duration:duration
              screenCoordinate:NSMakePoint(NSMidX(screen.frame),
                                           NSMinY(screen.frame) + NSHeight(screen.frame) * 0.7)
                     pointSize:24];
}

+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration screenCoordinate:(NSPoint)center pointSize:(CGFloat)pointSize {
    return [self showToastWithMessage:message duration:duration screenCoordinate:center pointSize:pointSize center:YES];
}

+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration topLeftScreenCoordinate:(NSPoint)topLeft pointSize:(CGFloat)pointSize {
    return [self showToastWithMessage:message duration:duration screenCoordinate:topLeft pointSize:pointSize center:NO];
}

+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration screenCoordinate:(NSPoint)screenCoordinate pointSize:(CGFloat)pointSize center:(BOOL)center {
    ToastWindowController *toast = [[ToastWindowController alloc] init];

    NSTextField *textField = [[NSTextField alloc] init];
    [textField setTextColor:[NSColor whiteColor]];
    [textField setBackgroundColor:[NSColor clearColor]];
    [textField setFont:[NSFont boldSystemFontOfSize:pointSize]];
    [textField setBordered:NO];
    [textField setStringValue:message];
    [textField setEditable:NO];
    [textField sizeToFit];

    RoundedRectView *roundedRect = [[RoundedRectView alloc] init];
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

    NSScreen *screen = [NSScreen screenContainingCoordinate:screenCoordinate] ?: [NSScreen mainScreen];
    if (!screen) {
        return;
    }
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSZeroRect
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO
                                                   screen:screen];
    [panel setOpaque:NO];
    NSRect rect;
    if (center) {
        rect = NSMakeRect(screenCoordinate.x - roundedRect.frame.size.width / 2,
                          screenCoordinate.y - roundedRect.frame.size.height / 2,
                          roundedRect.frame.size.width,
                          roundedRect.frame.size.height);
    } else {
        rect = NSMakeRect(screenCoordinate.x,
                          screenCoordinate.y,
                          roundedRect.frame.size.width,
                          roundedRect.frame.size.height);
    }
    [panel setFrame:rect display:YES];

    NSVisualEffectView *vev = [[NSVisualEffectView alloc] init];
    vev.wantsLayer = YES;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state = NSVisualEffectStateActive;
    vev.material = NSVisualEffectMaterialContentBackground;
    [panel.contentView addSubview:vev];
    vev.frame = roundedRect.bounds;
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vev.layer.cornerRadius = 5.0;

    [panel.contentView addSubview:roundedRect];
    panel.contentView.autoresizesSubviews = YES;
    panel.backgroundColor = [NSColor clearColor];
    roundedRect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    roundedRect.frame = panel.contentView.bounds;

    [roundedRect addSubview:textField];


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
    [[self.window.contentView animator] setAlphaValue:0];
    [visibleToast performSelector:@selector(removeObject:)
                       withObject:self
                       afterDelay:[[NSAnimationContext currentContext] duration]];
}


@end
