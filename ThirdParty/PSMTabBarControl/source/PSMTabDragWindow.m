//
//  PSMTabDragWindow.m
//  PSMTabBarControl
//
//  Created by Kent Sutherland on 6/1/06.
//  Copyright 2006 Kent Sutherland. All rights reserved.
//

#import "PSMTabDragWindow.h"
#import "PSMTabBarCell.h"
#import <Quartz/Quartz.h>

// A window's content view won't be transparent if it has a layer. This view exists simply to
// contain an image view whose layer has variable opacity.
@interface PSMClearView : NSView
@end

@implementation PSMClearView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor clearColor] set];
    NSRectFill(self.bounds);
}

@end

@implementation PSMTabDragWindow {
    PSMTabBarCell *_cell;
    NSImageView *_imageView;  // weak
}

+ (PSMTabDragWindow *)dragWindowWithTabBarCell:(PSMTabBarCell *)cell
                                         image:(NSImage *)image
                                     styleMask:(unsigned int)styleMask {
    return [[[PSMTabDragWindow alloc] initWithTabBarCell:cell
                                                   image:image
                                               styleMask:styleMask] autorelease];
}

- (instancetype)initWithTabBarCell:(PSMTabBarCell *)cell
                             image:(NSImage *)image
                         styleMask:(unsigned int)styleMask {
    self = [super initWithContentRect:NSZeroRect
                            styleMask:styleMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        NSRect frame = NSMakeRect(0,
                                  0,
                                  self.frame.size.width,
                                  self.frame.size.height);
        _cell = [cell retain];
        _imageView = [[[NSImageView alloc] initWithFrame:frame] autorelease];
        _imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _imageView.wantsLayer = YES;
        [_imageView makeBackingLayer];

        PSMClearView *clearView = [[[PSMClearView alloc] initWithFrame:frame] autorelease];
        [clearView addSubview:_imageView];
        clearView.autoresizesSubviews = YES;

        [self setContentView:clearView];
        [self setLevel:NSStatusWindowLevel];
        [self setIgnoresMouseEvents:YES];
        [self setOpaque:NO];

        [_imageView setImage:image];

        // Set the size of the window to be the exact size of the drag image
        NSSize imageSize = [image size];
        NSRect windowFrame = [self frame];

        windowFrame.origin.y += windowFrame.size.height - imageSize.height;
        windowFrame.size = imageSize;

        if (styleMask | NSBorderlessWindowMask) {
            windowFrame.size.height += 22;
        }

        [self setFrame:windowFrame display:YES];
    }
    return self;
}

- (void)dealloc {
    [_cell release];
    [super dealloc];
}

- (NSImage *)image {
    return _imageView.image;
}

- (void)fadeToAlpha:(CGFloat)alpha
           duration:(NSTimeInterval)duration
         completion:(void (^)())completion {
    [CATransaction begin];
    if (completion) {
        [CATransaction setCompletionBlock:^{
            completion();
        }];
    }

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    CALayer *layer = _imageView.layer.presentationLayer;
    animation.fromValue = @(layer.opacity);
    animation.toValue = (id)@(alpha);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    [_imageView.layer addAnimation:animation forKey:@"opacity"];
    [CATransaction commit];

    _imageView.layer.opacity = alpha;
}

- (void)setImageOpacity:(CGFloat)alpha {
    _imageView.layer.opacity = alpha;
    [_imageView.layer removeAllAnimations];
}

@end
