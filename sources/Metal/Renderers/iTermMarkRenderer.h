#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

typedef NS_ENUM(int, iTermMarkStyle) {
    iTermMarkStyleNone = -1,
    iTermMarkStyleSuccess = 0,
    iTermMarkStyleFailure = 1,
    iTermMarkStyleOther = 2
};

NS_ASSUME_NONNULL_BEGIN

@interface iTermMarkRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Call this before setting the viewport size for it to take effect in this frame.
- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row;

@end

NS_ASSUME_NONNULL_END
