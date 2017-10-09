#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBroadcastStripesRenderer : NSObject<iTermMetalRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

