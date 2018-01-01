#import <Foundation/Foundation.h>
#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermTimestampsRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic) NSColor *backgroundColor;
@property (nonatomic) NSColor *textColor;
@property (nonatomic, strong) NSArray<NSDate *> *timestamps;
@end

@interface iTermTimestampsRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

