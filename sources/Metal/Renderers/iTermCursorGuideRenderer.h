#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorGuideRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setColor:(NSColor *)color;
- (void)setRow:(int)row;

@end

NS_ASSUME_NONNULL_END
