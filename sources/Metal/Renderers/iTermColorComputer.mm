//
//  iTermColorComputer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/18.
//

#import "iTermColorComputer.h"

#import "iTermData.h"
#import "iTermMetalRenderer.h"
#import "iTermScreenChar.h"

@interface iTermColorComputerTransientState()
@property (nonatomic, readonly) int rows;
@property (nonatomic, strong) NSData *colorMap;
@property (nonatomic, readonly) id<MTLBuffer> configurationBuffer;
@property (nonatomic) iTermColorsConfiguration config;
@property (nonatomic, strong) id<MTLBuffer> debugBuffer;
@property (nonatomic, strong) id<MTLBuffer> outputBuffer;
@end

@implementation iTermColorComputerTransientState

- (int)rows {
    return _lines.length / (sizeof(screen_char_t) * (_config.gridSize.x + 1));
}

- (id<MTLBuffer>)configurationBufferWithPool:(iTermMetalBufferPool *)pool {
    return [pool requestBufferFromContext:self.poolContext
                                withBytes:&_config
                           checkIfChanged:YES];
}


- (const char *)debugOutput {
    iTermMetalDebugBuffer *buffer = (iTermMetalDebugBuffer *)self.debugBuffer.contents;
    return buffer->storage;
}

@end

@implementation iTermColorComputer {
    iTermMetalComputer *_computer;
    iTermMetalMixedSizeBufferPool *_colorMapPool;
    iTermMetalMixedSizeBufferPool *_bitmapPool;
    iTermMetalMixedSizeBufferPool *_outputPool;
    iTermMetalBufferPool *_configurationPool;
    iTermMetalBufferPool *_debugBufferPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        Class c = [iTermColorComputerTransientState class];
        _computer = [[iTermMetalComputer alloc] initWithDevice:device
                                           computeFunctionName:@"iTermColorKernelFunction"
                                           transientStateClass:c];
        _colorMapPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                     capacity:iTermMetalDriverMaximumNumberOfFramesInFlight + 1
                                                                         name:@"Serialized Color Maps"];
        const int categories = 5;  // Number of bitfields that get passed to kernel
        _bitmapPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                   capacity:categories * (iTermMetalDriverMaximumNumberOfFramesInFlight + 1)
                                                                       name:@"Bit fields"];
        _configurationPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermColorsConfiguration)];
        _debugBufferPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermMetalDebugBuffer)];
        _outputPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                   capacity:iTermMetalDriverMaximumNumberOfFramesInFlight + 1
                                                                       name:@"Color outputd"];
    }
    return self;
}

- (__kindof iTermMetalComputerTransientState *)createTransientStateWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalComputerTransientState * _Nonnull transientState =
        [_computer createTransientStateWithCommandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermColorComputerTransientState *)tState {
    tState.colorMap = _colorMap;
    tState.config = _config;
    iTermMetalDebugBuffer debugBuffer = {
        .offset = 0,
        .capacity = METAL_DEBUG_BUFFER_SIZE
    };
    memset(debugBuffer.storage, 0, METAL_DEBUG_BUFFER_SIZE);
    tState.debugBuffer = [_debugBufferPool requestBufferFromContext:tState.poolContext
                                                          withBytes:&debugBuffer
                                                     checkIfChanged:YES];
#warning TODO: Make the mode private
    tState.outputBuffer = [_outputPool requestBufferFromContext:tState.poolContext
                                                           size:(_config.gridSize.x + 1) * _config.gridSize.y * sizeof(iTermCellColors)];
}

