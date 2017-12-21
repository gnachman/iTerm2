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

struct iTermMetalBackgroundColorRLE {
    vector_float4 color;
    unsigned short origin;  // Not strictly needed but this is needed to binary search the RLEs
    unsigned short count;
#if __cplusplus
    bool operator<(const iTermMetalBackgroundColorRLE &other) const {
        return origin < other.origin;
    }
    bool operator<(const int &other) const {
        return origin < other;
    }
#endif
};

typedef struct iTermMetalBackgroundColorRLE iTermMetalBackgroundColorRLE;

@class iTermCharacterBitmap;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
@property (nonatomic) vector_float4 defaultBackgroundColor;


- (void)setGlyphKeysData:(NSData *)glyphKeysData
                   count:(int)count
          attributesData:(NSData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(NSData *)backgroundColorData  // array of iTermMetalBackgroundColorRLE background colors.
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;
- (void)willDraw;
- (void)didComplete;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation;

@end

NS_ASSUME_NONNULL_END

