#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorGuideRendererTransientState : iTermMetalCellRendererTransientState
- (void)setCursorCoord:(VT100GridCoord)coord within:(VT100GridSize)bounds;
@end

@interface iTermCursorGuideRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setColor:(NSColor *)color;

@end

NS_ASSUME_NONNULL_END
