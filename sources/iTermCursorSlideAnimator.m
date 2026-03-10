//
//  iTermCursorSlideAnimator.m
//  iTerm2
//

#import "iTermCursorSlideAnimator.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

@implementation iTermCursorSlideAnimator {
    CFTimeInterval _slideStartTime;
    NSRect _slideAnimationRect;      // Union of old + new cursor rects (in view coords)
    NSRect _slideStartRect;          // Old cursor position (in view coords)
    NSRect _slideEndRect;            // New cursor position (in view coords)
    NSImage *_slideScreenshot;       // Cached region without cursor
    NSColor *_slideCursorColor;
    BOOL _capturingSlideScreenshot;  // Prevents recursion during screenshot capture
    __weak NSView *_slideLegacyView; // Weak reference to the legacy view for animation
    BOOL _animationInProgress;
}

+ (CFTimeInterval)animationDuration {
    return [iTermAdvancedSettingsModel cursorSlideAnimationDuration];
}

#pragma mark - Properties

- (BOOL)animationInProgress {
    return _animationInProgress;
}

- (BOOL)capturingScreenshot {
    return _capturingSlideScreenshot;
}

- (NSColor *)cursorColor {
    return _slideCursorColor;
}

#pragma mark - Starting Animations

- (void)beginLegacyAnimationFrom:(NSRect)from
                              to:(NSRect)to
                           color:(NSColor *)color
                          inView:(NSView *)view {
    DLog(@"Begin legacy slide animation from %@ to %@ color=%@", NSStringFromRect(from), NSStringFromRect(to), color);

    // If an animation is already in progress, continue from the current animated position
    NSRect actualFrom = [self currentAnimatedPositionFrom:from];

    // Cancel any existing animation without requesting full redraw since we're
    // about to start a new one immediately
    if (_animationInProgress) {
        [self endLegacyAnimationAndRequestRedraw:NO];
    }

    // Store weak reference to the legacy view for display link callbacks
    _slideLegacyView = view;

    // Set animation state
    _animationInProgress = YES;
    _slideStartTime = CACurrentMediaTime();
    _slideStartRect = actualFrom;
    _slideEndRect = to;

    // Calculate the union rect (area that needs to be redrawn during animation)
    _slideAnimationRect = NSUnionRect(actualFrom, to);
    // Add a small margin for safety
    _slideAnimationRect = NSInsetRect(_slideAnimationRect, -1, -1);

    _slideCursorColor = [color copy];

    // Capture screenshot of the region (without cursor - cursor is already hidden via animationInProgress)
    [self captureScreenshotInView:view];

    // Trigger first redraw - subsequent frames will be requested after each draw
    [view setNeedsDisplayInRect:_slideAnimationRect];
}

- (void)beginMetalAnimationFrom:(NSRect)from to:(NSRect)to {
    DLog(@"Begin Metal slide animation from %@ to %@", NSStringFromRect(from), NSStringFromRect(to));

    // If an animation is already in progress, continue from the current animated position
    NSRect actualFrom = [self currentAnimatedPositionFrom:from];

    // Set animation state
    _animationInProgress = YES;
    _slideStartTime = CACurrentMediaTime();
    _slideStartRect = actualFrom;
    _slideEndRect = to;

    // Tell delegate we need continuous redraws
    [_delegate cursorSlideAnimatorSetAnimated:YES];
}

- (NSRect)currentAnimatedPositionFrom:(NSRect)fallback {
    if (!_animationInProgress) {
        return fallback;
    }

    CFTimeInterval elapsed = CACurrentMediaTime() - _slideStartTime;
    CGFloat progress = MIN(1.0, elapsed / [[self class] animationDuration]);
    CGFloat easedProgress = [self easedProgress:progress];

    CGFloat currentX = _slideStartRect.origin.x + (_slideEndRect.origin.x - _slideStartRect.origin.x) * easedProgress;
    CGFloat currentY = _slideStartRect.origin.y + (_slideEndRect.origin.y - _slideStartRect.origin.y) * easedProgress;
    NSRect result = NSMakeRect(currentX, currentY, _slideEndRect.size.width, _slideEndRect.size.height);
    DLog(@"Continuing from current animated position %@", NSStringFromRect(result));
    return result;
}

