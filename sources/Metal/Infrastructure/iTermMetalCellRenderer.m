#import "iTermMetalCellRenderer.h"

const CGFloat MARGIN_WIDTH = 10;
const CGFloat TOP_MARGIN = 2;
const CGFloat BOTTOM_MARGIN = 2;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermCellRenderConfiguration

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                               scale:(CGFloat)scale
                            cellSize:(CGSize)cellSize
                            gridSize:(VT100GridSize)gridSize
               usingIntermediatePass:(BOOL)usingIntermediatePass {
    self = [super initWithViewportSize:viewportSize scale:scale];
    if (self) {
        _cellSize = cellSize;
        _gridSize = gridSize;
        _usingIntermediatePass = usingIntermediatePass;
    }
    return self;
}

@end

@interface iTermMetalCellRendererTransientState()
@property (nonatomic, readwrite) id<MTLBuffer> offsetBuffer;
@property (nonatomic, readwrite) size_t piuElementSize;
@end

@implementation iTermMetalCellRendererTransientState

- (void)setPIUValue:(void *)valuePointer coord:(VT100GridCoord)coord {
    const size_t index = coord.x + coord.y * self.cellConfiguration.gridSize.width;
    memcpy(self.pius.contents + index * _piuElementSize, valuePointer, _piuElementSize);
}

- (const void *)piuForCoord:(VT100GridCoord)coord {
    const size_t index = coord.x + coord.y * self.cellConfiguration.gridSize.width;
    return self.pius.contents + index * _piuElementSize;
}

- (iTermCellRenderConfiguration *)cellConfiguration {
    return (iTermCellRenderConfiguration *)self.configuration;
}

@end

@implementation iTermMetalCellRenderer {
    Class _transientStateClass;
    size_t _piuElementSize;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                         piuElementSize:(size_t)piuElementSize
               transientStateClass:(Class)transientStateClass {
    self = [super initWithDevice:device
              vertexFunctionName:vertexFunctionName
            fragmentFunctionName:fragmentFunctionName
                        blending:blending
             transientStateClass:transientStateClass];
    if (self) {
        _piuElementSize = piuElementSize;
        _transientStateClass = transientStateClass;
    }
    return self;
}

- (Class)transientStateClass {
    return _transientStateClass;
}

- (void)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                      completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion {
    [super createTransientStateForConfiguration:configuration commandBuffer:commandBuffer completion:^(__kindof iTermMetalRendererTransientState * _Nonnull transientState) {
        iTermMetalCellRendererTransientState *tState = transientState;
        tState.piuElementSize = _piuElementSize;

        CGSize usableSize = CGSizeMake(tState.cellConfiguration.viewportSize.x - MARGIN_WIDTH * 2,
                                       tState.cellConfiguration.viewportSize.y - TOP_MARGIN - BOTTOM_MARGIN);
        vector_float2 offset = {
            MARGIN_WIDTH,
            fmod(usableSize.height, tState.cellConfiguration.cellSize.height) + BOTTOM_MARGIN
        };
        tState.offsetBuffer = [self.device newBufferWithBytes:&offset
                                                       length:sizeof(offset)
                                                      options:MTLResourceStorageModeShared];
        completion(tState);
    }];
}

@end

NS_ASSUME_NONNULL_END

