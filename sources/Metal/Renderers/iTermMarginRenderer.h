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
@property (nonatomic) vector_float4 regularColor;
@property (nonatomic) vector_float4 deselectedColor;
@property (nonatomic) VT100GridRect selectedCommandRect;
@property (nonatomic) BOOL hasSelectedRegion;

// A regular bottom margin ignores whether it should be deselected.
@property (nonatomic) BOOL forceRegularBottomMargin;

// Don't draw margins in this many points on the bottom. This includes the bottom margin.
@property (nonatomic) CGFloat suppressedBottomHeight;
@end

// Renders four margins around the periphery of the session as a solid color.
@interface iTermMarginRenderer : NSObject<iTermMetalCellRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
