//
//  iTermOffscreenCommandLineBackgroundRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/14/23.
//

#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermOffscreenCommandLineBackgroundRendererTransientState : iTermMetalRendererTransientState

@property (nonatomic) BOOL shouldDraw;

- (void)setOutlineColor:(vector_float4)outlineColor
        backgroundColor:(vector_float4)backgroundColor
              rowHeight:(CGFloat)rowHeight;

@end

@interface iTermOffscreenCommandLineBackgroundRenderer: NSObject<iTermMetalRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
