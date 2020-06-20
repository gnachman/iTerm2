//
//  iTermMTKView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/20.
//


// Inspired by MetalLayerView.swift from https://github.com/trishume/MetalTest
// Translated to Objective C by George Nachman.
// Captured at commit d30640a96d1a25a9074c24af3a39481c496efead
//
// https://github.com/trishume/MetalTest/blob/master/LICENSE:
//    Copyright 2019 Tristan Hume
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#import "iTermMTKView.h"

#if ENABLE_PHONY_MTKVIEW

#import <QuartzCore/QuartzCore.h>

// I think it's probably faster to set this to 0 to avoid using CA transactions, but it may allow
// the occasional glitch.
#define ENABLE_GMR_PRESENT_WITH_TRANSACTION 1

@interface iTermMTKView()<CALayerDelegate>
@end

@implementation iTermMTKView {
    id<CAMetalDrawable> _currentDrawable;
    MTLRenderPassDescriptor *_currentRenderPassDescriptor;
    CAMetalLayer *_metalLayer;
}

@synthesize device = _device;

// Thanks to https://stackoverflow.com/questions/45375548/resizing-mtkview-scales-old-content-before-redraw
// for the recipe behind this, although I had to add presentsWithTransaction and the wait to make it glitch-free
- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device {
    self = [super initWithFrame:frameRect];
    if (self) {
        _device = device;
        self.wantsLayer = YES;
        // consider using NSViewLayerContentsRedrawOnSetNeedsDisplay
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;

        // Tristan's comment:
        // This property only matters in the case of a rendering glitch, which shouldn't happen
        // any more.
        // The .topLeft version makes glitches less noticeable for normal UIs,
        // while NSViewLayerContentsPlacementScaleAxesIndependently matches what MTKView does and
        // makes them very noticeable.
#if ENABLE_GMR_PRESENT_WITH_TRANSACTION
        self.layerContentsPlacement = NSViewLayerContentsPlacementScaleAxesIndependently;
#else
        self.layerContentsPlacement = NSViewLayerContentsPlacementTopLeft;
#endif
    }
    return self;
}

- (CALayer *)makeBackingLayer {
    CAMetalLayer *metalLayer = [[CAMetalLayer alloc] init];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    metalLayer.colorspace = colorSpace;
    CFRelease(colorSpace);
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.device = _device;
    metalLayer.delegate = self;
    if (@available(macOS 10.13, *)) {
        metalLayer.allowsNextDrawableTimeout = false;
    }

    // Tristan's comment:
    // These properties are crucial to resizing working.
    metalLayer.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
    metalLayer.needsDisplayOnBoundsChange = YES;
#if ENABLE_GMR_PRESENT_WITH_TRANSACTION
    metalLayer.presentsWithTransaction = YES;
#endif

    return metalLayer;
}

- (void)setDrawableSize:(CGSize)drawableSize {
    _metalLayer.drawableSize = drawableSize;
}

- (CGSize)drawableSize {
    return _metalLayer.drawableSize;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.delegate it_mtkView:self drawableSizeWillChange:newSize];
    // The conversion below is necessary for high DPI drawing.
    _metalLayer.drawableSize = [self convertSizeToBacking:newSize];
    [self viewDidChangeBackingProperties];
}

// This will hopefully be called if the window moves between monitors of
// different DPIs but I haven't tested this part
- (void)viewDidChangeBackingProperties {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }
    _metalLayer.contentsScale = window.backingScaleFactor;
}

- (id<CAMetalDrawable>)currentDrawable {
    _currentDrawable = [_metalLayer nextDrawable];
    return _currentDrawable;
}

- (MTLRenderPassDescriptor *)currentRenderPassDescriptor {
    if (!_currentDrawable) {
        return nil;
    }
    _currentRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    MTLRenderPassColorAttachmentDescriptor *colorAttachment = _currentRenderPassDescriptor.colorAttachments[0];
    colorAttachment.texture = _currentDrawable.texture;
    colorAttachment.loadAction = MTLLoadActionClear;
    colorAttachment.storeAction = MTLStoreActionStore;
    colorAttachment.clearColor = MTLClearColorMake(0, 0, 0, 0);
    return _currentRenderPassDescriptor;
}

- (void)displayLayer:(CALayer *)layer {
    NSLog(@"display");
    // stress test with 100ms sleep, still works if this is uncommented
    // [NSThread sleepForTimeInterval:0.1];

    [self.delegate it_drawInMTKView:self];

//        let commandBuffer: MTLCommandBuffer = renderer.draw(passDescriptor: passDescriptor)!
//        commandBuffer.commit()
//        commandBuffer.waitUntilScheduled()
//        drawable.present()
//    }
}

- (void)draw {
    [self.layer setNeedsDisplay];
    [self.layer displayIfNeeded];
}

- (BOOL)it_isMetalView {
    return YES;
}

@end

@implementation MTKView(Phony)
- (BOOL)it_isMetalView {
    return YES;
}
@end

#else
@implementation iTermMTKView
@end
#endif  // ENABLE_PHONY_MTKVIEW
