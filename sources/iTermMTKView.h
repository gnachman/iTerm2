//
//  iTermMTKView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/20.
//

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

#define ENABLE_PHONY_MTKVIEW 1

NS_ASSUME_NONNULL_BEGIN

@protocol CAMetalDrawable;
@class iTermMTKView;

@protocol iTermMTKViewDelegate<NSObject>
- (void)it_mtkView:(nonnull iTermMTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)it_drawInMTKView:(nonnull iTermMTKView *)view;
@end

@protocol iTermMTKView<NSObject>
@property (nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly, nullable) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property (nonatomic, nullable, strong) id <MTLDevice> device;
@property (nonatomic) CGSize drawableSize;
- (void)draw;
- (BOOL)it_isMetalView;
@end

@interface MTKView (Phony)<iTermMTKView>
@end

#if ENABLE_PHONY_MTKVIEW
@interface iTermMTKView : NSView<iTermMTKView>
@property (nonatomic, weak) id<iTermMTKViewDelegate> delegate;

- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end
#else
@interface iTermMTKView: MTKView
@end
#endif

NS_ASSUME_NONNULL_END
