#import "iTermTextureMap.h"

#import "iTermTextureArray.h"
#import "iTermMetalGlyphKey.h"

#include "lrucache.hpp"
extern "C" {
#import "DebugLogging.h"
}
#import "GlyphKey.h"
#import "TextureMap.h"
#import "TextureMapStage.h"

#include <list>
#include <map>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

static const NSInteger iTermTextureMapNumberOfStages = 2;


@interface iTermTextureMapStage()
- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap
                        stageArray:(iTermTextureArray *)stageArray NS_DESIGNATED_INITIALIZER;
- (void)startNewFrame;
- (iTerm2::TextureMapStage *)textureMapStage;
@end

@implementation iTermTextureMap {
    iTerm2::TextureMap *_textureMap;
    NSMutableArray<iTermTextureMapStage *> *_stages;
    NSMutableArray<void (^)(iTermTextureMapStage *)> *_completionBlocks;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(CGSize)cellSize
                      capacity:(NSInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _cellSize = cellSize;
        _completionBlocks = [NSMutableArray array];
        _array = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.width
                                                   textureHeight:cellSize.height
                                                     arrayLength:_capacity
                                                          device:device];
        _textureMap = new iTerm2::TextureMap(capacity);
        _stages = [NSMutableArray array];
        for (NSInteger i = 0; i < iTermTextureMapNumberOfStages; i++) {
            [_stages addObject:[[iTermTextureMapStage alloc] initWithTextureMap:self
                                                                     stageArray:[self newTextureArrayForStageWithDevice:device]]];
        }
    }
    return self;
}

- (void)dealloc {
    delete _textureMap;
}

- (BOOL)haveStageAvailable {
    @synchronized(self) {
        return _stages.count > 0;
    }
}

- (void)requestStage:(void (^)(iTermTextureMapStage *stage))completion {
    iTermTextureMapStage *stage = nil;
    @synchronized(self) {
        stage = [self nextStage];
    }
    if (stage) {
        completion(stage);
    } else {
        [_completionBlocks addObject:[completion copy]];
    }
}

- (iTermTextureMapStage *)nextStage {
    iTermTextureMapStage *stage = _stages.lastObject;
    [_stages removeLastObject];
    [stage startNewFrame];
    return stage;
}

- (void)unlockIndexesFromStage:(iTerm2::TextureMapStage *)textureMapStage {
    _textureMap->unlock_stage(textureMapStage);
}

- (void)returnStage:(iTermTextureMapStage *)stage {
    [self unlockIndexesFromStage:stage.textureMapStage];

    [_stages insertObject:stage atIndex:0];
    if (_completionBlocks.count) {
        void (^block)(iTermTextureMapStage *) = _completionBlocks.firstObject;
        [_completionBlocks removeObjectAtIndex:0];
        block([self nextStage]);
    }
}

- (void)unlockIndexes:(const std::vector<int> &)indexes {
    for (int i : indexes) {
        _textureMap->unlock(i);
    }
}

- (iTermTextureArray *)newTextureArrayForStageWithDevice:(id<MTLDevice>)device {
    return [[iTermTextureArray alloc] initWithTextureWidth:_cellSize.width
                                             textureHeight:_cellSize.height
                                               arrayLength:_capacity / 2
                                                    device:device];
}

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                       textureMapStage:(iTerm2::TextureMapStage *)textureMapStage
                                            stageArray:(iTermTextureArray *)stageArray
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    const iTerm2::GlyphKey glyphKey(key, 4);
    int index = _textureMap->get_index(glyphKey, textureMapStage, relations, emoji);
    if (index >= 0) {
        DLog(@"%@: locked existing texture %@", self.label, @(index));
        return index;
    } else {
        NSDictionary<NSNumber *, NSImage *> *images = creation(column, emoji);
        if (images.count) {
            __block NSInteger result = -1;
            std::map<int, int> newRelations;
            for (NSNumber *part in images) {
                NSImage *image = images[part];
                const iTerm2::GlyphKey newGlyphKey(key, part.intValue);
                auto stageAndGlobalIndex = _textureMap->allocate_index(newGlyphKey, textureMapStage, *emoji);
                if (result < 0) {
                    result = stageAndGlobalIndex.second;
                }
                newRelations[part.intValue] = stageAndGlobalIndex.second;
                DLog(@"%@: create and stage new texture %@", self.label, @(index));
                DLog(@"Stage %@ at %@", key, @(index));
                [stageArray setSlice:stageAndGlobalIndex.first withImage:image];
            }
            _textureMap->define_class(newRelations);
            *relations = newRelations;
            return result;
        } else {
            return -1;
        }
    }
}

- (void)doNoOpBlitWithStage:(iTermTextureArray *)stageArray
               commandQueue:(id<MTLCommandQueue>)commandQueue {
    id <MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"Blit from stage";
    id <MTLBlitCommandEncoder> blitter = [commandBuffer blitCommandEncoder];
    [stageArray copyTextureAtIndex:0
                           toArray:_array
                             index:0
                           blitter:blitter];
    [blitter endEncoding];
    [commandBuffer commit];
}

- (void)blitFromStage:(iTerm2::TextureMapStage *)textureMapStage
                array:(iTermTextureArray *)stageArray
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    id<MTLBlitCommandEncoder> blitter = [commandBuffer blitCommandEncoder];
    textureMapStage->blit(stageArray, _array, blitter);
    [blitter endEncoding];
}

@end

@implementation iTermTextureMapStage {
    __weak iTermTextureMap *_textureMap;
    iTerm2::TextureMapStage *_textureMapStage;
}

- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap stageArray:(iTermTextureArray *)stageArray {
    self = [super init];
    if (self) {
        stageArray.texture.label = @"Stage";
        _textureMap = textureMap;
        _stageArray = stageArray;
    }
    return self;
}

- (void)dealloc {
    if (_textureMapStage) {
        delete _textureMapStage;
    }
}

- (void)startNewFrame {
    if (_textureMapStage) {
        delete _textureMapStage;
    }
    _textureMapStage = new iTerm2::TextureMapStage();
}

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    return [_textureMap findOrAllocateIndexOfLockedTextureWithKey:key
                                                           column:column
                                                  textureMapStage:_textureMapStage
                                                       stageArray:_stageArray
                                                        relations:relations
                                                            emoji:emoji
                                                         creation:creation];
}

- (void)blitNewTexturesFromStagingAreaWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    DLog(@"%@: blit from staging to completion", self);
    if (!_textureMapStage->have_indexes_to_blit()) {
        // Uncomment to make the stage appear in the GPU debugger
        // [self doNoOpBlitWithStage:];
        return;
    }

    [_textureMap blitFromStage:_textureMapStage array:_stageArray commandBuffer:commandBuffer];
}

- (iTerm2::TextureMapStage *)textureMapStage {
    return _textureMapStage;
}

@end
