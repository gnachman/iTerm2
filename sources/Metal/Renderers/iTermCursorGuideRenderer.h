#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorGuideRendererTransientState : iTermMetalCellRendererTransientState
// set to -1 if cursor's row is not currently visible.
- (void)setRow:(int)row;
@end

@interface iTermCursorGuideRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setColor:(NSColor *)color;

@end

NS_ASSUME_NONNULL_END
