//
//  iTermBackgroundDrawingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/18.
//

#import "iTermBackgroundDrawingHelper.h"

#import "iTermSharedImageStore.h"
#import "iTermVirtualOffset.h"
#import "SessionView.h"

typedef struct {
    NSRect solidBackgroundColorRect;
    
    iTermImageWrapper *image;
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
                        dirtyRect:(NSRect)dirtyRect
           visibleRectInContainer:(NSRect)visibleRectInContainer
           blendDefaultBackground:(BOOL)blendDefaultBackground
                       deselected:(BOOL)deselected
                             flip:(BOOL)shouldFlip
                    virtualOffset:(CGFloat)virtualOffset {
    const BOOL debug = NO;
    const iTermBackgroundDraws draws = [self drawsForBackgroundImageInView:view
                                                                 dirtyRect:dirtyRect
                                                             containerView:container
                                                    visibleRectInContainer:visibleRectInContainer
                                                    blendDefaultBackground:blendDefaultBackground];
    
    const float alpha = [self.delegate backgroundDrawingHelperUseTransparency] ? (1.0 - [self.delegate backgroundDrawingHelperTransparency]) : 1.0;
    NSColor *defaultBackgroundColor;
    if (deselected) {
        defaultBackgroundColor = [self.delegate backgroundDrawingHelperDeselectedDefaultBackgroundColor];
    } else {
        defaultBackgroundColor = [self.delegate backgroundDrawingHelperDefaultBackgroundColor];
    }
    if (!draws.image) {
        [[defaultBackgroundColor colorWithAlphaComponent:alpha] set];
        iTermRectFillUsingOperation(draws.solidBackgroundColorRect, NSCompositingOperationCopy, virtualOffset);
        return;
    }

    NSCompositingOperation operation;
    operation = NSCompositingOperationSourceOver;

    NSRect (^flip)(NSRect) = ^NSRect(NSRect r) {
        return NSMakeRect(r.origin.x,
                          draws.image.image.size.height - r.origin.y - r.size.height,
                          r.size.width,
                          r.size.height);
    };
    NSRect (^identity)(NSRect) = ^NSRect(NSRect r) {
        return r;
    };
    NSRect (^transform)(NSRect) = shouldFlip ? flip : identity;
    
    [draws.image.image it_drawInRect:draws.imageDestinationRect
                            fromRect:transform(draws.imageSourceRect)
                           operation:operation
                            fraction:alpha
                      respectFlipped:YES
                               hints:nil
                       virtualOffset:virtualOffset];
    // Draw letterboxes/pillarboxes
    [defaultBackgroundColor set];
    iTermRectFillUsingOperation(draws.boxes[0], NSCompositingOperationSourceOver, virtualOffset);
    iTermRectFillUsingOperation(draws.boxes[1], NSCompositingOperationSourceOver, virtualOffset);
    
    if (blendDefaultBackground) {
        // Blend default background color over background image.
        [[defaultBackgroundColor colorWithAlphaComponent:1 - [self.delegate backgroundDrawingHelperBlending]] set];
        iTermRectFillUsingOperation(draws.imageRect, NSCompositingOperationSourceOver, virtualOffset);
    }
    
    if (debug) {
        const NSRect adjustedRect = NSRectSubtractingVirtualOffset(dirtyRect, virtualOffset);
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:adjustedRect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(adjustedRect), NSMaxY(adjustedRect))];
        [[NSColor redColor] set];
        [path setLineWidth:1];
        [path stroke];
        iTermFrameRect(dirtyRect, virtualOffset);
        NSRect localRect = [container convertRect:dirtyRect fromView:view];
        NSString *s = [NSString stringWithFormat:@"rect=%@ local=%@ src=%@ dst=%@",
                       NSStringFromRect(NSRectSubtractingVirtualOffset(dirtyRect, virtualOffset)),
                       NSStringFromRect(NSRectSubtractingVirtualOffset(localRect, virtualOffset)),
                       NSStringFromRect(NSIntegralRect(draws.imageSourceRect)),
                       NSStringFromRect(NSIntegralRect(draws.imageDestinationRect))];

        [[NSColor whiteColor] set];
        iTermRectFill(NSMakeRect(100, dirtyRect.origin.y+20, 600, 24), virtualOffset);

        [s it_drawAtPoint:NSMakePoint(100, dirtyRect.origin.y+20)
           withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor]}
            virtualOffset:virtualOffset];
    }
}

