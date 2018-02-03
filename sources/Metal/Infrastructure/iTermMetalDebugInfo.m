//
//  iTermMetalDebugInfo.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/28/18.
//

#import "iTermMetalDebugInfo.h"

#import "DebugLogging.h"
#import "iTermMetalRenderer.h"
#import "iTermMetalRowData.h"
#import "NSImage+iTerm.h"
#import "NSURL+iTerm.h"

@implementation iTermMetalDebugDrawInfo {
    NSMutableDictionary<NSNumber *, id<MTLBuffer>> *_vertexBuffers;
    NSMutableDictionary<NSNumber *, id<MTLBuffer>> *_fragmentBuffers;
    NSMutableDictionary<NSNumber *, id<MTLTexture>> *_fragmentTextures;
    NSInteger _vertexCount;
    NSInteger _instanceCount;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vertexBuffers = [NSMutableDictionary dictionary];
        _fragmentBuffers = [NSMutableDictionary dictionary];
        _fragmentTextures = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setVertexBuffer:(id<MTLBuffer>)buffer atIndex:(NSUInteger)index {
    _vertexBuffers[@(index)] = buffer;
}

- (void)setFragmentBuffer:(id<MTLBuffer>)buffer atIndex:(NSUInteger)index {
    _fragmentBuffers[@(index)] = buffer;
}

- (void)setFragmentTexture:(id <MTLTexture>)texture atIndex:(NSUInteger)index {
    _fragmentTextures[@(index)] = texture;
}

- (void)drawWithVertexCount:(NSUInteger)vertexCount
              instanceCount:(NSUInteger)instanceCount {
    _vertexCount = vertexCount;
    _instanceCount = instanceCount;
}

- (void)writeToFolder:(NSURL *)folder {
    [_vertexBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer> _Nonnull obj, BOOL * _Nonnull stop) {
        [_formatter writeVertexBuffer:obj index:key.integerValue toFolder:folder];
    }];
    [_fragmentBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer>  _Nonnull obj, BOOL * _Nonnull stop) {
        [_formatter writeFragmentBuffer:obj index:key.integerValue toFolder:folder];
    }];
    [_fragmentTextures enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLTexture>  _Nonnull obj, BOOL * _Nonnull stop) {
        [_formatter writeFragmentTexture:obj index:key.integerValue toFolder:folder];
    }];
    NSString *description = [NSString stringWithFormat:@"vertex count: %@\ninstance count: %@\nrenderPipelineState: %@\n",
                             @(_vertexCount),
                             @(_instanceCount),
                             self.renderPipelineState];
    [description writeToURL:[folder URLByAppendingPathComponent:@"description.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

@end

@implementation iTermMetalDebugInfo {
    MTLRenderPassDescriptor *_renderPassDescriptor;
    MTLRenderPassDescriptor *_intermediateRenderPassDescriptor;
    NSMutableArray<iTermMetalRowData *> *_rowData;
    NSMutableArray<iTermMetalRendererTransientState *> *_transientStates;
    NSMutableArray<iTermMetalDebugDrawInfo *> *_draws;
    NSImage *_finalImage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rowData = [NSMutableArray array];
        _transientStates = [NSMutableArray array];
        _draws = [NSMutableArray array];
    }
    return self;
}

- (void)setRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    _renderPassDescriptor = renderPassDescriptor;
}

- (void)setIntermediateRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    _intermediateRenderPassDescriptor = renderPassDescriptor;
}

- (void)addRowData:(iTermMetalRowData *)rowData {
    [_rowData addObject:rowData];
}

- (void)addTransientState:(iTermMetalRendererTransientState *)tState {
    [_transientStates addObject:tState];
    tState.debugInfo = self;
}

- (void)addRenderOutputData:(NSData *)data
                       size:(CGSize)size
             transientState:(iTermMetalRendererTransientState *)tState {
    tState.renderedOutputForDebugging = [NSImage imageWithRawData:data
                                                             size:size
                                                    bitsPerSample:8
                                                  samplesPerPixel:4
                                                         hasAlpha:YES
                                                   colorSpaceName:NSDeviceRGBColorSpace];
}

- (NSUInteger)numberOfRecordedDraws {
    return _draws.count;
}

- (iTermMetalDebugDrawInfo *)newDrawWithFormatter:(id<iTermMetalDebugInfoFormatter>)formatter {
    iTermMetalDebugDrawInfo *draw = [[iTermMetalDebugDrawInfo alloc] init];
    draw.formatter = formatter;
    [_draws addObject:draw];
    return draw;
}

- (NSURL *)newFolderNamed:(NSString *)name root:(NSURL *)root {
    NSURL *folder = [root URLByAppendingPathComponent:name];
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        ELog(@"error creating folder %@: %@", folder, error);
        return nil;
    }
    return folder;
}

- (NSData *)newArchive {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSURL *root =
        [[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:uuid] URLByAppendingPathExtension:@"iterm2-metal-frame"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        return nil;
    }

    [self writeRenderPassDescriptor:_renderPassDescriptor
                                 to:[self newFolderNamed:@"RenderPassDescriptor"
                                                    root:root]];
    if (_intermediateRenderPassDescriptor) {
        [self writeRenderPassDescriptor:_intermediateRenderPassDescriptor
                                     to:[self newFolderNamed:@"IntermediateRenderPassDescriptor"
                                                        root:root]];
    }
    NSURL *rowDataFolder = [self newFolderNamed:@"RowData" root:root];
    [_rowData enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *name = [NSString stringWithFormat:@"rowdata.%04d", (int)idx];
        NSURL *folder = [rowDataFolder URLByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        [rowData writeDebugInfoToFolder:folder];
    }];

    [_transientStates enumerateObjectsUsingBlock:^(iTermMetalRendererTransientState * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        Class theClass = [obj class];
        NSURL *folder = [self newFolderNamed:[NSString stringWithFormat:@"state-%04d-%@", (int)obj.sequenceNumber, NSStringFromClass(theClass)]
                                        root:root];
        [obj writeDebugInfoToFolder:folder];

        if (obj.renderedOutputForDebugging) {
            NSString *filename = [NSString stringWithFormat:@"%04d-output.png", (int)obj.sequenceNumber];
            [obj.renderedOutputForDebugging saveAsPNGTo:[[folder URLByAppendingPathComponent:filename] path]];
        }
    }];

    [_draws enumerateObjectsUsingBlock:^(iTermMetalDebugDrawInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *name = [NSString stringWithFormat:@"draw-%04d-%@", (int)idx, obj.name];
        [obj writeToFolder:[self newFolderNamed:name root:root]];
    }];

    return [root zippedContents];
}

#pragma mark - Writers

- (void)writeRenderPassDescriptor:(MTLRenderPassDescriptor *)rpd to:(NSURL *)folder {
    [[rpd debugDescription] writeToURL:[folder URLByAppendingPathComponent:@"DebugDescription.txt"]
                            atomically:NO
                              encoding:NSUTF8StringEncoding
                                 error:nil];
    MTLRenderPassColorAttachmentDescriptor *attachment = rpd.colorAttachments[0];
    [[attachment debugDescription] writeToURL:[folder URLByAppendingPathComponent:@"ColorAttachment0.txt"]
                                   atomically:NO
                                     encoding:NSUTF8StringEncoding
                                        error:nil];
}

@end
