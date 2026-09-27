#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

typedef NS_ENUM(int, iTermMarkStyle) {
    iTermMarkStyleNone = -1,

    iTermMarkStyleRegularSuccess = 0,
    iTermMarkStyleRegularFailure = 1,
    iTermMarkStyleRegularOther = 2,

    iTermMarkStyleFoldedSuccess = 3,
    iTermMarkStyleFoldedFailure = 4,
    iTermMarkStyleFoldedOther = 5
};

NS_ASSUME_NONNULL_BEGIN

@interface iTermMarkRendererTransientState : iTermMetalCellRendererTransientState
- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row;
@end

@interface iTermMarkRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Called during the driver's per-frame update phase (before transient states are
// created). Recomputes the mark geometry and rebuilds the texture atlas if the
// cell configuration, colorspace, or resolved mark colors have changed since the
// last frame.
- (void)updateForCellConfiguration:(iTermCellRenderConfiguration *)cellConfiguration
                      successColor:(NSColor *)successColor
                        otherColor:(NSColor *)otherColor
                      failureColor:(NSColor *)failureColor;

@end

NS_ASSUME_NONNULL_END
