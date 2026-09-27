//
//  iTermFullScreenFlashRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermFullScreenFlashRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic) vector_float4 color;
@end

@interface iTermFullScreenFlashRenderer : NSObject<iTermMetalRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
