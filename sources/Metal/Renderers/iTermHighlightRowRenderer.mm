//
//  iTermHighlightRowRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/9/18.
//

#import "iTermHighlightRowRenderer.h"
#include <vector>

namespace iTerm2 {
    struct Highlight {
        vector_float4 color;
        int row;
    };
}

@interface iTermHighlightRowRendererTransientState()
- (void)enumerateDraws:(void (^)(vector_float4, int))block;
@end

@implementation iTermHighlightRowRendererTransientState {
    std::vector<iTerm2::Highlight> _highlights;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSMutableString *s = [NSMutableString string];
    for (auto h : _highlights) {
        [s appendFormat:@"color=(%@, %@, %@, %@) row=%@\n",
         @(h.color.x),
         @(h.color.y),
         @(h.color.z),
         @(h.color.w),
         @(h.row)];
    }
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (void)setOpacity:(CGFloat)opacity color:(vector_float3)color row:(int)row {
    iTerm2::Highlight h = {
        .color = simd_make_float4(color.x, color.y, color.z, opacity),
        .row = row
    };
    _highlights.push_back(h);
}

- (void)enumerateDraws:(void (^)(vector_float4, int))block {
    for (auto h : _highlights) {
        block(h.color, h.row);
    }
}

@end

@implementation iTermHighlightRowRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalBufferPool *_colorPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermHighlightRowVertexShader"
                                                  fragmentFunctionName:@"iTermHighlightRowFragmentShader"
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:0
                                                   transientStateClass:[iTermHighlightRowRendererTransientState class]];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateCursorGuideTS;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                                  commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermHighlightRowRendererTransientState *)tState {
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermHighlightRowRendererTransientState *tState = transientState;
    const VT100GridSize gridSize = tState.cellConfiguration.gridSize;
    const CGSize cellSize = tState.cellConfiguration.cellSize;
    const CGFloat top = tState.margins.top;
    const CGFloat left = tState.margins.left;
    const CGFloat right = tState.margins.right;

    [tState enumerateDraws:^(vector_float4 color, int row) {
        id<MTLBuffer> vertexBuffer = [self->_cellRenderer newQuadWithFrame:CGRectMake(0,
                                                                                      (gridSize.height - row - 1) * cellSize.height + top,
                                                                                      cellSize.width * gridSize.width + left + right,
                                                                                      cellSize.height)
                                                              textureFrame:CGRectMake(0, 0, 0, 0)
                                                               poolContext:tState.poolContext];
        id<MTLBuffer> colorBuffer = [self->_colorPool requestBufferFromContext:tState.poolContext
                                                                     withBytes:&color
                                                                checkIfChanged:YES];
        [self->_cellRenderer drawWithTransientState:tState
                                      renderEncoder:frameData.renderEncoder
                                   numberOfVertices:6
                                       numberOfPIUs:0
                                      vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                                    fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                           textures:@{}];
    }];
}

@end
