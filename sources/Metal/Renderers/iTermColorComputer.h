//
//  iTermColorComputer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/18.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

@class iTermData;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermColorComputerTransientState : iTermMetalComputerTransientState
@property (nonatomic, strong) iTermData *lines;
@property (nonatomic, strong) iTermData *selectedIndices;
@property (nonatomic, strong) iTermData *findMatches;
@property (nonatomic, strong) iTermData *annotatedIndices;
@property (nonatomic, strong) iTermData *markedIndices;
@property (nonatomic, strong) iTermData *underlinedIndices;
@property (nonatomic, readonly) const char *debugOutput;
@property (nonatomic, readonly) id<MTLBuffer> outputBuffer;  // iTermCellColors
@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermColorComputer : NSObject

@property (nonatomic, strong) NSData *colorMap;
@property (nonatomic) iTermColorsConfiguration config;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (__kindof iTermMetalComputerTransientState *)createTransientStateWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;

- (void)executeComputePassWithTransientState:(__kindof iTermMetalComputerTransientState *)transientState
                              computeEncoder:(id <MTLComputeCommandEncoder>)computeEncoder;

@end

NS_ASSUME_NONNULL_END
