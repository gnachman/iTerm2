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

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMarkRendererTransientState : iTermMetalCellRendererTransientState
- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row;
@end

@interface iTermMarkRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
