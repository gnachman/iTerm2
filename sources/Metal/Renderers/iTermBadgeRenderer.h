#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRenderer : NSObject<iTermMetalRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setBadgeImage:(NSImage *)image;

@end

NS_ASSUME_NONNULL_END

