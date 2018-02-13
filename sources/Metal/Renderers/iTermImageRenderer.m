//
//  iTermImageRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/7/18.
//

#import "iTermImageRenderer.h"

#import "iTermImageInfo.h"
#import "iTermTexture.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"

static NSString *const iTermImageRendererTextureMetadataKeyImageMissing = @"iTermImageRendererTextureMetadataKeyImageMissing";

@implementation iTermMetalImageRun

- (NSString *)debugDescription {
    NSString *info = [NSString stringWithFormat:@"startCoordInImage=%@ startCoordOnScreen=%@ length=%@ code=%@ size=%@ uniqueIdentifier=%@",
                      VT100GridCoordDescription(self.startingCoordInImage),
                      VT100GridCoordDescription(self.startingCoordOnScreen),
                      @(self.length),
                      @(self.code),
                      NSStringFromSize(_imageInfo.size),
                      _imageInfo.uniqueIdentifier];
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, info];
}

@end

@interface iTermImageRendererTransientState()
@property (nonatomic) iTermMetalCellRenderer *cellRenderer;
@property (nonatomic) NSTimeInterval timestamp;
// Counts the number of times each texture key is in use. Shared by all transient states.
@property (nonatomic, strong) NSCountedSet<NSNumber *> *counts;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<MTLTexture>> *textures;
@end

@implementation iTermImageRendererTransientState {
    NSMutableArray<iTermMetalImageRun *> *_runs;
    // Images that weren't available
    NSMutableSet<NSString *> *_missingImageUniqueIdentifiers;
    // Images that were available
    NSMutableSet<NSString *> *_foundImageUniqueIdentifiers;
    // Absolute line numbers that contained animation
    NSMutableSet<NSNumber *> *_animatedLines;
}

- (instancetype)initWithConfiguration:(__kindof iTermRenderConfiguration *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _missingImageUniqueIdentifiers = [NSMutableSet set];
        _foundImageUniqueIdentifiers = [NSMutableSet set];
        _animatedLines = [NSMutableSet set];
    }
    return self;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSMutableString *s = [NSMutableString string];

    NSString *runsString = [[_runs mapWithBlock:^id(iTermMetalImageRun *run) {
        return [run debugDescription];
    }] componentsJoinedByString:@"\n"];
    [s appendFormat:@"runs:\n%@\n", runsString];

    [s appendFormat:@"missingImageUniqueIDs: %@\n", _missingImageUniqueIdentifiers];
    [s appendFormat:@"foundImageUniqueIDs: %@\n", _foundImageUniqueIdentifiers];
    [s appendFormat:@"animated lines: %@\n", _animatedLines];

    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}


- (void)addRun:(iTermMetalImageRun *)imageRun {
    if (!_runs) {
        _runs = [NSMutableArray array];
    }
    [_runs addObject:imageRun];
    id key = [self keyForRun:imageRun];
    id<MTLTexture> texture = _textures[key];

    // Check if the image got loaded asynchronously. This happens when decoding an image takes a while.
    if ([iTermTexture metadataForTexture:texture][iTermImageRendererTextureMetadataKeyImageMissing] &&
        imageRun.imageInfo.ready) {
        [_textures removeObjectForKey:key];
    }

    if (_textures[key] == nil) {
        _textures[key] = [self newTextureForImageRun:imageRun];
    } else if (imageRun.imageInfo) {
        [_foundImageUniqueIdentifiers addObject:imageRun.imageInfo.uniqueIdentifier];
    }
    if (imageRun.imageInfo.animated) {
        [_animatedLines addObject:@(imageRun.startingCoordOnScreen.y + _firstVisibleAbsoluteLineNumber)];
    }
    [_counts addObject:key];
}

- (id)keyForRun:(iTermMetalImageRun *)run {
    NSUInteger temp = run.code;
    int frame = ([run.imageInfo frameForTimestamp:_timestamp] & 0xffff);
    return @(temp << 16 | frame);
}

