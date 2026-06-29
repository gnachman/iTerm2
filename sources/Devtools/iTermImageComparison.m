#import "iTermImageComparison.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"

@implementation iTermImageComparison

+ (iTermImageComparisonResult)compareImage:(NSImage *)image1
                                 withImage:(NSImage *)image2
                             diffImagePath:(NSString *)diffPath {
    iTermImageComparisonResult result = { 0 };

    NSData *data1 = [image1 rawPixelsInRGBColorSpace];
    NSData *data2 = [image2 rawPixelsInRGBColorSpace];

    if (!data1 || !data2 || data1.length != data2.length) {
        result.percentDifferent = 100.0;
        result.maxDifference = 1.0;
        return result;
    }

    const unsigned char *bytes1 = data1.bytes;
    const unsigned char *bytes2 = data2.bytes;
    // Threshold for counting a pixel as "different". Set above the noise floor
    // from GPU dithering (+/-1 per component) and color space conversion.
    const CGFloat threshold = 0.05;
    CGFloat sumOfSquares = 0;
    CGFloat maxDiff = 0;
    CGFloat sum = 0;
    NSUInteger differentCount = 0;
    NSUInteger pixelCount = data1.length / 4;

    NSMutableData *diffData = diffPath ? [NSMutableData dataWithCapacity:pixelCount * 3] : nil;

    for (NSUInteger i = 0; i < data1.length; i += 4) {
        CGFloat brightness1 = PerceivedBrightness(bytes1[i] / 255.0,
                                                   bytes1[i + 1] / 255.0,
                                                   bytes1[i + 2] / 255.0);
        CGFloat brightness2 = PerceivedBrightness(bytes2[i] / 255.0,
                                                   bytes2[i + 1] / 255.0,
                                                   bytes2[i + 2] / 255.0);
        CGFloat diff = fabs(brightness1 - brightness2);

        if (diffData) {
            unsigned char diffbytes[3];
            if (diff > 0) {
                diffbytes[0] = diff * 255;
                diffbytes[1] = (1.0 - diff) * 255;
                diffbytes[2] = 0;
            } else {
                unsigned char gray = (brightness1 + brightness2) * 128;
                diffbytes[0] = gray;
                diffbytes[1] = gray;
                diffbytes[2] = gray;
            }
            [diffData appendBytes:diffbytes length:3];
        }

        sumOfSquares += diff * diff;
        sum += diff;
        maxDiff = MAX(maxDiff, diff);
        if (diff > threshold) {
            differentCount++;
        }
    }

    result.totalPixels = pixelCount;
    result.differentPixels = differentCount;
    result.percentDifferent = pixelCount > 0 ? (100.0 * differentCount / pixelCount) : 0;
    result.maxDifference = maxDiff;
    result.variance = pixelCount > 0 ? (sumOfSquares / pixelCount - (sum / pixelCount) * (sum / pixelCount)) : 0;

    if (diffPath && diffData) {
        NSSize size = NSMakeSize(image1.size.width, image1.size.height);
        NSImage *diffImage = [NSImage imageWithRawData:diffData
                                                  size:size
                                            scaledSize:size
                                         bitsPerSample:8
                                       samplesPerPixel:3
                                              hasAlpha:NO
                                        colorSpaceName:NSCalibratedRGBColorSpace];
        [[diffImage dataForFileOfType:NSBitmapImageFileTypePNG] writeToFile:diffPath atomically:NO];
    }

    return result;
}

@end
