#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic) NSEdgeInsets edgeInsets;
@property (nonatomic) CGFloat transparencyAlpha;
@end

@interface iTermBackgroundImageRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic, readonly) NSImage *image;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Call this before creating transient state.
// Frame takes values in [0,1] giving relative location of the viewport within the tab.
- (void)setImage:(NSImage *)image
            mode:(iTermBackgroundImageMode)mode
           frame:(CGRect)frame
   containerSize:(CGSize)containerSize
         context:(nullable iTermMetalBufferPoolContext *)context;

@end

NS_ASSUME_NONNULL_END
