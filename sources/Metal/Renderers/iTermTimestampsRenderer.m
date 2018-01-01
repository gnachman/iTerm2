//
//  iTermTimestampsRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTimestampsRenderer.h"
#import "iTermTimestampDrawHelper.h"

#warning TODO :Use texture pools

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
@end

@implementation iTermTimestampsRendererTransientState {
    iTermTimestampDrawHelper *_drawHelper;
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
            [_drawHelper setDate:date forLine:idx];
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
        key.date = [_drawHelper rowIsRepeat:idx] ? 0 : round(date.timeIntervalSinceReferenceDate);
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
    NSCache<iTermTimestampKey *, id<MTLTexture>> *_cache;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
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

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
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

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTimestampsRendererTransientState *tState = transientState;
    _cache.countLimit = tState.cellConfiguration.gridSize.height * 4;
    const CGFloat scale = tState.configuration.scale;
    [tState enumerateRows:^(int row, iTermTimestampKey *key, NSRect frame) {
        id<MTLTexture> texture = [_cache objectForKey:key];
        if (!texture) {
            texture = [_cellRenderer textureFromImage:[tState imageForRow:row]
                                              context:tState.poolContext];
            [_cache setObject:texture forKey:key];
        }
        assert(tState.configuration.viewportSize.x > texture.width);
        tState.vertexBuffer = [_cellRenderer newQuadWithFrame:CGRectMake(frame.origin.x * scale,
                                                                         frame.origin.y * scale,
                                                                         frame.size.width * scale,
                                                                         frame.size.height * scale)
                                                 textureFrame:CGRectMake(0, 0, 1, 1)
                                                  poolContext:tState.poolContext];

        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): texture } ];
    }];
}

@end
