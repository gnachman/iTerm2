//
//  iTermRollAnimationWindow.m
//  iTerm2
//
//  Created by George Nachman on 6/25/16.
//
//

#import "iTermRollAnimationWindow.h"
#import "SolidColorView.h"
#import <QuartzCore/QuartzCore.h>

@interface iTermRollAnimationWindow()
@property(nonatomic) CALayer *layer;
@end

iTermAnimationDirection iTermAnimationDirectionOpposite(iTermAnimationDirection direction) {
    switch (direction) {
        case kAnimationDirectionRight:
            return kAnimationDirectionLeft;
        case kAnimationDirectionLeft:
            return kAnimationDirectionRight;
        case kAnimationDirectionDown:
            return kAnimationDirectionUp;
        case kAnimationDirectionUp:
            return kAnimationDirectionDown;
    }
    assert(false);
}

@implementation iTermRollAnimationWindow

+ (instancetype)rollAnimationWindowForWindow:(NSWindow *)window {
    NSSize size = window.frame.size;

    // Take a snapshot, including window decorations if there are any.
    NSData *data = [window dataWithPDFInsideRect:NSMakeRect(0, 0, size.width, size.height)];
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];

    // Create a new window to contain the animation over where the window to animate is.
    iTermRollAnimationWindow *animationWindow = [[[self alloc] initWithContentRect:window.frame
                                                                         styleMask:NSBorderlessWindowMask
                                                                           backing:NSBackingStoreBuffered
                                                                             defer:NO] autorelease];

    // The view hierarchy of the animation window is:
    // window
    //   contentView: SolidColorView with clearColor background color. This can't have a layer and be transparent because macOS is 💩.
    //     layerBackedView: A view with a layer.
    //       layer: This is actually a sublayer of layerBackedView's layer. This layer animates.
    animationWindow.opaque = NO;
    
    // Create clearView (the animationWindow's contentView).
    NSView *clearView = [[[SolidColorView alloc] initWithFrame:NSMakeRect(0,
                                                                          0,
                                                                          size.width,
                                                                          size.height)
                                                         color:[NSColor clearColor]] autorelease];
    animationWindow.contentView = clearView;

    // Create layerBackedView.
    NSView *layerBackedView = [[[NSView alloc] initWithFrame:clearView.bounds] autorelease];
    layerBackedView.wantsLayer = YES;
    layerBackedView.layer.backgroundColor = [[NSColor clearColor] CGColor];
    [clearView addSubview:layerBackedView];

    // Finish window initialization.
    [animationWindow makeKeyAndOrderFront:nil];
    
    // Set up layer that will animate by setting its contents to the snapshot
    // and adding it as a sublayer.
    CALayer *layer = [[CALayer alloc] init];
    layer.frame = CGRectMake(0, 0, size.width, size.height);
    layer.contents = image;
    layer.contentsScale = window.backingScaleFactor;
    [layerBackedView.layer addSublayer:layer];
    animationWindow.layer = layer;

    return animationWindow;
}

- (void)dealloc {
    [_layer release];
    [super dealloc];
}

- (void)animateInWithDirection:(iTermAnimationDirection)direction
                      duration:(NSTimeInterval)duration
                    completion:(void(^)())completion {
    [CATransaction begin];
    [CATransaction setAnimationDuration:duration];
    if (completion) {
        [CATransaction setCompletionBlock:completion];
    }
    [self addAnimationToCurrentCATransactionWithDirection:direction duration:duration animateIn:YES];
    [CATransaction commit];
}

- (void)animateOutWithDirection:(iTermAnimationDirection)direction
                       duration:(NSTimeInterval)duration
                     completion:(void(^)())completion {
    [CATransaction begin];
    [CATransaction setAnimationDuration:duration];
    if (completion) {
        [CATransaction setCompletionBlock:completion];
    }
    [self addAnimationToCurrentCATransactionWithDirection:direction duration:duration animateIn:NO];
    [CATransaction commit];
}

- (void)addAnimationToCurrentCATransactionWithDirection:(iTermAnimationDirection)direction
                                               duration:(NSTimeInterval)duration
                                              animateIn:(BOOL)animateIn {
    NSSize size = self.frame.size;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    NSPoint point = self.layer.position;
    if (animateIn) {
        animation.fromValue = [NSValue valueWithPoint:[self sourcePointForInitialPoint:point
                                                               forAnimationInDirection:direction
                                                                                  size:size]];
        animation.toValue = [NSValue valueWithPoint:point];
    } else {
        animation.fromValue = [NSValue valueWithPoint:point];
        animation.toValue = [NSValue valueWithPoint:[self sourcePointForInitialPoint:point
                                                             forAnimationInDirection:iTermAnimationDirectionOpposite(direction)
                                                                                size:size]];
    }
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    [self.layer addAnimation:animation forKey:@"position"];
}

- (NSPoint)sourcePointForInitialPoint:(NSPoint)point
              forAnimationInDirection:(iTermAnimationDirection)direction
                                 size:(NSSize)size {
    switch (direction) {
        case kAnimationDirectionUp:
            return NSMakePoint(point.x, point.y - size.height);
        case kAnimationDirectionDown:
            return NSMakePoint(point.x, point.y + size.height);
        case kAnimationDirectionLeft:
            return NSMakePoint(point.x + size.width, point.y);
        case kAnimationDirectionRight:
            return NSMakePoint(point.x - size.width, point.y);
    }
    assert(false);
}

@end
