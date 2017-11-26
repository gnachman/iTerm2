#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "iTermMetalGlyphKey.h"

// Usage:
// iTermTextureMap *textureMap = [[iTermTextureMap alloc] initWithDevice:device cellSize:cellSize capacity:capacity]
// [textureMap requestStage:^(iTermTextureMapStage *stage) {
//   id<MTLCommandQueue> commandQueue = ...
//   foreach key, column:
//     NSInteger index = [stage findOrAllocateIndexOfLockedTextureWithKey:key column:column creation:creation];
//     pius[i++].textureIndex = index;
//   [stage blitNewTexturesFromStagingAreaWithCommandQueue:commandQueue];
//
//   ... finish enqueueing more GPU work with commandQueue ...
//
//   [commandBuffer addCompletedHandler:^() {
//     [textureMap returnStage:stage];
//   }];
//   [commandBuffer commit];
// }];
@class iTermTextureArray;
@class iTermTextureMapStage;

@interface iTermTextureMap : NSObject

// Given in number of cells
@property (nonatomic, readonly) NSInteger capacity;
@property (nonatomic, readonly) iTermTextureArray *array;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) BOOL haveStageAvailable;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(CGSize)cellSize
                      capacity:(NSInteger)capacity
                numberOfStages:(NSInteger)numberOfStages NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)requestStage:(void (^)(iTermTextureMapStage *stage))completion;
- (void)returnStage:(iTermTextureMapStage *)stage;

@end

@interface iTermFallbackTextureMap : iTermTextureMap
@property (nonatomic, readonly) iTermTextureMapStage *onlyStage;
@end

@interface iTermTextureMapStage : NSObject
@property (nonatomic, weak) iTermTextureMap *textureMap;
@property (nonatomic, readonly) iTermTextureArray *stageArray;
@property (nonatomic, readonly) NSMutableData *piuData;
@property (nonatomic) NSInteger numberOfInstances;

- (instancetype)init NS_UNAVAILABLE;

- (void)blitNewTexturesFromStagingAreaWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
- (void)incrementInstances;

@end

@interface iTermFallbackTextureMapStage : iTermTextureMapStage
@end
