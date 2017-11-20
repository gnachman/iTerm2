//
//  iTermMarginRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMarginRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic) vector_float4 color;
@end

// Renders four margins around the periphery of the session as a solid color.
@interface iTermMarginRenderer : NSObject<iTermMetalCellRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
