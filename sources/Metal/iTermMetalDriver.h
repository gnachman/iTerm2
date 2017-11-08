#import "VT100GridTypes.h"

#import "iTermCursor.h"
#include "iTermMetalGlyphKey.h"

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

@interface iTermMetalCursorInfo : NSObject
@property (nonatomic) BOOL cursorVisible;
@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) ITermCursorType type;
@property (nonatomic, strong) NSColor *cursorColor;

// Block cursors care about drawing the character overtop the cursor in a
// different color than the character would normally be. If this is set, the
// text color will be changed to that of the `textColor` property.
@property (nonatomic) BOOL shouldDrawText;
@property (nonatomic) vector_float4 textColor;

// This is a "frame" cursor, as seen when the view does not have focus.
@property (nonatomic) BOOL frameOnly;
@end

@protocol iTermMetalDriverDataSourcePerFrameState<NSObject>

@property (nonatomic, readonly) VT100GridSize gridSize;

- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
               background:(vector_float4 *)backgrounds
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr;

- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo;

- (NSImage *)metalImageForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                              size:(CGSize)size
                             scale:(CGFloat)scale;

// Returns the background image or nil. If there's a background image, fill in blending and tiled.
- (NSImage *)metalBackgroundImageGetBlending:(CGFloat *)blending tiled:(BOOL *)tiled;

@end

@protocol iTermMetalDriverDataSource<NSObject>

- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame;

@end

// Our platform independent render class
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDriver : NSObject<MTKViewDelegate>

@property (nullable, nonatomic, weak) id<iTermMetalDriverDataSource> dataSource;

- (nullable instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;
- (void)setCellSize:(CGSize)cellSize gridSize:(VT100GridSize)gridSize scale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END

