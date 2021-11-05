#import <Foundation/Foundation.h>
#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBroadcastStripesRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)setColorSpace:(NSColorSpace *)colorSpace;

@end

NS_ASSUME_NONNULL_END

