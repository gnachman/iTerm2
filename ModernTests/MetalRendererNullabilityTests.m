//
//  MetalRendererNullabilityTests.m
//  ModernTests
//
//  The Metal driver passes nil to three renderer setters when a session has no
//  background image, no badge or no cursor guide color, under nonnull claims
//  (unit H1 of docs/swift-migration/nullability-triage.md). Each setter
//  tolerates nil. The renderer headers are not visible to Swift, so the claims
//  are pinned here in Objective-C. The per-frame state, glue and file-local
//  functions of the same unit cannot be built in isolation and are not tested
//  here.
//

#import <XCTest/XCTest.h>
#import <Metal/Metal.h>

#import "iTermBackgroundImageRenderer.h"
#import "iTermBadgeRenderer.h"
#import "iTermCursorGuideRenderer.h"
#import "iTermMetalBufferPool.h"
#import "iTermSharedImageStore.h"

@interface MetalRendererNullabilityTests : XCTestCase
@end

@implementation MetalRendererNullabilityTests {
    id<MTLDevice> _device;
}

- (void)setUp {
    [super setUp];
    _device = MTLCreateSystemDefaultDevice();
}

// -[iTermBackgroundImageRenderer setImage:...] makes no texture for a nil
// image and stores it.
- (void)testBackgroundImageRendererAcceptsNoImage {
    if (!_device) {
        XCTSkip(@"No Metal device");
    }
    iTermBackgroundImageRenderer *renderer = [[iTermBackgroundImageRenderer alloc] initWithDevice:_device];
    XCTAssertNotNil(renderer);
    NSColorSpace *colorSpace = [NSColorSpace sRGBColorSpace];
    // A bitmap in the target color space, so making its texture needs no
    // conversion (an image without a bitmap gives no CGImage, which
    // -bitmapInColorSpace: answers with nil under a nonnull claim).
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:2
                                                                    pixelsHigh:2
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    rep = [rep bitmapImageRepByRetaggingWithColorSpace:colorSpace];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(2, 2)];
    [image addRepresentation:rep];
    iTermImageWrapper *wrapper = [iTermImageWrapper withImage:image];
    [renderer setImage:wrapper
                  mode:iTermBackgroundImageModeStretch
                 frame:CGRectMake(0, 0, 1, 1)
         containerRect:CGRectMake(0, 0, 1, 1)
                 color:(vector_float4){ 0, 0, 0, 1 }
            colorSpace:colorSpace
               context:nil];
    XCTAssertEqual(renderer.image, wrapper);

    [renderer setImage:nil
                  mode:iTermBackgroundImageModeStretch
                 frame:CGRectMake(0, 0, 1, 1)
         containerRect:CGRectMake(0, 0, 1, 1)
                 color:(vector_float4){ 0, 0, 0, 1 }
            colorSpace:colorSpace
               context:nil];
    XCTAssertNil(renderer.image);
}

// -[iTermBadgeRenderer setBadgeImage:...] wraps a nil image, which gives no
// texture.
- (void)testBadgeRendererAcceptsNoImage {
    if (!_device) {
        XCTSkip(@"No Metal device");
    }
    iTermBadgeRenderer *renderer = [[iTermBadgeRenderer alloc] initWithDevice:_device];
    XCTAssertNotNil(renderer);
    [renderer setBadgeImage:nil
                 colorSpace:[NSColorSpace sRGBColorSpace]
                    context:[[iTermMetalBufferPoolContext alloc] init]];
    XCTAssertFalse(renderer.hasImage);
}

// -[iTermCursorGuideRenderer setColor:] compares and stores the color.
- (void)testCursorGuideRendererAcceptsNoColor {
    if (!_device) {
        XCTSkip(@"No Metal device");
    }
    iTermCursorGuideRenderer *renderer = [[iTermCursorGuideRenderer alloc] initWithDevice:_device];
    XCTAssertNotNil(renderer);
    XCTAssertNotNil([renderer valueForKey:@"color"]);
    [renderer setColor:nil];
    XCTAssertNil([renderer valueForKey:@"color"]);
}

@end
