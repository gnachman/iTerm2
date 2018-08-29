//
//  iTermBackgroundDrawingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/18.
//

#import "iTermBackgroundDrawingHelper.h"
#import "SessionView.h"

@implementation iTermBackgroundDrawingHelper {
    NSImage *_patternedImage;
}

- (void)drawBackgroundImageInView:(NSView *)view
                         viewRect:(NSRect)rect
           blendDefaultBackground:(BOOL)blendDefaultBackground {
    const float alpha = [self.delegate backgroundDrawingHelperUseTransparency] ? (1.0 - [self.delegate backgroundDrawingHelperTransparency]) : 1.0;
    NSImage *backgroundImage = [self.delegate backgroundDrawingHelperImage];
    if (backgroundImage) {
        SessionView *sessionView = [self.delegate backgroundDrawingHelperView];
        NSRect localRect = [sessionView convertRect:rect fromView:view];
        NSImage *image;
        const NSRect contentRect = sessionView.contentRect;
        NSRect sourceRect;
        NSRect boxes[2] = { NSZeroRect, NSZeroRect };
        NSRect drawRect = rect;
        NSRect imageRect = rect;
        
        switch ([self.delegate backgroundDrawingHelperBackgroundImageMode]) {
            case iTermBackgroundImageModeStretch:
                image = backgroundImage;
                sourceRect = [self sourceRectForImageSize:image.size
                                                 viewSize:contentRect.size
                                          destinationRect:localRect];
                break;
                
            case iTermBackgroundImageModeTile:
                image = [self patternedImage];
                sourceRect = [self sourceRectForImageSize:image.size
                                                 viewSize:contentRect.size
                                          destinationRect:localRect];
                break;
                
            case iTermBackgroundImageModeScaleAspectFill:
                image = backgroundImage;
                sourceRect = [self scaleAspectFillSourceRectForImageSize:image.size
                                                                viewSize:contentRect.size
                                                         destinationRect:localRect];
                break;
                
            case iTermBackgroundImageModeScaleAspectFit:
                image = backgroundImage;
                localRect = NSIntersectionRect(localRect, sessionView.bounds);
                sourceRect = [self scaleAspectFitSourceRectForForImageSize:image.size
                                                                  viewSize:contentRect.size
                                                           destinationRect:localRect
                                                                  drawRect:&drawRect
                                                                  boxRect1:&boxes[0]
                                                                  boxRect2:&boxes[1]
                                                                 imageRect:&imageRect];
                drawRect = [sessionView convertRect:drawRect fromView:view];
                for (int i = 0; i < sizeof(boxes) / sizeof(*boxes); i++) {
                    boxes[i] = [sessionView convertRect:boxes[i] fromView:view];
                }
                imageRect = [sessionView convertRect:imageRect fromView:view];
                break;
        }

        NSCompositingOperation operation;
        if (@available(macOS 10.14, *)) {
            operation = NSCompositingOperationSourceOver;
        } else {
            operation = NSCompositingOperationCopy;
        }
        [image drawInRect:drawRect
                 fromRect:sourceRect
                operation:operation
                 fraction:alpha
           respectFlipped:YES
                    hints:nil];
        // Draw letterboxes/pillarboxes
        NSColor *defaultBackgroundColor = [self.delegate backgroundDrawingHelperDefaultBackgroundColor];
        [defaultBackgroundColor set];
        NSRectFillUsingOperation(boxes[0], NSCompositingOperationSourceOver);
        NSRectFillUsingOperation(boxes[1], NSCompositingOperationSourceOver);

        if (blendDefaultBackground) {
            // Blend default background color over background image.
            [[defaultBackgroundColor colorWithAlphaComponent:1 - [self.delegate backgroundDrawingHelperBlending]] set];
            NSRectFillUsingOperation(imageRect, NSCompositingOperationSourceOver);
        }
    } else if (blendDefaultBackground) {
        // No image, so just draw background color.
        [[[self.delegate backgroundDrawingHelperDefaultBackgroundColor] colorWithAlphaComponent:alpha] set];
        NSRectFillUsingOperation(rect, NSCompositingOperationCopy);
    }
}