- (id<MTLTexture>)newTextureForImageRun:(iTermMetalImageRun *)run {
    CGSize cellSize = self.cellConfiguration.cellSize;
    const CGFloat scale = self.configuration.scale;
    cellSize.width /= scale;
    cellSize.height /= scale;
    NSImage *image = [run.imageInfo imageWithCellSize:cellSize timestamp:_timestamp];
    BOOL missing = NO;
    if (!image) {
        if (!run.imageInfo) {
            image = [NSImage imageOfSize:CGSizeMake(1, 1) color:[NSColor brownColor]];
        } else {
            image = [NSImage imageOfSize:CGSizeMake(1, 1) color:[NSColor grayColor]];
            missing = YES;
        }
    }
    if (run.imageInfo) {
        if (missing) {
            [_missingImageUniqueIdentifiers addObject:run.imageInfo.uniqueIdentifier];
        } else {
            [_foundImageUniqueIdentifiers addObject:run.imageInfo.uniqueIdentifier];
        }
    }
    id<MTLTexture> texture = [_cellRenderer textureFromImage:image context:self.poolContext];
    if (missing) {
        [iTermTexture setMetadataObject:@YES forKey:iTermImageRendererTextureMetadataKeyImageMissing onTexture:texture];
    }
    return texture;
}

- (void)enumerateDraws:(void (^)(NSNumber *, id<MTLBuffer>, id<MTLTexture>))block {
    const CGSize cellSize = self.cellConfiguration.cellSize;
    const CGPoint offset = CGPointMake(self.margins.left, self.margins.top);
    const CGFloat height = self.configuration.viewportSize.y;
    const CGFloat bottom = self.margins.top;

    [_runs enumerateObjectsUsingBlock:^(iTermMetalImageRun * _Nonnull run, NSUInteger idx, BOOL * _Nonnull stop) {
        id key = [self keyForRun:run];
        id<MTLTexture> texture = _textures[key];
        const CGSize textureSize = CGSizeMake(texture.width, texture.height);
        NSSize chunkSize = NSMakeSize(textureSize.width / run.imageInfo.size.width,
                                      textureSize.height / run.imageInfo.size.height);
        const CGRect textureFrame = NSMakeRect((chunkSize.width * run.startingCoordInImage.x) / textureSize.width,
                                               (textureSize.height - cellSize.height - chunkSize.height * run.startingCoordInImage.y) / textureSize.height,
                                               (chunkSize.width * run.length) / textureSize.width,
                                               (chunkSize.height) / textureSize.height);

        id<MTLBuffer> vertexBuffer = [_cellRenderer newQuadWithFrame:CGRectMake(run.startingCoordOnScreen.x * cellSize.width + offset.x,
                                                                                bottom + height - (run.startingCoordOnScreen.y * cellSize.height + offset.y + cellSize.height),
                                                                                run.length * cellSize.width,
                                                                                cellSize.height)
                                                        textureFrame:textureFrame
                                                         poolContext:self.poolContext];

        block(key, vertexBuffer, texture);
    }];
}

@end

@implementation iTermImageRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    NSMutableDictionary<NSNumber *, id<MTLTexture>> *_textures;
    NSCountedSet<NSNumber *> *_counts;

    // If a texture's reference count (stored in `_counts`) goes to 0 it doesn't get removed from
    // the dictionary immediately because if only one frame is ever in flight then all textures
    // would get removed at the end of each frame. When the count goes to 0, put it on notice. If
    // it's not used in the next frame, remove it.
    //
    // TODO: Consider keeping a counted set and removing textures after N frames of disuse, so that
    // short animated GIFs can avoid churning textures.
    NSMutableSet<NSNumber *> *_onNotice;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermImageVertexShader"
                                                  fragmentFunctionName:@"iTermImageFragmentShader"
                                                              blending:[iTermMetalBlending compositeSourceOver]
                                                        piuElementSize:0
                                                   transientStateClass:[iTermImageRendererTransientState class]];
        _textures = [NSMutableDictionary dictionary];
        _counts = [[NSCountedSet alloc] init];
        _onNotice = [NSMutableSet set];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateImageTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
    [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermImageRendererTransientState *)tState {
    tState.cellRenderer = _cellRenderer;
    tState.timestamp = [NSDate timeIntervalSinceReferenceDate];
    tState.textures = _textures;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermImageRendererTransientState *tState = transientState;

    NSMutableSet<NSNumber *> *texturesToRemove = [_onNotice mutableCopy];
    [tState enumerateDraws:^(id key, id<MTLBuffer> vertexBuffer, id<MTLTexture> texture) {
        [texturesToRemove removeObject:key];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): texture } ];
        [_counts removeObject:key];
        if ([_counts countForObject:key] == 0) {
            [_onNotice addObject:key];
        }
    }];
    [texturesToRemove enumerateObjectsUsingBlock:^(NSNumber * _Nonnull key, BOOL * _Nonnull stop) {
        [_textures removeObjectForKey:key];
        [_onNotice removeObject:key];
    }];
}

@end