- (void)executeComputePassWithTransientState:(__kindof iTermMetalComputerTransientState *)transientState
                              computeEncoder:(id <MTLComputeCommandEncoder>)computeEncoder {
    iTermColorComputerTransientState *tState = transientState;
    iTermData *lines = tState.lines;
    assert(lines);
    assert(lines.length > 0);
    id<MTLBuffer> screenCharsBuffer = [_computer.device newBufferWithBytesNoCopy:lines.mutableBytes
                                                                          length:lines.allocatedCapacity
                                                                         options:MTLResourceStorageModeShared
                                                                     deallocator:^(void * _Nonnull pointer, NSUInteger length) {
                                                                         // Just need to retain a reference to lines until it's done
                                                                         [lines length];
                                                                     }];
    id<MTLBuffer> colorMapBuffer = [_colorMapPool requestBufferFromContext:tState.poolContext
                                                                      size:tState.colorMap.length
                                                                     bytes:tState.colorMap.bytes];
    id<MTLBuffer> selectedIndices = [_bitmapPool requestBufferFromContext:tState.poolContext
                                                                     size:tState.selectedIndices.length
                                                                    bytes:tState.selectedIndices.bytes];
    id<MTLBuffer> findMatches = [_bitmapPool requestBufferFromContext:tState.poolContext
                                                                 size:tState.findMatches.length
                                                                bytes:tState.findMatches.bytes];
    id<MTLBuffer> annotatedIndices = [_bitmapPool requestBufferFromContext:tState.poolContext
                                                                      size:tState.annotatedIndices.length
                                                                     bytes:tState.annotatedIndices.bytes];
    id<MTLBuffer> markedIndices = [_bitmapPool requestBufferFromContext:tState.poolContext
                                                                   size:tState.markedIndices.length
                                                                  bytes:tState.markedIndices.bytes];
    id<MTLBuffer> underlinedIndices = [_bitmapPool requestBufferFromContext:tState.poolContext
                                                                       size:tState.underlinedIndices.length
                                                                      bytes:tState.underlinedIndices.bytes];
    id<MTLBuffer> configBuffer = [tState configurationBufferWithPool:_configurationPool];

    NSDictionary<NSNumber *, id<MTLBuffer>> *buffers =
    @{
      @(iTermVertexInputIndexColorMap): colorMapBuffer,
      @(iTermComputeIndexScreenChars): screenCharsBuffer,
      @(iTermVertexInputSelectedIndices): selectedIndices,
      @(iTermVertexInputFindMatchIndices): findMatches,
      @(iTermVertexInputAnnotatedIndices): annotatedIndices,
      @(iTermVertexInputMarkedIndices): markedIndices,
      @(iTermVertexInputUnderlinedIndices): underlinedIndices,
      @(iTermComputeIndexColorsConfig): configBuffer,
      @(iTermVertexInputDebugBuffer): tState.debugBuffer,
      @(iTermComputeIndexColors): tState.outputBuffer,
    };

    // https://developer.apple.com/documentation/metal/compute_processing/calculating_threadgroup_and_grid_sizes?language=objc

    // ∏(dims, threadsPerThreadgroup) ≤ maxTotalThreadsPerThreadgroup
    //                                = k * threadExecutionWidth
    const NSUInteger w = _computer.computePipelineState.threadExecutionWidth;
    const NSUInteger h = _computer.computePipelineState.maxTotalThreadsPerThreadgroup / w;
    const MTLSize threadsPerThreadgroup = MTLSizeMake(w, h, 1);

    // Number of buckets the grid gets divided into.
    const vector_uint2 gridSize = tState.config.gridSize;
    const MTLSize threadgroupsPerGrid = MTLSizeMake((gridSize.x + 1 + w - 1) / w,  // add 1 for eol marker
                                                    (gridSize.y + h - 1) / h,
                                                    1);

    // In this example, the grid is 11x7. There are 6 thread groups A…F.
    // Threadgroups per grid is 6 (3×2). Threads per threadgroup is 16 (4×4).
    // The kernel function has to bounds check its coordinates since not all threadgroups have
    // a data point for all locations it could cover.
    // AAAA BBBB CCC
    // AAAA BBBB CCC
    // AAAA BBBB CCC
    // AAAA BBBB CCC
    // DDDD EEEE FFF
    // DDDD EEEE FFF
    // DDDD EEEE FFF
    [_computer executeComputePassWithTransientState:tState
                                     computeEncoder:computeEncoder
                                           textures:@{}
                                            buffers:buffers
                                    threadgroupSize:threadgroupsPerGrid
                                   threadgroupCount:threadsPerThreadgroup];
}

@end