#pragma mark - Ending Animations

- (void)endLegacyAnimationAndRequestRedraw:(BOOL)requestRedraw {
    DLog(@"End legacy slide animation (requestRedraw=%d)", requestRedraw);
    _animationInProgress = NO;

    NSRect animRect = _slideAnimationRect;
    NSView *legacyView = _slideLegacyView;

    _slideScreenshot = nil;
    _slideCursorColor = nil;
    _slideAnimationRect = NSZeroRect;
    _slideStartRect = NSZeroRect;
    _slideEndRect = NSZeroRect;
    _slideLegacyView = nil;

    if (requestRedraw) {
        // Request final redraw to show cursor at final position
        [_delegate cursorSlideAnimatorRequestDelegateRedraw];

        // Also invalidate the animation region specifically
        if (legacyView && !NSIsEmptyRect(animRect)) {
            [legacyView setNeedsDisplayInRect:animRect];
        }
    }
}

- (void)endMetalAnimation {
    DLog(@"End Metal slide animation");
    _animationInProgress = NO;
    _slideStartRect = NSZeroRect;
    _slideEndRect = NSZeroRect;
}

#pragma mark - Querying Animation State

- (CGPoint)cursorPixelOffset {
    if (!_animationInProgress) {
        return CGPointZero;
    }

    CFTimeInterval elapsed = CACurrentMediaTime() - _slideStartTime;
    CGFloat progress = MIN(1.0, elapsed / [[self class] animationDuration]);

    // End animation when complete
    if (progress >= 1.0) {
        // Defer ending animation to avoid state changes during frame preparation
        DLog(@"cursorPixelOffset: animation complete, returning zero");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endMetalAnimation];
        });
        return CGPointZero;
    }

    // Keep requesting redraws - this triggers the next frame similar to how animated GIFs work
    [_delegate cursorSlideAnimatorSetAnimated:YES];
    [_delegate cursorSlideAnimatorRequestDelegateRedraw];

    // Ease-out interpolation
    CGFloat easedProgress = [self easedProgress:progress];

    // Calculate current position
    CGFloat currentX = _slideStartRect.origin.x + (_slideEndRect.origin.x - _slideStartRect.origin.x) * easedProgress;
    CGFloat currentY = _slideStartRect.origin.y + (_slideEndRect.origin.y - _slideStartRect.origin.y) * easedProgress;

    // Return offset from end position (where cursor would normally be drawn)
    return CGPointMake(currentX - _slideEndRect.origin.x, currentY - _slideEndRect.origin.y);
}

- (NSRect)currentCursorRect {
    if (!_animationInProgress) {
        return NSZeroRect;
    }

    CFTimeInterval elapsed = CACurrentMediaTime() - _slideStartTime;
    CGFloat progress = MIN(1.0, elapsed / [[self class] animationDuration]);
    CGFloat easedProgress = [self easedProgress:progress];

    CGFloat x = _slideStartRect.origin.x + (_slideEndRect.origin.x - _slideStartRect.origin.x) * easedProgress;
    CGFloat y = _slideStartRect.origin.y + (_slideEndRect.origin.y - _slideStartRect.origin.y) * easedProgress;
    return NSMakeRect(x, y, _slideEndRect.size.width, _slideEndRect.size.height);
}

#pragma mark - Legacy Drawing