#pragma mark - Private

- (NSImage *)patternedImage {
    // If there is a tiled background image, tesselate _backgroundImage onto
    // _patternedImage, which will be the source for future background image
    // drawing operations.
    SessionView *view = [self.delegate backgroundDrawingHelperView];
    if (!_patternedImage || !NSEqualSizes(_patternedImage.size, view.contentRect.size)) {
        _patternedImage = [[NSImage alloc] initWithSize:view.contentRect.size];
        [_patternedImage lockFocus];
        NSColor *pattern = [NSColor colorWithPatternImage:[self.delegate backgroundDrawingHelperImage]];
        [pattern drawSwatchInRect:NSMakeRect(0,
                                             0,
                                             _patternedImage.size.width,
                                             _patternedImage.size.height)];
        [_patternedImage unlockFocus];
    }
    return _patternedImage;
}

- (NSRect)sourceRectForImageSize:(NSSize)imageSize
                        viewSize:(NSSize)viewSize
                 destinationRect:(NSRect)destinationRect {
    double dx = imageSize.width / viewSize.width;
    double dy = imageSize.height / viewSize.height;
    
    NSRect sourceRect = NSMakeRect(destinationRect.origin.x * dx,
                                   destinationRect.origin.y * dy,
                                   destinationRect.size.width * dx,
                                   destinationRect.size.height * dy);
    return sourceRect;
}

- (NSRect)scaleAspectFillSourceRectForImageSize:(NSSize)imageSize
                                       viewSize:(NSSize)viewSize
                                destinationRect:(NSRect)destinationRect {
    CGFloat imageAspectRatio = imageSize.width / imageSize.height;
    CGFloat viewAspectRatio = viewSize.width / viewSize.height;
    NSRect imageSpaceRect;

    if (imageAspectRatio > viewAspectRatio) {
        // Image is wider in AR than view
        imageSpaceRect.origin.y = 0;
        imageSpaceRect.size.height = imageSize.height;
        
        const CGFloat scale = viewSize.height / imageSize.height;
        const CGFloat scaledWidth = imageSize.width * scale;
        const CGFloat crop = (scaledWidth - viewSize.width) / scale;
        imageSpaceRect.origin.x = crop / 2.0;
        imageSpaceRect.size.width = imageSize.width - crop;
    } else {
        // Image is taller in AR than view
        imageSpaceRect.origin.x = 0;
        imageSpaceRect.size.width = imageSize.width;
        
        const CGFloat scale = viewSize.width / imageSize.width;
        const CGFloat scaledHeight = imageSize.height * scale;
        const CGFloat crop = (scaledHeight - viewSize.height) / scale;
        imageSpaceRect.origin.y = crop / 2.0;
        imageSpaceRect.size.height = imageSize.height - crop;
    }
    
    // Compute the normalized offsets/sizes of the destination rect relative to the view.
    // The map directly onto the imageSpaceRect. In other words, if the destination rect's
    // origin is 25% of the way across the view, then it's also 25% of the way across the
    // imageSpaceRect.
    CGFloat x = destinationRect.origin.x / viewSize.width;
    CGFloat y = destinationRect.origin.y / viewSize.height;
    CGFloat w = destinationRect.size.width / viewSize.width;
    CGFloat h = destinationRect.size.height / viewSize.height;
    return NSMakeRect(imageSpaceRect.origin.x + NSWidth(imageSpaceRect) * x,
                      imageSpaceRect.origin.y + NSHeight(imageSpaceRect) * y,
                      imageSpaceRect.size.width * w,
                      imageSpaceRect.size.height * h);
}