- (iTermBackgroundDraws)drawsForBackgroundImageInView:(NSView *)view
                                            dirtyRect:(NSRect)dirtyRect
                                        containerView:(NSView *)containerView
                               visibleRectInContainer:(NSRect)windowVisibleAreaRect
                               blendDefaultBackground:(BOOL)blendDefaultBackground {
    iTermBackgroundDraws result;
    iTermImageWrapper *backgroundImage = [self.delegate backgroundDrawingHelperImage];
    result.image = backgroundImage;
    if (!backgroundImage && blendDefaultBackground) {
        // No image, so just draw background color.
        result.solidBackgroundColorRect = dirtyRect;
        return result;
    }
    result.solidBackgroundColorRect = NSZeroRect;
    
    if (backgroundImage) {
        const NSRect dirtyRectInContainerCoords = [containerView convertRect:dirtyRect fromView:view];
        NSRect dirtyRectInAdjustedContainerCoords = dirtyRectInContainerCoords;
        dirtyRectInAdjustedContainerCoords.origin.x -= windowVisibleAreaRect.origin.x;
        dirtyRectInAdjustedContainerCoords.origin.y -= windowVisibleAreaRect.origin.y;
        iTermImageWrapper *image;
        NSRect sourceRect;
        result.boxes[0] = NSZeroRect;
        result.boxes[1] = NSZeroRect;
        NSRect drawRect = dirtyRect;
        NSRect imageRect = dirtyRect;

        switch ([self.delegate backgroundDrawingHelperBackgroundImageMode]) {
            case iTermBackgroundImageModeStretch:
                image = backgroundImage;
                sourceRect = [self sourceRectForImageSize:image.image.size
                                                 viewSize:windowVisibleAreaRect.size
                                          destinationRect:dirtyRectInAdjustedContainerCoords];
                break;
                
            case iTermBackgroundImageModeTile:
                image = [self patternedImageForViewOfSize:windowVisibleAreaRect.size];
                sourceRect = [self sourceRectForImageSize:image.image.size
                                                 viewSize:windowVisibleAreaRect.size
                                          destinationRect:dirtyRectInAdjustedContainerCoords];
                break;
                
            case iTermBackgroundImageModeScaleAspectFill:
                image = backgroundImage;
                sourceRect = [self scaleAspectFillSourceRectForImageSize:image.image.size
                                                             contentRect:windowVisibleAreaRect
                                                         destinationRect:dirtyRectInAdjustedContainerCoords];
                break;
                
            case iTermBackgroundImageModeScaleAspectFit:
                image = backgroundImage;
                // TODO: The analyze complained about this dead store, which suggests I'm assing the wrong argument for dirtyRect below.
                // dirtyRectInAdjustedContainerCoords = NSIntersectionRect(dirtyRectInAdjustedContainerCoords, containerView.bounds);
                sourceRect = [iTermBackgroundDrawingHelper scaleAspectFitSourceRectForForImageSize:image.image.size
                                                                                   destinationRect:windowVisibleAreaRect
                                                                                         dirtyRect:dirtyRectInContainerCoords
                                                                                          drawRect:&drawRect
                                                                                          boxRect1:&result.boxes[0]
                                                                                          boxRect2:&result.boxes[1]];
                drawRect = [view convertRect:drawRect fromView:containerView];
                imageRect = drawRect;
                for (int i = 0; i < sizeof(result.boxes) / sizeof(*result.boxes); i++) {
                    result.boxes[i] = [view convertRect:result.boxes[i] fromView:containerView];
                }
                break;
        }
        result.image = image;
        result.imageDestinationRect = drawRect;
        result.imageSourceRect = sourceRect;
        result.imageRect = imageRect;
    }
    return result;
}

- (void)invalidate {
    _patternedImage = nil;
}

#pragma mark - Private