- (BOOL)drawAnimatedCursorInRect:(NSRect)dirtyRect {
    if (!_animationInProgress || _slideScreenshot == nil) {
        return NO;
    }

    // Only use the fast path if the dirty rect is approximately the animation rect.
    // If a larger region needs redrawing, let normal drawing handle it.
    const CGFloat tolerance = 2.0;
    BOOL isAnimationRectOnly = (fabs(dirtyRect.origin.x - _slideAnimationRect.origin.x) < tolerance &&
                                fabs(dirtyRect.origin.y - _slideAnimationRect.origin.y) < tolerance &&
                                fabs(dirtyRect.size.width - _slideAnimationRect.size.width) < tolerance &&
                                fabs(dirtyRect.size.height - _slideAnimationRect.size.height) < tolerance);

    if (!isAnimationRectOnly) {
        // A larger region needs to be drawn. Let normal drawing proceed.
        return NO;
    }

    // Validate that animation rect is still within the view bounds (handles resize)
    NSView *legacyView = _slideLegacyView;
    if (legacyView && !NSContainsRect(legacyView.bounds, _slideAnimationRect)) {
        // View was resized, abort animation
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endLegacyAnimationAndRequestRedraw:YES];
        });
        return NO;
    }

    // Fast path: just redraw the animation region with screenshot + interpolated cursor
    CFTimeInterval elapsed = CACurrentMediaTime() - _slideStartTime;
    CGFloat progress = MIN(1.0, elapsed / [[self class] animationDuration]);
    CGFloat easedProgress = [self easedProgress:progress];

    // Draw the screenshot (background without cursor)
    [_slideScreenshot drawInRect:_slideAnimationRect
                        fromRect:NSZeroRect
                       operation:NSCompositingOperationCopy
                        fraction:1.0
                  respectFlipped:YES
                           hints:nil];

    // Draw cursor at interpolated position
    NSRect cursorRect = [self interpolatedCursorRectWithEasedProgress:easedProgress];
    [_slideCursorColor set];
    NSRectFill(cursorRect);

    // Check if animation is complete
    if (progress >= 1.0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endLegacyAnimationAndRequestRedraw:YES];
        });
    } else {
        // Request next frame
        NSRect animRect = _slideAnimationRect;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_delegate cursorSlideAnimatorNeedsRedrawInRect:animRect inView:legacyView];
        });
    }

    return YES;
}

- (void)drawCursorAfterNormalDrawInView:(NSView *)view
                       startedThisFrame:(BOOL)startedThisFrame {
    if (!_animationInProgress || _slideCursorColor == nil || _capturingSlideScreenshot) {
        return;
    }

    CFTimeInterval elapsed = CACurrentMediaTime() - _slideStartTime;
    CGFloat progress = MIN(1.0, elapsed / [[self class] animationDuration]);

    if (startedThisFrame) {
        // New animation just started - draw cursor at start position
        [_slideCursorColor set];
        NSRectFill(_slideStartRect);
    } else {
        // Animation was already in progress - draw at interpolated position
        CGFloat easedProgress = [self easedProgress:progress];
        NSRect cursorRect = [self interpolatedCursorRectWithEasedProgress:easedProgress];
        [_slideCursorColor set];
        NSRectFill(cursorRect);
    }

    // Request next frame or end animation
    if (progress >= 1.0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endLegacyAnimationAndRequestRedraw:YES];
        });
    } else {
        NSRect animRect = _slideAnimationRect;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_delegate cursorSlideAnimatorNeedsRedrawInRect:animRect inView:view];
        });
    }
}

#pragma mark - Private Helpers

- (CGFloat)easedProgress:(CGFloat)progress {
    // Ease-out interpolation: 1 - (1 - t)^2
    return 1.0 - pow(1.0 - progress, 2);
}

- (NSRect)interpolatedCursorRectWithEasedProgress:(CGFloat)easedProgress {
    CGFloat x = _slideStartRect.origin.x + (_slideEndRect.origin.x - _slideStartRect.origin.x) * easedProgress;
    CGFloat y = _slideStartRect.origin.y + (_slideEndRect.origin.y - _slideStartRect.origin.y) * easedProgress;
    return NSMakeRect(x, y, _slideEndRect.size.width, _slideEndRect.size.height);
}

- (void)captureScreenshotInView:(NSView *)view {
    _slideScreenshot = nil;

    // Create bitmap rep for the animation rect
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:_slideAnimationRect];
    if (rep == nil) {
        DLog(@"Failed to create bitmap rep for slide screenshot");
        return;
    }

    // Set flag to prevent recursion - cacheDisplayInRect: will trigger drawRect:inView:
    _capturingSlideScreenshot = YES;

    // Cache the display (this will render without cursor since animationInProgress is YES)
    [view cacheDisplayInRect:_slideAnimationRect toBitmapImageRep:rep];

    _capturingSlideScreenshot = NO;

    // Create NSImage from the rep
    _slideScreenshot = [[NSImage alloc] initWithSize:_slideAnimationRect.size];
    [_slideScreenshot addRepresentation:rep];
}

@end