- (NSRect)scaleAspectFitSourceRectForForImageSize:(NSSize)imageSize
                                         viewSize:(NSSize)viewSize
                                  destinationRect:(NSRect)destinationRect
                                         drawRect:(out NSRect *)drawRect
                                         boxRect1:(out NSRect *)boxRect1
                                         boxRect2:(out NSRect *)boxRect2
                                        imageRect:(out NSRect *)imageRect {
    CGFloat imageAspectRatio = imageSize.width / imageSize.height;
    CGFloat viewAspectRatio = viewSize.width / viewSize.height;
    
    // Compute the viewRect which is the part of the view that has an image (and not a letterbox/pillarbox)
    NSRect viewRect;
    CGFloat scale;
    if (imageAspectRatio > viewAspectRatio) {
        // Image is wider in AR than view
        // There will be letterboxes
        viewRect.origin.x = 0;
        viewRect.size.width = viewSize.width;
        viewRect.size.height = viewSize.width / imageAspectRatio;
        viewRect.origin.y = (viewSize.height - viewRect.size.height) / 2.0;
        scale = imageSize.width / viewSize.width;
    } else {
        // Image is taller in AR than view
        // There will be pillarboxes (possibly degenerate)
        viewRect.origin.y = 0;
        viewRect.size.height = viewSize.height;
        viewRect.size.width = viewSize.height * imageAspectRatio;
        viewRect.origin.x = (viewSize.width - viewRect.size.width) / 2.0;
        scale = imageSize.height / viewSize.height;
    }
    
    *imageRect = NSIntersectionRect(viewRect, destinationRect);
    NSRect destinationRectRelativeToViewRect = NSMakeRect(destinationRect.origin.x - viewRect.origin.x,
                                                          destinationRect.origin.y - viewRect.origin.y,
                                                          destinationRect.size.width,
                                                          destinationRect.size.height);
    NSRect sourceRect = NSMakeRect(destinationRectRelativeToViewRect.origin.x * scale,
                                   destinationRectRelativeToViewRect.origin.y * scale,
                                   destinationRectRelativeToViewRect.size.width * scale,
                                   destinationRectRelativeToViewRect.size.height * scale);

    *drawRect = destinationRect;
    
    if (imageAspectRatio <= viewAspectRatio) {
        // Left pillarbox
        const CGFloat pillarboxWidth = (viewSize.width - viewRect.size.width) / 2;
        NSRect leftPillarboxInViewCoords = NSMakeRect(0,
                                                      0,
                                                      pillarboxWidth,
                                                      viewSize.height);
        *boxRect1 = NSIntersectionRect(leftPillarboxInViewCoords, destinationRect);

        // Right pillarbox
        NSRect rightPillarboxInViewCoords = NSMakeRect(viewSize.width - pillarboxWidth,
                                                       0,
                                                       pillarboxWidth,
                                                       viewSize.height);
        *boxRect2 = NSIntersectionRect(rightPillarboxInViewCoords, destinationRect);

        *drawRect = NSIntersectionRect(viewRect, destinationRect);
        sourceRect.origin.x = 0;
        sourceRect.size.width = imageSize.width;
    } else {
        // Top letterbox
        CGFloat letterboxHeight = (viewSize.height - viewRect.size.height) / 2;
        NSRect topLetterboxInViewCoords = NSMakeRect(0,
                                                     0,
                                                     viewSize.width,
                                                     letterboxHeight);
        *boxRect1 = NSIntersectionRect(topLetterboxInViewCoords, destinationRect);
        *drawRect = NSIntersectionRect(viewRect, destinationRect);
        
        // Bottom letterbox
        NSRect bottomLetterboxInViewCoords = NSMakeRect(0,
                                                        viewSize.height - letterboxHeight,
                                                        viewSize.width,
                                                        letterboxHeight);
        *boxRect2 = NSIntersectionRect(bottomLetterboxInViewCoords, destinationRect);
        sourceRect.origin.y = 0;
        sourceRect.size.height = imageSize.height;
    }

    return sourceRect;
}

@end
