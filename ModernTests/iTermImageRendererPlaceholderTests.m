//
//  iTermImageRendererPlaceholderTests.m
//  ModernTests
//
//  The Metal image renderer caches one texture per image code. When a code has
//  no image info, it caches a brown placeholder. That placeholder must not
//  outlive the missing info: once the code has an image, the next frame has to
//  draw the image. The legacy renderer looks the code up on every draw, so a
//  stale placeholder shows up only in the GPU renderer.
//

#import <XCTest/XCTest.h>
#import <Metal/Metal.h>

#import "iTermImage.h"
#import "iTermImageInfo.h"
#import "iTermImageRenderer.h"

@interface iTermImageRendererPlaceholderTests : XCTestCase
@end

@implementation iTermImageRendererPlaceholderTests {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    iTermCellRenderConfiguration *_configuration;
}

- (void)setUp {
    [super setUp];
    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];
    _configuration =
    [[iTermCellRenderConfiguration alloc] initWithViewportSize:(vector_uint2){800, 600}
                                          legacyScrollbarWidth:0
                                                         scale:2.0
                                            hasBackgroundImage:NO
                                                  extraMargins:NSEdgeInsetsZero
                  maximumExtendedDynamicRangeColorComponentValue:1.0
                                                    colorSpace:[NSColorSpace sRGBColorSpace]
                                              rightExtraPixels:0
                                        panelReservationPixels:0
                                                      cellSize:CGSizeMake(10, 20)
                                                     glyphSize:CGSizeMake(10, 20)
                                        cellSizeWithoutSpacing:CGSizeMake(10, 20)
                                                      gridSize:VT100GridSizeMake(80, 24)
                                         usingIntermediatePass:NO];
}

- (iTermImageRendererTransientState *)transientStateForRenderer:(iTermImageRenderer *)renderer {
    return [renderer createTransientStateForCellConfiguration:_configuration
                                                commandBuffer:[_queue commandBuffer]];
}

- (iTermMetalImageRun *)runWithCode:(unichar)code imageInfo:(iTermImageInfo *)imageInfo {
    iTermMetalImageRun *run = [[iTermMetalImageRun alloc] init];
    run.code = code;
    run.startingCoordInImage = VT100GridCoordMake(0, 0);
    run.startingCoordOnScreen = VT100GridCoordMake(0, 0);
    run.length = 4;
    run.imageInfo = imageInfo;
    return run;
}

// A bitmap already in the configuration's color space, so making a texture
// from it needs no conversion.
- (iTermImageInfo *)readyImageInfoWithCode:(unichar)code {
    NSColorSpace *colorSpace = [NSColorSpace sRGBColorSpace];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:20
                                                                    pixelsHigh:4
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    rep = [rep bitmapImageRepByRetaggingWithColorSpace:colorSpace];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(20, 4)];
    [image addRepresentation:rep];

    iTermImageInfo *info = [[iTermImageInfo alloc] initWithCode:code];
    info.size = NSMakeSize(4, 1);
    [info setImageFromImage:[iTermImage imageWithNativeImage:image] data:nil];
    return info;
}

- (id<MTLTexture>)onlyTextureIn:(iTermImageRendererTransientState *)tState {
    NSDictionary *textures = [tState valueForKey:@"textures"];
    XCTAssertEqual(textures.count, 1u);
    return textures.allValues.firstObject;
}

- (void)testBrownPlaceholderIsReplacedOnceImageInfoExists {
    if (!_device) {
        XCTSkip(@"No Metal device");
    }
    const unichar code = 1234;
    iTermImageRenderer *renderer = [[iTermImageRenderer alloc] initWithDevice:_device];

    // Frame 1: the code has no image info, so the renderer caches a brown placeholder.
    iTermImageRendererTransientState *first = [self transientStateForRenderer:renderer];
    [first addRun:[self runWithCode:code imageInfo:nil]];
    id<MTLTexture> placeholder = [self onlyTextureIn:first];
    XCTAssertLessThanOrEqual(placeholder.width, 2u);

    // Frame 2: the same code now has a ready image. It must get a real texture.
    iTermImageInfo *info = [self readyImageInfoWithCode:code];
    XCTAssertTrue(info.ready);
    iTermImageRendererTransientState *second = [self transientStateForRenderer:renderer];
    [second addRun:[self runWithCode:code imageInfo:info]];
    id<MTLTexture> texture = [self onlyTextureIn:second];
    XCTAssertNotEqual(texture, placeholder);
    XCTAssertGreaterThan(texture.width, 2u);
}

// A real image's texture stays cached across frames.
- (void)testImageTextureIsReusedWhileImageInfoExists {
    if (!_device) {
        XCTSkip(@"No Metal device");
    }
    const unichar code = 1235;
    iTermImageRenderer *renderer = [[iTermImageRenderer alloc] initWithDevice:_device];
    iTermImageInfo *info = [self readyImageInfoWithCode:code];

    iTermImageRendererTransientState *first = [self transientStateForRenderer:renderer];
    [first addRun:[self runWithCode:code imageInfo:info]];
    id<MTLTexture> texture = [self onlyTextureIn:first];

    iTermImageRendererTransientState *second = [self transientStateForRenderer:renderer];
    [second addRun:[self runWithCode:code imageInfo:info]];
    XCTAssertEqual([self onlyTextureIn:second], texture);
}

@end
