//
//  iTermIndicatorRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermIndicatorDescriptor : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic) NSRect frame;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL dark;
@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermIndicatorRendererTransientState : iTermMetalRendererTransientState
@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermIndicatorRenderer : NSObject<iTermMetalRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)reset;
- (void)addIndicator:(iTermIndicatorDescriptor *)indicator
          colorSpace:(NSColorSpace *)colorSpace
             context:(iTermMetalBufferPoolContext *)context;

@end

NS_ASSUME_NONNULL_END
