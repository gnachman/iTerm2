#import "iTermMarkRenderer.h"
#import "iTermTextureArray.h"
#import "iTermMetalCellRenderer.h"

@interface iTermMarkRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) iTermTextureArray *marksArrayTexture;
@property (nonatomic) CGSize markSize;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *marks;
@end

@implementation iTermMarkRendererTransientState

- (nonnull NSData *)newMarkPerInstanceUniforms {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:sizeof(iTermMarkPIU) * _marks.count];
    iTermMarkPIU *pius = (iTermMarkPIU *)data.mutableBytes;
    __block size_t i = 0;
    [_marks enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull rowNumber, NSNumber * _Nonnull styleNumber, BOOL * _Nonnull stop) {
        MTLOrigin origin = [_marksArrayTexture offsetForIndex:styleNumber.integerValue];
        pius[i] = (iTermMarkPIU) {
            .offset = {
                2,
                (self.cellConfiguration.gridSize.height - rowNumber.intValue - 1) * self.cellConfiguration.cellSize.height
            },
            .textureOffset = { origin.x, origin.y }
        };
        i++;
    }];
    return data;
}

@end

@implementation iTermMarkRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermTextureArray *_marksArrayTexture;
    CGSize _markSize;
    NSMutableDictionary<NSNumber *, NSNumber *> *_marks;
    iTermMetalMixedSizeBufferPool *_piuPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _marks = [NSMutableDictionary dictionary];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermMarkVertexShader"
                                                  fragmentFunctionName:@"iTermMarkFragmentShader"
                                                              blending:YES
                                                        piuElementSize:sizeof(iTermMarkPIU)
                                                   transientStateClass:[iTermMarkRendererTransientState class]];
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:iTermMetalDriverMaximumNumberOfFramesInFlight + 1
                                                                    name:@"mark PIU"];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateMarkTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermMarkRendererTransientState *)tState {
    CGSize markSize = CGSizeMake(MAX(1, tState.margins.left - 2 * tState.configuration.scale),
                                 MAX(1, MIN(15, tState.cellConfiguration.cellSize.height - 1 * tState.configuration.scale)));
    if (!CGSizeEqualToSize(markSize, _markSize)) {
        // Mark size has changed
        _markSize = markSize;
        _marksArrayTexture = [[iTermTextureArray alloc] initWithTextureWidth:_markSize.width
                                                               textureHeight:_markSize.height
                                                                 arrayLength:3
                                                                      device:_cellRenderer.device];

        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:[NSColor blueColor] size:_markSize]];
        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:[NSColor redColor] size:_markSize]];
        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:[NSColor yellowColor] size:_markSize]];
    }
    tState.marksArrayTexture = _marksArrayTexture;
    tState.markSize = _markSize;
    tState.marks = [_marks copy];
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:_markSize poolContext:tState.poolContext];

    if (_marks.count > 0) {
        NSData *data = [tState newMarkPerInstanceUniforms];
        tState.pius = [_piuPool requestBufferFromContext:tState.poolContext
                                                    size:data.length];
        memcpy(tState.pius.contents, data.bytes, data.length);
    }
}

- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row {
    if (markStyle == iTermMarkStyleNone) {
        [_marks removeObjectForKey:@(row)];
    } else {
        _marks[@(row)] = @(markStyle);
    }
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermMarkRendererTransientState *tState = transientState;
    if (tState.marks.count == 0) {
        return;
    }

    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:_marks.count
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.marksArrayTexture.texture } ];
}

#pragma mark - Private

- (NSImage *)newImageWithMarkOfColor:(NSColor *)color size:(CGSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    NSBezierPath *path = [NSBezierPath bezierPath];

    [image lockFocus];
    [path moveToPoint:NSMakePoint(0,0)];
    [path lineToPoint:NSMakePoint(size.width - 1, size.height / 2)];
    [path lineToPoint:NSMakePoint(0, size.height - 1)];
    [path lineToPoint:NSMakePoint(0,0)];

    [color setFill];
    [path fill];
    [image unlockFocus];

    return image;
}

@end
