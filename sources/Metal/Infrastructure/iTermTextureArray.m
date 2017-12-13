#import <AppKit/AppKit.h>

#import "DebugLogging.h"
#import "iTermTextureArray.h"
#import <CoreImage/CoreImage.h>

const int iTermTextureMapMaxCharacterParts = 5;
const int iTermTextureMapMiddleCharacterPart = (iTermTextureMapMaxCharacterParts / 2) * iTermTextureMapMaxCharacterParts + (iTermTextureMapMaxCharacterParts / 2);

int ImagePartDX(int part) {
    return (part % iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

int ImagePartDY(int part) {
    return (part / iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

int ImagePartFromDeltas(int dx, int dy) {
    const int radius = iTermTextureMapMaxCharacterParts / 2;
    return (dx + radius) + (dy + radius) * iTermTextureMapMaxCharacterParts;
}

@implementation iTermTextureArray {
    uint32_t _width;
    uint32_t _height;
    NSUInteger _count;
    NSInteger _cellsPerRow;
    NSUInteger _arrayLength;
}

+ (CGSize)atlasSizeForUnitSize:(CGSize)unitSize arrayLength:(NSUInteger)length cellsPerRow:(out NSInteger *)cellsPerRowOut {
    CGFloat pixelsNeeded = unitSize.width * unitSize.height * (double)length;
    CGFloat minimumEdgeLength = ceil(sqrt(pixelsNeeded));
    NSInteger cellsPerRow = MAX(1, ceil(minimumEdgeLength / unitSize.width));
    if (cellsPerRowOut) {
        *cellsPerRowOut = cellsPerRow;
    }
    return CGSizeMake(unitSize.width * cellsPerRow,
                      unitSize.height * ceil((double)length / (double)cellsPerRow));
}

- (instancetype)initWithTextureWidth:(uint32_t)width
                       textureHeight:(uint32_t)height
                         arrayLength:(NSUInteger)length
                              device:(id <MTLDevice>)device {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _arrayLength = length;
        CGSize atlasSize = [iTermTextureArray atlasSizeForUnitSize:CGSizeMake(width, height)
                                                       arrayLength:length
                                                       cellsPerRow:&_cellsPerRow];

        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
        textureDescriptor.width = atlasSize.width;
        textureDescriptor.height = atlasSize.height;
        textureDescriptor.arrayLength = 1;

        _atlasSize = CGSizeMake(textureDescriptor.width, textureDescriptor.height);
        
        _texture = [device newTextureWithDescriptor:textureDescriptor];
    }

    return self;
}

- (void)dealloc {
    _texture = nil;
}

#pragma mark - APIs

- (BOOL)addSliceWithContentsOfFile:(NSString *)path {
    return [self setSlice:_count++ withContentsOfFile:path];
}

- (void)addSliceWithImage:(NSImage *)image {
    [self setSlice:_count++ withImage:image];
}

- (void)copyTextureAtIndex:(NSInteger)index
                   toArray:(iTermTextureArray *)destination
                     index:(NSInteger)destinationIndex
                   blitter:(id<MTLBlitCommandEncoder>)blitter {
    [blitter copyFromTexture:_texture
                 sourceSlice:0
                 sourceLevel:0
                sourceOrigin:[self offsetForIndex:index]
                  sourceSize:MTLSizeMake(_width, _height, 1)
                   toTexture:destination.texture
            destinationSlice:0
            destinationLevel:0
           destinationOrigin:[destination offsetForIndex:destinationIndex]];
}

- (MTLOrigin)offsetForIndex:(NSInteger)index {
    return MTLOriginMake(_width * (index % _cellsPerRow),
                         _height * (index / _cellsPerRow),
                         0);
}

#pragma mark - Private

- (BOOL)setSlice:(NSUInteger)slice withContentsOfFile:(NSString *)path {
    return [self setSlice:slice withImage:[[NSImage alloc] initWithContentsOfFile:path]];
}

- (BOOL)setSlice:(NSUInteger)slice withImage:(NSImage *)nsimage {
    ITDebugAssert(slice < _arrayLength);
    NSBitmapImageRep *bitmapRepresentation = [[NSBitmapImageRep alloc] initWithData:[nsimage TIFFRepresentation]];
    if (!bitmapRepresentation) {
        return NO;
    }
#warning Is this right? Really should be SRGB shouldn't it?
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        return NO;
    }

    uint32_t width = _width;
    uint32_t height = _height;
    uint32_t rowBytes = width * 4;

    CGContextRef context = CGBitmapContextCreate(NULL,
                                                  width,
                                                  height,
                                                  8,
                                                  rowBytes,
                                                  colorSpace,
                                                  kCGImageAlphaPremultipliedLast);

    CGColorSpaceRelease(colorSpace);

    if (!context) {
        return NO;
    }

    CGRect bounds = CGRectMake(0, 0, width, height);

    CGContextClearRect(context, bounds);

    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1.0);

    CGContextDrawImage(context, bounds, bitmapRepresentation.CGImage);

    const void *bytes = CGBitmapContextGetData(context);

    if (bytes) {
        MTLOrigin origin = [self offsetForIndex:slice];
        MTLRegion region = MTLRegionMake2D(origin.x, origin.y, _width, _height);

        [_texture replaceRegion:region
                    mipmapLevel:0
                          slice:0
                      withBytes:bytes
                    bytesPerRow:rowBytes
                  bytesPerImage:rowBytes*height];
    }

    CGContextRelease(context);

    return YES;
}

@end

