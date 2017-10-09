#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTextureMap;

@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;

- (void)setGlyphKeysData:(NSData *)glyphKeysData
          attributesData:(NSData *)attributesData
                     row:(int)row
                creation:(NSImage *(NS_NOESCAPE ^)(int x))creation;
- (void)willDraw;
- (void)didComplete;

@end

@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic, readonly) BOOL canRenderImmediately;

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