- (iTermImageWrapper *)patternedImageForViewOfSize:(NSSize)size {
    // If there is a tiled background image, tessellate _backgroundImage onto
    // _patternedImage, which will be the source for future background image
    // drawing operations.
    if (!_patternedImage || !NSEqualSizes(_patternedImage.size, size)) {
        _patternedImage = [[NSImage alloc] initWithSize:size];
        [_patternedImage lockFocus];
        NSColor *pattern = [NSColor colorWithPatternImage:[[self.delegate backgroundDrawingHelperImage] image]];
        [pattern drawSwatchInRect:NSMakeRect(0,
                                             0,
                                             _patternedImage.size.width,
                                             _patternedImage.size.height)];
        [_patternedImage unlockFocus];
    }
    return [iTermImageWrapper withImage:_patternedImage];
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

+ (NSRect)scaleAspectFitRectWithImageOfSize:(NSSize)imageSize
                          inDestinationRect:(NSRect)destinationRect
                                      scale:(out CGFloat *)scale {
    const CGFloat imageAspectRatio = imageSize.width / imageSize.height;
    const CGFloat viewAspectRatio = destinationRect.size.width / destinationRect.size.height;
    if (imageAspectRatio > viewAspectRatio) {
        // Image is wider in AR than view
        // There will be letterboxes
        NSRect rectWithImage;
        rectWithImage.origin.x = destinationRect.origin.x;
        rectWithImage.size.width = destinationRect.size.width;
        rectWithImage.size.height = destinationRect.size.width / imageAspectRatio;
        rectWithImage.origin.y = destinationRect.origin.y + (destinationRect.size.height - rectWithImage.size.height) / 2.0;
        *scale = imageSize.width / destinationRect.size.width;
        return rectWithImage;
    } else {
        // Image is taller in AR than view
        // There will be pillarboxes (possibly degenerate)
        NSRect rectWithImage;
        rectWithImage.origin.y = destinationRect.origin.y;
        rectWithImage.size.height = destinationRect.size.height;
        rectWithImage.size.width = destinationRect.size.height * imageAspectRatio;
        rectWithImage.origin.x = destinationRect.origin.x + (destinationRect.size.width - rectWithImage.size.width) / 2.0;
        *scale = imageSize.height / destinationRect.size.height;
        return rectWithImage;
    }
}

+ (void)getPillarBoxesForImageRect:(NSRect)rectWithImage
                   destinationRect:(NSRect)destinationRect
                         dirtyRect:(NSRect)dirtyRect
                          boxRect1:(out NSRect *)boxRect1
                          boxRect2:(out NSRect *)boxRect2 {
    // Left pillarbox
    const CGFloat pillarboxWidth = (destinationRect.size.width - rectWithImage.size.width) / 2;
    NSRect leftPillarboxInViewCoords = NSMakeRect(destinationRect.origin.x,
                                                  destinationRect.origin.y,
                                                  pillarboxWidth,
                                                  destinationRect.size.height);
    if (boxRect1) {
        *boxRect1 = NSIntersectionRect(NSIntersectionRect(leftPillarboxInViewCoords,
                                                          destinationRect),
                                       dirtyRect);
    }
    
    // Right pillarbox
    NSRect rightPillarboxInViewCoords = NSMakeRect(destinationRect.origin.x + destinationRect.size.width - pillarboxWidth,
                                                   destinationRect.origin.y,
                                                   pillarboxWidth,
                                                   destinationRect.size.height);
    if (boxRect2) {
        *boxRect2 = NSIntersectionRect(NSIntersectionRect(rightPillarboxInViewCoords,
                                                          destinationRect),
                                       dirtyRect);
    }
}

+ (void)getLetterBoxesForImageRect:(NSRect)rectWithImage
                   destinationRect:(NSRect)destinationRect
                         dirtyRect:(NSRect)dirtyRect
                          boxRect1:(out NSRect *)boxRect1
                          boxRect2:(out NSRect *)boxRect2 {
    // Top letterbox
    CGFloat letterboxHeight = (destinationRect.size.height - rectWithImage.size.height) / 2;
    NSRect topLetterboxInViewCoords = NSMakeRect(destinationRect.origin.x,
                                                 destinationRect.origin.y,
                                                 destinationRect.size.width,
                                                 letterboxHeight);
    if (boxRect1) {
        *boxRect1 = NSIntersectionRect(NSIntersectionRect(topLetterboxInViewCoords,
                                                          destinationRect),
                                       dirtyRect);
    }
    
    // Bottom letterbox
    NSRect bottomLetterboxInViewCoords = NSMakeRect(destinationRect.origin.x,
                                                    destinationRect.origin.y + destinationRect.size.height - letterboxHeight,
                                                    destinationRect.size.width,
                                                    letterboxHeight);
    if (boxRect2) {
        *boxRect2 = NSIntersectionRect(NSIntersectionRect(bottomLetterboxInViewCoords,
                                                          destinationRect),
                                       dirtyRect);
    }
}

+ (void)getClippedScaleAspectFitSourceRect:(inout NSRect *)sourceRectInOut
                           destinationRect:(inout NSRect *)destinationRectInOut
                                    inRect:(NSRect)clipRect {
    const NSRect originalSourceRect = *sourceRectInOut;
    const NSRect originalDestinationRect = *destinationRectInOut;
    
    const NSRect clippedDestinationRect = NSIntersectionRect(clipRect, originalDestinationRect);
    if (NSEqualRects(originalDestinationRect, clippedDestinationRect)) {
        // Nothing to do: destination rect is entirely within clip rect.
        return;
    }
    *destinationRectInOut = clippedDestinationRect;
    
    const CGFloat leftLost = (NSMinX(clippedDestinationRect) - NSMinX(originalDestinationRect)) / NSWidth(originalDestinationRect);
    const CGFloat topLost = (NSMinY(clippedDestinationRect) - NSMinY(originalDestinationRect)) / NSHeight(originalDestinationRect);
    const CGFloat rightLost = (NSMaxX(originalDestinationRect) - NSMaxX(clippedDestinationRect)) / NSWidth(originalDestinationRect);
    const CGFloat bottomLost = (NSMaxY(originalDestinationRect) - NSMaxY(clippedDestinationRect)) / NSHeight(originalDestinationRect);
    
    const NSRect sourceRect = NSMakeRect(NSMinX(originalSourceRect) + leftLost * NSWidth(originalSourceRect),
                                         NSMinY(originalSourceRect) + topLost * NSHeight(originalSourceRect),
                                         NSWidth(originalSourceRect) - (leftLost + rightLost) * NSWidth(originalSourceRect),
                                         NSHeight(originalSourceRect) - (bottomLost + topLost) * NSHeight(originalSourceRect));
    *sourceRectInOut = sourceRect;
}

+ (NSRect)scaleAspectFitSourceRectForForImageSize:(NSSize)imageSize
                                  destinationRect:(NSRect)destinationRect
                                        dirtyRect:(NSRect)dirtyRect
                                         drawRect:(out NSRect *)drawRect
                                         boxRect1:(out NSRect *)boxRect1
                                         boxRect2:(out NSRect *)boxRect2 {
    CGFloat imageAspectRatio = imageSize.width / imageSize.height;
    CGFloat viewAspectRatio = destinationRect.size.width / destinationRect.size.height;
    
    // Compute the viewRect which is the part of the view that has an image (and not a letterbox/pillarbox)
    CGFloat scale = 0;
    const NSRect rectWithImage = [self scaleAspectFitRectWithImageOfSize:imageSize
                                                       inDestinationRect:destinationRect
                                                                   scale:&scale];
    *drawRect = rectWithImage;

    NSRect destinationRectRelativeToViewRect = NSMakeRect(destinationRect.origin.x - rectWithImage.origin.x,
                                                          destinationRect.origin.y - rectWithImage.origin.y,
                                                          destinationRect.size.width,
                                                          destinationRect.size.height);
    NSRect sourceRect = NSMakeRect(destinationRectRelativeToViewRect.origin.x * scale,
                                   destinationRectRelativeToViewRect.origin.y * scale,
                                   destinationRectRelativeToViewRect.size.width * scale,
                                   destinationRectRelativeToViewRect.size.height * scale);
    
    if (imageAspectRatio <= viewAspectRatio) {
        [self getPillarBoxesForImageRect:rectWithImage
                         destinationRect:destinationRect
                               dirtyRect:dirtyRect
                                boxRect1:boxRect1
                                boxRect2:boxRect2];
    } else {
        [self getLetterBoxesForImageRect:rectWithImage
                         destinationRect:destinationRect
                               dirtyRect:dirtyRect
                                boxRect1:boxRect1
                                boxRect2:boxRect2];
    }

    // Ensure the bounds of the source rect are legit. The out-of-bounds parts are covered by letter/pillar boxes.
    NSRect safeSourceRect = NSIntersectionRect(sourceRect, NSMakeRect(0, 0, imageSize.width, imageSize.height));
    
    [self getClippedScaleAspectFitSourceRect:&safeSourceRect
                             destinationRect:drawRect
                                      inRect:dirtyRect];
    return safeSourceRect;
}

@end
