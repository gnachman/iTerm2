//
//  iTermBackgroundDrawingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/18.
//

#import "iTermBackgroundDrawingHelper.h"
#import "SessionView.h"

typedef struct {
    NSRect solidBackgroundColorRect;
    
    NSImage *image;
    NSRect imageDestinationRect;
    NSRect imageSourceRect;
    NSRect boxes[2];
    NSRect imageRect;
} iTermBackgroundDraws;

@implementation iTermBackgroundDrawingHelper {
    NSImage *_patternedImage;
}

- (void)drawBackgroundImageInView:(NSView *)view
                        container:(NSView *)container
                         viewRect:(NSRect)rect
                      contentRect:(NSRect)contentRect
           blendDefaultBackground:(BOOL)blendDefaultBackground
                             flip:(BOOL)shouldFlip {
    const BOOL debug = NO;
    const iTermBackgroundDraws draws = [self drawsForBackgroundImageInView:view
                                                                  viewRect:rect
                                                             containerView:container
                                                               contentRect:contentRect
                                                    blendDefaultBackground:blendDefaultBackground];
    
    const float alpha = [self.delegate backgroundDrawingHelperUseTransparency] ? (1.0 - [self.delegate backgroundDrawingHelperTransparency]) : 1.0;
    if (!draws.image) {
        [[[self.delegate backgroundDrawingHelperDefaultBackgroundColor] colorWithAlphaComponent:alpha] set];
        NSRectFillUsingOperation(draws.solidBackgroundColorRect, NSCompositingOperationCopy);
        return;
    }

    NSCompositingOperation operation;
    if (@available(macOS 10.14, *)) {
        operation = NSCompositingOperationSourceOver;
    } else {
        operation = NSCompositingOperationCopy;
    }

    NSRect (^flip)(NSRect) = ^NSRect(NSRect r) {
        return NSMakeRect(r.origin.x, draws.image.size.height - r.origin.y - r.size.height, r.size.width, r.size.height);
    };
    NSRect (^identity)(NSRect) = ^NSRect(NSRect r) {
        return r;
    };
    NSRect (^transform)(NSRect) = shouldFlip ? flip : identity;
    
    [draws.image drawInRect:draws.imageDestinationRect
                   fromRect:transform(draws.imageSourceRect)
                  operation:operation
                   fraction:alpha
             respectFlipped:YES
                      hints:nil];
    // Draw letterboxes/pillarboxes
    NSColor *defaultBackgroundColor = [self.delegate backgroundDrawingHelperDefaultBackgroundColor];
    [defaultBackgroundColor set];
    NSRectFillUsingOperation(draws.boxes[0], NSCompositingOperationSourceOver);
    NSRectFillUsingOperation(draws.boxes[1], NSCompositingOperationSourceOver);
    
    if (blendDefaultBackground) {
        // Blend default background color over background image.
        [[defaultBackgroundColor colorWithAlphaComponent:1 - [self.delegate backgroundDrawingHelperBlending]] set];
        NSRectFillUsingOperation(draws.imageRect, NSCompositingOperationSourceOver);
    }
    
    if (debug) {
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:rect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [[NSColor redColor] set];
        [path setLineWidth:1];
        [path stroke];
        NSFrameRect(rect);
        NSRect localRect = [container convertRect:rect fromView:view];
        NSString *s = [NSString stringWithFormat:@"rect=%@ local=%@ src=%@ dst=%@",
                       NSStringFromRect(rect),
                       NSStringFromRect(localRect),
                       NSStringFromRect(NSIntegralRect(draws.imageSourceRect)),
                       NSStringFromRect(NSIntegralRect(draws.imageDestinationRect))];

        [[NSColor whiteColor] set];
        NSRectFill(NSMakeRect(100, rect.origin.y+20, 600, 24));

        [s drawAtPoint:NSMakePoint(100, rect.origin.y+20) withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor] }];
    }
}

- (iTermBackgroundDraws)drawsForBackgroundImageInView:(NSView *)view
                                             viewRect:(NSRect)rect
                                        containerView:(NSView *)containerView
                                          contentRect:(NSRect)contentRect
                               blendDefaultBackground:(BOOL)blendDefaultBackground {
    iTermBackgroundDraws result;
    NSImage *backgroundImage = [self.delegate backgroundDrawingHelperImage];
    result.image = backgroundImage;
    if (!backgroundImage && blendDefaultBackground) {
        // No image, so just draw background color.
        result.solidBackgroundColorRect = rect;
        return result;
    }
    result.solidBackgroundColorRect = NSZeroRect;
    
    if (backgroundImage) {
        NSRect localRect = [containerView convertRect:rect fromView:view];
        NSImage *image;
        NSRect sourceRect;
        result.boxes[0] = NSZeroRect;
        result.boxes[1] = NSZeroRect;
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
                image = [self patternedImageForViewOfSize:contentRect.size];
                sourceRect = [self sourceRectForImageSize:image.size
                                                 viewSize:contentRect.size
                                          destinationRect:localRect];
                break;
                
            case iTermBackgroundImageModeScaleAspectFill:
                image = backgroundImage;
                sourceRect = [self scaleAspectFillSourceRectForImageSize:image.size
                                                             contentRect:contentRect
                                                         destinationRect:localRect];
                break;
                
            case iTermBackgroundImageModeScaleAspectFit:
                image = backgroundImage;
                localRect = NSIntersectionRect(localRect, containerView.bounds);
                sourceRect = [self scaleAspectFitSourceRectForForImageSize:image.size
                                                                  viewSize:contentRect.size
                                                           destinationRect:localRect
                                                                  drawRect:&drawRect
                                                                  boxRect1:&result.boxes[0]
                                                                  boxRect2:&result.boxes[1]
                                                                 imageRect:&imageRect];
                drawRect = [view convertRect:drawRect fromView:containerView];
                for (int i = 0; i < sizeof(result.boxes) / sizeof(*result.boxes); i++) {
                    result.boxes[i] = [view convertRect:result.boxes[i] fromView:containerView];
                }
                imageRect = [view convertRect:imageRect fromView:containerView];
                break;
        }
        result.image = image;
        result.imageDestinationRect = drawRect;
        result.imageSourceRect = sourceRect;
        result.imageRect = imageRect;
    }
    return result;
}

#pragma mark - Private

- (NSImage *)patternedImageForViewOfSize:(NSSize)size {
    // If there is a tiled background image, tessellate _backgroundImage onto
    // _patternedImage, which will be the source for future background image
    // drawing operations.
    if (!_patternedImage || !NSEqualSizes(_patternedImage.size, size)) {
        _patternedImage = [[NSImage alloc] initWithSize:size];
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
                                    contentRect:(NSRect)contentRect
                                destinationRect:(NSRect)destinationRect {
    const NSSize viewSize = contentRect.size;
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
    }

    // Ensure the bounds of the source rect are legit. The out-of-bounds parts are covered by letter/pillar boxes.
    NSRect safeSourceRect = NSIntersectionRect(sourceRect, NSMakeRect(0, 0, imageSize.width, imageSize.height));
    return safeSourceRect;
}

@end
