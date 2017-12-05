#import "iTermASCIITexture.h"
#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"

NS_ASSUME_NONNULL_BEGIN

// Describes how underlines should be drawn.
typedef struct {
    // Offset from the top of the cell, in points.
    float offset;

    // Line thickness, in points.
    float thickness;

    // Color to draw line in.
    vector_float4 color;
} iTermMetalUnderlineDescriptor;

@class iTermTextureMap;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;


- (void)setGlyphKeysData:(NSData *)glyphKeysData
                   count:(int)count
          attributesData:(NSData *)attributesData
                     row:(int)row
     backgroundColorData:(NSData *)backgroundColorData  // array of vector_float4 background colors.
                creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;
- (void)willDrawWithDefaultBackgroundColor:(vector_float4)defaultBackgroundColor;
- (void)didComplete;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic, readonly) BOOL canRenderImmediately;

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(nullable NSImage *(^)(char, iTermASCIITextureAttributes))creation;

@end

NS_ASSUME_NONNULL_END

