#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermCopyModeCursorRenderer;

// Cursor geometry, in grid pixel coordinates: origin at the bottom left of the
// grid, before the viewport offset is applied. Shared by the cursor renderers
// and by the text renderer's recoloring of text under a box cursor so the two
// cannot drift apart.

// Height of a cursor that covers the cell vertically.
CGFloat iTermCursorHeightForCellConfiguration(iTermCellRenderConfiguration *cellConfiguration);

// Bottom left corner of a cursor of height `cursorHeight` at `coord`.
CGPoint iTermCursorOriginForCellConfiguration(iTermCellRenderConfiguration *cellConfiguration,
                                              VT100GridCoord coord,
                                              CGPoint pixelOffset,
                                              CGFloat cursorHeight);

// Frame of the filled box cursor at `coord`.
CGRect iTermBlockCursorFrame(iTermCellRenderConfiguration *cellConfiguration,
                             VT100GridCoord coord,
                             BOOL doubleWidth,
                             CGPoint pixelOffset);

@interface iTermCursorRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) BOOL doubleWidth;
@property (nonatomic) BOOL backgroundIsDark;
// Pixel offset for smooth cursor animation
@property (nonatomic) CGPoint pixelOffset;

// When YES, draw the cursor as a bright HDR white (the HDR-cursor hint applied).
@property (nonatomic) BOOL useHDRCursor;
// Requested peak brightness for the HDR cursor, in units of reference white.
@property (nonatomic) CGFloat hdrBrightness;
// Opacity in [0, 1] for smooth blink fading. Defaults to 1.
@property (nonatomic) CGFloat fadeAlpha;
@end

@interface iTermCursorRenderer : NSObject<iTermMetalCellRenderer>

+ (instancetype)newUnderlineCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newBarCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newIMECursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newBlockCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newFrameCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newKeyCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newHorizontalShadowCursorRendererWithDevice:(id<MTLDevice>)device;
+ (instancetype)newVerticalShadowCursorRendererWithDevice:(id<MTLDevice>)device;

+ (iTermCopyModeCursorRenderer *)newCopyModeCursorRendererWithDevice:(id<MTLDevice>)device;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermCopyModeCursorRendererTransientState : iTermCursorRendererTransientState
@property (nonatomic) BOOL selecting;
@end

@interface iTermCopyModeCursorRenderer : iTermCursorRenderer
@end

@interface iTermFrameCursorRenderer : iTermCursorRenderer
@end

@interface iTermKeyCursorRenderer : iTermCursorRenderer
@end

NS_ASSUME_NONNULL_END
