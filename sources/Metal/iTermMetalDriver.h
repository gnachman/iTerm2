#import "VT100GridTypes.h"

#import "iTermASCIITexture.h"
#import "iTermCursor.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRenderer.h"

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
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

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSourcePerFrameState<NSObject>

@property (nonatomic, readonly) VT100GridSize gridSize;
@property (nonatomic, readonly) vector_float4 defaultBackgroundColor;

- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
               background:(iTermMetalBackgroundColorRLE *)backgrounds
                 rleCount:(int *)rleCount
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr;

- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo;

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                        size:(CGSize)size
                                                                       scale:(CGFloat)scale
                                                                       emoji:(BOOL *)emoji;

// Returns the background image or nil. If there's a background image, fill in blending and tiled.
- (NSImage *)metalBackgroundImageGetBlending:(CGFloat *)blending tiled:(BOOL *)tiled;

// An object that compares as equal if ascii characters produced by metalImagesForGlyph would
// produce the same bitmap.
- (id)metalASCIICreationIdentifier;

// Returns metrics and optional color for underlines.
- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSource<NSObject>

- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame;
- (void)metalDriverDidDrawFrame;

@end

// Our platform independent render class
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDriver : NSObject<MTKViewDelegate>

@property (nullable, nonatomic, weak) id<iTermMetalDriverDataSource> dataSource;

- (nullable instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;
- (void)setCellSize:(CGSize)cellSize gridSize:(VT100GridSize)gridSize scale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END

