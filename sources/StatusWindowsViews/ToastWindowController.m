//
//  ToastWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "ToastWindowController.h"
#import <QuartzCore/QuartzCore.h>
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
    [textField setFont:[NSFont systemFontOfSize:pointSize weight:NSFontWeightMedium]];
    [textField setBordered:NO];
    [textField setStringValue:message];
    [textField setEditable:NO];
    NSShadow *textShadow = [[NSShadow alloc] init];
    textShadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.3];
    textShadow.shadowOffset = NSMakeSize(0, -1);
    textShadow.shadowBlurRadius = 2.0;
    [textField setShadow:textShadow];
    [textField sizeToFit];

    RoundedRectView *roundedRect = [[RoundedRectView alloc] init];
    const int hPadding = 28;
    const int vPadding = 14;
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

    const CGFloat cornerRadius = 10.0;
    NSSize contentSize = roundedRect.frame.size;

    // Make window larger to accommodate spring overshoot (20% extra on each side)
    const CGFloat overshootPadding = 0.2;
    CGFloat windowWidth = contentSize.width * (1.0 + overshootPadding * 2);
    CGFloat windowHeight = contentSize.height * (1.0 + overshootPadding * 2);
    CGFloat contentInset = contentSize.width * overshootPadding;
    CGFloat contentInsetY = contentSize.height * overshootPadding;

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSZeroRect
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO
                                                   screen:screen];
    [panel setOpaque:NO];
    NSRect windowRect;
    if (center) {
        windowRect = NSMakeRect(screenCoordinate.x - windowWidth / 2,
                                screenCoordinate.y - windowHeight / 2,
                                windowWidth,
                                windowHeight);
    } else {
        windowRect = NSMakeRect(screenCoordinate.x - contentInset,
                                screenCoordinate.y - contentInsetY,
                                windowWidth,
                                windowHeight);
    }
    [panel setFrame:windowRect display:YES];
    panel.backgroundColor = [NSColor clearColor];

    // Create container view centered in the window
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(contentInset, contentInsetY, contentSize.width, contentSize.height)];
    container.wantsLayer = YES;
    [panel.contentView addSubview:container];

    // Create a mask image for rounded corners
    NSImage *maskImage = [NSImage imageWithSize:contentSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:dstRect xRadius:cornerRadius yRadius:cornerRadius];
        [[NSColor blackColor] setFill];
        [path fill];
        return YES;
    }];
    maskImage.capInsets = NSEdgeInsetsMake(cornerRadius, cornerRadius, cornerRadius, cornerRadius);

    NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:container.bounds];
    vev.wantsLayer = YES;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state = NSVisualEffectStateActive;
    vev.material = NSVisualEffectMaterialHUDWindow;
    vev.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vev.maskImage = maskImage;
    [container addSubview:vev];

    [vev addSubview:textField];
    textField.frame = NSMakeRect((vev.bounds.size.width - textField.frame.size.width) / 2,
                                  (vev.bounds.size.height - textField.frame.size.height) / 2,
                                  textField.frame.size.width,
                                  textField.frame.size.height);

    // Set up spring animation on the container
    // Create scale-from-center transform by combining translate + scale + translate
    CGFloat startScale = 0.3;
    CGFloat centerX = contentSize.width / 2;
    CGFloat centerY = contentSize.height / 2;
    CATransform3D toOrigin = CATransform3DMakeTranslation(-centerX, -centerY, 0);
    CATransform3D scale = CATransform3DMakeScale(startScale, startScale, 1.0);
    CATransform3D fromOrigin = CATransform3DMakeTranslation(centerX, centerY, 0);
    CATransform3D fromTransform = CATransform3DConcat(CATransform3DConcat(toOrigin, scale), fromOrigin);

    CALayer *animLayer = vev.layer;

    animLayer.transform = fromTransform;
    panel.alphaValue = 0.0;
    [panel orderFrontRegardless];

    CASpringAnimation *scaleAnimation = [CASpringAnimation animationWithKeyPath:@"transform"];
    scaleAnimation.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    scaleAnimation.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    scaleAnimation.mass = 1.0;
    scaleAnimation.stiffness = 300.0;
    scaleAnimation.damping = 18.0;
    scaleAnimation.initialVelocity = 0.0;
    scaleAnimation.duration = scaleAnimation.settlingDuration;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    animLayer.transform = CATransform3DIdentity;
    [CATransaction commit];

    [animLayer addAnimation:scaleAnimation forKey:@"springScale"];

    // Fade in
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.15;
        panel.animator.alphaValue = 1.0;
    } completionHandler:nil];

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
