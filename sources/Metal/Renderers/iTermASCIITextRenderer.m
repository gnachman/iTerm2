//
//  iTermASCIITextRenderer.m
//  iTerm2Shared
//
//  Created by George Nachman on 2/17/18.
//

#import "iTermASCIITextRenderer.h"

#import "iTermASCIITexture.h"
#import "ScreenChar.h"

@interface iTermASCIITextRendererTransientState()
@property (nonatomic, readonly) NSArray<NSData *> *lines;
@property (nonatomic, strong) iTermASCIITextureGroup *asciiTextureGroup;
@end

@implementation iTermASCIITextRendererTransientState {
    iTerm2::PIUArray<iTermTextPIU> _asciiPIUArrays[iTermASCIITextureAttributesMax * 2];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    @autoreleasepool {
        for (int i = 0; i < sizeof(_asciiPIUArrays) / sizeof(*_asciiPIUArrays); i++) {
            NSMutableString *s = [NSMutableString string];
            const int size = _asciiPIUArrays[i].size();
            for (int j = 0; j < size; j++) {
                const iTermTextPIU &a = _asciiPIUArrays[i].get(j);
                [s appendString:[self.class formatTextPIU:a]];
            }
            NSMutableString *name = [NSMutableString stringWithFormat:@"asciiPIUs."];
            if (i & iTermASCIITextureAttributesBold) {
                [name appendString:@"B"];
            }
            if (i & iTermASCIITextureAttributesItalic) {
                [name appendString:@"I"];
            }
            if (i & iTermASCIITextureAttributesThinStrokes) {
                [name appendString:@"T"];
            }
            [name appendString:@".txt"];
            [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    }
    NSString *s = [NSString stringWithFormat:@"backgroundTexture=%@\nasciiUnderlineDescriptor=%@\defaultBackgroundColor=(%@, %@, %@, %@)",
                   _backgroundTexture,
                   iTermMetalUnderlineDescriptorDescription(&_asciiUnderlineDescriptor),
                   @(_defaultBackgroundColor.x),
                   @(_defaultBackgroundColor.y),
                   @(_defaultBackgroundColor.z),
                   @(_defaultBackgroundColor.w)];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

@end

@implementation iTermASCIITextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalMixedSizeBufferPool *_piuPool;
    iTermASCIITextureGroup *_asciiTextureGroup;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermASCIITextVertexShader"
                                                  fragmentFunctionName:@"iTermASCIITextFragmentShader"
                                                              blending:[iTermMetalBlending compositeSourceOver]
                                                        piuElementSize:sizeof(screen_char_t)
                                                   transientStateClass:[iTermASCIITextRendererTransientState class]];
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:512
                                                                    name:@"ASCII PIU lines"];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateASCIITextTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
    [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermASCIITextRendererTransientState *)tState {
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellConfiguration.cellSize
                                           poolContext:tState.poolContext];
    tState.vertexBuffer.label = @"Vertices";
    tState.asciiTextureGroup = _asciiTextureGroup;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermASCIITextRendererTransientState *tState = transientState;

    [tState enumerateDraws:^(NSData *data) {
        id<MTLBuffer> pius = [_piuPool requestBufferFromContext:tState.poolContext
                                                           size:data.length
                                                          bytes:data.bytes];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:data.length / sizeof(screen_char_t)
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                 @(iTermVertexInputIndexPerInstanceUniforms): pius,
                                                 @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.marksArrayTexture.texture } ];
    }];
}

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    iTermASCIITextureGroup *replacement = [[iTermASCIITextureGroup alloc] initWithCellSize:cellSize
                                                                                    device:_cellRenderer.device
                                                                        creationIdentifier:(id)creationIdentifier
                                                                                  creation:creation];
    if (![replacement isEqual:_asciiTextureGroup]) {
        _asciiTextureGroup = replacement;
    }
}


@end
