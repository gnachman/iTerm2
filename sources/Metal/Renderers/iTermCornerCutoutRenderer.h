//
//  iTermCornerCutoutRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/29/18.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermCornerCutoutRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic) BOOL drawLeft;
@property (nonatomic) BOOL drawRight;
@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermCornerCutoutRenderer : NSObject<iTermMetalRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
