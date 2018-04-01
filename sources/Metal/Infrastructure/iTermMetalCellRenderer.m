#import "iTermAdvancedSettingsModel.h"

#import "iTermMetalCellRenderer.h"
#import "iTermMetalBufferPool.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermCellRenderConfiguration

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                               scale:(CGFloat)scale
                            cellSize:(CGSize)cellSize
              cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                            gridSize:(VT100GridSize)gridSize
               usingIntermediatePass:(BOOL)usingIntermediatePass {
    self = [super initWithViewportSize:viewportSize scale:scale];
    if (self) {
        _cellSize = cellSize;
        _cellSizeWithoutSpacing = cellSizeWithoutSpacing;
        _gridSize = gridSize;
        _usingIntermediatePass = usingIntermediatePass;
    }
    return self;
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@: %p viewportSize=%@x%@ scale=%@ cellSize=%@ cellSizeWithoutSpacing=%@ gridSize=%@ usingIntermediatePass=%@>",
            NSStringFromClass([self class]),
            self,
            @(self.viewportSize.x),
            @(self.viewportSize.y),
            @(self.scale),
            NSStringFromSize(self.cellSize),
            NSStringFromSize(self.cellSizeWithoutSpacing),
            VT100GridSizeDescription(self.gridSize),
            self.usingIntermediatePass ? @"YES" : @"NO"];
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

- (NSEdgeInsets)margins {
    const CGFloat MARGIN_WIDTH = [iTermAdvancedSettingsModel terminalMargin] * self.configuration.scale;
    const CGFloat MARGIN_HEIGHT = 0;

    CGSize usableSize = CGSizeMake(self.cellConfiguration.viewportSize.x - MARGIN_WIDTH * 2,
                                   self.cellConfiguration.viewportSize.y - MARGIN_HEIGHT * 2);
    return NSEdgeInsetsMake(fmod(usableSize.height, self.cellConfiguration.cellSize.height) + MARGIN_HEIGHT,
                            MARGIN_WIDTH,
                            MARGIN_HEIGHT,
                            fmod(usableSize.width, self.cellConfiguration.cellSize.width) + MARGIN_WIDTH);
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];

    NSString *info = [NSString stringWithFormat:@"margins=(top=%@, left=%@, bottom=%@,right= %@)", @(self.margins.top), @(self.margins.left), @(self.margins.bottom), @(self.margins.right)];
    [info writeToURL:[folder URLByAppendingPathComponent:@"CellTransientState.txt"]
          atomically:NO
            encoding:NSUTF8StringEncoding
               error:NULL];

}

@end

@implementation iTermMetalCellRenderer {
    Class _transientStateClass;
    size_t _piuElementSize;
    iTermMetalBufferPool *_offsetBuffers;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(nullable iTermMetalBlending *)blending
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
        _offsetBuffers = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2)];
    }
    return self;
}

- (Class)transientStateClass {
    return _transientStateClass;
}

- (__kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState *transientState =
    [super createTransientStateForConfiguration:configuration commandBuffer:commandBuffer];

    iTermMetalCellRendererTransientState *tState = transientState;
    tState.piuElementSize = _piuElementSize;

    const NSEdgeInsets margins = tState.margins;
    const vector_float2 offset = {
        margins.left,
        margins.top
    };
    tState.offsetBuffer = [_offsetBuffers requestBufferFromContext:tState.poolContext
                                                         withBytes:&offset
                                                    checkIfChanged:YES];
    return tState;
}

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputIndexOffset && buffer.length == sizeof(vector_float2)) {
        vector_float2 *v = (vector_float2 *)buffer.contents;
        NSString *s = [NSString stringWithFormat:@"offset=(%@, %@)\n",
                       @(v->x), @(v->y)];
        [s writeToURL:[folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexOffset.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    } else {
        [super writeVertexBuffer:buffer index:index toFolder:folder];
    }
}

@end

NS_ASSUME_NONNULL_END

