#import "iTermTextureMap.h"
#import "iTermTextureMap+CPP.h"

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

extern "C" {

const int iTermTextureMapMaxCharacterParts = 5;
const int iTermTextureMapMiddleCharacterPart = (iTermTextureMapMaxCharacterParts / 2) * iTermTextureMapMaxCharacterParts + (iTermTextureMapMaxCharacterParts / 2);

int ImagePartDX(int part) {
    return (part % iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

int ImagePartDY(int part) {
    return (part / iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

int ImagePartFromDeltas(int dx, int dy) {
    const int radius = iTermTextureMapMaxCharacterParts / 2;
    return (dx + radius) + (dy + radius) * iTermTextureMapMaxCharacterParts;
}

}

@interface iTermTextureMapStage()
- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap
                        stageArray:(iTermTextureArray *)stageArray NS_DESIGNATED_INITIALIZER;
- (void)startNewFrame;
- (iTerm2::TextureMapStage *)textureMapStage;
- (void)reset;
@end


@implementation iTermTextureMap {
    iTerm2::TextureMap *_textureMap;
    NSMutableArray<iTermTextureMapStage *> *_stages;
    NSMutableArray<void (^)(iTermTextureMapStage *)> *_completionBlocks;
}

+ (iTermTextureArray *)newTextureArrayWithCellSize:(CGSize)cellSize
                                          capacity:(NSInteger)capacity
                                            device:(id<MTLDevice>)device {
    return [[iTermTextureArray alloc] initWithTextureWidth:cellSize.width
                                             textureHeight:cellSize.height
                                               arrayLength:capacity
                                                    device:device];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(CGSize)cellSize
                      capacity:(NSInteger)capacity
                numberOfStages:(NSInteger)numberOfStages {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _cellSize = cellSize;
        _completionBlocks = [NSMutableArray array];
        _array = [iTermTextureMap newTextureArrayWithCellSize:cellSize capacity:capacity device:device];
        _textureMap = new iTerm2::TextureMap(capacity);
        _stages = [NSMutableArray array];
        for (NSInteger i = 0; i < numberOfStages; i++) {
            [_stages addObject:[self newStageWithDevice:device]];
        }
    }
    return self;
}

- (void)dealloc {
    delete _textureMap;
}

- (iTermTextureMapStage *)newStageWithDevice:(id<MTLDevice>)device {
    return [[iTermTextureMapStage alloc] initWithTextureMap:self
                                                 stageArray:[self newTextureArrayForStageWithDevice:device]];
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
    [self unlockIndexes:*stage.locks];
    [stage reset];

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
                                               arrayLength:_capacity
                                                    device:device];
}

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                       textureMapStage:(iTerm2::TextureMapStage *)textureMapStage
                                            stageArray:(iTermTextureArray *)stageArray
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    const iTerm2::GlyphKey glyphKey(key, iTermTextureMapMiddleCharacterPart);
    int index = _textureMap->get_index(glyphKey, textureMapStage, relations, emoji);
    if (index >= 0) {
        // Normal code path: there is already a glyph with this key. Return its index.
        DLog(@"%@: locked existing texture %@", self.label, @(index));
        return index;
    } else {
        // Expensive path: render a new glyph. Allocate an index in the stage and in the texture
        // map. Record that it needs to be blitted. The glyph may take more than one cell in which
        // case the relations array needs to be filled out and the preceding steps happen for each
        // part.
        NSDictionary<NSNumber *, NSImage *> *images = creation(column, emoji);
        if (images.count) {
            if (_textureMap->get_free_count() < images.count) {
                // Very expensive path: the texture map is full. The caller must create temporary
                // textures and use multiple drawing passes.
                return iTermTextureMapStatusOutOfMemory;
            }

            __block NSInteger result = iTermTextureMapStatusGlyphNotRenderable;
            std::map<int, int> newRelations;

            for (NSNumber *part in images) {
                // Allocate a stage index and a global index for this image.
                NSImage *image = images[part];
                const iTerm2::GlyphKey newGlyphKey(key, part.intValue);
                auto stageAndGlobalIndex = _textureMap->allocate_index(newGlyphKey, textureMapStage, *emoji);
                const int &stageIndex = stageAndGlobalIndex.first;
                const int &globalIndex = stageAndGlobalIndex.second;
                assert(stageIndex >= 0);

                // Record the global index of the first image, which we will return to the caller and
                // can be used to find all the other parts of this glyph.
                if (result < 0) {
                    result = globalIndex;
                }

                // Record the map from this part to the global index so the caller will know which
                // glyphs it will use for its current cell. This is an optimization: it could always
                // call this method a second time to get the relations.
                newRelations[part.intValue] = globalIndex;

                // Add the image to the stage's texture.
                DLog(@"%@: create and stage new texture %@", self.label, @(globalIndex));
                DLog(@"Stage %@ at %@", @(key->code), @(stageIndex));
                [stageArray setSlice:stageIndex withImage:image];
            }
            _textureMap->define_class(newRelations);
            *relations = newRelations;
            return result;
        } else {
            // The creation method failed to draw the glyph. Happens with undrawable characters like
            // space.
            return iTermTextureMapStatusGlyphNotRenderable;
        }
    }
}

- (void)doNoOpBlitWithStage:(iTermTextureArray *)stageArray
               commandQueue:(id<MTLCommandQueue>)commandQueue {
    if (_array) {
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
}

- (void)blitFromStage:(iTerm2::TextureMapStage *)textureMapStage
                array:(iTermTextureArray *)stageArray
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_array) {
        id<MTLBlitCommandEncoder> blitter = [commandBuffer blitCommandEncoder];
        textureMapStage->blit(stageArray, _array, blitter);
        [blitter endEncoding];
    }
}

@end

@implementation iTermFallbackTextureMap {
    iTermFallbackTextureMapStage *_stage;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device cellSize:(CGSize)cellSize capacity:(NSInteger)capacity numberOfStages:(NSInteger)numberOfStages {
    assert(numberOfStages == 1);
    return [super initWithDevice:device cellSize:cellSize capacity:capacity numberOfStages:1];
}

- (iTermTextureMapStage *)newStageWithDevice:(id<MTLDevice>)device {
    _stage = [[iTermFallbackTextureMapStage alloc] initWithTextureMap:self stageArray:nil];
    [_stage startNewFrame];
    return _stage;
}

- (void)requestStage:(void (^)(iTermTextureMapStage *stage))completion {
    completion(_stage);
}

- (void)returnStage:(iTermTextureMapStage *)stage {
}

- (void)blitFromStage:(iTerm2::TextureMapStage *)textureMapStage
                array:(iTermTextureArray *)stageArray
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [self doesNotRecognizeSelector:_cmd];
}

- (iTermTextureMapStage *)onlyStage {
    if (!_stage) {
        _stage = [[iTermFallbackTextureMapStage alloc] initWithTextureMap:self stageArray:nil];
    }
    return _stage;
}

@end

@implementation iTermTextureMapStage {
@protected
    iTerm2::TextureMapStage *_textureMapStage;
    std::vector<int> *_locks;
}

- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap stageArray:(iTermTextureArray *)stageArray {
    self = [super init];
    if (self) {
        stageArray.texture.label = @"Stage";
        _textureMap = textureMap;
        _stageArray = stageArray;
        _locks = new std::vector<int>();
        _piuData = [NSMutableData data];
    }
    return self;
}

- (void)dealloc {
    if (_textureMapStage) {
        delete _textureMapStage;
    }
    delete _locks;
}

- (std::vector<int> *)locks {
    return _locks;
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

- (void)incrementInstances {
    _numberOfInstances++;
}

- (void)reset {
    _locks->clear();
    _textureMapStage->reset();
    _piuData.length = 0;
    _numberOfInstances = 0;
}

@end

@implementation iTermFallbackTextureMapStage

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    // Note that this passes the texture map's array as the stageArray because the fallback
    // stage does not keep its own array. The texture map is short-lived so blitting is not
    // needed.
    return [self.textureMap findOrAllocateIndexOfLockedTextureWithKey:key
                                                               column:column
                                                      textureMapStage:_textureMapStage
                                                           stageArray:self.textureMap.array
                                                            relations:relations
                                                                emoji:emoji
                                                             creation:creation];
}

- (void)blitNewTexturesFromStagingAreaWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
}

@end

