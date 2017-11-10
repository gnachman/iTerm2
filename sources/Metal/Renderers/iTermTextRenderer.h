#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTextureMap;

@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;

- (void)setGlyphKeysData:(NSData *)glyphKeysData
                   count:(int)count
          attributesData:(NSData *)attributesData
                     row:(int)row
     backgroundColorData:(NSData *)backgroundColorData  // array of vector_float4 background colors.
                creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x))creation;
- (void)willDrawWithDefaultBackgroundColor:(vector_float4)defaultBackgroundColor;
- (void)didComplete;

@end

@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic, readonly) BOOL canRenderImmediately;

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

