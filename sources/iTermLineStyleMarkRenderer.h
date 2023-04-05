//
//  iTermLineStyleMarkRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/8/23.
//

#import <Foundation/Foundation.h>
#import "iTermMarkRenderer.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    vector_float4 success;
    vector_float4 other;
    vector_float4 failure;
} iTermLineStyleMarkColors;

@interface iTermLineStyleMarkRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic) iTermLineStyleMarkColors colors;

- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row;
@end

@interface iTermLineStyleMarkRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
