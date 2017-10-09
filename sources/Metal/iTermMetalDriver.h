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
@end

@protocol iTermMetalDriverDataSourcePerFrameState<NSObject>

- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
               background:(vector_float4 *)backgrounds
                      row:(int)row
                    width:(int)width;

- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo;

- (NSImage *)metalImageForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                              size:(CGSize)size
                             scale:(CGFloat)scale;
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

