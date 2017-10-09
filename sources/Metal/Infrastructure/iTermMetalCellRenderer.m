#import "iTermMetalCellRenderer.h"

const CGFloat MARGIN_WIDTH = 10;
const CGFloat TOP_MARGIN = 2;
const CGFloat BOTTOM_MARGIN = 2;

NS_ASSUME_NONNULL_BEGIN

@interface iTermMetalCellRendererTransientState()
@property (nonatomic, readwrite) VT100GridSize gridSize;
@property (nonatomic, readwrite) CGSize cellSize;
@property (nonatomic, readwrite) id<MTLBuffer> offsetBuffer;
@property (nonatomic, readwrite) size_t piuElementSize;
@end

@implementation iTermMetalCellRendererTransientState

- (void)setPIUValue:(void *)valuePointer coord:(VT100GridCoord)coord {
    const size_t index = coord.x + coord.y * self.gridSize.width;
    memcpy(self.pius.contents + index * _piuElementSize, valuePointer, _piuElementSize);
}

- (const void *)piuForCoord:(VT100GridCoord)coord {
    const size_t index = coord.x + coord.y * self.gridSize.width;
    return self.pius.contents + index * _piuElementSize;
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

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                                   cellSize:(CGSize)cellSize
                                   gridSize:(VT100GridSize)gridSize
                              commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer completion:(nonnull void (^)(__kindof iTermMetalCellRendererTransientState * _Nonnull))completion {
    [super createTransientStateForViewportSize:viewportSize commandBuffer:commandBuffer completion:^(__kindof iTermMetalRendererTransientState * _Nonnull transientState) {
        iTermMetalCellRendererTransientState *tState = transientState;
        tState.piuElementSize = _piuElementSize;
        tState.gridSize = gridSize;
        tState.cellSize = cellSize;

        CGSize usableSize = CGSizeMake(tState.viewportSize.x - MARGIN_WIDTH * 2,
                                       tState.viewportSize.y - TOP_MARGIN - BOTTOM_MARGIN);

        vector_float2 offset = {
            MARGIN_WIDTH,
            fmod(usableSize.height, tState.cellSize.height) + BOTTOM_MARGIN
        };
        tState.offsetBuffer = [self.device newBufferWithBytes:&offset
                                                       length:sizeof(offset)
                                                      options:MTLResourceStorageModeShared];
        completion(tState);
    }];
}

@end

NS_ASSUME_NONNULL_END

