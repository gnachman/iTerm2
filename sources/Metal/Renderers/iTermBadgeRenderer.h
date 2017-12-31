#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic) CGRect sourceRect;
@property (nonatomic) CGRect destinationRect;
@end

@interface iTermBadgeRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic, readonly) BOOL hasImage;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setBadgeImage:(NSImage *)image
              context:(iTermMetalBufferPoolContext *)context;

@end

NS_ASSUME_NONNULL_END
