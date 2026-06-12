//
//  iTermCursorSlideAnimator.h
//  iTerm2
//
//  Encapsulates smooth cursor slide animation state and logic for both
//  legacy (screenshot-based) and Metal (pixel offset) rendering paths.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermCursorSlideAnimatorDelegate <NSObject>

// Called when the animator needs to request a redraw of a region.
- (void)cursorSlideAnimatorNeedsRedrawInRect:(NSRect)rect inView:(NSView *)view;

// Called when Metal animation state changes (to set drawingHelper.animated).
- (void)cursorSlideAnimatorSetAnimated:(BOOL)animated;

// Called when the animator needs a full delegate redraw.
- (void)cursorSlideAnimatorRequestDelegateRedraw;

@end

@interface iTermCursorSlideAnimator : NSObject

@property (nonatomic, weak, nullable) id<iTermCursorSlideAnimatorDelegate> delegate;

// YES while a slide animation is in progress. Used by drawing code to hide the real cursor.
@property (nonatomic, readonly) BOOL animationInProgress;

// YES while capturing a screenshot for legacy animation. Used to prevent recursion.
@property (nonatomic, readonly) BOOL capturingScreenshot;

// The animation duration in seconds.
@property (class, nonatomic, readonly) CFTimeInterval animationDuration;

#pragma mark - Starting Animations

// Start a legacy (screenshot-based) animation. The view is used to capture screenshots
// and request redraws.
- (void)beginLegacyAnimationFrom:(NSRect)from
                              to:(NSRect)to
                           color:(NSColor *)color
                          inView:(NSView *)view;

// Start a Metal animation. Metal will query cursorPixelOffset each frame.
- (void)beginMetalAnimationFrom:(NSRect)from to:(NSRect)to;

#pragma mark - Querying Animation State

// Returns the current cursor pixel offset from the final position.
// Returns CGPointZero if not animating or animation is complete.
// For Metal: this is the offset to apply to cursor rendering.
// For legacy: this can be used but typically drawAnimatedCursorInRect: handles it.
- (CGPoint)cursorPixelOffset;

#pragma mark - Legacy Drawing

// Fast path for legacy animation: if dirtyRect matches the animation region,
// draws the screenshot + interpolated cursor and returns YES.
// Returns NO if normal drawing should proceed.
- (BOOL)drawAnimatedCursorInRect:(NSRect)dirtyRect;

// Draw the cursor at the appropriate position during legacy animation.
// Call this after normal drawing when animationInProgress is YES.
// Returns YES if animation started this frame (cursor drawn at start position).
- (void)drawCursorAfterNormalDrawInView:(NSView *)view
                   startedThisFrame:(BOOL)startedThisFrame;

@end

NS_ASSUME_NONNULL_END
