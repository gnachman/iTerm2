//
//  iTermTimestampsRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTimestampsRenderer.h"

#import "iTermTexturePool.h"
#import "iTermTimestampDrawHelper.h"

@interface iTermTimestampKey : NSObject
@property (nonatomic) CGFloat width;
@property (nonatomic) vector_float4 textColor;
@property (nonatomic) vector_float4 backgroundColor;
@property (nonatomic) NSTimeInterval date;
@end

@implementation iTermTimestampKey

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[iTermTimestampKey class]]) {
        return NO;
    }
    iTermTimestampKey *otherKey = other;
    return (_width == otherKey->_width &&
            _textColor.x == otherKey->_textColor.x &&
            _textColor.y == otherKey->_textColor.y &&
            _textColor.z == otherKey->_textColor.z &&
            _backgroundColor.x == otherKey->_backgroundColor.x &&
            _backgroundColor.y == otherKey->_backgroundColor.y &&
            _backgroundColor.z == otherKey->_backgroundColor.z &&
            _date == otherKey->_date);
}

@end

@interface iTermTimestampsRendererTransientState()
- (void)enumerateRows:(void (^)(int row, iTermTimestampKey *key, NSRect frame))block;
- (NSImage *)imageForRow:(int)row;
- (void)addPooledTexture:(iTermPooledTexture *)pooledTexture;
@end

@implementation iTermTimestampsRendererTransientState {
    iTermTimestampDrawHelper *_drawHelper;
    NSMutableArray<iTermPooledTexture *> *_pooledTextures;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSMutableString *s = [NSMutableString stringWithFormat:@"backgroundColor=%@\ntextColor=%@\n",
                          _backgroundColor, _textColor];
    [_timestamps enumerateObjectsUsingBlock:^(NSDate * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [s appendFormat:@"%@\n", obj];
    }];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (void)addPooledTexture:(iTermPooledTexture *)pooledTexture {
    if (!_pooledTextures) {
        _pooledTextures = [NSMutableArray array];
    }
    [_pooledTextures addObject:pooledTexture];
}

- (void)enumerateRows:(void (^)(int row, iTermTimestampKey *key, NSRect frame))block {
    assert(_timestamps);
    const CGFloat rowHeight = self.cellConfiguration.cellSize.height / self.cellConfiguration.scale;
    if (!_drawHelper) {
        _drawHelper = [[iTermTimestampDrawHelper alloc] initWithBackgroundColor:_backgroundColor
                                                                      textColor:_textColor
                                                                            now:[NSDate timeIntervalSinceReferenceDate]
                                                             useTestingTimezone:NO
                                                                      rowHeight:rowHeight
                                                                         retina:self.configuration.scale > 1];
        [_timestamps enumerateObjectsUsingBlock:^(NSDate * _Nonnull date, NSUInteger idx, BOOL * _Nonnull stop) {
            [self->_drawHelper setDate:date forLine:idx];
        }];
    }
    const CGFloat visibleWidth = _drawHelper.suggestedWidth;
    const vector_float4 textColor = simd_make_float4(_textColor.redComponent,
                                                     _textColor.greenComponent,
                                                     _textColor.blueComponent,
                                                     _textColor.alphaComponent);
    const vector_float4 backgroundColor = simd_make_float4(_backgroundColor.redComponent,
                                                           _backgroundColor.greenComponent,
                                                           _backgroundColor.blueComponent,
                                                           _backgroundColor.alphaComponent);
    [_timestamps enumerateObjectsUsingBlock:^(NSDate * _Nonnull date, NSUInteger idx, BOOL * _Nonnull stop) {
        iTermTimestampKey *key = [[iTermTimestampKey alloc] init];
        key.width = visibleWidth;
        key.textColor = textColor;
        key.backgroundColor = backgroundColor;
        key.date = [self->_drawHelper rowIsRepeat:idx] ? 0 : round(date.timeIntervalSinceReferenceDate);
        block(idx,
              key,
              NSMakeRect(self.configuration.viewportSize.x / self.configuration.scale - visibleWidth,
                         self.configuration.viewportSize.y / self.configuration.scale - ((idx + 1) * rowHeight),
                         visibleWidth,
                         rowHeight));

    }];
}

- (NSImage *)imageForRow:(int)row {
    NSSize size = NSMakeSize(_drawHelper.suggestedWidth,
                             self.cellConfiguration.cellSize.height / self.cellConfiguration.scale);
    assert(size.width * size.height > 0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [_drawHelper drawRow:row
               inContext:[NSGraphicsContext currentContext]
                   frame:NSMakeRect(0, 0, size.width, size.height)];
    [image unlockFocus];

    return image;
}

@end

@implementation iTermTimestampsRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    NSCache<iTermTimestampKey *, iTermPooledTexture *> *_cache;
    iTermTexturePool *_texturePool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _texturePool = [[iTermTexturePool alloc] init];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTimestampsVertexShader"
                                                  fragmentFunctionName:@"iTermTimestampsFragmentShader"
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:0
                                                   transientStateClass:[iTermTimestampsRendererTransientState class]];
        _cache = [[NSCache alloc] init];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateTimestampsTS;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!_enabled) {
        return nil;
    }
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                                  commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermTimestampsRendererTransientState *)tState {
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTimestampsRendererTransientState *tState = transientState;
    _cache.countLimit = tState.cellConfiguration.gridSize.height * 4;
    const CGFloat scale = tState.configuration.scale;
    [tState enumerateRows:^(int row, iTermTimestampKey *key, NSRect frame) {
        iTermPooledTexture *pooledTexture = [self->_cache objectForKey:key];
        if (!pooledTexture) {
            NSImage *image = [tState imageForRow:row];
            iTermMetalBufferPoolContext *context = tState.poolContext;
            id<MTLTexture> texture = [self->_cellRenderer textureFromImage:image
                                                                   context:context
                                                                      pool:self->_texturePool];
            assert(texture);
            pooledTexture = [[iTermPooledTexture alloc] initWithTexture:texture
                                                                   pool:self->_texturePool];
            [self->_cache setObject:pooledTexture forKey:key];
        }
        [tState addPooledTexture:pooledTexture];
        assert(tState.configuration.viewportSize.x > pooledTexture.texture.width);
        tState.vertexBuffer = [self->_cellRenderer newQuadWithFrame:CGRectMake(frame.origin.x * scale,
                                                                               frame.origin.y * scale,
                                                                               frame.size.width * scale,
                                                                               frame.size.height * scale)
                                                       textureFrame:CGRectMake(0, 0, 1, 1)
                                                        poolContext:tState.poolContext];

        [self->_cellRenderer drawWithTransientState:tState
                                      renderEncoder:frameData.renderEncoder
                                   numberOfVertices:6
                                       numberOfPIUs:0
                                      vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                                    fragmentBuffers:@{}
                                           textures:@{ @(iTermTextureIndexPrimary): pooledTexture.texture } ];
    }];
}

@end
